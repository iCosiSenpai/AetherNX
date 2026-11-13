import Foundation

/// A cheat file of a game's Cheats folder, `<build ID>.txt` in Atmosphère's format, read as the host reads it (dm/host/hle_cheats.c, parse_file;
/// docs/frontends.md, Cheats). `[Name]` opens a cheat and `{Name}` the master, which is always on. The name is what lies between the brackets, cut
/// at 127 bytes. An entry with no code words is a label (a section marker, credits) unless lines under it are prose, which makes it broken. The
/// toggles are `<build ID>.enabled` at the top of the Cheats folder: the keys of the cheats on, one per line, a duplicate name's later entries as
/// "Name #2", "Name #3", … (counting every earlier entry of that name).
struct CheatFile: Identifiable, Equatable, Sendable {
    struct Entry: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable { case cheat, master, label, broken }
        var name: String
        /// Its line in `<build ID>.enabled`.
        var key: String
        var kind: Kind
        var id: String { key }
    }

    /// Upper case, as the host names `<build ID>.enabled`.
    var buildId: String
    var url: URL
    var entries: [Entry]
    var id: String { buildId }

    var cheats: [Entry] { entries.filter { $0.kind == .cheat } }

    /// The build ID a cheat file's name gives: 16 hex digits, then `.txt`.
    static func buildId(ofFileNamed name: String) -> String? {
        guard name.lowercased().hasSuffix(".txt") else { return nil }
        let stem = String(name.dropLast(4))
        return TitleID.isValid(stem) ? stem.uppercased() : nil
    }

    static func parse(_ text: String) -> [Entry] {
        struct Raw { var name: String; var master: Bool; var code = 0; var prose = 0 }
        var raws: [Raw] = []
        var current: Int?
        func body(_ piece: Substring) {
            guard let i = current else { return }   // lines before any header belong to nothing (site files carry prose)
            let words = piece.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
            if words.isEmpty { return }
            if words.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) { raws[i].code += 1 } else { raws[i].prose += 1 }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard let first = trimmed.first, first == "[" || first == "{" else { body(trimmed); continue }
            let close: Character = first == "[" ? "]" : "}"
            let inside = trimmed.dropFirst()
            guard let end = inside.firstIndex(of: close), end > inside.startIndex else { current = nil; continue }
            raws.append(Raw(name: cut(String(inside[..<end])), master: first == "{"))
            current = raws.count - 1
            body(inside[inside.index(after: end)...])   // code words may follow the header on its line
        }
        var entries: [Entry] = []
        for (i, raw) in raws.enumerated() {
            let dup = raws[..<i].filter { $0.name == raw.name }.count
            let kind: Entry.Kind = raw.code > 0 ? (raw.master ? .master : .cheat) : (raw.prose > 0 ? .broken : .label)
            entries.append(Entry(name: raw.name, key: dup > 0 ? "\(raw.name) #\(dup + 1)" : raw.name, kind: kind))
        }
        return entries
    }

    /// The host keeps 127 bytes of a name, cut on a character boundary.
    private static func cut(_ name: String) -> String {
        guard name.utf8.count > 127 else { return name }
        var out = ""
        for ch in name {
            if out.utf8.count + String(ch).utf8.count > 127 { break }
            out.append(ch)
        }
        return out
    }

    // MARK: The toggles

    static func enabledURL(cheatsFolder: URL, buildId: String) -> URL { cheatsFolder.appending(path: "\(buildId.uppercased()).enabled") }

    /// The keys of `<build ID>.enabled`; none when there is no file (the host then starts every cheat off).
    static func enabled(in data: Data?) -> Set<String> {
        guard let data else { return [] }
        return Set(String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { !$0.isEmpty })
    }

    /// The file's new content: the cheats on, in the file's order. Keys the file does not have (another version's) are kept after them.
    func enabledData(on: Set<String>, previous: Set<String>) -> Data {
        let known = Set(cheats.map(\.key))
        let lines = cheats.map(\.key).filter(on.contains) + previous.subtracting(known).sorted()
        return Data(lines.map { $0 + "\n" }.joined().utf8)
    }

    /// The master switch: while `.cheats-off-<title ID>` is in the Cheats folder, no cheat of the game runs.
    static func masterOffURL(cheatsFolder: URL, titleId: String) -> URL { cheatsFolder.appending(path: ".cheats-off-\(titleId.uppercased())") }
}
