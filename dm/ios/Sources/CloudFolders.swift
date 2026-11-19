import Foundation

/// The public documents container and per-title folder identity shared by the two launchers and Studio.
enum CloudFolders {
    static let containerID = "iCloud.io.github.icosisenpai.horizonnative"
    static let marker = ".aethernx-title"

    static func drive(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static func native(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Mobile Documents/iCloud~io~github~icosisenpai~horizonnative/Documents", isDirectory: true)
    }

    static func accessible(_ root: URL, fileManager: FileManager = .default) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: root.path, isDirectory: &directory)
            && directory.boolValue && fileManager.isReadableFile(atPath: root.path) && fileManager.isWritableFile(atPath: root.path)
    }

    static func folderName(_ name: String) -> String {
        let separators = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        let cleaned = name.components(separatedBy: separators).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var length = 0
        let bounded = cleaned.prefix { character in
            length += String(character).utf8.count
            return length <= 180
        }
        return bounded.isEmpty ? "Game" : String(bounded)
    }

    static func owns(_ folder: URL, titleID: String) -> Bool {
        let value = try? String(contentsOf: folder.appendingPathComponent(marker), encoding: .utf8)
        return value == titleID.uppercased() + "\n"
    }

    static func existingLegacyContents(in folder: URL, titleID: String, fileManager fm: FileManager = .default) -> Bool {
        if fm.fileExists(atPath: folder.appendingPathComponent(titleID).path) { return true }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("game.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (manifest["titleId"] as? String)?.uppercased() == titleID
    }

    static func destinations(primary: String, fallback: String?, name: String, titleID: String) -> (primary: URL?, fallback: URL?) {
        func resolve(_ path: String?) -> URL? {
            guard let path, !path.isEmpty else { return nil }
            return try? game(in: URL(fileURLWithPath: path, isDirectory: true), name: name, titleID: titleID)
        }
        return (resolve(primary), fallback == primary ? nil : resolve(fallback))
    }

    static func knownGameFolders(in root: URL, titleID: String) -> [URL] {
        (try? gameFolders(in: root, titleID: titleID.uppercased(), fileManager: .default)) ?? []
    }

    private static func gameFolders(in root: URL, titleID: String, fileManager fm: FileManager) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
        return try entries.compactMap { entry in
            let values = try entry.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            let name = entry.lastPathComponent
            guard name == titleID || owns(entry, titleID: titleID) || existingLegacyContents(in: entry, titleID: titleID, fileManager: fm) else { return nil }
            return root.appendingPathComponent(name, isDirectory: true)
        }
    }

    /// Find a managed folder even after a game is renamed. Migrate a legacy ID folder only if the target is vacant.
    /// A conflict keeps the ID folder and both copies. Existing bookmarks can still point at the original contents.
    static func game(in root: URL, name: String, titleID: String, fileManager fm: FileManager = .default) throws -> URL {
        let root = root.resolvingSymlinksInPath()
        let id = titleID.uppercased()
        guard id.utf8.count == 16, id.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
              accessible(root, fileManager: fm) else { throw CocoaError(.fileWriteNoPermission) }
        let legacy = root.appendingPathComponent(id, isDirectory: true)
        let title = folderName(name)
        let named = root.appendingPathComponent(title, isDirectory: true)
        let alternate = root.appendingPathComponent("\(title) [\(id)]", isDirectory: true)
        let known = try gameFolders(in: root, titleID: id, fileManager: fm)
        let matches = known.filter { $0.lastPathComponent != id }
        let hasLegacy = known.contains { $0.lastPathComponent == id }
        if hasLegacy && !matches.isEmpty { return legacy }
        if let existing = matches.first(where: { $0 == named || $0 == alternate }) ?? matches.sorted(by: { $0.path < $1.path }).first {
            if !owns(existing, titleID: id) {
                try Data((id + "\n").utf8).write(to: existing.appendingPathComponent(marker), options: .atomic)
            }
            return existing
        }
        let target = fm.fileExists(atPath: named.path) ? alternate : named
        if fm.fileExists(atPath: target.path) {
            if hasLegacy { return legacy }
            throw CocoaError(.fileWriteFileExists)
        }
        let bytes = Data((id + "\n").utf8)
        if hasLegacy {
            try bytes.write(to: legacy.appendingPathComponent(marker), options: .atomic)
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?, moveError: Error?
            coordinator.coordinate(writingItemAt: legacy, options: .forMoving, writingItemAt: target, options: [],
                                   error: &coordinationError) { source, destination in
                do { try fm.moveItem(at: source, to: destination) }
                catch { moveError = error }
            }
            if let error = coordinationError ?? moveError { throw error }
        } else {
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            try bytes.write(to: target.appendingPathComponent(marker), options: .atomic)
        }
        return target
    }
}

#if os(iOS)
// The iOS launcher passes its own signed container's Documents directory.
@_cdecl("dm_cloud_named_game")
func dmCloudNamedGame(_ root: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>, _ id: UnsafePointer<CChar>,
                      _ out: UnsafeMutablePointer<CChar>, _ capacity: Int32) -> Int32 {
    do {
        let folder = try CloudFolders.game(in: URL(fileURLWithPath: String(cString: root)),
                                           name: String(cString: name), titleID: String(cString: id))
        let bytes = Array(folder.path.utf8CString)
        guard bytes.count <= capacity else { return 0 }
        bytes.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: bytes.count) }
        return 1
    } catch {
        fputs("launcher: keeping the existing iCloud save layout (\(error.localizedDescription))\n", stderr)
        return 0
    }
}
#endif
