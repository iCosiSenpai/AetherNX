// Mac app launcher: the settings window shown before the game starts, in the launcher's own process (launcher.c calls dm_mac_launcher before it starts the host). Its settings come from the
// app's Resources/dm/launcher.json (dm/games/settings.py with SETTINGS_PLATFORM=mac); the model and the shared parts are the iOS launcher's (dm/ios/Sources/LauncherSettings.swift,
// LauncherRow.swift), and so is the store: launcher.<VAR> in the app's preferences, which launcher.c reads when the window is not shown (docs/frontends.md, Saved choices).
// The window is the game's product card, as on the iPhone: the header (icon, name, version, Play), the summary strip of what Play starts with, then the settings: basic ones (level basic)
// first, the others under Advanced settings, each in the list's sections. Play puts the settings into this process's environment, which the host inherits; Quit and closing the window end
// the app without the game. A game controller moves through the window as on the iPhone (LauncherNav). "Show this window at launch" off: no window unless Option is held at launch, and
// launcher.c applies the saved choices. A settings list that cannot be read is shown as such, with Play (saved choices, as without the window) and Quit. The window never takes focus by
// itself: an app opened in the background (open -g) keeps its window behind until the player switches to it
import AppKit
import SwiftUI

private func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }

struct LauncherView: View {
    @ObservedObject var m: LauncherModel
    var problem: String? = nil   // the settings list could not be read: the window says so, Play starts the game as launcher.c would without the window
    let done: (Bool) -> Void
    let fit: (CGFloat) -> Void
    @AppStorage("window.show") private var show = true
    @AppStorage("window.advanced") private var advanced = false
    @AppStorage("cloudSaves.folder") private var cloudFolder = ""
    @StateObject private var nav = LauncherNav()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        for section in drawnSections { o += drawnRows(section).map { .row($0.env) } }
        if hasAdvanced { o.append(.advanced) }
        if CloudSavesSection.fixed == nil { o.append(.cloud); if !cloudFolder.isEmpty { o.append(.cloudOff) } }
        if m.changed { o.append(.reset) }
        o += [.showAtLaunch, .quit]
        return o
    }

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(icon: Image(nsImage: NSApp.applicationIconImage), name: info("CFBundleName") ?? "Game", version: info("CFBundleShortVersionString") ?? "", iconSize: 64, stackBelow: 400) {
                Button { done(true) } label: { Label("Play", systemImage: "play.fill").padding(.horizontal, 10).frame(minHeight: 24) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .tint(tint.fill)
                    .keyboardShortcut(.defaultAction)
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
            nav.play = { done(true) }
            nav.adjust = { f, d in if case .row(let e) = f, let s = m.settings.first(where: { $0.env == e }) { m.step(s, by: d) } }
            nav.activate = { f in
                switch f {
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
                default: break
                }
            }
        }
        .task { await nav.run() }
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
        return 2
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
    app.setActivationPolicy(.prohibited)   // the host is the game's app from here on
    guard launcher.play else { fputs("launcher: quit without starting the game\n", stderr); return 0 }
    if problem != nil { return 2 }
    model.apply()
    return 1
}
