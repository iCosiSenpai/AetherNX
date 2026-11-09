import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Keys", systemImage: "key") { KeysSettings() }
            Tab("Building", systemImage: "hammer") { BuildingSettings() }
        }
        .frame(width: 540)
        .scenePadding(.minimum)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.downloadArtwork) private var downloadArtwork = true
    @AppStorage(Pref.notifyBuilds) private var notifyBuilds = true
    @AppStorage(Pref.checkUpdatesAtLaunch) private var checkUpdatesAtLaunch = true
    @AppStorage(Pref.showsMenuBarItem) private var showsMenuBarItem = true

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
                    Button("Update") { model.updateEngine() }
                        .disabled(model.engine == nil || !model.canStartJob)
                        .help("git pull in the AetherNX folder")
                    if model.engine == nil {
                        Button("Download") { model.downloadEngine() }
                            .disabled(!model.canStartJob)
                    }
                }
            } header: {
                Text("AetherNX Tools")
            } footer: {
                Text("The folder with the aethernx command and the build scripts. The app runs the builds from there.")
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

            Section {
                Toggle("Check for updates at launch", isOn: $checkUpdatesAtLaunch)
                Toggle("Show AetherNX in the menu bar", isOn: $showsMenuBarItem)
                Button("Check for Updates…") { model.checkForUpdates(userInitiated: true) }
            } header: {
                Text("Updates")
            } footer: {
                Text("The app from AetherNX's GitHub releases, the tools from their Git remote, and what nxnative, the engine AetherNX is built on, changed since AetherNX's last sync.")
            }

            Section {
                Toggle("Notify me when a build finishes", isOn: $notifyBuilds)
                    .onChange(of: notifyBuilds) { _, on in if on { Notifier.requestPermission() } }
                Button("Open Setup Assistant…") { model.showsSetupAssistant = true }
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
    @AppStorage(Pref.showFPS) private var showFPS = false
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

            Section("iPhone and iPad") {
                Toggle("Show the frame rate", isOn: $showFPS)
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
