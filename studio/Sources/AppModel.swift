import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Keys of the settings the app keeps in UserDefaults.
enum Pref {
    static let enginePath = "enginePath"
    static let libraryFolders = "libraryFolders"
    static let keysPath = "keysPath"
    static let defaultTarget = "defaultTarget"
    static let language = "language"
    static let keepExtracted = "keepExtracted"
    static let pipelineArchive = "pipelineArchive"
    static let showFPS = "showFPS"
    static let macSigningIdentity = "macSigningIdentity"
    static let extraArguments = "extraArguments"

    static func register() {
        UserDefaults.standard.register(defaults: [
            keepExtracted: true,
            pipelineArchive: true,
            showFPS: false,
            defaultTarget: BuildTarget.mac.rawValue,
        ])
    }
}

/// The prod.keys file the builds use, checked without ever showing a key.
struct KeysStatus: Equatable {
    enum State: Equatable {
        case notSet, missing, unreadable, invalid, ok(count: Int)
    }

    var path: String
    var isAutomatic: Bool
    var state: State

    static var standardLocation: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".switch/prod.keys").path
    }

    static func current() -> KeysStatus {
        let saved = UserDefaults.standard.string(forKey: Pref.keysPath) ?? ""
        if saved.isEmpty {
            let standard = standardLocation
            guard FileManager.default.fileExists(atPath: standard) else { return KeysStatus(path: "", isAutomatic: true, state: .notSet) }
            return KeysStatus(path: standard, isAutomatic: true, state: check(standard))
        }
        return KeysStatus(path: saved, isAutomatic: false, state: check(saved))
    }

    static func check(_ path: String) -> State {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .unreadable }
        var count = 0
        var hasHeaderKey = false
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].hasPrefix(";"), !parts[0].hasPrefix("#"),
                  !parts[1].isEmpty, parts[1].allSatisfy(\.isHexDigit) else { continue }
            count += 1
            if parts[0] == "header_key" { hasHeaderKey = true }
        }
        return hasHeaderKey ? .ok(count: count) : .invalid
    }

    var isUsable: Bool { if case .ok = state { true } else { false } }
}

struct LogLine: Identifiable, Equatable {
    enum Kind { case output, error, info, command }
    let id: Int
    let text: String
    let kind: Kind
}

struct JobOutcome: Equatable {
    var title: String
    var succeeded: Bool
    var message: String
    var date: Date
}

struct Confirmation: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var actionTitle: String
    var action: @MainActor () -> Void
}

@MainActor
@Observable
final class AppModel {
    var engine: URL?
    var engineVersion: String?
    var libraryFolders: [String] {
        didSet { UserDefaults.standard.set(libraryFolders, forKey: Pref.libraryFolders) }
    }
    private(set) var games: [Game] = []
    private(set) var scanErrors: [ScanError] = []
    private(set) var scanFailure: String?
    private(set) var isScanning = false
    @ObservationIgnored private var rescanPending = false
    private(set) var hasScanned = false
    var selectedGameID: Game.ID?
    private(set) var job: Job?
    private(set) var outcomes: [Game.ID: JobOutcome] = [:]
    private(set) var activity: [LogLine] = []
    private var nextLineID = 0
    var showsActivity = false
    var showsSetupCheck = false
    private(set) var setupReport: SetupReport?
    private(set) var isCheckingSetup = false
    var keys = KeysStatus.current()
    var confirmation: Confirmation?
    var errorMessage: String?

    init() {
        Pref.register()
        libraryFolders = UserDefaults.standard.stringArray(forKey: Pref.libraryFolders) ?? []
        engine = Engine.locate(saved: UserDefaults.standard.string(forKey: Pref.enginePath) ?? "")
        readEngineVersion()
        rescan()
    }

    var selectedGame: Game? {
        guard let selectedGameID else { return nil }
        return games.first { $0.id == selectedGameID }
    }

    var canStartJob: Bool { engine != nil && job?.isRunning != true }

    func jobFor(_ game: Game) -> Job? {
        guard let job, job.gameID == game.id else { return nil }
        return job
    }

    // MARK: Engine

    func setEngine(_ url: URL) {
        guard Engine.isEngine(url) else {
            errorMessage = String(localized: "“\(url.lastPathComponent)” is not an AetherNX folder: it has no aethernx command and build scripts.")
            return
        }
        engine = url
        UserDefaults.standard.set(url.path, forKey: Pref.enginePath)
        readEngineVersion()
        rescan()
    }

    func chooseEngineFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose the AetherNX folder (the one with the aethernx command).")
        panel.prompt = String(localized: "Use Folder")
        if panel.runModal() == .OK, let url = panel.url { setEngine(url) }
    }

    func downloadEngine() {
        let destination = Engine.defaultCloneLocation
        if Engine.isEngine(destination) { setEngine(destination); return }
        if FileManager.default.fileExists(atPath: destination.path) {
            errorMessage = String(localized: "\(destination.path) already exists. Move it away or choose it as the AetherNX folder.")
            return
        }
        startJob(Job(title: String(localized: "Downloading AetherNX"), gameID: nil, target: nil),
                 executable: URL(filePath: "/usr/bin/git"),
                 arguments: ["clone", "--depth", "1", Links.engineGit, destination.path],
                 directory: FileManager.default.homeDirectoryForCurrentUser) { [weak self] ok in
            if ok { self?.setEngine(destination) }
        }
    }

    func updateEngine() {
        guard let engine else { return }
        startJob(Job(title: String(localized: "Updating AetherNX"), gameID: nil, target: nil),
                 executable: URL(filePath: "/usr/bin/git"), arguments: ["pull", "--ff-only"], directory: engine) { [weak self] _ in
            self?.readEngineVersion()
        }
    }

    private func readEngineVersion() {
        guard let engine, let text = try? String(contentsOf: engine.appending(path: "VERSION"), encoding: .utf8) else {
            engineVersion = nil
            return
        }
        engineVersion = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Library

    func rescan() {
        keys = KeysStatus.current()
        guard let engine, !libraryFolders.isEmpty else {
            games = []
            scanErrors = []
            scanFailure = nil
            hasScanned = true
            return
        }
        guard !isScanning else {
            rescanPending = true   // the folders changed during a scan: scan again when it ends
            return
        }
        isScanning = true
        let folders = libraryFolders
        Task {
            let result = await CommandRunner.capture(executable: engine.appending(path: "aethernx"), arguments: ["scan", "--json"] + folders, directory: engine)
            isScanning = false
            hasScanned = true
            defer {
                if rescanPending {
                    rescanPending = false
                    rescan()
                }
            }
            guard result.status == 0 else {
                scanFailure = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init)
                    ?? String(localized: "The library scan stopped with exit code \(result.status).")
                return
            }
            do {
                let decoded = try JSONDecoder.snakeCase.decode(ScanResult.self, from: result.stdout)
                games = decoded.games
                scanErrors = decoded.errors
                scanFailure = nil
                if selectedGameID == nil || !games.contains(where: { $0.id == selectedGameID }) {
                    selectedGameID = games.first?.id
                }
            } catch {
                scanFailure = String(localized: "Could not read the scan result: \(error.localizedDescription)")
            }
        }
    }

    func addLibraryFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !libraryFolders.contains(path) else { return }
        libraryFolders.append(path)
        rescan()
    }

    func removeLibraryFolder(_ path: String) {
        libraryFolders.removeAll { $0 == path }
        rescan()
    }

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose a folder with your games: one folder per game, or a single game's folder.")
        panel.prompt = String(localized: "Add")
        if panel.runModal() == .OK { panel.urls.forEach(addLibraryFolder) }
    }

    // MARK: Jobs

    func build(_ game: Game, target: BuildTarget) {
        guard canStartJob, let engine, game.isBuildable else { return }
        keys = KeysStatus.current()
        guard keys.isUsable else {
            errorMessage = String(localized: "Set your prod.keys in Settings → Keys before building.")
            return
        }
        let defaults = UserDefaults.standard
        var args = ["build", game.folder, "--target", target.rawValue, "-k", keys.path, "--progress", "json"]
        args.append(defaults.bool(forKey: Pref.keepExtracted) || target == .xcode ? "--keep-extracted" : "--no-keep-extracted")
        if let language = defaults.string(forKey: Pref.language), !language.isEmpty { args += ["--language", language] }
        if !defaults.bool(forKey: Pref.pipelineArchive) { args += ["--gpu", "none"] }
        if target == .ios || target == .iosSlim { args.append(defaults.bool(forKey: Pref.showFPS) ? "--show-fps" : "--no-show-fps") }
        if target == .mac, let identity = defaults.string(forKey: Pref.macSigningIdentity), !identity.isEmpty { args += ["--mac-sign", identity] }
        if let extra = defaults.string(forKey: Pref.extraArguments), !extra.isEmpty {
            args += extra.split(separator: " ").map(String.init)
        }
        let job = Job(title: target.jobTitle, gameID: game.id, target: target)
        startJob(job, executable: engine.appending(path: "aethernx"), arguments: args, directory: engine) { [weak self] ok in
            guard let self else { return }
            if ok, target == .mac { self.log(String(localized: "\(game.name) is ready: press Play."), kind: .info) }
        }
    }

    func unpack(_ game: Game) {
        guard canStartJob, let engine, game.kind == .archives else { return }
        // A game's id is its archive when the archive sits straight in a library folder, else the game's folder.
        startJob(Job(title: String(localized: "Unpacking \(game.name)"), gameID: game.id, target: nil),
                 executable: engine.appending(path: "aethernx"), arguments: ["unpack", game.id], directory: engine)
    }

    func chooseArchiveToUnpack() {
        guard canStartJob, let engine else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "zst", "001"].compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Choose an archive with a game's packages. It is extracted into a folder next to it.")
        panel.prompt = String(localized: "Unpack")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        startJob(Job(title: String(localized: "Unpacking \(url.lastPathComponent)"), gameID: nil, target: nil),
                 executable: engine.appending(path: "aethernx"), arguments: ["unpack", url.path], directory: engine) { [weak self] ok in
            guard let self, ok, !self.libraryFolders.contains(parent) else { return }
            self.addLibraryFolder(URL(filePath: parent))
        }
    }

    func generateFunctionTables(_ game: Game) {
        guard canStartJob, let engine else { return }
        startJob(Job(title: String(localized: "Making function tables"), gameID: game.id, target: nil),
                 executable: engine.appending(path: "aethernx"), arguments: ["decomp-init", game.folder], directory: engine)
    }

    func lift(_ game: Game) {
        guard canStartJob, let engine else { return }
        startJob(Job(title: String(localized: "Translating main to C"), gameID: game.id, target: nil),
                 executable: engine.appending(path: "aethernx"), arguments: ["lift", game.folder], directory: engine)
    }

    func installPythonPackages() {
        guard canStartJob, let engine else { return }
        startJob(Job(title: String(localized: "Installing Python packages"), gameID: nil, target: nil),
                 executable: engine.appending(path: "aethernx"), arguments: ["setup"], directory: engine) { [weak self] _ in
            self?.runSetupCheck()
        }
    }

    private func startJob(_ job: Job, executable: URL, arguments: [String], directory: URL?, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard self.job?.isRunning != true else { return }
        self.job = job
        log("$ \(([executable.lastPathComponent] + arguments).map(Self.quoted).joined(separator: " "))", kind: .command)
        let runner = CommandRunner(executable: executable, arguments: arguments, directory: directory)
        job.runner = runner
        do {
            try runner.start(onLine: { [weak self, weak job] line, isError in
                guard let self, let job else { return }
                if let text = job.handle(line: line, isError: isError) { self.log(text, kind: isError ? .error : .output) }
            }, onExit: { [weak self, weak job] status in
                guard let self, let job else { return }
                job.finish(status: status)
                let ok = job.state == .succeeded
                if let gameID = job.gameID {
                    self.outcomes[gameID] = JobOutcome(title: job.title, succeeded: ok, message: job.failureMessage ?? "", date: .now)
                }
                self.log(job.state.summary(for: job.title), kind: ok ? .info : .error)
                if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
                completion?(ok)
                self.rescan()
            })
        } catch {
            job.state = .failed
            job.failureMessage = error.localizedDescription
            log(error.localizedDescription, kind: .error)
        }
    }

    private static func quoted(_ s: String) -> String {
        s.contains(" ") || s.contains("'") ? "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" : s
    }

    func log(_ text: String, kind: LogLine.Kind) {
        nextLineID += 1
        activity.append(LogLine(id: nextLineID, text: text, kind: kind))
        if activity.count > 5000 { activity.removeFirst(activity.count - 5000) }
    }

    func clearActivity() { activity.removeAll() }

    // MARK: Game actions

    func play(_ game: Game) {
        guard let app = game.macApp else { return }
        NSWorkspace.shared.openApplication(at: URL(filePath: app), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    func importPackagesIntoSelectedGame() {
        guard let game = selectedGame, game.isBuildable else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["nsp", "xci", "nsz", "xcz"].compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Choose update or DLC packages for \(game.name). They are copied into the game's folder.")
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        let folder = URL(filePath: game.folder)
        let sources = panel.urls.filter { $0.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL }
        guard !sources.isEmpty else { return }
        log(String(localized: "Copying \(sources.count) file(s) into \(game.name)…"), kind: .info)
        Task {
            let failures = await Task.detached(priority: .userInitiated) { () -> [String] in
                var failures: [String] = []
                for source in sources {
                    let destination = folder.appending(path: source.lastPathComponent)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) { continue }
                        try FileManager.default.copyItem(at: source, to: destination)
                    } catch {
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return failures
            }.value
            for failure in failures { log(failure, kind: .error) }
            if failures.isEmpty { log(String(localized: "Files copied. Build again to include them."), kind: .info) }
            rescan()
        }
    }

    func confirmMoveToTrash(_ path: String, title: String, message: String) {
        confirmation = Confirmation(title: title, message: message, actionTitle: String(localized: "Move to Trash")) { [weak self] in
            NSWorkspace.shared.recycle([URL(filePath: path)]) { _, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription }
                    self?.rescan()
                }
            }
        }
    }

    // MARK: Setup check

    func runSetupCheck() {
        guard let engine, !isCheckingSetup else { return }
        isCheckingSetup = true
        Task {
            let result = await CommandRunner.capture(executable: engine.appending(path: "aethernx"), arguments: ["doctor", "--json"], directory: engine)
            isCheckingSetup = false
            setupReport = try? JSONDecoder.snakeCase.decode(SetupReport.self, from: result.stdout)
            if setupReport == nil {
                errorMessage = String(localized: "The setup check did not run: \(result.stderr.suffix(300))")
            }
        }
    }
}

extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
