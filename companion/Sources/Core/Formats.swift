import CryptoKit
import Foundation

// The files a game folder of iCloud Drive › AetherNX holds, as Studio and the engine write them (docs/companion.md, The game folder).
// Nothing here uses UIKit or SwiftUI: companion/tests compiles this folder for the Mac and checks it against synthetic folders.

enum TitleID {
    /// 16 hex digits.
    static func isValid(_ text: String) -> Bool { text.count == 16 && text.allSatisfy(\.isHexDigit) }
}

/// `game.json`: what Studio says the game is.
struct GameManifest: Codable, Equatable, Sendable {
    static let fileName = "game.json"
    static let format = 1

    var format: Int
    var name: String
    var titleId: String
    var version: String?
    var icon: String?
    var bundleId: String?

    /// The file's content, or nil for a file of a later format, or one without a name or a title ID.
    static func decode(_ data: Data) -> GameManifest? {
        guard var manifest = try? JSONDecoder().decode(GameManifest.self, from: data), manifest.format <= format,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, TitleID.isValid(manifest.titleId) else { return nil }
        manifest.titleId = manifest.titleId.uppercased()
        if let icon = manifest.icon, icon.contains("/") || icon.hasPrefix(".") { manifest.icon = nil }   // a file of this folder, never a path
        return manifest
    }
}

/// The header of a packed save, `<title ID>/save.dmsync` (dm/host/save_sync.c), little-endian: "DMSYNC1\n", u32 version, u32 entries,
/// 32 hex digits of the hash, i64 saved (Unix seconds), char title[24], char device[56], i64 restored (Unix seconds; 0: no restore).
struct SaveHeader: Equatable, Sendable {
    static let size = 8 + 4 + 4 + 32 + 8 + 24 + 56 + 8
    static let magic = Data("DMSYNC1\n".utf8)
    /// Where the restore time is: the header's last 8 bytes, after the device name's 56.
    static let restoredAt = size - 8

    var version: UInt32
    /// Folders and files in the save.
    var entries: UInt32
    var hash: String
    /// The newest change of any file in it.
    var saved: Date
    var titleId: String
    /// The model it was sent from ("Mac16,1", "iPhone17,1").
    var device: String
    /// When a Restore put this save back as the cloud's (GameActions.restore): the engine takes that for a change of the cloud's save made then,
    /// not for a save as old as its files. nil for a save as a device sent it.
    var restored: Date?

    init?(_ data: Data) {
        guard data.count >= Self.size, data.prefix(8) == Self.magic else { return nil }
        let bytes = [UInt8](data.prefix(Self.size))
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(bytes[at + $1]) << (8 * $1) } }
        func i64(_ at: Int) -> Int64 { Int64(bitPattern: (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[at + $1]) << (8 * UInt64($1)) }) }
        func text(_ at: Int, _ count: Int) -> String {
            let field = bytes[at..<(at + count)]
            return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
        }
        version = u32(8)
        entries = u32(12)
        hash = text(16, 32)
        saved = Date(timeIntervalSince1970: TimeInterval(i64(48)))
        titleId = text(56, 24)
        if bytes[Self.restoredAt - 1] == 0 {
            device = text(80, 56)
            let at = i64(Self.restoredAt)
            restored = at > 0 ? Date(timeIntervalSince1970: TimeInterval(at)) : nil
        } else {   // a name over its 56 bytes: a file from before the restore time took the last 8 (the engine reads it the same way)
            device = text(80, 64)
            restored = nil
        }
    }

    /// A header with these fields (the demo library's saves, and the tests).
    static func encode(entries: UInt32, hash: String, saved: Date, titleId: String, device: String, restored: Date? = nil) -> Data {
        var data = magic
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        /// `count` bytes: the text (at most `room` of them), then zeros.
        func field(_ text: String, _ count: Int, room: Int) {
            let raw = Array(text.utf8.prefix(room))
            data.append(contentsOf: raw + Array(repeating: 0, count: count - raw.count))
        }
        put(UInt32(1))
        put(entries)
        field(hash, 32, room: 32)   // 32 digits, no terminator
        put(Int64(saved.timeIntervalSince1970))
        field(titleId, 24, room: 23)
        field(device, 56, room: 55)
        put(Int64(restored?.timeIntervalSince1970 ?? 0))
        return data
    }

    /// A packed save with the restore time in its header: what Restore writes as the cloud's save. Nothing else of the file changes, so its hash holds.
    static func marking(_ packed: Data, restored: Date) -> Data? {
        guard packed.count >= size, packed.prefix(8) == magic else { return nil }
        var bytes = [UInt8](packed)
        bytes[restoredAt - 1] = 0   // the device name ends before the time (one over its 56 bytes loses its last ones)
        let at = Int64(restored.timeIntervalSince1970)
        for i in 0..<8 { bytes[restoredAt + i] = UInt8(truncatingIfNeeded: at >> (8 * i)) }
        return Data(bytes)
    }

    /// Whether two packed saves are the same file but for the restore time: a save and the same save put back are one backup.
    static func sameSave(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count, a.count >= size else { return a == b }
        return a.prefix(restoredAt - 1) == b.prefix(restoredAt - 1) && a.dropFirst(size) == b.dropFirst(size)
    }

    /// A readable name for the model: "Mac", "iPhone", "iPad", else the model itself.
    var deviceKind: String {
        for kind in ["iPhone", "iPad", "Mac"] where device.hasPrefix(kind) { return kind }
        return device.isEmpty ? "?" : device
    }
}

/// A whole packed save (dm/host/save_sync.c): the header, then one entry per folder and file, then "DMSYNCE\n" and the end of the file. An entry is
/// u8 type (1 folder, 2 file), u8 0, u16 path length, u16 guest-name length, u16 0, u64 size, i64 date, then the path (save/… or save_device/…),
/// the guest name and the contents. The hash runs over each entry's first 16 bytes, its path, its guest name and its contents.
enum PackedSave {
    static let end = Data("DMSYNCE\n".utf8)

    struct Checked: Equatable, Sendable {
        var header: SaveHeader
        /// Regular files in it; 0: it holds no save.
        var files: Int
    }

    /// The save, when the file is whole as the engine checks one before it takes it (ss_read): version 1, every entry in the file and under save/ or
    /// save_device/, the end marker with nothing after it, and the header's hash the entries' own. nil for any other file: a device would take that
    /// for a damaged save and replace it with its own.
    static func check(_ data: Data) -> Checked? {
        guard let header = SaveHeader(data), header.version == 1 else { return nil }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Checked? in
            var at = SaveHeader.size, files = 0
            var sha = SHA256()
            func next(_ count: Int) -> UnsafeRawBufferPointer? {   // the next bytes of the file, nil past its end
                guard count >= 0, count <= buf.count - at else { return nil }
                defer { at += count }
                return UnsafeRawBufferPointer(rebasing: buf[at..<(at + count)])
            }
            for _ in 0..<header.entries {
                guard let head = next(24) else { return nil }
                let type = head[0], pathLength = Int(head[2]) | Int(head[3]) << 8, guestLength = Int(head[4]) | Int(head[5]) << 8
                let size = (0..<8).reduce(UInt64(0)) { $0 | UInt64(head[8 + $1]) << (8 * UInt64($1)) }
                guard type == 1 || type == 2, pathLength > 0, pathLength < 1024, guestLength <= 1024, type == 2 || size == 0, size <= UInt64(buf.count),
                      let path = next(pathLength), pathIsInside(path), let guest = next(guestLength), let contents = next(Int(size)) else { return nil }
                sha.update(bufferPointer: UnsafeRawBufferPointer(rebasing: head[0..<16]))
                sha.update(bufferPointer: path)
                sha.update(bufferPointer: guest)
                sha.update(bufferPointer: contents)
                if type == 2 { files += 1 }
            }
            guard let tail = next(end.count), tail.elementsEqual(end), at == buf.count else { return nil }
            let hash = files == 0 ? "" : sha.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()   // no save: no hash
            return hash == header.hash ? Checked(header: header, files: files) : nil
        }
    }

    /// A path of a save: under save/ or save_device/, with no empty, `.` or `..` part and no zero byte (the engine's path_ok).
    private static func pathIsInside(_ raw: UnsafeRawBufferPointer) -> Bool {
        let parts = raw.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false).map { Array($0) }
        guard !raw.contains(0), parts.count >= 2, parts[0] == Array("save".utf8) || parts[0] == Array("save_device".utf8) else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0 != Array(".".utf8) && $0 != Array("..".utf8) }
    }

    /// Files packed as the engine packs a save (ss_pack), for the demo library and the tests: `files` in the engine's order (by path, in byte order),
    /// each path under save/ or save_device/ and every file dated `saved`.
    static func pack(files: [(path: String, contents: Data)], saved: Date, titleId: String, device: String, restored: Date? = nil) -> Data {
        var body = Data()
        var sha = SHA256()
        func put<T: FixedWidthInteger>(_ value: T, into data: inout Data) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        for file in files {
            let path = Data(file.path.utf8)
            var head = Data([2, 0])
            put(UInt16(path.count), into: &head)
            put(UInt16(0), into: &head)   // no guest name: the host name is the game's
            put(UInt16(0), into: &head)
            put(UInt64(file.contents.count), into: &head)
            sha.update(data: head)        // the first 16 bytes: not the date
            put(Int64(saved.timeIntervalSince1970), into: &head)
            sha.update(data: path)
            sha.update(data: file.contents)
            body.append(head)
            body.append(path)
            body.append(file.contents)
        }
        let hash = files.isEmpty ? "" : sha.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
        return SaveHeader.encode(entries: UInt32(files.count), hash: hash, saved: saved, titleId: titleId, device: device, restored: restored) + body + end
    }
}

/// `Mods/mods.json`: the mods turned off and their order, for every device. Studio writes it too (GameExtras.ModState in Mods.swift).
struct ModState: Codable, Equatable, Sendable {
    static let fileName = "mods.json"

    var format = 1
    var order: [String]
    var off: [String]

    init(order: [String] = [], off: [String] = []) {
        self.order = order
        self.off = off
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        off = try c.decodeIfPresent([String].self, forKey: .off) ?? []
    }

    static func decode(_ data: Data) -> ModState? {
        guard let state = try? JSONDecoder().decode(ModState.self, from: data), state.format <= 1 else { return nil }
        return state
    }

    /// The bytes Studio writes as well: sorted keys, the mods off sorted and once each.
    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let clean = ModState(order: order, off: Array(Set(off)).sorted())
        return ((try? encoder.encode(clean)) ?? Data()) + Data("\n".utf8)
    }
}
