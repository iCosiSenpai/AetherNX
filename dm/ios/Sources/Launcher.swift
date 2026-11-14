// Launcher: the screen shown before the game starts (front_ios.m dm_show_launcher), laid out as the game's own product card. The header names the game (icon, name, version)
// with Play; the summary strip states what Play starts with (the basic settings, cloud saves, the memory available) and takes the player to each setting; the settings follow,
// grouped by section (rows and shared parts: LauncherRow.swift). When the header scrolls away, the navigation bar takes a small icon and Play.
// Its settings come from the app's dm/launcher.json (an app of several programs: dm/p<N>/launcher.json), which build_ipa.sh writes for this game from dm/games/settings.tsv (dm/games/settings.py): each sets an environment variable the
// host reads when the game starts. A variable an env file set (Documents/env.txt, the bundle's dm/env.txt; main.m lists them in DM_ENV_FILE_KEYS) or the launch environment set is shown,
// locked. Choices that differ from the game's default are kept in UserDefaults; Reset to tested defaults shows the defaults, and Play then forgets them. DM_LAUNCHER=0 in
// Documents/env.txt starts the game at once with the saved choices; DM_SAVED_CHOICES=0 ignores them (and keeps them). A game controller moves through the screen (LauncherNav):
// up and down, left and right to change a value, A to choose, Menu to play.
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

func appIcon() -> UIImage? {   // also the in-game menu's header (InGameMenu.swift)
    if let i = UIImage(named: "AppIcon") { return i }
    guard let icons = info("CFBundleIcons") as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
          let files = primary["CFBundleIconFiles"] as? [String], let last = files.last else { return nil }
    return UIImage(named: last)
}

/// DM_SAVE_SYNC from an env file or the launch environment wins over the folder picked here (CloudSaves.m dm_cloud_saves_env): the section shows it, fixed
private let cloudOverride: String? = {
    let env = ProcessInfo.processInfo.environment
    let keys = ((env["DM_ENV_FILE_KEYS"] ?? "") + " " + (env["DM_ENV_LAUNCH_KEYS"] ?? "")).split(separator: " ")
    return keys.contains("DM_SAVE_SYNC") ? env["DM_SAVE_SYNC"] : nil
}()

/// Cloud saves: an iCloud Drive folder shared with the Mac app (chosen in its settings window's Cloud saves too). The host brings the save in from there when the game starts
/// and sends it there after each save (dm/host/save_sync.h); the folder is a bookmark (CloudSaves.m).
@MainActor private final class CloudSavesState: ObservableObject {
    @Published var folder = ""
    @Published var container = ""   // automatic iCloud's folder (CloudSaves.h): empty when the build has no iCloud container or iCloud is off
    @Published var auto = true
    @Published var note = ""
    @Published var picking = false
    func refresh() {
        var stale: ObjCBool = false
        folder = dm_cloud_saves_path(&stale) ?? ""
        container = dm_cloud_container_path() ?? ""
        auto = dm_cloud_auto()
        if stale.boolValue && folder.isEmpty { note = "The folder chosen before can no longer be read (the app is signed differently now). Choose it again." }
    }
    /// No folder picked, automatic iCloud on and available: the game syncs through the app's iCloud container
    var usingICloud: Bool { folder.isEmpty && auto && !container.isEmpty }
    /// The folder the save syncs through at Play, as dm_cloud_saves_env sets DM_SAVE_SYNC: the game's Mods and Cheats are beside it (GameExtras.swift). nil: none
    var inUse: String? {
        if let o = cloudOverride { return o.hasPrefix("/") ? o : nil }
        return !folder.isEmpty ? folder : usingICloud ? container : nil
    }
    func turnOff() { dm_clear_cloud_saves(); dm_cloud_set_auto(false); refresh(); note = "" }
    func useICloud() { dm_clear_cloud_saves(); dm_cloud_set_auto(true); refresh(); note = "Saved. The game syncs through iCloud when you press Play." }
    var summary: String {
        if let o = cloudOverride { return o == "0" || o.isEmpty ? "Off" : "env.txt" }
        return !folder.isEmpty ? "On" : usingICloud ? "iCloud" : "Off"
    }
}

private struct CloudSavesSection: View {
    @ObservedObject var state: CloudSavesState
    let name: String
    let tint: GameTint
    let focused: Bool
    let offFocused: Bool
    let autoFocused: Bool

    var body: some View {
        Section {
            if let o = cloudOverride {
                LabeledContent("Folder") { Text(o == "0" || o.isEmpty ? "Off" : o == "icloud" ? "icloud (the Mac's iCloud Drive: off here)" : o).lineLimit(2).truncationMode(.head) }
                Label("DM_SAVE_SYNC is set by an env file or at launch, so this start uses it.", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                LabeledContent("Folder") {
                    Text(!state.folder.isEmpty ? (state.folder as NSString).lastPathComponent : state.usingICloud ? "iCloud (automatic)" : "Off").lineLimit(1).truncationMode(.middle)
                }
                Button(state.folder.isEmpty ? "Choose a Folder in iCloud Drive…" : "Choose a Different Folder…") { state.picking = true }
                    .focusRing(focused, tint)
                    // The sheet sits on the button, not on the Section: SwiftUI hands a Section's modifiers to every row, so one tap presented a picker per row and they invalidated each other (LNPANDY/NX2Apple#315).
                    .sheet(isPresented: $state.picking) {
                        // It opens at the game's own folder in iCloud Drive › AetherNX, where its save, mods and cheats are (GameExtras.suggestedFolder). What the picker does with a
                        // folder that is not there (a game Studio names otherwise) is not checked on a device yet: the player can still go to any folder from it
                        DocumentPicker(types: [.folder], directory: GameExtras.suggestedFolder(gameName: name)) { url in
                            state.picking = false
                            if dm_store_cloud_saves(url) { state.note = "Saved. The game uses this folder when you press Play."; state.refresh() }
                            else { state.note = "That folder could not be remembered. Try a different one." }
                        } onCancel: { state.picking = false }
                    }
                if !state.container.isEmpty && !state.usingICloud {
                    Button("Use iCloud Automatically") { state.useICloud() }
                        .focusRing(autoFocused, tint)
                }
                if !state.folder.isEmpty || state.usingICloud {
                    Button("Turn Off Cloud Saves", role: .destructive) { state.turnOff() }
                        .focusRing(offFocused, tint)
                }
            }
        } header: {
            Text("Cloud Saves")
        } footer: {
            Text(!state.note.isEmpty ? state.note : !state.container.isEmpty
                 ? "Saves sync through iCloud by themselves (iCloud Drive › HorizonNative): on the Mac, choose that folder in the app's Cloud Saves. Or choose this game's folder in iCloud Drive › AetherNX (\(GameExtras.folderName(for: name))), which AetherNX on the Mac keeps: its mods and cheats then come with the save. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups."
                 : "Choose this game's folder in iCloud Drive › AetherNX (\(GameExtras.folderName(for: name))), which AetherNX on the Mac keeps: its mods and cheats then come with the save. Any folder in iCloud Drive works for the save, with the same one in the Mac app's Cloud Saves. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups.")
        }
        .id("cloud")
    }
}

/// The app's dm folder (a game of several programs, main.m: the running program's dm/p<N>): its launcher.json, and main's rewriter table with the build ID
private func appDMFolder() -> URL? {
    getenv("DM_APP_DM").map { URL(fileURLWithPath: String(cString: $0)) } ?? Bundle.main.resourceURL?.appendingPathComponent("dm")
}

/// The main module's build ID, which names its cheat file (GameExtras.buildID)
private let mainBuildID: String? = appDMFolder().flatMap { GameExtras.buildID(fixups: $0.appendingPathComponent("main.fixups.tsv").path) }

/// Mods and cheats: the game's folder beside the cloud save (GameExtras.swift), as Play will use it. Read off the main thread when the launcher shows, when
/// the cloud folder changes and when the app comes back to the front (the player may have changed them in AetherNX Companion meanwhile)
@MainActor private final class GameExtrasState: ObservableObject {
    @Published var folder: GameExtras.Folder?
    @Published var cloud: String?
    private var reads = 0
    func refresh(cloud: String?) {
        self.cloud = cloud
        reads += 1
        let mine = reads, tid = String(cString: dm_save_title()), build = mainBuildID
        guard let cloud else { folder = nil; return }
        DispatchQueue.global(qos: .utility).async {
            let f = GameExtras.read(cloud: cloud, titleID: tid, buildID: build, fetch: true)   // asks iCloud for what it listed only, so Play finds it
            DispatchQueue.main.async { if self.reads == mine { self.folder = f } }
        }
    }
}

/// What Play uses from the game's folder: each mod, highest priority first, and the cheats. Shown, not changed here: AetherNX on the Mac and AetherNX
/// Companion turn them on and off (Mods/mods.json, Cheats/<build ID>.enabled), and the change applies at the next Play
private struct GameExtrasSection: View {
    @ObservedObject var state: GameExtrasState
    let titleID: String

    var body: some View {
        if let f = state.folder, let cloud = state.cloud {
            Section {
                if f.mods.isEmpty {
                    LabeledContent("Mods") { Text(f.hasMods ? "None" : "No Mods folder") }
                }
                ForEach(f.mods, id: \.name) { m in
                    LabeledContent { Text(status(m, f)).foregroundStyle(m.used && !f.stateWaiting ? .primary : .secondary) } label: { Text(m.name).lineLimit(1).truncationMode(.middle) }
                }
                LabeledContent("Cheats") { Text(cheats(f)).foregroundStyle(f.cheatFile != nil && !f.cheatsOff && !f.cheatWaiting ? .primary : .secondary) }
            } header: {
                Text("Mods and Cheats")
            } footer: {
                Text(footer(f, cloud: cloud))
            }
            .id("extras")
        }
    }

    private func status(_ m: GameExtras.Mod, _ f: GameExtras.Folder) -> String {
        if m.romfs == nil { return m.hasCode ? "Code mod: not run" : "No romfs folder" }
        if f.stateWaiting { return "Waiting for iCloud" }
        if m.off { return "Off" }
        if m.waiting > 0 { return "Downloading (\(m.waiting) files)" }
        if m.hasColon { return "Not used: “:” in its path" }
        return m.hasCode ? "On (files only)" : "On"
    }

    private func cheats(_ f: GameExtras.Folder) -> String {
        guard f.cheats != nil else { return "No Cheats folder" }
        if f.cheatsOff { return "Off" }
        guard f.cheatFile != nil else { return mainBuildID == nil ? "Build unknown" : "None for this version" }
        if f.cheatWaiting { return "Downloading" }
        return f.cheatsOn == 1 ? "1 on" : "\(f.cheatsOn) on"
    }

    private func footer(_ f: GameExtras.Folder, cloud: String) -> String {
        var t = "From \(GameExtras.displayName(f.base))."
        if let up = GameExtras.gameFolderAbove(cloud, titleID: titleID) {
            t += " This is the save's own folder inside \(GameExtras.displayName(up)): choose that one in Cloud Saves to bring the game's mods and cheats too."
        }
        if f.stateWaiting { t += " mods.json is not on this iPhone yet: no mod is used until iCloud brings it." }
        if f.stateUnread { t += " mods.json cannot be read, so every mod is on." }
        if !f.mods.isEmpty { t += " Mods higher in the list win when two change the same file." }
        if f.cheatFile != nil, let b = mainBuildID { t += " Cheats: \(b).txt; they change data only on the iPhone." }
        return t + " Turn them on and off in AetherNX on the Mac or in AetherNX Companion: they apply at the next Play."
    }
}

/// UIDocumentPickerViewController for a folder, in the two callbacks a SwiftUI sheet wants.
private struct DocumentPicker: UIViewControllerRepresentable {
    var types: [UTType] = [.folder]
    /// Where it opens; nil: where it was last
    var directory: URL?
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // .open (not .import): the folder stays where it is and the bookmark keeps pointing at it.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.directoryURL = directory
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

private struct LauncherView: View {
    @ObservedObject var m: LauncherModel
    /// Why the settings list could not be read (dm/launcher.json damaged): the screen says so and Play starts the game with its tested defaults
    let problem: String?
    let play: () -> Void

    @StateObject private var nav = LauncherNav()
    @StateObject private var controllers = ControllerListModel()
    @StateObject private var cloud = CloudSavesState()
    @StateObject private var extras = GameExtrasState()
    @State private var memory = os_proc_available_memory()
    @State private var checking = false
    @State private var check = 0   // which Play the running check is for: one the player went on from without it is dropped
    @State private var report: SaveSyncReport?
    @State private var asking: SaveSyncReport.Step?
    @State private var headerGone = false
    @Environment(\.verticalSizeClass) private var vertical
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private let icon = appIcon()
    private let tint = GameTint.from(appIcon()?.cgImage)
    private let name = (info("CFBundleDisplayName") as? String) ?? (info("CFBundleName") as? String) ?? "Game"
    private let version = (info("CFBundleShortVersionString") as? String) ?? ""

    private var items: [SummaryItem] {
        m.summaryItems() + [SummaryItem(id: "cloud", value: cloud.summary, caption: "Cloud saves", locked: cloudOverride != nil)]
    }
    private var focusOrder: [LauncherFocus] {
        var o: [LauncherFocus] = [.play]
        o += items.map(\.focus)
        for section in m.sections {
            o += m.rows(in: section).map { .row($0.env) }
            if section == "Controls" { o += controllers.rows.map { .controller($0.id) } }
        }
        if m.changed { o.append(.reset) }
        if cloudOverride == nil {
            o.append(.cloud)
            if !cloud.container.isEmpty && !cloud.usingICloud { o.append(.cloudAuto) }
            if !cloud.folder.isEmpty || cloud.usingICloud { o.append(.cloudOff) }
        }
        o += SupportLink.allCases.map { .support($0.rawValue) }
        return o
    }

    /// The game starts with these settings and controller choices
    private func launch() { controllers.merge = m.values["DM_PAD_MERGE"] == "1"; controllers.apply(); play() }

    private func isAsking(_ step: SaveSyncReport.Step) -> Binding<Bool> {
        Binding(get: { asking == step }, set: { if !$0 && asking == step { asking = nil } })
    }

    /// Play, once the cloud's save is compared with this iPhone's (save_sync_report, SaveSyncReport): a save that changed on both sides is the player's pick, not the
    /// newer file's, and a cloud save that did not come is said so before the game starts without it.
    private func start() {
        check += 1; checking = true; asking = nil
        let mine = check
        dm_cloud_saves_env()   // DM_SAVE_SYNC from the picked folder, as the game's mount will read it (front_ios.m calls it again at the start)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.compare()
            DispatchQueue.main.async {
                guard checking, check == mine else { return }   // the player played without it
                checking = false
                switch SaveSyncReport.step(r) {
                case .play(let choice): go(choice)
                case let step: report = r; asking = step
                }
            }
        }
    }

    /// Blocks while the cloud's file downloads (SaveSyncReport.waitMs at most). nil: no report (the host then decides as it always did)
    private static func compare() -> SaveSyncReport? {
        // getenv, not ProcessInfo.environment: main.m sets DM_SAVE and applies env.txt after that snapshot
        guard let save = getenv("DM_SAVE") else { fputs("launcher: save sync: no DM_SAVE\n", stderr); return nil }
        var buf = [CChar](repeating: 0, count: 1024)
        guard save_sync_report(save, dm_save_title(), nil, SaveSyncReport.waitMs, &buf, buf.count) == 0 else {
            fputs("launcher: save sync: no report on \(String(cString: save))\n", stderr)
            return nil
        }
        let line = String(cString: buf)
        fputs("launcher: save sync: \(line)\n", stderr)
        return SaveSyncReport(line: line)
    }

    private func go(_ choice: String?) {
        asking = nil
        if let choice { setenv("DM_SAVE_SYNC_CHOICE", choice, 1); fputs("launcher: DM_SAVE_SYNC_CHOICE=\(choice)\n", stderr) }
        launch()
    }

    @ViewBuilder private var playButton: some View {
        VStack(spacing: 6) {
            Button(action: start) {
                Label("Play", systemImage: "play.fill").font(.title3.weight(.semibold)).labelStyle(.titleAndIcon)
                    .padding(.horizontal, 18).frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)   // a solid capsule in the game's colour (white text on it passes 4.5:1, GameTint)
            .buttonBorderShape(.capsule)
            .tint(tint.fill)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)   // Return on an iPad keyboard, as in the Mac window
            .focusCapsule(nav.isFocused(.play), tint)
            .accessibilityHint("Starts the game with these settings")
            .disabled(checking)
            if checking {   // the cloud save is being compared (start)
                HStack(spacing: 6) { ProgressView(); Text("Checking the cloud save…").font(.callout).foregroundStyle(.secondary) }
                Button("Play Without It") { checking = false; go("offline") }.font(.callout)
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    List {
                        Section {
                            GameHeader(icon: icon.map(Image.init(uiImage:)), name: name, version: version, iconSize: vertical == .compact ? 76 : 96) { playButton }
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 4, trailing: 4))
                                .id("header")
                        }
                        Section {
                            SummaryStrip(items: items, tint: tint, nav: nav) { it in nav.focus = it.id == "cloud" ? .cloud : .row(it.id) }
                                .listRowBackground(Color.clear)   // hairlines on the page's ground, as a product page's information row
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .id("summary")
                        } footer: {
                            PadHint(nav: nav)
                        }
                        if let problem {
                            Section {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("This app's settings list cannot be read.")
                                        Text("Play starts the game with its tested defaults. Packing the game again restores the list. (\(problem))").font(.footnote).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            }
                        }
                        ForEach(m.sections, id: \.self) { section in
                            let rows = m.rows(in: section)
                            if !rows.isEmpty {
                                Section(section) {
                                    ForEach(rows) { SettingRow(s: $0, m: m, tint: tint, focused: nav.isFocused(.row($0.env))) }
                                    if section == "Controls" { ConnectedControllers(controllers: controllers, tint: tint) { nav.isFocused(.controller($0)) } }
                                }
                            }
                        }
                        if !m.settings.isEmpty {
                            Section {
                                Button("Reset to Tested Defaults") { m.reset() }
                                    .disabled(!m.changed)
                                    .focusRing(nav.isFocused(.reset), tint)
                                    .id("reset")
                            } footer: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Brings back every setting this game was tested with. Values set by an env file stay.")
                                    if memory > 0 {   // what the system leaves this app now: a large game needs the Increased Memory Limit entitlement
                                        Text("Memory available to the game: \(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))").monospacedDigit()
                                    }
                                }
                            }
                        }
                        CloudSavesSection(state: cloud, name: name, tint: tint, focused: nav.isFocused(.cloud), offFocused: nav.isFocused(.cloudOff), autoFocused: nav.isFocused(.cloudAuto))
                        GameExtrasSection(state: extras, titleID: String(cString: dm_save_title()))
                        SupportSection(tint: tint) { nav.isFocused(.support($0.rawValue)) }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .contentMargins(.horizontal, max(12, (geo.size.width - 820) / 2), for: .scrollContent)   // a readable column on a wide screen, wide enough for the whole strip on an iPad
                    .contentMargins(.top, 0, for: .scrollContent)
                    .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 110 } action: { _, gone in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { headerGone = gone }
                    }
                    .onChange(of: nav.focus) { _, f in
                        guard let f else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(f.scrollID, anchor: .center) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {   // only once the header has scrolled away: an item hidden by opacity still draws its glass platter
                if headerGone {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            if let icon { Image(uiImage: icon).resizable().frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).accessibilityHidden(true) }
                            Text(name).font(.headline).lineLimit(1)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: start) { Text("Play").fontWeight(.semibold) }
                            .buttonStyle(.glassProminent).tint(tint.fill)   // a toolbar draws its own glass: only the prominent glass style takes the tint there
                            .accessibilityHint("Starts the game with these settings")
                    }
                }
            }
            .toolbarBackground(headerGone ? .visible : .hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)   // the game starts on black: a light screen before it would flash
        .onAppear {
            cloud.refresh()   // resolves the picked folder, holding its scope (CloudSaves.m), before its game folder is read
            extras.refresh(cloud: cloud.inUse)
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
                case .reset: m.reset()
                case .cloud: if cloudOverride == nil { cloud.picking = true }
                case .cloudOff: cloud.turnOff(); nav.focus = .cloud
                case .cloudAuto: cloud.useICloud(); nav.focus = .cloud
                case .support(let e): if let l = SupportLink(rawValue: e) { openURL(l.url) }
                default: break
                }
            }
            if dm_take_play_link() { start() }   // the app was opened by aethernx-<title ID>://play (front_ios.m front_ios_open_url)
        }
        .task { await nav.run() }
        .onChange(of: m.values["DM_PAD_MERGE"]) { _, v in controllers.merge = v == "1"; controllers.refresh() }
        .task {
            controllers.merge = m.values["DM_PAD_MERGE"] == "1"
            while !Task.isCancelled { controllers.refresh(); try? await Task.sleep(for: .seconds(1)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DMCloudContainerResolved"))) { _ in cloud.refresh() }   // automatic iCloud became known
        .onChange(of: cloud.inUse) { _, folder in extras.refresh(cloud: folder) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in extras.refresh(cloud: cloud.inUse) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DMPlayLink"))) { _ in if dm_take_play_link() { start() } }   // aethernx-<title ID>://play while the launcher shows
        .confirmationDialog(SaveSyncReport.chooseTitle, isPresented: isAsking(.choose), titleVisibility: .visible, presenting: report) { r in
            Button(r.localLabel(here: "iPhone")) { go(r.localChoice) }
            Button(r.cloudLabel) { go(r.cloudChoice) }
            Button("Cancel", role: .cancel) {}
        } message: { r in Text(r.chooseMessage(here: "iPhone")) }
        .confirmationDialog(SaveSyncReport.unreadableTitle, isPresented: isAsking(.unreadable), titleVisibility: .visible, presenting: report) { r in
            Button("Play This iPhone's Save") { go("offline") }   // the mount does not wait for the cloud again
            Button("Try Again") { DispatchQueue.main.async { start() } }
            Button("Cancel", role: .cancel) {}
        } message: { r in Text(r.unreadableMessage(here: "iPhone")) }
        .task {
            while !Task.isCancelled {
                memory = os_proc_available_memory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// DM_ROMFS_OVERLAY and DM_CHEATS from the game's folder beside the cloud save that DM_SAVE_SYNC names (GameExtras.swift): front_ios.m startGame calls it after
// dm_cloud_saves_env, with or without the launcher, before the host's cheats and RomFS mount read them. The picked folder's security scope covers the game's
// folder, which is it or inside it, and CloudSaves.m holds it for the session
@_cdecl("dm_game_extras_env")
public func dmGameExtrasEnv() {
    GameExtras.apply(cloud: getenv("DM_SAVE_SYNC").map { String(cString: $0) }, titleID: String(cString: dm_save_title()), buildID: mainBuildID)
}

// aethernx-<title ID>://play (front_ios.m front_ios_open_url): whether the link asks to press Play
@_cdecl("dm_link_plays")
public func dmLinkPlays(_ link: UnsafePointer<CChar>) -> Bool { GameExtras.linkPlays(String(cString: link)) }

// Shows the launcher over the root view controller and calls done once the settings are in the environment; false (done is not called) when there is no launcher
@_cdecl("dm_show_launcher")
public func dmShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) -> Bool {
    // a game of several programs (main.m): the running program's settings, in its dm/p<N>
    guard let url = appDMFolder()?.appendingPathComponent("launcher.json"), let data = try? Data(contentsOf: url) else { return false }   // packed without settings: nothing to choose
    let env = ProcessInfo.processInfo.environment
    var settings: [Setting] = [], problem: String?
    do { settings = try JSONDecoder().decode(SettingsFile.self, from: data).settings }
    catch { problem = "dm/launcher.json: \(error.localizedDescription)"; fputs("[RED] launcher: \(problem!)\n", stderr) }
    if problem == nil && settings.isEmpty { return false }
    if env["DM_LAUNCHER"] == "0" {
        fputs("launcher: off (DM_LAUNCHER=0)\n", stderr)
        if problem == nil { LauncherModel(settings).applySaved() }
        return false
    }
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    let model = LauncherModel(settings)
    var host: UIViewController?
    let view = LauncherView(m: model, problem: problem) {
        guard let h = host else { return }
        host = nil
        model.apply()
        h.dismiss(animated: false) { done() }
    }
    let h = DmHostingController(rootView: view)
    h.modalPresentationStyle = .fullScreen
    host = h
    parent.present(h, animated: false)
    fputs("launcher: \(settings.count) settings shown\(problem == nil ? "" : " (the settings list cannot be read)")\n", stderr)
    return true
}
