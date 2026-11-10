import Foundation

/// Disk space: what a volume has free, what macOS could give back, and how much a file or folder takes.
enum Storage {
    struct Space: Equatable {
        /// Free now, as the build script measures it (statvfs).
        var free: Int64
        /// Free plus what macOS can purge on request, such as local Time Machine snapshots.
        var withPurgeable: Int64
        var purgeable: Int64 { max(0, withPurgeable - free) }
    }

    /// The space on the volume that holds `path`, or the nearest folder above it that exists.
    static func space(at path: String) -> Space? {
        var url = URL(filePath: path)
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 { url = url.deletingLastPathComponent() }
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacity else { return nil }
        return Space(free: Int64(free), withPurgeable: max(Int64(free), values.volumeAvailableCapacityForImportantUsage ?? Int64(free)))
    }

    /// The space a file or folder takes on disk; 0 when it is not there. Walks the whole tree: call it off the main thread.
    nonisolated static func size(of path: String) -> Int64 {
        let url = URL(filePath: path)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Removes every local Time Machine snapshot of the startup disk (`tmutil thinlocalsnapshots`), the space macOS keeps
    /// for files deleted since the last hourly snapshot. Backups on other disks stay. Returns whether tmutil succeeded.
    static func thinLocalSnapshots() async -> Bool {
        let result = await CommandRunner.capture(executable: URL(filePath: "/usr/bin/tmutil"), arguments: ["thinlocalsnapshots", "/", "999999999999", "4"], directory: nil)
        return result.status == 0
    }

    /// The per-user cache folder (`getconf DARWIN_USER_CACHE_DIR`), where each app's Metal and URL caches live.
    static var userCacheDirectory: URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
