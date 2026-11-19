import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(search: search)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                DetailContainer(search: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showsActivity {
                    Divider()
                    ActivityView()
                        .frame(height: 210)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search games")
        .frame(minWidth: 820, minHeight: 520)
        .toolbar { MainToolbar() }
        .sheet(isPresented: $model.showsSetupCheck) { SetupCheckView() }
        .sheet(isPresented: $model.showsSetupAssistant) { SetupAssistantView() }
        .sheet(item: $model.removalRequest) { RemovalSheet(request: $0) }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(model.confirmation?.title ?? "", isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
                            presenting: model.confirmation) { confirmation in
            Button(confirmation.actionTitle, role: .destructive) { confirmation.action() }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.showsActivity)
        .onChange(of: model.page) { old, _ in if old == .updates { model.dismissUpdateNotice() } }
        .onChange(of: model.consoleRequested) { _, requested in
            guard requested else { return }
            model.consoleRequested = false
            openWindow(id: "console")
        }
    }
}

/// The detail column: the page the sidebar chose. The library's home and a game's page first say what to do when something is missing.
private struct DetailContainer: View {
    let search: String
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.page {
        case .settings: SettingsPage()
        case .updates: UpdatesPage()
        case .activity: ActivityPage()
        case .devices: DevicesPage()
        case .home, .game: library
        }
    }

    @ViewBuilder
    private var library: some View {
        if model.engine == nil {
            EngineMissingView()
        } else if model.libraryFolders.isEmpty {
            LibraryEmptyView()
        } else if model.page == .game, let game = model.selectedGame {
            GameDetailView(game: game)
                .id(game.id)
        } else if !model.hasScanned {
            StartupView()
        } else if model.games.isEmpty && model.isScanning {
            ProgressView("Looking for games…")
                .controlSize(.small)
        } else if model.games.isEmpty {
            NoGamesFoundView()
        } else {
            HomeView(search: search)
        }
    }
}

private struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.chooseLibraryFolder(selectsGames: true)
            } label: {
                Label("Add Library Folder…", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .help("Add Library Folder…")
        }
        ToolbarItem(placement: .primaryAction) {
            if let job = model.job, job.isRunning {
                JobToolbarIndicator(job: job)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if model.updates.hasUpdates {
                Button {
                    model.showsUpdates = true
                } label: {
                    Label("Update Available", systemImage: "arrow.down.circle.fill")
                }
                .help("An update of AetherNX or its tools is ready")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ConsoleModeButton()
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showsActivity.toggle()
            } label: {
                Label("Activity", systemImage: "list.bullet.rectangle")
            }
            .help("Show or hide the activity log under the page (⇧⌘Y)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if model.page == .settings { model.sidebarSelection = .home } else { model.showSettings(model.settingsPane) }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings, in this window (⌘,)")
        }
    }
}

private struct ConsoleModeButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "console")
        } label: {
            Label("Console Mode", systemImage: "gamecontroller")
        }
        .help("Play from the couch: the library full screen, for a controller (⌃⌘C, or ≡ on the controller)")
    }
}

/// A compact progress ring in the toolbar while a job runs, visible from every game.
private struct JobToolbarIndicator: View {
    let job: Job
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            if let id = job.gameID { model.selectedGameID = id } else { model.sidebarSelection = .page(.activity) }
        } label: {
            HStack(spacing: 6) {
                if let fraction = job.fraction {
                    ProgressView(value: fraction).progressViewStyle(.circular)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }
                Text(job.title)
                    .lineLimit(1)
            }
            .controlSize(.small)
        }
        .help(job.stageLabel)
    }
}

// MARK: - First-run and empty states

struct StudioArtwork: View {
    private static let image = Bundle.main.url(forResource: "Startup", withExtension: "jpg").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Color(red: 0.025, green: 0.043, blue: 0.095)
            .overlay {
                if let image = Self.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

struct StartupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "AetherNX Studio")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Looking for games…")
                Text("Looking for games…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.83))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background { StudioArtwork().overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
        } }
        .environment(\.colorScheme, .dark)
        .clipShape(.rect(cornerRadius: 18))
        .frame(maxWidth: 920)
        .padding(28)
    }
}

private struct EngineMissingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Find AetherNX", systemImage: "shippingbox")
        } description: {
            Text("AetherNX Studio drives the AetherNX build tools. Choose the folder where you cloned them, or download them to ~/AetherNX.")
        } actions: {
            Button("Choose Folder…") { model.chooseEngineFolder() }
                .buttonStyle(.borderedProminent)
            Button("Download") { model.downloadEngine() }
                .disabled(model.isJobBusy)
        }
        .overlay(alignment: .bottom) {
            if let job = model.job, job.isRunning || job.state == .failed {
                JobCard(job: job)
                    .frame(maxWidth: 520)
                    .padding()
            }
        }
    }
}

private struct LibraryEmptyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Your Games")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a game folder or a library of game folders. Keep one NUP per game folder.")
                    .foregroundStyle(.white.opacity(0.83))
                    .frame(maxWidth: 310, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Add Library Folder…") { model.chooseLibraryFolder(selectsGames: true) }
                .buttonStyle(.borderedProminent)
                Button("Unpack Archive…") { model.chooseArchiveToUnpack() }
                    .disabled(!model.canStartJob)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .background { StudioArtwork().overlay {
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
        } }
        .environment(\.colorScheme, .dark)
        .clipShape(.rect(cornerRadius: 18))
        .frame(maxWidth: 920)
        .padding(28)
    }
}

private struct NoGamesFoundView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Games Found", systemImage: "magnifyingglass")
        } description: {
            if let failure = model.scanFailure {
                Text(failure).textSelection(.enabled)
            } else if let error = model.scanErrors.first {
                Text(error.message).textSelection(.enabled)
            } else {
                Text("No supported game files were found in the selected folders.")
            }
        } actions: {
            Button("Add Library Folder…") { model.chooseLibraryFolder(selectsGames: true) }
                .buttonStyle(.borderedProminent)
            Button("Rescan") { model.rescan() }
            Button("Library Settings…") { model.showSettings(.library) }
        }
    }
}
