// Launcher: the screen shown before the game starts (front_ios.m dm_show_launcher), laid out as the game's own product card. The header names the game (icon, name, version)
// with Play; the summary strip states what Play starts with (the basic settings, cloud saves, the memory available) and takes the player to each setting; the settings follow,
// grouped by section (rows and shared parts: LauncherRow.swift). When the header scrolls away, the navigation bar takes a small icon and Play.
// Its settings come from the app's dm/launcher.json, which build_ipa.sh writes for this game from dm/games/settings.tsv (dm/games/settings.py): each sets an environment variable the
// host reads when the game starts. A variable an env file set (Documents/env.txt, the bundle's dm/env.txt; main.m lists them in DM_ENV_FILE_KEYS) or the launch environment set is shown,
// locked. Choices that differ from the game's default are kept in UserDefaults; Reset to tested defaults shows the defaults, and Play then forgets them. DM_LAUNCHER=0 in
// Documents/env.txt starts the game at once with the saved choices; DM_SAVED_CHOICES=0 ignores them (and keeps them). A game controller moves through the screen (LauncherNav):
// up and down, left and right to change a value, A to choose, Menu to play.
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

private func appIcon() -> UIImage? {
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
    @Published var note = ""
    @Published var picking = false
    func refresh() {
        var stale: ObjCBool = false
        folder = dm_cloud_saves_path(&stale) ?? ""
        if stale.boolValue && folder.isEmpty { note = "The folder chosen before can no longer be read (the app is signed differently now). Choose it again." }
    }
    func turnOff() { dm_clear_cloud_saves(); refresh(); note = "" }
    var summary: String {
        if let o = cloudOverride { return o == "0" || o.isEmpty ? "Off" : "env.txt" }
        return folder.isEmpty ? "Off" : "On"
    }
}

private struct CloudSavesSection: View {
    @ObservedObject var state: CloudSavesState
    let tint: GameTint
    let focused: Bool
    let offFocused: Bool

    var body: some View {
        Section {
            if let o = cloudOverride {
                LabeledContent("Folder") { Text(o == "0" || o.isEmpty ? "Off" : o == "icloud" ? "icloud (the Mac's iCloud Drive: off here)" : o).lineLimit(2).truncationMode(.head) }
                Label("DM_SAVE_SYNC is set by an env file or at launch, so this start uses it.", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                LabeledContent("Folder") {
                    Text(state.folder.isEmpty ? "Off" : (state.folder as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
                Button(state.folder.isEmpty ? "Choose a Folder in iCloud Drive…" : "Choose a Different Folder…") { state.picking = true }
                    .focusRing(focused, tint)
                if !state.folder.isEmpty {
                    Button("Turn Off Cloud Saves", role: .destructive) { state.turnOff() }
                        .focusRing(offFocused, tint)
                }
            }
        } header: {
            Text("Cloud Saves")
        } footer: {
            Text(state.note.isEmpty
                 ? "Choose a folder in iCloud Drive, and the same one in the Mac app's Cloud Saves. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups."
                 : state.note)
        }
        .id("cloud")
        .sheet(isPresented: $state.picking) {
            DocumentPicker(types: [.folder]) { url in
                state.picking = false
                if dm_store_cloud_saves(url) { state.note = "Saved. The game uses this folder when you press Play."; state.refresh() }
                else { state.note = "That folder could not be remembered. Try a different one." }
            } onCancel: { state.picking = false }
        }
    }
}

/// UIDocumentPickerViewController for a folder, in the two callbacks a SwiftUI sheet wants.
private struct DocumentPicker: UIViewControllerRepresentable {
    var types: [UTType] = [.folder]
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // .open (not .import): the folder stays where it is and the bookmark keeps pointing at it.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
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
    @StateObject private var cloud = CloudSavesState()
    @State private var memory = os_proc_available_memory()
    @State private var headerGone = false
    @Environment(\.verticalSizeClass) private var vertical
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        for section in m.sections { o += m.rows(in: section).map { .row($0.env) } }
        if m.changed { o.append(.reset) }
        if cloudOverride == nil { o.append(.cloud); if !cloud.folder.isEmpty { o.append(.cloudOff) } }
        return o
    }

    private var playButton: some View {
        Button(action: play) {
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
                        CloudSavesSection(state: cloud, tint: tint, focused: nav.isFocused(.cloud), offFocused: nav.isFocused(.cloudOff))
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
                        Button(action: play) { Text("Play").fontWeight(.semibold) }
                            .buttonStyle(.glassProminent).tint(tint.fill)   // a toolbar draws its own glass: only the prominent glass style takes the tint there
                            .accessibilityHint("Starts the game with these settings")
                    }
                }
            }
            .toolbarBackground(headerGone ? .visible : .hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)   // the game starts on black: a light screen before it would flash
        .onAppear {
            cloud.refresh()
            nav.order = { focusOrder }
            nav.play = play
            nav.adjust = { f, d in if case .row(let e) = f, let s = m.settings.first(where: { $0.env == e }) { m.step(s, by: d) } }
            nav.activate = { f in
                switch f {
                case .summary(let e): nav.focus = e == "cloud" ? .cloud : .row(e)
                case .row(let e):
                    guard let s = m.settings.first(where: { $0.env == e }), s.kind != "range" else { return }
                    m.step(s, by: s.kind == "toggle" ? (m.value(s) == s.onValue ? -1 : 1) : 1)
                case .reset: m.reset()
                case .cloud: if cloudOverride == nil { cloud.picking = true }
                case .cloudOff: cloud.turnOff(); nav.focus = .cloud
                default: break
                }
            }
        }
        .task { await nav.run() }
        .task {
            while !Task.isCancelled {
                memory = os_proc_available_memory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// Shows the launcher over the root view controller and calls done once the settings are in the environment; false (done is not called) when there is no launcher
@_cdecl("dm_show_launcher")
public func dmShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) -> Bool {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url) else { return false }   // packed without settings: nothing to choose
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
    let h = UIHostingController(rootView: view)
    h.modalPresentationStyle = .fullScreen
    host = h
    parent.present(h, animated: false)
    fputs("launcher: \(settings.count) settings shown\(problem == nil ? "" : " (the settings list cannot be read)")\n", stderr)
    return true
}
