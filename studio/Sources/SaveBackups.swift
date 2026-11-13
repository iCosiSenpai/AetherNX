import Foundation

/// A game's save backups on this Mac, in the folder the engine keeps beside the save (docs/settings.md, Cloud saves): `<save dir>/save-backups`.
///
/// The engine's cloud sync puts a save there before replacing it, as `<date> local` (this Mac's) or `<date> cloud` (iCloud Drive's), and keeps the newest
/// 10 of each; it leaves any other folder alone (dm/host/save_sync.c, is_backup). Studio adds `<date> manual` (Back Up Now) and `<date> before restore`
/// (this Mac's save, set aside by a restore), which stay until the player deletes them. Each backup holds the game's two save folders as the engine names
/// them, `save` and `save_device`, whichever the game had.
enum SaveBackups {
    static let folders = ["save", "save_device"]

    struct Backup: Identifiable, Hashable {
        enum Kind: String { case local, cloud, manual, beforeRestore = "before restore", other }
        var id: String { path }
        let path: String
        let name: String
        let date: Date?
        let kind: Kind
    }

    enum Failure: LocalizedError {
        case noSave, interruptedSync, nothingInBackup
        var errorDescription: String? {
            switch self {
            case .noSave: String(localized: "There is no save to back up yet.")
            case .interruptedSync: String(localized: "A cloud sync of this save was cut off: start the game once, so it puts the save back, then try again.")
            case .nothingInBackup: String(localized: "That backup holds no save.")
            }
        }
    }

    static func folder(saveDir: String) -> String { (saveDir as NSString).appendingPathComponent("save-backups") }

    /// "2026-11-13 21.40.05": the engine's stamp (backup_dir), local time.
    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    /// The backups, newest first.
    static func list(saveDir: String) -> [Backup] {
        let dir = folder(saveDir: saveDir)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names.compactMap { name -> Backup? in
            var isDir: ObjCBool = false
            let path = (dir as NSString).appendingPathComponent(name)
            guard !name.hasPrefix("."), FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                  folders.contains(where: { FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent($0)) }) else { return nil }
            let date = name.count >= 19 ? stamp.date(from: String(name.prefix(19))) : nil
            let rest = date == nil ? "" : String(name.dropFirst(19)).trimmingCharacters(in: .whitespaces)
            let kind = [Backup.Kind.local, .cloud, .manual, .beforeRestore].first { rest == $0.rawValue || rest.hasPrefix($0.rawValue + " ") } ?? .other
            return Backup(path: path, name: name, date: date, kind: kind)
        }
        .sorted { ($0.date ?? .distantPast, $0.name) > ($1.date ?? .distantPast, $1.name) }
    }

    /// Whether the game has a save on this Mac: something in either save folder but Finder's .DS_Store (the engine's has_save).
    static func hasSave(saveDir: String) -> Bool {
        folders.contains { name in
            let path = (saveDir as NSString).appendingPathComponent(name)
            return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).contains { $0 != ".DS_Store" }
        }
    }

    /// A new backup folder `<now> <kind>`, numbered when one of that second exists (the engine's backup_dir does the same).
    private static func newFolder(saveDir: String, kind: Backup.Kind, now: Date) throws -> String {
        let dir = folder(saveDir: saveDir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let base = (dir as NSString).appendingPathComponent("\(stamp.string(from: now)) \(kind.rawValue)")
        var path = base, k = 2
        while FileManager.default.fileExists(atPath: path) { path = "\(base) \(k)"; k += 1 }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        return path
    }

    /// Back Up Now: copies of the game's save folders into `<now> manual`. The save itself is not touched.
    @discardableResult
    static func backUp(saveDir: String, now: Date = .now) throws -> String {
        guard hasSave(saveDir: saveDir) else { throw Failure.noSave }
        let path = try newFolder(saveDir: saveDir, kind: .manual, now: now)
        do {
            for name in folders {
                let src = (saveDir as NSString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src) { try FileManager.default.copyItem(atPath: src, toPath: (path as NSString).appendingPathComponent(name)) }
            }
        } catch {
            try? FileManager.default.removeItem(atPath: path)
            throw error
        }
        return path
    }

    /// Puts a backup back as the game's save. This Mac's save goes first to `<now> before restore` (moved, not copied), then copies of the backup's
    /// folders take its place, dated now: the cloud sync sends them at the next start, since only this Mac's save changed (or, if iCloud Drive's
    /// changed too, the newer one wins, and this is the newer). Refused while a cut-off sync's note (`save.pull`) waits for the next start.
    /// Returns the folder that holds the save it replaced, if there was one.
    @discardableResult
    static func restore(_ backup: Backup, saveDir: String, now: Date = .now) throws -> String? {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: (saveDir as NSString).appendingPathComponent("save.pull")) else { throw Failure.interruptedSync }
        let present = folders.filter { fm.fileExists(atPath: (backup.path as NSString).appendingPathComponent($0)) }
        guard !present.isEmpty else { throw Failure.nothingInBackup }
        // Copy the backup next to the save first: if a copy fails, nothing of the save has moved
        let staging = (saveDir as NSString).appendingPathComponent(".restore-\(UUID().uuidString)")
        try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: staging) }
        for name in present { try fm.copyItem(atPath: (backup.path as NSString).appendingPathComponent(name), toPath: (staging as NSString).appendingPathComponent(name)) }
        touch(staging, now: now)
        var kept: String?
        if hasSave(saveDir: saveDir) {
            kept = try newFolder(saveDir: saveDir, kind: .beforeRestore, now: now)
        }
        for name in folders {
            let here = (saveDir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: here) {
                if let kept { try fm.moveItem(atPath: here, toPath: (kept as NSString).appendingPathComponent(name)) } else { try fm.removeItem(atPath: here) }
            }
            let incoming = (staging as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: incoming) { try fm.moveItem(atPath: incoming, toPath: here) }
        }
        return kept
    }

    /// Every file and folder under path dated now, so the restored save is the newer one if iCloud Drive's changed too.
    private static func touch(_ path: String, now: Date) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: path) else { return }
        for case let rel as String in walker {
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: (path as NSString).appendingPathComponent(rel))
        }
    }
}
