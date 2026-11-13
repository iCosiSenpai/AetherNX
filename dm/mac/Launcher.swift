// Mac app launcher: the settings window shown before the game starts, in the launcher's own process (launcher.c calls dm_mac_launcher before it starts the host). Its settings come from the
// app's Resources/dm/launcher.json (dm/games/settings.py with SETTINGS_PLATFORM=mac); the model and the shared parts are the iOS launcher's (dm/ios/Sources/LauncherSettings.swift,
// LauncherRow.swift), and so is the store: launcher.<VAR> in the app's preferences, which launcher.c reads when the window is not shown (docs/frontends.md, Saved choices).
// The window is the game's product card, as on the iPhone: the header (icon, name, version, Play), the summary strip of what Play starts with, then the settings: basic ones (level basic)
// first, the others under Advanced settings, each in the list's sections. Play puts the settings into this process's environment, which the host inherits; Quit and closing the window end
// the app without the game. A game controller moves through the window as on the iPhone (LauncherNav). "Show this window at launch" off: no window unless Option is held at launch, and
// launcher.c applies the saved choices. A settings list that cannot be read is shown as such, with Play (saved choices, as without the window) and Quit. The window never takes focus by
// itself: an app opened in the background (open -g) keeps its window behind until the player switches to it
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
        let folder = getenv("DM_SAVE_SYNC").map { String(cString: $0) } ?? (UserDefaults.standard.string(forKey: "cloudSaves.folder") ?? "")
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
    @ObservedObject var m: LauncherModel
    var problem: String? = nil   // the settings list could not be read: the window says so, Play starts the game as launcher.c would without the window
    let done: (Bool) -> Void
    let fit: (CGFloat) -> Void
    @AppStorage("window.show") private var show = true
    @AppStorage("window.advanced") private var advanced = false
    @AppStorage("cloudSaves.folder") private var cloudFolder = ""
    @StateObject private var nav = LauncherNav()
    @StateObject private var controllers = ControllerListModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private let tint = GameTint.from(NSApp.applicationIconImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))

    private var items: [SummaryItem] {
        let cloud = CloudSavesSection.fixed.map { $0 == "0" || $0.isEmpty ? "Off" : "env.txt" } ?? (cloudFolder.isEmpty ? "Off" : "On")
        return m.summaryItems() + [SummaryItem(id: "cloud", value: cloud, caption: "Cloud saves", locked: CloudSavesSection.fixed != nil)]
    }
    private var hasAdvanced: Bool { m.settings.contains { !$0.basic } }
    // The rows as drawn: the basic ones, or with Advanced settings open every row, each in its own section (one Game, one Controls)
    private var drawnSections: [String] { advanced ? m.sections : m.sections(basic: true) }
    private func drawnRows(_ section: String) -> [Setting] { advanced ? m.rows(in: section) : m.rows(in: section, basic: true) }
    private var focusOrder: [LauncherFocus] {
        var o: [LauncherFocus] = [.play]
        o += items.map(\.focus)
        for section in drawnSections {
            o += drawnRows(section).map { .row($0.env) }
            if section == "Controls" { o += controllers.rows.map { .controller($0.id) } }
        }
        if hasAdvanced { o.append(.advanced) }
        if CloudSavesSection.fixed == nil { o.append(.cloud); if !cloudFolder.isEmpty { o.append(.cloudOff) } }
        if m.changed { o.append(.reset) }
        o += SupportLink.allCases.map { .support($0.rawValue) }
        o += [.showAtLaunch, .quit]
        return o
    }

    @State private var checking = false
    @State private var check = 0   // which Play the running check is for: one the player went on from without it is dropped

    /// The game starts with these settings and controller choices
    private func play() { controllers.merge = m.values["DM_PAD_MERGE"] == "1"; controllers.apply(); done(true) }
    /// Play, once the cloud's save is compared with this Mac's: a save that changed on both sides is the player's pick, not the newer file's (SaveCheck)
    private func start() {
        guard !checking else { return }
        check += 1; checking = true
        let mine = check
        DispatchQueue.global(qos: .userInitiated).async {
            let r = SaveCheck.report()
            DispatchQueue.main.async {
                guard checking, check == mine else { return }   // the player played without it
                checking = false
                switch SaveCheck.ask(r, cancel: "Cancel") {
                case .play(let choice): SaveCheck.apply(choice); play()
                case .retry: start()
                case .cancel: break   // back to the window, nothing chosen
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(icon: Image(nsImage: NSApp.applicationIconImage), name: info("CFBundleName") ?? "Game", version: info("CFBundleShortVersionString") ?? "", iconSize: 64, stackBelow: 400) {
                Button(action: start) { Label("Play", systemImage: "play.fill").padding(.horizontal, 10).frame(minHeight: 24) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .tint(tint.fill)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking)
                    .focusCapsule(nav.isFocused(.play), tint)
                    .accessibilityHint("Starts the game with these settings")
            }
            .padding([.horizontal, .top], 20).padding(.bottom, 12)
            if !items.isEmpty {
                SummaryStrip(items: items, tint: tint, nav: nav) { it in nav.focus = it.id == "cloud" ? .cloud : .row(it.id) }
                    .padding(.horizontal, 8)
                PadHint(nav: nav).padding(.top, 4)
                Divider().padding(.top, 8)
            }
            ScrollViewReader { proxy in
                Form {
                    if let problem {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This app's settings list cannot be read.")
                                    Text("Play starts the game with your saved choices and its tested defaults. Packing the game again restores the list. (\(problem))")
                                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        }
                    }
                    ForEach(drawnSections, id: \.self) { section in
                        let rows = drawnRows(section)
                        if !rows.isEmpty {
                            Section(section) {
                                ForEach(rows) { SettingRow(s: $0, m: m, tint: tint, focused: nav.isFocused(.row($0.env))) }
                                if section == "Controls" { ConnectedControllers(controllers: controllers, tint: tint) { nav.isFocused(.controller($0)) } }
                            }
                        }
                    }
                    if hasAdvanced {
                        Section {
                            DisclosureGroup("Advanced settings", isExpanded: $advanced) {}
                                .focusRing(nav.isFocused(.advanced), tint, radius: 8)
                                .id("advanced")
                        } footer: {
                            Text(advanced ? "Every setting is shown, in its section above." : "Shows the other settings in their sections above.")
                        }
                    }
                    CloudSavesSection(tint: tint, focused: nav.isFocused(.cloud), offFocused: nav.isFocused(.cloudOff), choose: $choosing)
                    Section {   // always here: the tested defaults are one action away, also for a basic setting changed with Advanced closed
                        Button("Reset to Tested Defaults") { m.reset() }
                            .disabled(!m.changed)
                            .focusRing(nav.isFocused(.reset), tint, radius: 8)
                            .id("reset")
                    } footer: {
                        Text("Brings back every setting this game was tested with. Values set by an env file or at launch stay.")
                    }
                    SupportSection(tint: tint) { nav.isFocused(.support($0.rawValue)) }
                }
                .formStyle(.grouped)
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom - $0.containerSize.height
                } action: { _, extraHeight in
                    fit(extraHeight)
                }
                .onChange(of: advanced) { _, _ in   // the rows appear above the disclosure: keep the control just used in view
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("advanced", anchor: .bottom) }
                }
                .onChange(of: nav.focus) { _, f in
                    guard let f else { return }
                    if case .row(let e) = f, m.settings.contains(where: { $0.env == e && !$0.basic }), !advanced { advanced = true }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(f.scrollID, anchor: .center) }
                }
            }
            Divider()
            HStack {
                Toggle("Show this window at launch", isOn: $show).toggleStyle(.checkbox)
                    .focusRing(nav.isFocused(.showAtLaunch), tint, radius: 6)
                Spacer()
                if checking {
                    ProgressView().controlSize(.small)
                    Text("Checking the cloud save…").foregroundStyle(.secondary)
                    Button("Play Without It") { checking = false; SaveCheck.apply("offline"); play() }
                }
                Button("Quit") { done(false) }.keyboardShortcut(.cancelAction)
                    .focusRing(nav.isFocused(.quit), tint, radius: 8)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .id("footer")
        }
        .frame(minWidth: 520, idealWidth: 560)
        .background(Color(nsColor: .textBackgroundColor))   // the grouped Form's own ground, behind the header and the bottom bar too
        .onAppear {
            nav.order = { focusOrder }
            nav.play = start
            nav.adjust = { f, d in
                if case .controller(let id) = f { controllers.step(id, d) }
                if case .row(let e) = f, let s = m.settings.first(where: { $0.env == e }) { m.step(s, by: d) }
            }
            nav.activate = { f in
                switch f {
                case .controller(let id): controllers.step(id, 1)
                case .summary(let e): nav.focus = e == "cloud" ? .cloud : .row(e)
                case .row(let e):
                    guard let s = m.settings.first(where: { $0.env == e }), s.kind != "range" else { return }
                    m.step(s, by: s.kind == "toggle" ? (m.value(s) == s.onValue ? -1 : 1) : 1)
                case .advanced: advanced.toggle()
                case .reset: m.reset()
                case .cloud: if CloudSavesSection.fixed == nil { choosing = true }
                case .cloudOff: cloudFolder = ""; nav.focus = .cloud
                case .showAtLaunch: show.toggle()
                case .quit: done(false)
                case .support(let e): if let l = SupportLink(rawValue: e) { openURL(l.url) }
                default: break
                }
            }
        }
        .task { await nav.run() }
        .onChange(of: m.values["DM_PAD_MERGE"]) { _, v in controllers.merge = v == "1"; controllers.refresh() }
        .task {
            controllers.merge = m.values["DM_PAD_MERGE"] == "1"
            while !Task.isCancelled { controllers.refresh(); try? await Task.sleep(for: .seconds(1)) }
        }
    }

    @State private var choosing = false

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
        Section {
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
                    if !folder.isEmpty { Button("Turn Off") { folder = "" }.focusRing(offFocused, tint, radius: 8) }
                }
            }
        } header: {
            Text("Cloud Saves")
        } footer: {
            Text("Choose the iCloud Drive folder the iPhone app uses for this game. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups.")
        }
        .id("cloud")
        .onChange(of: choose) { _, now in if now { choose = false; pick() } }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "Use for Cloud Saves"
        panel.message = "The folder the iPhone app chose in its launcher's Cloud Saves"
        panel.directoryURL = URL(fileURLWithPath: folder.isEmpty ? Self.drive : folder)
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    static let drive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"   // iCloud Drive, as the Finder shows it

    /// A path under iCloud Drive as the Finder and the Files app name it: iCloud Drive › Documents › dev › Zelda; any other path as it is
    static func shown(_ path: String) -> String {
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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = name; w.isReleasedWhenClosed = false; w.delegate = self
        w.contentMinSize = NSSize(width: 520, height: 0)
        window = w
        if let screen = w.screen ?? NSScreen.main {
            w.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.midX - w.frame.width / 2, y: screen.visibleFrame.maxY))
        }
        let host = NSHostingView(rootView: LauncherView(m: model, problem: problem, done: { [weak self] in self?.finish($0) }, fit: { [weak self] in self?.fit($0) }))
        host.sizingOptions = []   // the Form's measured scroll content owns the height, including after collapse
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

    func fit(_ extraHeight: CGFloat) {
        guard let w = window, let screen = w.screen else { return }
        let frame = LauncherWindowLayout.fitted(w.frame, extraHeight: extraHeight, visible: screen.visibleFrame)
        if abs(frame.height - w.frame.height) > 0.5 { w.setFrame(frame, display: true) }
    }

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
    static func fitted(_ frame: NSRect, extraHeight: CGFloat, visible: NSRect) -> NSRect {
        let top = min(frame.maxY, visible.maxY)
        let height = min(frame.height + extraHeight, top - visible.minY)
        return NSRect(x: frame.minX, y: top - height, width: frame.width, height: height)
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
