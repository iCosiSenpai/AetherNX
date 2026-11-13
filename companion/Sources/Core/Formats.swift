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
/// 32 hex digits of the hash, i64 saved (Unix seconds), char title[24], char device[64].
struct SaveHeader: Equatable, Sendable {
    static let size = 8 + 4 + 4 + 32 + 8 + 24 + 64
    static let magic = Data("DMSYNC1\n".utf8)

    var version: UInt32
    /// Folders and files in the save.
    var entries: UInt32
    var hash: String
    /// The newest change of any file in it.
    var saved: Date
    var titleId: String
    /// The model it was sent from ("Mac16,1", "iPhone17,1").
    var device: String

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
        device = text(80, 64)
    }

    /// A header with these fields (the demo library's saves, and the tests).
    static func encode(entries: UInt32, hash: String, saved: Date, titleId: String, device: String) -> Data {
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
        field(device, 64, room: 63)
        return data
    }

    /// A readable name for the model: "Mac", "iPhone", "iPad", else the model itself.
    var deviceKind: String {
        for kind in ["iPhone", "iPad", "Mac"] where device.hasPrefix(kind) { return kind }
        return device.isEmpty ? "?" : device
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
