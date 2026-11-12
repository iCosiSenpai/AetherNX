import AppKit
import SwiftUI

/// Settings, as a page of the main window: the groups in a list beside them when the window has room, as tabs above them when it is narrow.
/// The iPhone and iPad settings are on the Devices page.
struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.layoutWidth) private var layoutWidth

    var body: some View {
        @Bindable var model = model
        Group {
            if layoutWidth == .compact {
                VStack(spacing: 0) {
                    Picker("Settings", selection: $model.settingsPane) {
                        ForEach(SettingsPane.allCases) { pane in
                            Text(pane.title).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                    Divider()
                    pane(model.settingsPane)
                }
            } else {
                HStack(spacing: 0) {
                    List(selection: $model.settingsPane) {
                        ForEach(SettingsPane.allCases) { pane in
                            Label(pane.title, systemImage: pane.systemImage).tag(pane)
                        }
                        Section {
                            Button {
                                model.sidebarSelection = .page(.devices)
                            } label: {
                                Label("iPhone & iPad…", systemImage: "iphone.gen3")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(width: 220)
                    Divider()
                    pane(model.settingsPane)
                        .frame(maxWidth: 860)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Settings")
        .measuringLayoutWidth()
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettings()
        case .library: LibrarySettings()
        case .keys: KeysSettings()
        case .building: BuildingSettings()
        case .cloud: CloudSettings()
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.notifyBuilds) private var notifyBuilds = true
    @AppStorage(Pref.checkUpdatesAtLaunch) private var checkUpdatesAtLaunch = true
    @AppStorage(Pref.showsMenuBarItem) private var showsMenuBarItem = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.engine.map { abbreviated($0.path) } ?? String(localized: "Not set"))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(model.engine == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        Button("Choose…") { model.chooseEngineFolder() }
                    }
                }
                if let version = model.engineVersion {
                    LabeledContent("Version", value: version)
                }
                HStack {
                    Button("Check Setup…") { model.showsSetupCheck = true }
                        .disabled(model.engine == nil)
                    Button("Updates…") { model.sidebarSelection = .page(.updates) }
                    if model.engine == nil {
                        Button("Download") { model.downloadEngine() }
                            .disabled(!model.canStartJob)
                    }
                }
            } header: {
                Text("AetherNX Engine")
            } footer: {
                Text("The folder with the aethernx command, the build scripts and the HorizonNative engine. The app runs the builds from there, and updates it on its own, without a new version of the app (Updates).")
            }

            Section {
                Toggle("Check for updates at launch", isOn: $checkUpdatesAtLaunch)
                Toggle("Show AetherNX in the menu bar", isOn: $showsMenuBarItem)
                Toggle("Notify me when a build finishes", isOn: $notifyBuilds)
                    .onChange(of: notifyBuilds) { _, on in if on { Notifier.requestPermission() } }
            } header: {
                Text("App")
            }

            Section {
                Button("Open Setup Assistant…") { model.showsSetupAssistant = true }
            } footer: {
                Text("The assistant checks what the builds need on this Mac (Xcode, Python, Git and the rest), says what each one is for, and installs what it can.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Library

private struct LibrarySettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.downloadArtwork) private var downloadArtwork = true

    var body: some View {
        Form {
            Section {
                if model.libraryFolders.isEmpty {
                    Text("No folders yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.libraryFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(abbreviated(folder))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(folder)
                        Spacer()
                        Button {
                            model.removeLibraryFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from the library (the folder stays on disk)")
                        .accessibilityLabel("Remove \(folder)")
                    }
                }
                Button("Add Folder…") { model.chooseLibraryFolder() }
            } header: {
                Text("Library Folders")
            } footer: {
                Text("One folder per game, with its base game, update and DLC (.nsp, .xci, .nsz, .xcz), or an archive of them.")
            }

            Section {
                Toggle("Download game artwork", isOn: $downloadArtwork)
                HStack {
                    Text("\(model.artwork.art.values.filter { $0.source != nil }.count) games have artwork")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Download Again") { model.artwork.clear() }
                        .help("Forget the saved pictures; each game is looked up again when it shows")
                }
            } header: {
                Text("Game Artwork")
            } footer: {
                Text("Icons and banners of Switch games come from nlib.cc by title ID; other games, Switch 2 ones among them, get their box art from Wikipedia by name. Only the title ID or the name is sent. Without a picture online, the icon in the game's own files is used.")
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Saves, mods and cheats

private struct CloudSettings: View {
    var body: some View {
        Form {
            CloudSavesSettings()
            Section {
                Label("Mods: a folder per mod in the game's Mods folder, with a romfs folder inside. Turn them on and off, and order them, on the game's page. No rebuild: they apply at the game's next start.",
                      systemImage: "puzzlepiece.extension")
                Label("Cheats: Atmosphère cheat files named by the game's build ID, in its Cheats folder. Turn single cheats on and off while playing, from the game's Cheats menu.",
                      systemImage: "wand.and.stars")
            } header: {
                Text("Mods and Cheats")
            } footer: {
                Text("Both folders sit next to the game's save: in iCloud Drive › AetherNX › the game's name when the cloud is on, so every Mac and device of yours sees the same ones; else on this Mac. Code mods (exefs) and mods that need a loader do not work with the engine.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Keys

private struct KeysSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.keysPath) private var keysPath = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("prod.keys") {
                    HStack {
                        Text(model.keys.path.isEmpty ? String(localized: "Not set") : abbreviated(model.keys.path))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: choose)
                    }
                }
                status
                if !keysPath.isEmpty {
                    HStack {
                        Button("Show in Finder") { Finder.reveal(keysPath) }
                        Button("Use ~/.switch/prod.keys") {
                            keysPath = ""
                            model.keys = KeysStatus.current()
                        }
                    }
                }
            } footer: {
                Text("Dump the keys from your own Switch. AetherNX passes this file to the build on this Mac; it is never uploaded or put into the apps. Without a choice here, ~/.switch/prod.keys is used.")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.keys = KeysStatus.current() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.keys.state {
        case .ok(let count):
            Label("\(count) keys, including header_key", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notSet:
            Label("No keys yet: builds cannot decrypt the games.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .missing:
            Label("The file is not there any more.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unreadable:
            Label("The file cannot be read.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .invalid:
            Label("This does not look like prod.keys: it has no header_key.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.message = String(localized: "Choose your prod.keys file.")
        if panel.runModal() == .OK, let url = panel.url {
            keysPath = url.path
            model.keys = KeysStatus.current()
        }
    }
}

// MARK: - Building

private struct BuildingSettings: View {
    @AppStorage(Pref.defaultTarget) private var defaultTarget = BuildTarget.mac.rawValue
    @AppStorage(Pref.language) private var language = ""
    @AppStorage(Pref.keepExtracted) private var keepExtracted = true
    @AppStorage(Pref.pipelineArchive) private var pipelineArchive = true
    @AppStorage(Pref.macSigningIdentity) private var signingIdentity = ""
    @AppStorage(Pref.extraArguments) private var extraArguments = ""

    var body: some View {
        Form {
            Section {
                Picker("Build button makes", selection: $defaultTarget) {
                    ForEach(BuildTarget.menuOrder) { target in
                        Text(target.title).tag(target.rawValue)
                    }
                }
                Picker("Game language", selection: $language) {
                    Text("Game default").tag("")
                    Divider()
                    ForEach(GameLanguage.all, id: \.code) { language in
                        Text(verbatim: language.name).tag(language.code)
                    }
                }
            } footer: {
                Text((BuildTarget(rawValue: defaultTarget) ?? .mac).detail)
            }

            Section {
                Toggle("Keep extracted game files", isOn: $keepExtracted)
                Toggle("Include pre-built shader pipelines", isOn: $pipelineArchive)
            } header: {
                Text("Speed and Disk Space")
            } footer: {
                Text("Kept files make the next build much faster and take about as much space as the game. Pre-built pipelines avoid stutters the first time a scene appears, at the cost of a longer build and a bigger app.")
            }

            Section {
                TextField("Signing identity", text: $signingIdentity, prompt: Text("Ad-hoc"))
                TextField("Extra build options", text: $extraArguments, prompt: Text(verbatim: "--allow-damaged"))
            } header: {
                Text("Advanced")
            } footer: {
                Text("A Developer ID identity lets the Mac app open on other Macs. Extra options go to scripts/build_ipa_from_nsp.py as written.")
            }
        }
        .formStyle(.grouped)
    }
}

private func abbreviated(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}
