import AppKit
import Foundation

/// The AetherNX checkout the app drives: it holds `./aethernx` and the build scripts.
enum Engine {
    static func isEngine(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: url.appending(path: "aethernx").path)
            && fm.fileExists(atPath: url.appending(path: "scripts/build_ipa_from_nsp.py").path)
    }

    /// The saved folder, else a checkout the app sits in (build/AetherNX.app), else a few usual places.
    static func locate(saved: String) -> URL? {
        if !saved.isEmpty {
            let url = URL(filePath: (saved as NSString).expandingTildeInPath)
            if isEngine(url) { return url }
        }
        var url = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<3 {
            if isEngine(url) { return url }
            url = url.deletingLastPathComponent()
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for path in ["AetherNX", "Developer/AetherNX", "dev/AetherNX", "Projects/AetherNX", "GitHub/AetherNX", "Documents/GitHub/AetherNX", "Documents/AetherNX"] {
            let candidate = home.appending(path: path)
            if isEngine(candidate) { return candidate }
        }
        return nil
    }

    static var defaultCloneLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "AetherNX")
    }
}

/// Runs a command and hands its output over line by line.
@MainActor
final class CommandRunner {
    private let process = Process()
    private(set) var isRunning = false

    init(executable: URL, arguments: [String], directory: URL?, environment: [String: String] = [:]) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        // An app started from Finder has a short PATH: add Homebrew's, where the build's tools live.
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", path].joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        for (key, value) in environment { env[key] = value }
        process.environment = env
    }

    /// Starts the process; `onLine` gets each line (stdout or stderr), `onExit` the exit status.
    func start(onLine: @escaping @MainActor (String, Bool) -> Void, onExit: @escaping @MainActor (Int32) -> Void) throws {
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let group = DispatchGroup()
        for (pipe, isError) in [(out, false), (err, true)] {
            group.enter()
            Thread.detachNewThread {
                let handle = pipe.fileHandleForReading
                var buffer = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                        buffer.removeSubrange(buffer.startIndex...newline)
                        DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line, isError) } }
                    }
                }
                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line, isError) } }
                }
                group.leave()
            }
        }
        process.terminationHandler = { process in
            let status = process.terminationStatus
            group.notify(queue: .main) {
                MainActor.assumeIsolated {
                    self.isRunning = false
                    onExit(status)
                }
            }
        }
        try process.run()
        isRunning = true
    }

    /// SIGINT first, so the build script stops cleanly; SIGTERM if it is still there after five seconds.
    func interrupt() {
        guard process.isRunning else { return }
        process.interrupt()
        let process = self.process
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }
    }

    /// Runs to the end and returns stdout and stderr; for short commands such as scan and doctor.
    nonisolated static func capture(executable: URL, arguments: [String], directory: URL?, environment: [String: String] = [:]) async -> (status: Int32, stdout: Data, stderr: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = directory
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
                for (key, value) in environment { env[key] = value }
                process.environment = env
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, Data(), error.localizedDescription))
                    return
                }
                var errData = Data()
                let errReader = DispatchGroup()
                errReader.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    errReader.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errReader.wait()
                continuation.resume(returning: (process.terminationStatus, outData, String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}

enum Finder {
    static func reveal(_ path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        } else {
            let parent = (path as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: parent) { NSWorkspace.shared.open(URL(filePath: parent)) }
        }
    }

    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(filePath: path))
    }
}

extension Int64 {
    var fileSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
