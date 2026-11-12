import AppKit
import CryptoKit
import Foundation
import Observation
import Security
import zlib

/// Where AetherNX stands against the newest versions: the Studio app (GitHub releases), the AetherNX tools checkout
/// (its Git remote), and nxnative, the engine AetherNX is built on (its commits since AetherNX's last sync).
@MainActor
@Observable
final class UpdateCenter {
    struct AppRelease: Equatable {
        var version: String
        var notes: String
        var page: URL
        var zip: URL?
        var sums: URL?
    }

    struct Tools: Equatable {
        struct Commit: Equatable, Identifiable {
            var id: String { hash }
            var hash: String
            var date: String
            var subject: String
        }

        var behind: Int
        var ahead: Int
        var hasLocalChanges: Bool
        var branch: String
        var tracking: String
        var isTracking: Bool
        var newestCommit: String
        var newestSubject: String?
        var newestVersion: String?
        /// The changes an update brings, newest first (at most 40).
        var newCommits: [Commit] = []
        /// What they touch: the engine (games are rebuilt to get it), the shader chain (every game's shaders are translated again at its next
        /// build), the Studio app's own sources (they come with a new release of the app, not with this update).
        var touchesEngine = false
        var touchesShaderChain = false
        var touchesApp = false
        /// A fast-forward pull applies: the folder follows its remote branch and has no changes of its own.
        var canUpdate: Bool { isTracking && ahead == 0 && !hasLocalChanges }
    }

    struct Upstream: Equatable {
        var aheadBy: Int
        var synced: String
        var syncedDate: String?
        var page: URL
        var newestSubject: String?
        var newestDate: Date?
    }

    enum Phase: Equatable { case idle, checking, installing(String) }

    private(set) var phase: Phase = .idle
    private(set) var lastChecked: Date?
    /// A release newer than this app, else nil.
    private(set) var appRelease: AppRelease?
    private(set) var appError: String?
    private(set) var tools: Tools?
    private(set) var toolsError: String?
    private(set) var upstream: Upstream?
    private(set) var upstreamError: String?

    nonisolated static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    nonisolated static let releasesAPI = URL(string: "https://api.github.com/repos/iCosiSenpai/AetherNX/releases/latest")!
    nonisolated static let commitsAPI = URL(string: "https://api.github.com/repos/iCosiSenpai/AetherNX/commits?per_page=100")!
    nonisolated static let upstreamRepository = "seedds/nxnative"
    /// Releases are signed with this Developer ID team; an update must be too.
    nonisolated static let publisherRequirement = #"identifier "io.github.icosisenpai.aethernx" and anchor apple generic and certificate leaf[subject.OU] = "6KV8L8WQ9D""#

    var toolsUpdateAvailable: Bool { (tools?.behind ?? 0) > 0 }
    var upstreamChanges: Int { upstream?.aheadBy ?? 0 }
    /// Something the user can install now.
    var hasUpdates: Bool { appRelease != nil || toolsUpdateAvailable }
    var isChecking: Bool { phase == .checking }

    /// What was found, to show the launch notice once per new finding.
    var findings: String {
        [appRelease.map { "app \($0.version)" }, toolsUpdateAvailable ? tools.map { "tools \($0.newestCommit)" } : nil,
         upstreamChanges > 0 ? "nxnative \(upstreamChanges)" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    /// A build of this app that the publisher signed (a release), not one made on this Mac.
    let isRelease = UpdateCenter.satisfiesPublisher(Bundle.main.bundleURL)

    // MARK: Checking

    func check(engine: URL?, completion: (@MainActor () -> Void)? = nil) {
        guard phase == .idle else { return }
        phase = .checking
        Task {
            async let release = Self.latestRelease()
            async let toolsResult = Self.toolsStatus(engine: engine)
            async let upstreamResult = Self.upstreamStatus(engine: engine)
            switch await release {
            case .success(let r): appRelease = r; appError = nil
            case .failure(let e): appError = e.message
            }
            switch await toolsResult {
            case .success(let t): tools = t; toolsError = nil
            case .failure(let e): tools = nil; toolsError = e.message
            }
            switch await upstreamResult {
            case .success(let u): upstream = u; upstreamError = nil
            case .failure(let e): upstreamError = e.message
            }
            lastChecked = .now
            phase = .idle
            completion?()
        }
    }

    struct CheckError: Error { var message: String }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "AetherNXStudio/\(currentVersion) (+https://github.com/iCosiSenpai/AetherNX)",
            "Accept": "application/vnd.github+json",
        ]
        return URLSession(configuration: configuration)
    }()

    private nonisolated static func json(_ url: URL) async -> Result<Any, CheckError> {
        guard let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse else {
            return .failure(CheckError(message: String(localized: "GitHub could not be reached.")))
        }
        if http.statusCode == 403 || http.statusCode == 429 {
            return .failure(CheckError(message: String(localized: "GitHub asks to wait before checking again (too many checks in an hour).")))
        }
        guard http.statusCode == 200, let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(CheckError(message: String(localized: "GitHub answered \(http.statusCode).")))
        }
        return .success(object)
    }

    private nonisolated static func latestRelease() async -> Result<AppRelease?, CheckError> {
        switch await json(releasesAPI) {
        case .failure(let e): return .failure(e)
        case .success(let object):
            guard let release = object as? [String: Any], let tag = release["tag_name"] as? String,
                  let page = (release["html_url"] as? String).flatMap(URL.init(string:)) else {
                return .failure(CheckError(message: String(localized: "The release information could not be read.")))
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isVersion(version, newerThan: currentVersion) else { return .success(nil) }
            let assets = release["assets"] as? [[String: Any]] ?? []
            func asset(_ name: String) -> URL? {
                assets.first { $0["name"] as? String == name }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
            }
            return .success(AppRelease(version: version, notes: release["body"] as? String ?? "", page: page,
                                       zip: asset("AetherNX-\(version).zip"), sums: asset("SHA256SUMS")))
        }
    }

    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let y = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private nonisolated static func git(_ engine: URL, _ arguments: [String], timeout: TimeInterval? = nil) async -> (ok: Bool, out: String) {
        // No password prompt, and a transfer that stalls (a captive portal, a dead proxy) gives up: the check must come back for the buttons it disables to work again
        let result = await CommandRunner.capture(executable: URL(filePath: "/usr/bin/git"), arguments: ["-C", engine.path] + arguments, directory: engine,
                                                 environment: ["GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/usr/bin/false", "GIT_HTTP_LOW_SPEED_LIMIT": "1000", "GIT_HTTP_LOW_SPEED_TIME": "20"],
                                                 timeout: timeout)
        return (result.status == 0, String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private nonisolated static func toolsStatus(engine: URL?) async -> Result<Tools?, CheckError> {
        guard let engine else { return .success(nil) }
        guard await git(engine, ["rev-parse", "--is-inside-work-tree"]).ok else {
            return .failure(CheckError(message: String(localized: "The AetherNX folder is not a Git checkout: download the tools again to get updates.")))
        }
        guard await git(engine, ["fetch", "--quiet", "origin"], timeout: 90).ok else {
            return .failure(CheckError(message: String(localized: "The tools' remote could not be reached.")))
        }
        let branch = await git(engine, ["rev-parse", "--abbrev-ref", "HEAD"]).out
        let upstreamRef = await git(engine, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        var tracking = upstreamRef.ok ? upstreamRef.out : ""
        if tracking.isEmpty {
            // A branch of its own: compare with the remote's default branch
            let head = await git(engine, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
            tracking = head.ok && !head.out.isEmpty ? head.out : "origin/main"
        }
        let counts = await git(engine, ["rev-list", "--left-right", "--count", "HEAD...\(tracking)"]).out.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard counts.count == 2 else { return .failure(CheckError(message: String(localized: "The tools' history could not be compared with \(tracking).")) ) }
        let changes = await git(engine, ["status", "--porcelain", "--untracked-files=no"]).out
        let newest = await git(engine, ["rev-parse", "--short", tracking]).out
        let subject = await git(engine, ["log", "-1", "--format=%s", tracking]).out
        let version = await git(engine, ["show", "\(tracking):VERSION"])
        var tools = Tools(behind: counts[1], ahead: counts[0], hasLocalChanges: !changes.isEmpty, branch: branch, tracking: tracking,
                          isTracking: upstreamRef.ok, newestCommit: newest, newestSubject: subject.isEmpty ? nil : subject,
                          newestVersion: version.ok ? version.out : nil)
        if counts[1] > 0 {
            let log = await git(engine, ["log", "--format=%h%x09%as%x09%s", "-n", "40", "HEAD..\(tracking)"]).out
            tools.newCommits = log.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
                return parts.count == 3 ? Tools.Commit(hash: parts[0], date: parts[1], subject: parts[2]) : nil
            }
            let files = await git(engine, ["diff", "--name-only", "HEAD...\(tracking)"]).out.split(separator: "\n").map(String.init)
            (tools.touchesEngine, tools.touchesShaderChain, tools.touchesApp) = Self.impact(of: files)
        }
        return .success(tools)
    }

    /// What a set of changed files means for the player: (engine, shader chain, app).
    nonisolated static func impact(of files: [String]) -> (Bool, Bool, Bool) {
        let engine = files.contains { $0.hasPrefix("dm/") || ($0.hasPrefix("scripts/") && !$0.hasPrefix("scripts/release")) }
        let chain = files.contains { $0 == "dm/gfx/nvn/dmsh_chain.h" || $0.hasPrefix("dm/gfx/tools/dmsh_xlate") || $0 == "dm/gfx/tools/dmsh_chain.lock" }
        let app = files.contains { $0.hasPrefix("studio/") }
        return (engine, chain, app)
    }

    /// The nxnative commit of AetherNX's last sync: the subject "Sync with seedds/nxnative up to <commit> (<date>)" in the
    /// tools' history, else in the AetherNX repository's recent commits (a shallow download keeps no history).
    private nonisolated static func lastSync(engine: URL?) async -> (commit: String, date: String?)? {
        func parse(_ subject: String) -> (String, String?)? {
            guard let match = subject.firstMatch(of: #/up to ([0-9a-f]{7,40})(?: \((\d{4}-\d{2}-\d{2})\))?/#) else { return nil }
            return (String(match.1), match.2.map(String.init))
        }
        if let engine {
            let local = await git(engine, ["log", "-1", "--format=%s", "--grep=^Sync with seedds/nxnative up to "])
            if local.ok, let found = parse(local.out) { return found }
        }
        guard case .success(let object) = await json(commitsAPI), let commits = object as? [[String: Any]] else { return nil }
        for commit in commits {
            guard let message = (commit["commit"] as? [String: Any])?["message"] as? String,
                  message.hasPrefix("Sync with seedds/nxnative up to "), let found = parse(message) else { continue }
            return found
        }
        return nil
    }

    private nonisolated static func upstreamStatus(engine: URL?) async -> Result<Upstream?, CheckError> {
        guard let sync = await lastSync(engine: engine) else {
            return .failure(CheckError(message: String(localized: "The nxnative version of AetherNX's engine could not be found.")))
        }
        guard let compare = URL(string: "https://api.github.com/repos/\(upstreamRepository)/compare/\(sync.commit)...main") else { return .success(nil) }
        switch await json(compare) {
        case .failure(let e): return .failure(e)
        case .success(let object):
            guard let info = object as? [String: Any], let ahead = info["ahead_by"] as? Int else {
                return .failure(CheckError(message: String(localized: "nxnative's changes could not be read.")))
            }
            let page = (info["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(upstreamRepository)/commits/main")!
            var result = Upstream(aheadBy: ahead, synced: sync.commit, syncedDate: sync.date, page: page)
            if ahead > 0, let newest = URL(string: "https://api.github.com/repos/\(upstreamRepository)/commits?per_page=1"),
               case .success(let list) = await json(newest), let first = (list as? [[String: Any]])?.first,
               let commit = first["commit"] as? [String: Any] {
                result.newestSubject = (commit["message"] as? String)?.split(separator: "\n").first.map(String.init)
                if let date = (commit["committer"] as? [String: Any])?["date"] as? String { result.newestDate = ISO8601DateFormatter().date(from: date) }
            }
            return .success(result)
        }
    }

    // MARK: Installing the app

    /// Downloads the release, checks its checksum and its signature, puts it in place of this app and opens it.
    /// A build made on this Mac (not signed by the publisher) opens the release page instead.
    func installApp() {
        guard let release = appRelease else { return }
        guard isRelease, let zip = release.zip, let sums = release.sums else {
            NSWorkspace.shared.open(release.page)
            return
        }
        let current = Bundle.main.bundleURL
        // Run from the disk image (read-only) or from where macOS keeps a downloaded app apart until it is moved (App Translocation, also read-only): the bundle
        // cannot be replaced there, so the release page opens instead of a download that would end in a file system error
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path), !current.path.contains("/AppTranslocation/") else {
            appError = String(localized: "AetherNX runs from a place it cannot replace itself in (its disk image, or a downloaded copy not yet moved): move it to Applications to update in place.")
            NSWorkspace.shared.open(release.page)
            return
        }
        phase = .installing(String(localized: "Downloading AetherNX \(release.version)…"))
        Task {
            do {
                let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let (archive, archiveResponse) = try await Self.session.data(from: zip)
                let (list, listResponse) = try await Self.session.data(from: sums)
                guard (archiveResponse as? HTTPURLResponse)?.statusCode == 200, (listResponse as? HTTPURLResponse)?.statusCode == 200 else {
                    throw CheckError(message: String(localized: "The download did not complete."))
                }
                phase = .installing(String(localized: "Checking the download…"))
                let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
                let listed = String(decoding: list, as: UTF8.self).split(whereSeparator: \.isNewline)
                    .first { $0.hasSuffix(" " + zip.lastPathComponent) }?.split(separator: " ").first.map(String.init)
                guard listed?.lowercased() == digest else { throw CheckError(message: String(localized: "The download does not match the release's checksum.")) }
                // What is unpacked before the signature is checked must stay in this folder: only the app (and ditto's __MACOSX copy of its metadata), no path
                // that leaves the folder and no link a later entry could be written through (the checksum comes from the same release, so it proves nothing about that)
                guard Self.isSafeAppArchive(archive) else { throw CheckError(message: String(localized: "The download holds something other than the app: it was not installed.")) }
                let zipFile = folder.appending(path: zip.lastPathComponent)
                try archive.write(to: zipFile)
                let unpacked = folder.appending(path: "unpacked")
                let ditto = await CommandRunner.capture(executable: URL(filePath: "/usr/bin/ditto"), arguments: ["-x", "-k", zipFile.path, unpacked.path], directory: nil)
                let app = unpacked.appending(path: "AetherNX.app")
                guard ditto.status == 0, FileManager.default.fileExists(atPath: app.path) else { throw CheckError(message: String(localized: "The download could not be unpacked.")) }
                guard Self.satisfiesPublisher(app),
                      Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version else {
                    throw CheckError(message: String(localized: "The downloaded app is not signed by AetherNX's publisher, or is another version: it was not installed."))
                }
                phase = .installing(String(localized: "Installing…"))
                _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
                try? FileManager.default.removeItem(at: folder)   // now: relaunch ends this process, and the defer above never runs
                Self.relaunch(current)
            } catch {
                phase = .idle
                appError = (error as? CheckError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Whether the code at `url` is signed by the publisher, nested code included (codesign --verify --deep --strict -R).
    nonisolated static func satisfiesPublisher(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(publisherRequirement as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// Whether every entry of a release archive stays in the folder it is unpacked in: a file or a folder (no link) under
    /// AetherNX.app/ or ditto's __MACOSX/, with no empty, "." or ".." part, no backslash and no leading "/".
    nonisolated static func isSafeAppArchive(_ data: Data) -> Bool {
        guard let entries = zipEntries(data), !entries.isEmpty else { return false }
        return entries.allSatisfy { entry in
            let type = entry.mode & 0o170000
            guard type == 0 || type == 0o100000 || type == 0o040000, !entry.name.contains("\\") else { return false }
            var parts = entry.name.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count > 1, parts.last == "" { parts.removeLast() }   // a folder's name ends in "/"
            guard let first = parts.first, first == "AetherNX.app" || first == "__MACOSX" else { return false }
            return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        }
    }

    /// The entries of a ZIP archive as ditto unpacks it, name and Unix mode, or nil when a reader could find anything else.
    /// ditto walks the local headers in file order, names each entry from its local header and takes its mode from the central
    /// directory record of the same rank; it also unpacks a local entry the central directory leaves out. So the local headers
    /// must follow one another from the start of the file to the central directory, each with the name and sizes of its record,
    /// and each compressed stream must end where its record says. Zip64, encryption and methods other than stored and deflate
    /// are refused: a release is a ditto archive far under 4 GB.
    nonisolated static func zipEntries(_ data: Data) -> [(name: String, mode: UInt16)]? {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int? { at >= 0 && at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : nil }
        func u32(_ at: Int) -> Int? { u16(at).flatMap { low in u16(at + 2).map { low | $0 << 16 } } }
        // The end record: 22 bytes, then a comment that must reach the end of the file exactly
        guard bytes.count >= 22,
              let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 0xFFFF), by: -1)
                .first(where: { u32($0) == 0x0605_4b50 && u16($0 + 20) == bytes.count - $0 - 22 }),
              u16(end + 4) == 0, u16(end + 6) == 0, let count = u16(end + 10), u16(end + 8) == count, count != 0xFFFF,
              let size = u32(end + 12), let start = u32(end + 16), start + size == end else { return nil }
        var entries: [(name: String, mode: UInt16)] = []
        var record = start, local = 0
        for _ in 0..<count {
            guard u32(record) == 0x0201_4b50, let flags = u16(record + 8), let method = u16(record + 10),
                  let packed = u32(record + 20), let unpacked = u32(record + 24), let nameLength = u16(record + 28),
                  let extraLength = u16(record + 30), let commentLength = u16(record + 32), let attributes = u32(record + 38),
                  let offset = u32(record + 42), record + 46 + nameLength + extraLength + commentLength <= end,
                  flags & 1 == 0, method == 0 || method == 8, packed != 0xFFFF_FFFF, unpacked != 0xFFFF_FFFF else { return nil }
            let name = bytes[(record + 46)..<(record + 46 + nameLength)]
            guard !name.contains(0), let text = String(bytes: name, encoding: .utf8) else { return nil }
            // Its local header comes right after the previous entry, with the same name, flags and method
            guard offset == local, u32(local) == 0x0403_4b50, u16(local + 6) == flags, u16(local + 8) == method,
                  u16(local + 26) == nameLength, let localExtra = u16(local + 28),
                  local + 30 + nameLength + localExtra + packed <= start,
                  bytes[(local + 30)..<(local + 30 + nameLength)] == name else { return nil }
            let body = local + 30 + nameLength + localExtra
            if flags & 8 == 0 {
                guard u32(local + 18) == packed, u32(local + 22) == unpacked else { return nil }
            }
            if method == 0 {
                guard flags & 8 == 0, packed == unpacked else { return nil }   // a stored entry's end is known only from its sizes
            } else {
                guard inflates(bytes, from: body, count: packed, to: unpacked) else { return nil }
            }
            local = body + packed
            if flags & 8 != 0 {
                // The data descriptor, with or without its signature, repeats the record's sizes
                let sizes = u32(local) == 0x0807_4b50 ? local + 8 : local + 4
                guard u32(sizes) == packed, u32(sizes + 4) == unpacked else { return nil }
                local = sizes + 8
            }
            entries.append((text, UInt16(attributes >> 16)))
            record += 46 + nameLength + extraLength + commentLength
        }
        guard record == end, local == start else { return nil }
        return entries
    }

    /// Whether `count` bytes from `start` are one raw deflate stream that ends on its last byte and inflates to `size` bytes, so
    /// that a reader finding the end by inflating stops where the central directory says. zlib reports what it did not read;
    /// the Compression framework does not.
    nonisolated static func inflates(_ bytes: [UInt8], from start: Int, count: Int, to size: Int) -> Bool {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return false }
        defer { inflateEnd(&stream) }
        var scratch = [UInt8](repeating: 0, count: 1 << 16)
        return bytes.withUnsafeBufferPointer { input in
            scratch.withUnsafeMutableBufferPointer { output in
                stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress! + start)
                stream.avail_in = UInt32(count)
                while true {
                    stream.next_out = output.baseAddress
                    stream.avail_out = UInt32(output.count)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    if status == Z_STREAM_END { return stream.avail_in == 0 && stream.total_out == UInt(size) }
                    // The input ran out before the end, the stream is damaged, or it inflates past the record's size
                    if status != Z_OK || stream.total_out > UInt(size) { return false }
                }
            }
        }
    }

    /// Opens the app again once this process has ended.
    private static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let waiter = Process()
        waiter.executableURL = URL(filePath: "/bin/sh")
        waiter.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.3; done; /usr/bin/open \"$0\"", app.path]
        try? waiter.run()
        NSApp.terminate(nil)
    }
}
