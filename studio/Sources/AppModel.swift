import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications

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
    static let setupCompleted = "setupCompleted"
    static let downloadArtwork = "downloadArtwork"
    static let notifyBuilds = "notifyBuilds"
    static let checkUpdatesAtLaunch = "checkUpdatesAtLaunch"
    static let showsMenuBarItem = "showsMenuBarItem"
    static let seenUpdates = "seenUpdates"
    static let installDevice = "installDevice"
    static let signingTeam = "signingTeam"
    static let installSeparateFiles = "installSeparateFiles"
    static let installFiles = "installFiles"
    static let installLaunch = "installLaunch"
    static let ascKeyPath = "ascKeyPath"
    static let ascKeyID = "ascKeyID"
    static let ascIssuer = "ascIssuer"
    static let iCloudContainer = "iCloudContainer"
    static let cloudSavesFolder = "cloudSavesFolder"

    static func register() {
        UserDefaults.standard.register(defaults: [
            keepExtracted: true,
            pipelineArchive: true,
            showFPS: false,
            defaultTarget: BuildTarget.mac.rawValue,
            downloadArtwork: true,
            notifyBuilds: true,
            checkUpdatesAtLaunch: true,
            showsMenuBarItem: true,
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
    /// The game whose page shows; nil on the other pages. Choosing one opens its page.
    var selectedGameID: Game.ID? {
        didSet { if selectedGameID != nil { page = .game } }
    }
    /// What the window's detail column shows (Navigation.swift): every page is in this one window.
    var page: Page = .home
    var settingsPane: SettingsPane = .general
    private(set) var job: Job?
    private(set) var outcomes: [Game.ID: JobOutcome] = [:]
    /// The last job of each game that ended well, for the game's page ("Built 12 Nov, 18:42, in 37 min").
    private(set) var lastSuccess: [Game.ID: JobOutcome] = [:]
    /// Raised when a game's mods or cheats changed, so their sections read their folders again.
    var extrasRevision = 0
    /// studio/tools/snapshots.swift: the sidebar draws no selection (its translucent highlight cannot be drawn offscreen, and comes out black)
    @ObservationIgnored var snapshotMode = false
    private(set) var activity: [LogLine] = []
    private var nextLineID = 0
    var showsActivity = false
    var showsSetupCheck = false
    var showsSetupAssistant = false
    /// The Updates page, which the launch notice also opens (it was a sheet: now a page of the window).
    var showsUpdates: Bool {
        get { page == .updates }
        set {
            if newValue { page = .updates } else if page == .updates { page = selectedGameID == nil ? .home : .game }
        }
    }
    private(set) var setupReport: SetupReport?
    /// Why the last setup check gave no report (no JSON from `doctor`: a Python that cannot run, say), shown where the report would be.
    private(set) var setupError: String?
    private(set) var isCheckingSetup = false
    private(set) var prerequisites: [SetupReport.Check] = []
    var keys = KeysStatus.current()
    var confirmation: Confirmation?
    var errorMessage: String?
    /// Game controller input; ≡ (Menu) opens Console Mode, which then takes the input.
    let gamepad = Gamepad()
    var consoleRequested = false
    @ObservationIgnored var consoleHandler: (@MainActor (Gamepad.Event) -> Void)?
    let artwork = ArtworkStore()
    let updates = UpdateCenter()
    let playLog = PlayLog()
    let devices = DeviceCenter()
    /// What each game takes on disk, by kind, for its Danger Zone; measured when its page opens, forgotten at each scan.
    private(set) var removalPlans: [Game.ID: RemovalPlan] = [:]
    @ObservationIgnored private var measuring: Set<Game.ID> = []
    var removalRequest: RemovalRequest?
    private(set) var removingGameID: Game.ID?

    init() {
        Pref.register()
        showsSetupAssistant = !UserDefaults.standard.bool(forKey: Pref.setupCompleted)
        libraryFolders = UserDefaults.standard.stringArray(forKey: Pref.libraryFolders) ?? []
        engine = Engine.locate(saved: UserDefaults.standard.string(forKey: Pref.enginePath) ?? "")
        readEngineVersion()
        rescan()
        if UserDefaults.standard.bool(forKey: Pref.checkUpdatesAtLaunch) { checkForUpdates(userInitiated: false) }
        gamepad.onEvent = { [weak self] event in
            guard let self else { return }
            if let handler = consoleHandler {
                handler(event)
            } else if event == .menu {
                consoleRequested = true
            }
        }
    }

    var selectedGame: Game? {
        guard let selectedGameID else { return nil }
        return games.first { $0.id == selectedGameID }
    }

    var canStartJob: Bool { engine != nil && job?.isRunning != true }

    /// The selection of the sidebar, as the page it shows.
    var sidebarSelection: SidebarItem? {
        get {
            switch page {
            case .home: .home
            case .game: selectedGameID.map(SidebarItem.game) ?? .home
            default: .page(page)
            }
        }
        set {
            switch newValue {
            case .game(let id): selectedGameID = id
            case .page(let other):
                selectedGameID = nil
                page = other
            case .home, nil:
                selectedGameID = nil
                page = .home
            }
        }
    }

    func showSettings(_ pane: SettingsPane) {
        settingsPane = pane
        sidebarSelection = .page(.settings)
    }

    /// Takes a finished job off the screen: its card goes, and the page is as it was before the job started.
    func dismissJob() {
        guard let job, !job.isRunning else { return }
        if let id = job.gameID { outcomes[id] = nil }
        self.job = nil
    }

    func dismissOutcome(_ gameID: Game.ID) { outcomes[gameID] = nil }

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
            self?.checkForUpdates(userInitiated: true)
        }
    }

    // MARK: Updates

    /// Checks the app, the tools and nxnative. At launch the window shows what turned up, once per new finding;
    /// asked for, it always shows.
    func checkForUpdates(userInitiated: Bool) {
        if userInitiated { showsUpdates = true }
        updates.check(engine: engine) { [weak self] in
            guard let self, !userInitiated else { return }
            let findings = updates.findings
            if !findings.isEmpty, findings != UserDefaults.standard.string(forKey: Pref.seenUpdates), !showsSetupAssistant {
                showsUpdates = true
            }
        }
    }

    /// The window was closed: what it showed does not open it again at the next launch.
    func dismissUpdateNotice() {
        UserDefaults.standard.set(updates.findings, forKey: Pref.seenUpdates)
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
                removalPlans = [:]
                var apps: [String: String] = [:]
                for game in games { for app in game.macApps { apps[URL(filePath: app).standardizedFileURL.path] = PlayLog.key(for: game) } }
                playLog.setKnownApps(apps)
                applyCloudSavesFolder()   // a game built since the last scan takes the library's cloud folder
                if let id = selectedGameID, !games.contains(where: { $0.id == id }) {   // the game went away: back to the library's home
                    selectedGameID = nil
                    if page == .game { page = .home }
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
        guard canStartJob, engine != nil, game.isBuildable else { return }
        if target == .device, !devices.hasLoaded {   // the devices are read when first needed: an install started before Settings was ever opened
            devices.refresh(engine: engine) { [weak self] in
                guard let self, devices.hasLoaded else { return }
                build(game, target: target)
            }
            return
        }
        keys = KeysStatus.current()
        // A dump holds the game's files already decrypted: only packages need the keys
        guard keys.isUsable || game.kind == .dump else {
            errorMessage = String(localized: "Set your prod.keys in Settings → Keys before building.")
            return
        }
        // The build stops at once without room for the game's image; say so here, with what can be done about it
        if !game.isExtracted, let space = Storage.space(at: game.folder), space.free < game.firstBuildSpace {
            let need = game.firstBuildSpace.fileSize, free = space.free.fileSize
            if space.withPurgeable >= game.firstBuildSpace {
                confirmation = Confirmation(
                    title: String(localized: "Free the space held by Time Machine snapshots?"),
                    message: String(localized: "The first build of \(game.name) needs about \(need) free, and the disk has \(free). macOS keeps \(space.purgeable.fileSize) more in local Time Machine snapshots of files deleted in the last 24 hours. Removing those snapshots frees it now; backups on other disks stay."),
                    actionTitle: String(localized: "Remove Snapshots and Build")) { [weak self] in
                    Task {
                        guard let self else { return }
                        self.log(String(localized: "Removing local Time Machine snapshots…"), kind: .info)
                        let ok = await Storage.thinLocalSnapshots()
                        let after = Storage.space(at: game.folder)?.free ?? 0
                        self.log(String(localized: "\(after.fileSize) free now."), kind: ok ? .info : .error)
                        if after >= game.firstBuildSpace { self.startBuild(game, target: target) } else {
                            self.errorMessage = String(localized: "There is still not enough room: \(after.fileSize) free of about \(need) needed.")
                        }
                    }
                }
            } else {
                errorMessage = String(localized: "The first build of \(game.name) needs about \(need) free on its disk, and there is \(free). Free some space, for example in the Danger Zone of a game you no longer play, or move the game to a disk with more room.")
            }
            return
        }
        startBuild(game, target: target)
    }

    private func startBuild(_ game: Game, target: BuildTarget) {
        guard canStartJob, let engine else { return }
        let defaults = UserDefaults.standard
        var install: InstallOptions?
        var deviceName = ""
        var environment: [String: String] = [:]
        if target == .device {
            guard let device = devices.selectedDevice else {
                errorMessage = devices.error ?? String(localized: "Choose the iPhone or iPad to install on in Settings → iPhone & iPad. Connect it with a cable, unlock it and choose Trust if it is not listed.")
                return
            }
            guard device.isReachable else {
                errorMessage = String(localized: "\(device.name) is not connected now: connect it with a cable, or unlock it on the same network, then install again.")
                devices.refresh(engine: engine)
                return
            }
            guard let team = devices.selectedTeam else {
                errorMessage = devices.teams.isEmpty
                    ? String(localized: "No Apple team to sign with: sign in with your Apple ID in Xcode › Settings › Accounts, or type your team ID in Settings → iPhone & iPad.")
                    : String(localized: "Choose the team that signs the app in Settings → iPhone & iPad.")
                return
            }
            install = InstallOptions(device: device.udid, team: team,
                                     files: defaults.string(forKey: Pref.installFiles) ?? (defaults.bool(forKey: Pref.installSeparateFiles) ? "separate" : "auto"),
                                     launch: defaults.bool(forKey: Pref.installLaunch), iCloudContainer: defaults.string(forKey: Pref.iCloudContainer) ?? "")
            deviceName = device.name
            environment = Self.signingEnvironment(keyPath: defaults.string(forKey: Pref.ascKeyPath) ?? "", keyID: defaults.string(forKey: Pref.ascKeyID) ?? "",
                                                  issuer: defaults.string(forKey: Pref.ascIssuer) ?? "")
        }
        guard let args = Self.buildArguments(folder: game.folder, target: target, keys: keys.isUsable ? keys.path : nil,
                                             keepExtracted: defaults.bool(forKey: Pref.keepExtracted), language: defaults.string(forKey: Pref.language),
                                             pipelineArchive: defaults.bool(forKey: Pref.pipelineArchive), showFPS: defaults.bool(forKey: Pref.showFPS),
                                             macSigningIdentity: defaults.string(forKey: Pref.macSigningIdentity), extra: defaults.string(forKey: Pref.extraArguments) ?? "",
                                             install: install) else {
            errorMessage = String(localized: "The extra build options in Settings → Building have a quote that is not closed.")
            return
        }
        let job = Job(title: target == .device ? String(localized: "Installing on \(deviceName)") : target.jobTitle, gameID: game.id, target: target)
        job.retry = { [weak self] in self?.build(game, target: target) }
        if defaults.bool(forKey: Pref.notifyBuilds) { Notifier.requestPermission() }
        startJob(job, executable: engine.appending(path: "aethernx"), arguments: args, directory: engine, environment: environment) { [weak self] ok in
            guard let self else { return }
            if ok, target == .mac { self.log(String(localized: "\(game.name) is ready: press Play."), kind: .info) }
            if ok, target == .device { self.log(String(localized: "\(game.name) is on \(deviceName)."), kind: .info) }
            if defaults.bool(forKey: Pref.notifyBuilds) && !NSApp.isActive {
                let ready = target == .device ? String(localized: "\(game.name) is on \(deviceName)") : String(localized: "\(game.name) is ready")
                Notifier.post(title: ok ? ready : String(localized: "The build of \(game.name) stopped"),
                              body: ok ? (target == .mac ? String(localized: "Open AetherNX and press Play.") : job.title) : (job.failureMessage ?? ""))
            }
        }
    }

    /// A zip for a bug report: the game's logs, versions and settings, and never any game data (scripts/bug_report.py). It is shown in Finder.
    func makeBugReport(_ game: Game) {
        guard canStartJob, let engine, game.isBuildable else { return }
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let out = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop/AetherNX-report-\(game.titleId ?? "game")-\(stamp).zip").path
        startJob(Job(title: String(localized: "Making a bug report"), gameID: game.id, target: nil),
                 executable: engine.appending(path: "aethernx"), arguments: ["report", game.folder, "--out", out], directory: engine) { ok in
            if ok { Finder.reveal(out) }
        }
    }

    // MARK: Cloud saves

    /// The library's cloud folder reaches every built game that has no choice of its own (CloudSaves.applyLibraryFolder).
    func applyCloudSavesFolder() {
        let folder = UserDefaults.standard.string(forKey: Pref.cloudSavesFolder) ?? ""
        var targets: [String: String] = [:]
        for game in games where game.macApp != nil {
            guard let domain = CloudSaves.domain(for: game) else { continue }
            let target = CloudSaves.libraryTarget(folder, gameName: game.name)
            if !target.isEmpty {
                try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
                GameExtras.prepare(folder: target, game: game)
            }
            targets[domain] = target
        }
        guard !targets.isEmpty else { return }
        let changed = CloudSaves.applyLibraryFolders(targets)
        for game in games where game.macApp != nil { refreshExtras(game) }
        if changed > 0 {
            log(folder.isEmpty ? String(localized: "Cloud saves: off for \(changed) game(s) that followed the library's setting.")
                               : String(localized: "Cloud saves: \(changed) game(s) now sync through \(CloudSaves.displayName(folder))."), kind: .info)
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

    private func startJob(_ job: Job, executable: URL, arguments: [String], directory: URL?, environment: [String: String] = [:],
                          completion: (@MainActor (Bool) -> Void)? = nil) {
        guard self.job?.isRunning != true else { return }
        self.job = job
        log("$ \(([executable.lastPathComponent] + arguments).map(Self.quoted).joined(separator: " "))", kind: .command)
        let runner = CommandRunner(executable: executable, arguments: arguments, directory: directory, environment: environment)
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
                    // A failure stays on the game's page until it is dismissed; a success or a stop leaves nothing behind
                    self.outcomes[gameID] = job.state == .failed ? JobOutcome(title: job.title, succeeded: false, message: job.failureMessage ?? "", date: .now) : nil
                    if ok { self.lastSuccess[gameID] = JobOutcome(title: job.title, succeeded: true, message: job.lastMessage, date: .now) }
                }
                switch job.state {
                case .cancelled: if self.job === job { self.job = nil }
                case .succeeded:
                    // The card says "done" for a few seconds, then the page is as it was before the job
                    Task { @MainActor [weak self, weak job] in
                        try? await Task.sleep(for: .seconds(6))
                        guard let self, let job, self.job === job, !job.isRunning else { return }
                        self.job = nil
                    }
                default: break
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
        refreshExtras(game)   // the mods on and the cheats folder, as the game's folder holds them now
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

    func confirmMoveToTrash(_ path: String, title: String, message: String, then done: (@MainActor () -> Void)? = nil) {
        confirmation = Confirmation(title: title, message: message, actionTitle: String(localized: "Move to Trash")) { [weak self] in
            NSWorkspace.shared.recycle([URL(filePath: path)]) { _, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription }
                    done?()
                    self?.rescan()
                }
            }
        }
    }

    func chooseKeysFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.message = String(localized: "Choose your prod.keys file.")
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Pref.keysPath)
            keys = KeysStatus.current()
        }
    }

    // MARK: Danger Zone

    func measure(_ game: Game) {
        guard removalPlans[game.id] == nil, !measuring.contains(game.id) else { return }
        measuring.insert(game.id)
        let folders = libraryFolders
        Task {
            let plan = await Task.detached(priority: .utility) { RemovalPlan.make(for: game, libraryFolders: folders) }.value
            measuring.remove(game.id)
            removalPlans[game.id] = plan
        }
    }

    /// Removes the chosen parts of a game, to the Trash or for good. With the game files gone, its folder goes too when
    /// nothing else is left in it, and a library folder that was only this game leaves the library.
    func remove(_ items: [RemovalPlan.Item], of game: Game, permanently: Bool, forgetsGame: Bool) {
        guard removingGameID == nil, jobFor(game)?.isRunning != true else { return }
        guard !playLog.isRunning(game) else {   // its app runs from the extracted files and writes the saves
            errorMessage = String(localized: "\(game.name) is open: quit it before removing it.")
            return
        }
        removingGameID = game.id
        let paths = items.flatMap(\.paths)
        let domains = items.flatMap(\.domains)
        let size = items.reduce(0) { $0 + $1.size }
        let folder = game.folder
        let ownsFolder = game.kind != .archives || game.id == game.folder
        log(permanently ? String(localized: "Deleting \(size.fileSize) of \(game.name)…") : String(localized: "Moving \(size.fileSize) of \(game.name) to the Trash…"), kind: .info)
        Task {
            // The launcher's settings first: cfprefsd keeps a copy of a plist removed under it
            for domain in domains {
                _ = await CommandRunner.capture(executable: URL(filePath: "/usr/bin/defaults"), arguments: ["delete", domain], directory: nil)
            }
            var failures = await Self.discard(paths, permanently: permanently)
            if forgetsGame && ownsFolder && Self.isSafeToRemove(folder) && Self.holdsNoFiles(folder) {
                failures += await Self.discard([folder], permanently: permanently)
                if libraryFolders.contains(folder) { libraryFolders.removeAll { $0 == folder } }
            }
            if forgetsGame { playLog.forget(game) }
            for failure in failures { log(failure, kind: .error) }
            log(failures.isEmpty ? String(localized: "\(game.name): \(size.fileSize) removed.") : String(localized: "\(game.name): some items could not be removed."), kind: failures.isEmpty ? .info : .error)
            removingGameID = nil
            removalPlans[game.id] = nil
            if forgetsGame, selectedGameID == game.id { selectedGameID = nil }
            rescan()
        }
    }

    private nonisolated static func discard(_ paths: [String], permanently: Bool) async -> [String] {
        let urls = paths.map { URL(filePath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) || (try? $0.checkResourceIsReachable()) == true }
        guard !urls.isEmpty else { return [] }
        if permanently {
            return await Task.detached(priority: .userInitiated) {
                var failures: [String] = []
                for url in urls {
                    do { try FileManager.default.removeItem(at: url) } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                return failures
            }.value
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle(urls) { _, error in
                    continuation.resume(returning: error.map { [$0.localizedDescription] } ?? [])
                }
            }
        }
    }

    /// A folder that is not the home folder, a top-level folder, a volume, or one of the home folder's own (Downloads, Documents…) or a folder holding one.
    nonisolated static func isSafeToRemove(_ path: String) -> Bool {
        let fm = FileManager.default
        let target = URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL
        let kept: [FileManager.SearchPathDirectory] = [.desktopDirectory, .documentDirectory, .downloadsDirectory, .moviesDirectory, .musicDirectory, .picturesDirectory,
                                                      .libraryDirectory, .applicationDirectory, .sharedPublicDirectory]
        // Compared as paths: these URLs end in "/" and a URL made from a path does not, so as URLs they are never equal
        let own = ([fm.homeDirectoryForCurrentUser] + kept.compactMap { fm.urls(for: $0, in: .userDomainMask).first }).map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        return target.pathComponents.count > 3 && !own.contains { $0 == target.path || $0.hasPrefix(target.path + "/") }
    }

    /// Whether a folder holds nothing but empty folders and Finder's own files.
    nonisolated static func holdsNoFiles(_ path: String) -> Bool {
        guard let walker = FileManager.default.enumerator(at: URL(filePath: path), includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        for case let url as URL in walker {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            let name = url.lastPathComponent
            if name == ".DS_Store" || name.hasPrefix("._") || name == "Icon\r" { continue }
            return false
        }
        return true
    }

    // MARK: Setup check

    /// Runs the commands that install missing pieces (Prerequisites.swift), then checks again.
    func startSetupJob(_ job: Job, script: String) {
        startJob(job, executable: URL(filePath: "/bin/zsh"), arguments: ["-c", script], directory: engine ?? FileManager.default.homeDirectoryForCurrentUser,
                 environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "NONINTERACTIVE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]) { [weak self] _ in
            self?.runSetupCheck()
            self?.refreshPrerequisites()
        }
    }

    /// What this Mac has of what AetherNX needs before its own check can run (MacPrerequisites).
    func refreshPrerequisites() {
        Task { prerequisites = await MacPrerequisites.check() }
    }

    func runSetupCheck() {
        guard let engine, !isCheckingSetup else { return }
        isCheckingSetup = true
        Task {
            let result = await CommandRunner.capture(executable: engine.appending(path: "aethernx"), arguments: ["doctor", "--json"], directory: engine)
            isCheckingSetup = false
            setupReport = try? JSONDecoder.snakeCase.decode(SetupReport.self, from: result.stdout)
            if setupReport == nil {   // shown in the setup check and the Setup Assistant themselves: an alert would come up behind their sheet
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                setupError = String(localized: "The setup check did not run: \(detail.isEmpty ? String(localized: "Exit code \(result.status)") : String(detail.suffix(300)))")
            } else {
                setupError = nil
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

extension AppModel {
    /// `./aethernx build` with the settings of Settings → Building, for one target; nil when the extra options have a quote that is not closed.
    nonisolated static func buildArguments(folder: String, target: BuildTarget, keys: String?, keepExtracted: Bool, language: String?, pipelineArchive: Bool, showFPS: Bool,
                                           macSigningIdentity: String?, extra: String, install: InstallOptions? = nil) -> [String]? {
        guard let extraWords = splitArguments(extra) else { return nil }
        var args: [String]
        if target == .device {
            // `./aethernx install` builds the game's Xcode project itself, from the extracted files it keeps, then signs and installs it
            guard let install else { return nil }
            args = ["install", folder, "--progress", "json", "--device", install.device, "--team", install.team, "--files", install.files]
            if install.launch { args.append("--launch") }
            if !install.iCloudContainer.isEmpty { args += ["--icloud-container", install.iCloudContainer] }
            if let keys { args += ["-k", keys] }
        } else {
            args = ["build", folder, "--target", target.rawValue, "--progress", "json"]
            if let keys { args += ["-k", keys] }
            // Xcode builds from the extracted files, and a build with the game files separate keeps them for the copy to the phone: the build refuses either without them
            args.append(keepExtracted || target == .xcode || target == .iosSlim ? "--keep-extracted" : "--no-keep-extracted")
        }
        if let language, !language.isEmpty { args += ["--language", language] }
        if !pipelineArchive { args += ["--gpu", "none"] }
        if target == .ios || target == .iosSlim || target == .device { args.append(showFPS ? "--show-fps" : "--no-show-fps") }
        if target == .mac, let macSigningIdentity, !macSigningIdentity.isEmpty { args += ["--mac-sign", macSigningIdentity] }
        return args + extraWords
    }

    /// The App Store Connect API key of Settings → iPhone & iPad, for `./aethernx install`: in its environment, so that neither the key's path nor the
    /// account's issuer ID is written to the activity log with the command. Nothing without a key file.
    nonisolated static func signingEnvironment(keyPath: String, keyID: String, issuer: String) -> [String: String] {
        guard !keyPath.isEmpty else { return [:] }
        var env = ["AETHERNX_ASC_KEY": keyPath]
        if !keyID.isEmpty { env["AETHERNX_ASC_KEY_ID"] = keyID }
        if !issuer.isEmpty { env["AETHERNX_ASC_ISSUER"] = issuer }
        return env
    }

    /// The words of the extra build options as a shell would split them, without running one: spaces separate them, quotes keep a value with spaces
    /// together ('…' takes everything as written, "…" takes \" and \\ as one character), and a backslash outside quotes keeps the next character.
    /// nil when a quote is not closed.
    nonisolated static func splitArguments(_ text: String) -> [String]? {
        var words: [String] = [], word = "", inWord = false
        var quote: Character?, escaped = false
        for c in text {
            if escaped {
                if quote == "\"" && c != "\"" && c != "\\" { word.append("\\") }   // inside "…", a backslash is kept before any other character
                word.append(c); escaped = false; inWord = true
            } else if c == "\\" && quote != "'" {
                escaped = true
            } else if let open = quote {
                if c == open { quote = nil } else { word.append(c) }
            } else if c == "'" || c == "\"" {
                quote = c; inWord = true
            } else if c.isWhitespace {
                if inWord { words.append(word); word = ""; inWord = false }
            } else {
                word.append(c); inWord = true
            }
        }
        if quote != nil { return nil }
        if escaped { word.append("\\"); inWord = true }
        if inWord { words.append(word) }
        return words
    }
}

/// macOS notifications when a build ends while AetherNX is in the background.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
