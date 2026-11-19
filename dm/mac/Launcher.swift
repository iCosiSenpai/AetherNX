// Mac app launcher: the settings window shown before the game starts, in the launcher's own process (launcher.c calls dm_mac_launcher before it starts the host). Its settings come from the
// app's Resources/dm/launcher.json (dm/games/settings.py with SETTINGS_PLATFORM=mac); the model and the shared parts are the iOS launcher's (dm/ios/Sources/LauncherSettings.swift,
// LauncherRow.swift), and so is the store: launcher.<VAR> in the app's preferences, which launcher.c reads when the window is not shown (docs/frontends.md, Saved choices).
// The Mac window presents settings by category. Play sets the environment the host inherits. Closing the window ends the app before the game starts.
// Holding Option shows the window even when the player's preference is to skip it. A background launch leaves the window behind the active app.
import AppKit
import QuartzCore
import SwiftUI

private func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }

/// The host's comparison of the two saves (dm/host/save_sync.c). This launcher links save_sync.o but imports no C header (pack_app.py builds it with swiftc and no bridging
/// header), so the symbol is declared here.
@_silgen_name("save_sync_report")
private func save_sync_report(_ save: UnsafePointer<CChar>, _ title: UnsafePointer<CChar>, _ folder: UnsafePointer<CChar>?, _ waitMs: Int32,
                              _ out: UnsafeMutablePointer<CChar>, _ n: Int) -> Int32

/// Cloud saves before Play: this Mac's save against the cloud's (SaveSyncReport, shared with the iPhone launcher), and the question it needs, as alerts.
/// It runs with the window's Play and, with the window off, before dmMacLauncher returns; DM_LAUNCHER=0 asks nothing (the host takes the newer save).
enum SaveCheck {
    enum Outcome { case play(String?), retry, cancel }

    /// Blocks while the cloud's file comes (SaveSyncReport.waitMs at most): call it off the main thread. nil: no report (sync is then left to the host as before)
    static func report() -> SaveSyncReport? {
        // getenv, not ProcessInfo.environment: launcher.c sets DM_SAVE and applies the env files in this process before the window
        guard let save = getenv("DM_SAVE") else { fputs("launcher: save sync: no DM_SAVE\n", stderr); return nil }
        guard let id = info("DMTitleID"), !id.isEmpty else { fputs("launcher: save sync: no DMTitleID\n", stderr); return nil }
        // the folder as launcher.c will pass it (cloud_saves_folder): DM_SAVE_SYNC from the launch environment or an env file, else the window's choice; "0" = off
        let folder = getenv("DM_SAVE_SYNC").map { String(cString: $0) } ?? MacCloudRoute.current().active
        var buf = [CChar](repeating: 0, count: 1024)
        let r = (folder.isEmpty ? "0" : folder).withCString { save_sync_report(save, id, $0, SaveSyncReport.waitMs, &buf, buf.count) }
        let line = String(cString: buf)
        guard r == 0 else { fputs("launcher: save sync: no report on \(String(cString: save))\n", stderr); return nil }
        fputs("launcher: save sync: \(line)\n", stderr)
        return SaveSyncReport(line: line)
    }

    /// The question the report needs, as a modal alert; `cancel` names the way back ("Cancel" to the window, "Quit" without one)
    static func ask(_ r: SaveSyncReport?, cancel: String) -> Outcome {
        switch SaveSyncReport.step(r) {
        case .play(let choice): return .play(choice)
        case .choose:
            guard let r else { return .play(nil) }
            let a = NSAlert()
            a.messageText = SaveSyncReport.chooseTitle
            a.informativeText = r.chooseMessage(here: "Mac")
            a.alertStyle = .warning
            a.addButton(withTitle: r.localLabel(here: "Mac"))
            a.addButton(withTitle: r.cloudLabel)
            a.addButton(withTitle: cancel)
            a.buttons[0].keyEquivalent = ""   // no default: Return must not pick a save (the newer is not always the one to keep)
            a.buttons[2].keyEquivalent = "\u{1b}"
            switch a.runModal() {
            case .alertFirstButtonReturn: return .play(r.localChoice)
            case .alertSecondButtonReturn: return .play(r.cloudChoice)
            default: return .cancel
            }
        case .unreadable:
            let a = NSAlert()
            a.messageText = SaveSyncReport.unreadableTitle
            a.informativeText = r?.unreadableMessage(here: "Mac") ?? ""
            a.addButton(withTitle: "Play This Mac's Save")
            a.addButton(withTitle: "Try Again")
            a.addButton(withTitle: cancel)
            a.buttons[2].keyEquivalent = "\u{1b}"
            switch a.runModal() {
            case .alertFirstButtonReturn: return .play("offline")   // the mount does not wait for the cloud again
            case .alertSecondButtonReturn: return .retry
            default: return .cancel
            }
        }
    }

    static func apply(_ choice: String?) {
        guard let choice else { return }
        setenv("DM_SAVE_SYNC_CHOICE", choice, 1)
        fputs("launcher: DM_SAVE_SYNC_CHOICE=\(choice)\n", stderr)
    }

    /// With the window off: the check and its question before the game, the app in front only while it asks. false: the player quit
    static func withoutWindow() -> Bool {
        final class Box: @unchecked Sendable { let lock = NSLock(); var report: SaveSyncReport?; var waiting = false }
        let app = NSApplication.shared
        defer { app.setActivationPolicy(.prohibited) }
        while true {
            let box = Box(), sem = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                let r = report()
                box.lock.lock(); box.report = r; box.lock.unlock()
                sem.signal()
                DispatchQueue.main.async { if box.waiting { app.abortModal() } }   // runs inside the waiting alert's modal loop, if there is one
            }
            if sem.wait(timeout: .now() + 0.5) == .timedOut {   // a cloud file to download: say so, and let the player go on without it
                app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = "Checking the cloud save…"
                a.informativeText = "Waiting for iCloud to deliver this game's save."
                a.addButton(withTitle: "Play Without It")
                a.addButton(withTitle: "Quit")
                box.waiting = true
                let answer = a.runModal()
                box.waiting = false
                if answer == .alertFirstButtonReturn { apply("offline"); return true }
                if answer == .alertSecondButtonReturn { return false }
                sem.wait()   // aborted: the report is in
            }
            box.lock.lock(); let r = box.report; box.lock.unlock()
            if case .play(let choice) = SaveSyncReport.step(r) { apply(choice); return true }
            app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
            switch ask(r, cancel: "Quit") {
            case .play(let choice): apply(choice); return true
            case .retry: continue
            case .cancel: return false
            }
        }
    }
}

struct LauncherView: View {
    enum Page: Hashable, Identifiable {
        case settings(String), cloud, support

        var id: String {
            switch self {
            case .settings(let name): "settings." + name
            case .cloud: "cloud"
            case .support: "support"
            }
        }

        var title: String {
            switch self {
            case .settings(let name): name
            case .cloud: "Cloud Saves"
            case .support: "Support"
            }
        }

        var symbol: String {
            switch self {
            case .settings("Game"): "display"
            case .settings("Controls"): "gamecontroller"
            case .settings("Performance"): "gauge.with.dots.needle.50percent"
            case .settings: "slider.horizontal.3"
            case .cloud: "icloud"
            case .support: "questionmark.circle"
            }
        }

        var focus: LauncherFocus { .summary(id) }

        func rows(_ model: LauncherModel, advanced: Bool) -> [Setting] {
            guard case .settings(let section) = self else { return [] }
            let visible = model.rows(in: section)
            let basic = visible.filter(\.basic)
            return advanced || basic.isEmpty ? visible : basic
        }

        func offersAdvanced(_ model: LauncherModel) -> Bool {
            guard case .settings(let section) = self else { return false }
            let visible = model.rows(in: section)
            return visible.contains(where: \.basic) && visible.contains { !$0.basic }
        }
    }

    @ObservedObject var m: LauncherModel
    var problem: String? = nil
    var name = info("CFBundleName") ?? "Game"
    var version = info("CFBundleShortVersionString") ?? ""
    let done: (Bool) -> Void
    @AppStorage("window.show") private var show = true
    @AppStorage("window.advanced") private var advanced = false
    @AppStorage("cloudSaves.folder") private var cloudFolder = ""
    @StateObject private var nav = LauncherNav()
    @StateObject private var controllers = ControllerListModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var page: Page?
    @State private var choosing = false
    @State private var checking = false
    @State private var check = 0

    private let icon = NSApp.applicationIconImage
    private let tint = GameTint.from(NSApp.applicationIconImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))

    static func pages(for model: LauncherModel) -> [Page] { model.sections.map(Page.settings) + [.cloud, .support] }

    private var pages: [Page] { Self.pages(for: m) }
    private var selected: Page { page ?? pages[0] }

    private var focusOrder: [LauncherFocus] {
        var order: [LauncherFocus] = [.play]
        if problem == nil {
            order += pages.map(\.focus)
            if selected.offersAdvanced(m) { order.append(.advanced) }
            order += selected.rows(m, advanced: advanced).filter { !m.fixed.contains($0.env) }.map { .row($0.env) }
            if selected == .settings("Controls") && !controllers.merge {
                order += controllers.rows.filter { $0.player >= 0 }.map { .controller($0.id) }
            }
            if selected == .cloud && CloudSavesSection.fixed == nil {
                order.append(.cloud)
                if !cloudFolder.isEmpty { order.append(.cloudOff) }
            }
            if selected == .support { order += SupportLink.allCases.map { .support($0.rawValue) } }
            if m.changed { order.append(.reset) }
        }
        return order + [.showAtLaunch, .quit]
    }

    private func select(_ next: Page) {
        page = next
        if nav.active { nav.focus = next.focus }
    }

    private func play() {
        controllers.merge = m.values["DM_PAD_MERGE"] == "1"
        controllers.apply()
        done(true)
    }

    private func start() {
        guard !checking else { return }
        check += 1
        checking = true
        let mine = check
        DispatchQueue.global(qos: .userInitiated).async {
            let report = SaveCheck.report()
            DispatchQueue.main.async {
                guard checking, check == mine else { return }
                checking = false
                switch SaveCheck.ask(report, cancel: "Cancel") {
                case .play(let choice): SaveCheck.apply(choice); play()
                case .retry: start()
                case .cancel: break
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            LauncherHero(icon: icon, name: name, version: version)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 14)

            if let problem {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This app's settings list cannot be read.", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("Play uses your saved choices. Pack the game again to restore its settings. (\(problem))")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            } else {
                navigation
                Divider()
                settings
            }

            footer
        }
        .frame(minWidth: 580, minHeight: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            nav.order = { focusOrder }
            nav.play = start
            nav.adjust = { focus, direction in
                if case .controller(let id) = focus { controllers.step(id, direction) }
                if case .row(let env) = focus, let setting = m.settings.first(where: { $0.env == env }) {
                    m.step(setting, by: direction)
                }
            }
            nav.activate = activate
        }
        .task { await nav.run() }
        .onChange(of: m.values["DM_PAD_MERGE"]) { _, value in
            controllers.merge = value == "1"
            controllers.refresh()
        }
        .task {
            controllers.merge = m.values["DM_PAD_MERGE"] == "1"
            while !Task.isCancelled {
                controllers.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(pages) { entry in
                            Button { select(entry) } label: {
                                Label(entry.title, systemImage: entry.symbol)
                                    .font(.system(.subheadline, weight: selected == entry ? .semibold : .medium))
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(selected == entry ? .primary : .secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selected == entry ? tint.mark.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected == entry ? .isSelected : [])
                            .focusRing(nav.isFocused(entry.focus), tint, radius: 9)
                            .id(entry.id)
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.hidden)
                .onChange(of: nav.focus) { _, focus in
                    if case .summary(let id) = focus { proxy.scrollTo(id, anchor: .center) }
                }
            }
            if selected.offersAdvanced(m) {
                Toggle("Advanced", isOn: $advanced)
                    .toggleStyle(.checkbox)
                    .focusRing(nav.isFocused(.advanced), tint, radius: 6)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 22)
        .padding(.bottom, 4)
    }

    private var settings: some View {
        ScrollViewReader { proxy in
            ScrollView {
                switch selected {
                case .settings:
                    VStack(alignment: .leading, spacing: 0) {
                        let rows = selected.rows(m, advanced: advanced)
                        ForEach(rows) { setting in
                            SettingRow(s: setting, m: m, tint: tint, focused: nav.isFocused(.row(setting.env)))
                                .padding(.vertical, 10)
                            if setting.id != rows.last?.id { Divider().opacity(0.65) }
                        }
                        if selected == .settings("Controls") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Connected Controllers").font(.headline).accessibilityAddTraits(.isHeader)
                                ConnectedControllers(controllers: controllers, tint: tint) { nav.isFocused(.controller($0)) }
                            }
                            .padding(.vertical, 12)
                        } else if rows.isEmpty {
                            Text("No settings are available in this category.").foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                    }
                case .cloud:
                    CloudSavesSection(tint: tint, focused: nav.isFocused(.cloud), offFocused: nav.isFocused(.cloudOff), choose: $choosing)
                case .support:
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(SupportLink.allCases) { link in
                            Link(destination: link.url) {
                                Label { Text(link.title) } icon: { SupportChip(link: link, size: 22) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .help(link.subtitle)
                            .focusRing(nav.isFocused(.support(link.rawValue)), tint)
                            .id(LauncherFocus.support(link.rawValue).scrollID)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .defaultScrollAnchor(.top)
            .id(selected)
            .onChange(of: nav.focus) { _, focus in
                guard let focus else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    proxy.scrollTo(focus.scrollID, anchor: .center)
                }
            }
            .contentMargins(.horizontal, 26, for: .scrollContent)
            .contentMargins(.vertical, 8, for: .scrollContent)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            if checking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking the cloud save…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Play Without It") { checking = false; SaveCheck.apply("offline"); play() }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            HStack(spacing: 12) {
                Toggle("Show at launch", isOn: $show).toggleStyle(.checkbox)
                    .help("Show this window when opening the game")
                    .focusRing(nav.isFocused(.showAtLaunch), tint, radius: 6)
                Spacer()
                if problem == nil {
                    Button("Reset Defaults") { m.reset() }
                        .disabled(!m.changed)
                        .help("Restore this game's tested settings")
                        .focusRing(nav.isFocused(.reset), tint, radius: 8)
                }
                Button("Quit") { done(false) }.keyboardShortcut(.cancelAction)
                    .focusRing(nav.isFocused(.quit), tint, radius: 8)
                Button(action: start) {
                    Label("Play", systemImage: "play.fill")
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 9))
                .controlSize(.large)
                .tint(tint.fill)
                .keyboardShortcut(.defaultAction)
                .disabled(checking)
                .focusRing(nav.isFocused(.play), tint, radius: 9)
                .accessibilityHint("Starts the game with these settings")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            PadHint(nav: nav).padding(.bottom, nav.active ? 10 : 0)
        }
    }

    private func activate(_ focus: LauncherFocus) {
        switch focus {
        case .summary(let id):
            if let target = pages.first(where: { $0.id == id }) { select(target) }
        case .controller(let id): controllers.step(id, 1)
        case .row(let env):
            guard let setting = m.settings.first(where: { $0.env == env }), setting.kind != "range" else { return }
            m.step(setting, by: setting.kind == "toggle" && m.value(setting) == setting.onValue ? -1 : 1)
        case .advanced: advanced.toggle()
        case .reset: m.reset()
        case .cloud: if CloudSavesSection.fixed == nil { choosing = true }
        case .cloudOff:
            for key in ["cloudSaves.primaryRoot", "cloudSaves.fallbackRoot", "cloudSaves.fromLibrary"] { UserDefaults.standard.removeObject(forKey: key) }
            cloudFolder = ""; nav.focus = .cloud
        case .showAtLaunch: show.toggle()
        case .quit: done(false)
        case .support(let id): if let link = SupportLink(rawValue: id) { openURL(link.url) }
        default: break
        }
    }
}

private struct LauncherHero: View {
    let icon: NSImage?
    let name: String
    let version: String

    var body: some View {
        HStack(spacing: 17) {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !version.isEmpty {
                    Text("Version \(version)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(17)
        .background {
            ZStack(alignment: .trailing) {
                Color(red: 0.045, green: 0.068, blue: 0.12)
                if let icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 265, height: 265)
                        .blur(radius: 52)
                        .opacity(0.35)
                }
                LinearGradient(
                    colors: [Color(red: 0.045, green: 0.068, blue: 0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.09))
                .allowsHitTesting(false)
        }
    }
}

/// Cloud saves: a folder the save is synced through (dm/host/save_sync.h), the one the iPhone app picks in its launcher's Cloud Saves section. It is kept in this app's
/// preferences as cloudSaves.folder, which launcher.c puts into DM_SAVE_SYNC before the host starts; a DM_SAVE_SYNC an env file or the launch environment set wins, and is shown here.
struct CloudSavesSection: View {
    let tint: GameTint
    let focused: Bool
    var offFocused = false
    @Binding var choose: Bool
    @AppStorage("cloudSaves.folder") private var folder = ""
    static let fixed: String? = {
        let env = ProcessInfo.processInfo.environment
        let keys = ((env["DM_ENV_FILE_KEYS"] ?? "") + " " + (env["DM_ENV_LAUNCH_KEYS"] ?? "")).split(separator: " ")
        return keys.contains("DM_SAVE_SYNC") || env["DM_SAVE_SYNC"] != nil ? env["DM_SAVE_SYNC"] : nil
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Folder") {
                Text(Self.fixed.map { $0 == "0" || $0.isEmpty ? "Off" : Self.shown($0) } ?? (folder.isEmpty ? "Off" : Self.shown(folder)))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            if Self.fixed != nil {
                Label("DM_SAVE_SYNC is set by an env file or at launch, so this start uses it.", systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button(folder.isEmpty ? "Choose a Folder…" : "Choose a Different Folder…", action: pick)
                        .focusRing(focused, tint, radius: 8)
                    if !folder.isEmpty { Button("Turn Off") { clearRouting(); folder = "" }.focusRing(offFocused, tint, radius: 8) }
                }
            }
            Text("Choose the same iCloud Drive folder on each device to share saves. A replaced save is kept in save-backups.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .id("cloud")
        .onChange(of: choose) { _, now in if now { choose = false; pick() } }
    }

    private func clearRouting() {
        for key in ["cloudSaves.primaryRoot", "cloudSaves.fallbackRoot", "cloudSaves.fromLibrary"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "Use for Cloud Saves"
        panel.message = "The folder the iPhone app chose in its launcher's Cloud Saves"
        panel.directoryURL = URL(fileURLWithPath: folder.isEmpty ? Self.drive : folder)
        if panel.runModal() == .OK, let url = panel.url { clearRouting(); folder = url.path }
    }

    static let drive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"   // iCloud Drive, as the Finder shows it

    /// A path under iCloud Drive as the Finder and the Files app name it: iCloud Drive › Documents › dev › Zelda; any other path as it is
    static func shown(_ path: String) -> String {
        let native = CloudFolders.native().path
        if path == native || path.hasPrefix(native + "/") {
            return (["iCloud Drive", "AetherNX"] + path.dropFirst(native.count).split(separator: "/").map(String.init)).joined(separator: " › ")
        }
        guard path == drive || path.hasPrefix(drive + "/") else { return path }
        return (["iCloud Drive"] + path.dropFirst(drive.count).split(separator: "/").map(String.init)).joined(separator: " › ")
    }
}

private final class Launcher: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: LauncherModel
    let problem: String?
    var window: NSWindow?
    var play = false

    init(_ model: LauncherModel, problem: String?) { self.model = model; self.problem = problem }

    func applicationDidFinishLaunching(_ n: Notification) {
        let name = info("CFBundleName") ?? "Game"
        let menu = NSMenu(), item = NSMenuItem(), app = NSMenu()
        app.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        app.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = app; menu.addItem(item); NSApp.mainMenu = menu
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 510), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "AetherNX"; w.isReleasedWhenClosed = false; w.delegate = self
        w.contentMinSize = NSSize(width: 580, height: 430)
        window = w
        if let screen = w.screen ?? NSScreen.main {
            w.setFrame(LauncherWindowLayout.initial(w.frame.size, visible: screen.visibleFrame), display: false)
        }
        let host = NSHostingView(rootView: LauncherView(m: model, problem: problem, done: { [weak self] in self?.finish($0) }))
        host.sizingOptions = []
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        // no activation and no ordering in front of another app's windows: LaunchServices activates an app opened from Finder or the Dock (applicationDidBecomeActive), open -g does not
        if NSApp.isActive { w.makeKeyAndOrderFront(nil) } else { w.orderBack(nil) }
    }
    func applicationDidBecomeActive(_ n: Notification) { window?.makeKeyAndOrderFront(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {   // ⌘Q, or a logout or restart: the app ends without the game (exit 0, as Quit)
        fputs("launcher: quit without starting the game\n", stderr)
        return .terminateNow   // not terminateCancel, which a logout or restart takes as a refusal and stops
    }
    func windowWillClose(_ n: Notification) { finish(false) }

    func finish(_ play: Bool) {
        guard let w = window else { return }
        window = nil; self.play = play
        // The main thread blocks in launcher.c's waitpid once run() returns, so the window must leave the screen now: no fade-out (it runs on later run-loop passes),
        // and dmMacLauncher flushes the order-out (AppKit commits it at the end of a pass). Without both, the window stayed on screen, not responding, until the game ended
        w.animationBehavior = .none
        w.delegate = nil; w.orderOut(nil)
        NSApp.stop(nil)
        NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)   // run returns at the next event
    }
}

enum LauncherWindowLayout {
    static func initial(_ preferred: NSSize, visible: NSRect) -> NSRect {
        let width = min(preferred.width, visible.width)
        let height = min(preferred.height, visible.height)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }
}

// 1: Play (the window's settings are in the environment), 0: the player quit, 2: start without the window's settings (no launcher.json, "Show this window at launch" off, or Play in a window
// whose settings list could not be read): launcher.c applies the saved choices
@_cdecl("dm_mac_launcher")
public func dmMacLauncher() -> Int32 {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url) else { return 2 }   // packed without settings: nothing to choose
    if (UserDefaults.standard.object(forKey: "window.show") as? Bool) == false && !NSEvent.modifierFlags.contains(.option) {
        fputs("launcher: settings window off (hold Option at launch to show it)\n", stderr)
        return SaveCheck.withoutWindow() ? 2 : 0
    }
    var settings: [Setting] = [], problem: String?
    do { settings = try JSONDecoder().decode(SettingsFile.self, from: data).settings }
    catch { problem = "dm/launcher.json: \(error.localizedDescription)"; fputs("[RED] launcher: \(problem!)\n", stderr) }
    if problem == nil && settings.isEmpty { return 2 }
    let model = LauncherModel(settings)
    let app = NSApplication.shared, launcher = Launcher(model, problem: problem)
    app.setActivationPolicy(.regular)
    app.delegate = launcher
    fputs("launcher: \(settings.count) settings shown\(problem == nil ? "" : " (the settings list cannot be read)")\n", stderr)
    app.run()
    CATransaction.flush()   // finish's order-out
    app.setActivationPolicy(.prohibited)   // the host is the game's app from here on
    guard launcher.play else { fputs("launcher: quit without starting the game\n", stderr); return 0 }
    if problem != nil { return 2 }
    model.apply()
    return 1
}

private struct MacCloudRoute {
    let active: String
    var standby: String? = nil
    var usesStandby = false
    var hasFallback = false

    static func current() -> Self {
        let defaults = UserDefaults.standard
        let configured = defaults.string(forKey: "cloudSaves.folder") ?? ""
        guard !configured.isEmpty else { return Self(active: "") }
        let primary = defaults.string(forKey: "cloudSaves.primaryRoot")
        guard let primary, !primary.isEmpty, let id = info("DMTitleID") else { return Self(active: configured) }

        let fallback = defaults.string(forKey: "cloudSaves.fallbackRoot")
        let paths = CloudFolders.destinations(primary: primary, fallback: fallback, name: info("CFBundleName") ?? "Game", titleID: id)
        let main = paths.primary?.path
        let standby = paths.fallback?.path
        return Self(active: main ?? standby ?? "0", standby: main != nil && standby != main ? standby : nil,
                    usesStandby: main == nil && standby != nil, hasFallback: fallback != nil)
    }
}

/// Freeze the host's route for this launch. An explicit DM_SAVE_SYNC keeps its original precedence.
@_cdecl("dm_mac_resolve_cloud_folder")
public func dmMacResolveCloudFolder() {
    guard getenv("DM_SAVE_SYNC") == nil else { return }
    let route = MacCloudRoute.current()
    guard !route.active.isEmpty else { return }
    setenv("DM_SAVE_SYNC", route.active, 1)
    if let standby = route.standby { setenv("DM_SAVE_SYNC_MIRROR", standby, 1) }
    if route.hasFallback {
        setenv("DM_SAVE_SYNC_CHOICE", "ask", 0)
        setenv("DM_SAVE_SYNC_PAIRED", "1", 1)
    }
    if route.usesStandby { fputs("launcher: using the secondary cloud provider\n", stderr) }
    if route.active == "0" { fputs("launcher: configured cloud folders are unavailable\n", stderr) }
    else { fputs("launcher: cloud saves through \(route.active)\n", stderr) }
}

// The mods of the game folder's Mods/mods.json (GameExtras.swift macOverlay), which AetherNX Studio and AetherNX Companion write: launcher.c mods_and_cheats takes them
// before Studio's mods.folders, so a change made on the iPhone applies at the next start without Studio opened. The game folder is the one beside the cloud save
// (DM_SAVE_SYNC, set before this from cloudSaves.folder), or the app's own in Application Support. Writes the RomFS folders, ':'-separated, into out: 1 (an empty string
// when every mod is off), 0 when the folder has no mods.json it can use (launcher.c then takes mods.folders), -1 when they do not fit
@_cdecl("dm_mac_game_mods")
public func dmMacGameMods(_ titleID: UnsafePointer<CChar>, _ out: UnsafeMutablePointer<CChar>, _ cap: Int) -> Int32 {
    guard let overlay = GameExtras.macOverlay(saveSync: getenv("DM_SAVE_SYNC").map { String(cString: $0) }, titleID: String(cString: titleID)) else { return 0 }
    let bytes = Array(overlay.joined(separator: ":").utf8CString)
    guard bytes.count <= cap else { return -1 }
    bytes.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: bytes.count) }
    return 1
}
