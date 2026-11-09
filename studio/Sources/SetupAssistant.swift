import AppKit
import SwiftUI

/// The first launch: the tools, the keys, a library and a few choices, one step at a time. Help → Setup Assistant opens it again.
struct SetupAssistantView: View {
    enum Step: Int, CaseIterable {
        case welcome, tools, keys, library, preferences

        var title: LocalizedStringKey {
            switch self {
            case .welcome: "Welcome"
            case .tools: "Tools"
            case .keys: "Keys"
            case .library: "Library"
            case .preferences: "Preferences"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.welcome

    var body: some View {
        VStack(spacing: 0) {
            StepBar(current: step)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 14)
            Divider()
            ScrollView {
                Group {
                    switch step {
                    case .welcome: WelcomeStep()
                    case .tools: ToolsStep()
                    case .keys: KeysStep()
                    case .library: LibraryStep()
                    case .preferences: PreferencesStep()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            Divider()
            HStack {
                if step == .welcome {
                    Button("Skip Setup") { finish() }
                } else {
                    Button("Back") { go(-1) }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if let hint { Text(hint).font(.callout).foregroundStyle(.secondary) }
                if step == .preferences {
                    Button("Start Using AetherNX") { finish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(step == .welcome ? "Get Started" : "Continue") { go(1) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: 560)
        .interactiveDismissDisabled()
    }

    /// Why Continue may not be the best idea yet; Continue still works, everything can be set later.
    private var hint: LocalizedStringKey? {
        switch step {
        case .tools where model.engine == nil: "Without the tools nothing can be built."
        case .library where model.libraryFolders.isEmpty: "You can add folders later."
        default: nil
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeOut(duration: 0.15)) { step = next }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Pref.setupCompleted)
        model.rescan()
        dismiss()
    }
}

private struct StepBar: View {
    let current: SetupAssistantView.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SetupAssistantView.Step.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= current.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 22, height: 22)
                        if step.rawValue < current.rawValue {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                        } else {
                            Text(verbatim: "\(step.rawValue + 1)").font(.caption.weight(.semibold))
                                .foregroundStyle(step == current ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        }
                    }
                    Text(step.title)
                        .font(.callout.weight(step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                        .lineLimit(1)
                }
                if step != SetupAssistantView.Step.allCases.last {
                    Rectangle().fill(.quaternary).frame(height: 1).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current.rawValue + 1) of \(SetupAssistantView.Step.allCases.count): \(Text(current.title))"))
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to AetherNX")
                        .font(.largeTitle.weight(.bold))
                    Text("Your own Switch games, rebuilt as Mac and iPhone apps.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("cpu", "Native, not emulated", "The game's own code is rewritten once, on this Mac, and runs directly on Apple silicon with Metal graphics.")
                feature("macbook.and.iphone", "One app per game", "A Mac app you open from Finder, or an IPA for your iPhone and iPad.")
                feature("gamecontroller", "A console on the couch", "Console Mode puts the library full screen for a controller.")
                feature("lock.shield", "Your files stay yours", "Builds run on this Mac. Your keys and games are never uploaded.")
            }
            Text("The next steps check the tools, your keys and where your games are. Everything can be changed later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func feature(_ image: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ToolsStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "The AetherNX tools", detail: "The build scripts and the engine. The app runs every build from their folder.")
            StatusRow(ok: model.engine != nil,
                      title: model.engine.map { Text(verbatim: ($0.path as NSString).abbreviatingWithTildeInPath) } ?? Text("Not found on this Mac"),
                      detail: model.engineVersion.map { Text("Version \($0)") }) {
                Button("Choose Folder…") { model.chooseEngineFolder() }
                if model.engine == nil {
                    Button("Download") { model.downloadEngine() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canStartJob)
                }
            }
            if let job = model.job, job.gameID == nil, job.isRunning || job.state == .failed {
                JobCard(job: job)
            }
            if model.engine != nil {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Setup check").font(.headline)
                    Spacer()
                    if model.isCheckingSetup { ProgressView().controlSize(.small) }
                    Button("Check Again") { model.runSetupCheck() }
                        .disabled(model.isCheckingSetup)
                }
                if let report = model.setupReport {
                    let missing = report.checks.filter { !$0.ok && $0.required }
                    if missing.isEmpty {
                        Label("Everything a build needs is in place.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("\(missing.count) things a build needs are missing:", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(missing) { CheckRow(check: $0) }
                        }
                        if report.checks.contains(where: { $0.group == "Python" && !$0.ok }) {
                            Button("Install Python Packages") { model.installPythonPackages() }
                                .disabled(!model.canStartJob)
                        }
                    }
                }
            }
        }
        .onAppear { if model.engine != nil && model.setupReport == nil { model.runSetupCheck() } }
        .onChange(of: model.engine) { _, engine in if engine != nil { model.runSetupCheck() } }
    }
}

private struct KeysStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "Your keys", detail: "A build decrypts the game's packages (.nsp, .xci) with the prod.keys dumped from your own Switch. The file stays on this Mac and never goes into the apps.")
            StatusRow(ok: model.keys.isUsable,
                      title: Text(model.keys.path.isEmpty ? String(localized: "No prod.keys yet") : (model.keys.path as NSString).abbreviatingWithTildeInPath),
                      detail: keysDetail) {
                Button(model.keys.isUsable ? "Choose Another…" : "Choose prod.keys…") { model.chooseKeysFile() }
                    .buttonStyle(.borderedProminent)
            }
            Label("A dump folder (the game's files already extracted, with exefs and romfs folders) needs no keys.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.keys = KeysStatus.current() }
    }

    private var keysDetail: Text? {
        switch model.keys.state {
        case .ok(let count): Text("\(count) keys, including header_key")
        case .notSet: Text("Without a choice, ~/.switch/prod.keys is used when it is there.")
        case .missing: Text("The file is not there any more.")
        case .unreadable: Text("The file cannot be read.")
        case .invalid: Text("This does not look like prod.keys: it has no header_key.")
        }
    }
}

private struct LibraryStep: View {
    @Environment(AppModel.self) private var model

    private var suggestions: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Games", "Documents/Games", "Downloads"].map { home.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) && !model.libraryFolders.contains($0.standardizedFileURL.path) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "Where your games are", detail: "One folder per game, with its base game, update and DLC (.nsp, .xci, .nsz, .xcz), a dump of its files, or an archive of them. Add the folder that holds those folders.")
            if model.libraryFolders.isEmpty {
                StatusRow(ok: false, title: Text("No library folders yet"), detail: nil) {
                    Button("Add Folder…") { model.chooseLibraryFolder() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.libraryFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.tint)
                            Text(verbatim: (folder as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Button {
                                model.removeLibraryFolder(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Remove \(folder)"))
                        }
                    }
                    Button("Add Another Folder…") { model.chooseLibraryFolder() }
                }
                Group {
                    if model.isScanning {
                        Label("Looking for games…", systemImage: "magnifyingglass")
                    } else {
                        Label("\(model.games.count) games found", systemImage: "gamecontroller")
                    }
                }
                .foregroundStyle(.secondary)
            }
            ForEach(suggestions, id: \.self) { url in
                Button {
                    model.addLibraryFolder(url)
                } label: {
                    Label("Add \((url.path as NSString).abbreviatingWithTildeInPath)", systemImage: "plus.circle")
                }
                .buttonStyle(.link)
            }
        }
    }
}

private struct PreferencesStep: View {
    @AppStorage(Pref.defaultTarget) private var defaultTarget = BuildTarget.mac.rawValue
    @AppStorage(Pref.language) private var language = ""
    @AppStorage(Pref.downloadArtwork) private var downloadArtwork = true
    @AppStorage(Pref.notifyBuilds) private var notifyBuilds = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "A few choices", detail: "These are in Settings too.")
            Form {
                Picker("Build button makes", selection: $defaultTarget) {
                    ForEach(BuildTarget.menuOrder) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Game language", selection: $language) {
                    Text("Game default").tag("")
                    Divider()
                    ForEach(GameLanguage.all, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
                Toggle(isOn: $downloadArtwork) {
                    Text("Download game artwork")
                    Text("Icons and banners from nlib.cc and Wikipedia; only the game's title ID or name is sent. Without them, the icon in the game's files is used.")
                }
                Toggle(isOn: $notifyBuilds) {
                    Text("Notify me when a build finishes")
                    Text("A build can take an hour: a notification tells you when the game is ready.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)
        }
        .onChange(of: notifyBuilds) { _, on in if on { Notifier.requestPermission() } }
    }
}

// MARK: - Pieces

private struct StepHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.weight(.bold))
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusRow<Actions: View>: View {
    let ok: Bool
    let title: Text
    let detail: Text?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title)
                .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityLabel(ok ? Text("Ready") : Text("Not set"))
            VStack(alignment: .leading, spacing: 2) {
                title.lineLimit(2).truncationMode(.head)
                if let detail { detail.font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
