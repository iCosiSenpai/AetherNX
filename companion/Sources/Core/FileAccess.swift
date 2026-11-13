import Foundation

/// Reads and writes in a folder iCloud Drive keeps: through NSFileCoordinator, so iCloud never sends a half-written file and a read waits for a
/// write in progress; every write whole, to a temporary file renamed over the old one.
enum FileAccess {
    static func read(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &error) { url in
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            ok = (try? data.write(to: url, options: .atomic)) != nil
        }
        return ok && error == nil
    }

    @discardableResult
    static func remove(_ url: URL) -> Bool {
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forDeleting], error: &error) { url in
            ok = (try? FileManager.default.removeItem(at: url)) != nil
        }
        return ok
    }

    @discardableResult
    static func copy(_ from: URL, to: URL) -> Bool {
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: from, options: [], writingItemAt: to, options: [.forReplacing], error: &error) { from, to in
            try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            ok = (try? FileManager.default.copyItem(at: from, to: to)) != nil
        }
        return ok
    }

    /// What a folder holds, by the names iCloud Drive shows. A file not downloaded to this device yet may be listed as `.<name>.icloud`: it is
    /// given under its own name, in `pending`.
    struct Listing {
        var names: [String] = []
        var pending: Set<String> = []
        func has(_ name: String) -> Bool { names.contains(name) }
    }

    static func list(_ folder: URL) -> Listing {
        var listing = Listing()
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            if name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > 8 {
                let real = String(name.dropFirst().dropLast(7))
                listing.names.append(real)
                listing.pending.insert(real)
            } else {
                listing.names.append(name)
                if isDataless(folder.appending(path: name)) { listing.pending.insert(name) }
            }
        }
        listing.names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return listing
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    /// A file iCloud lists but has not brought to this device yet.
    static func isDataless(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Asks iCloud for a file; a later read finds it.
    static func download(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
