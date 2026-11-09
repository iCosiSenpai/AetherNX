import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(search: search)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                DetailContainer()
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
        .animation(.easeOut(duration: 0.2), value: model.showsActivity)
    }
}

/// The detail column: what to do first when something is missing, else the selected game.
private struct DetailContainer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.engine == nil {
            EngineMissingView()
        } else if model.libraryFolders.isEmpty {
            LibraryEmptyView()
        } else if let game = model.selectedGame {
            GameDetailView(game: game)
                .id(game.id)
        } else if model.isScanning || !model.hasScanned {
            ProgressView("Looking for games…")
                .controlSize(.small)
        } else if model.games.isEmpty {
            NoGamesFoundView()
        } else {
            ContentUnavailableView("Select a Game", systemImage: "gamecontroller", description: Text("Choose a game in the sidebar."))
        }
    }
}

private struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Add Library Folder…", systemImage: "folder.badge.plus") { model.chooseLibraryFolder() }
                Button("Unpack Archive…", systemImage: "archivebox") { model.chooseArchiveToUnpack() }
                    .disabled(!model.canStartJob)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add games")
            .disabled(model.engine == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            if let job = model.job, job.isRunning {
                JobToolbarIndicator(job: job)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showsActivity.toggle()
            } label: {
                Label("Activity", systemImage: "list.bullet.rectangle")
            }
            .help("Show or hide the activity log (⇧⌘Y)")
        }
    }
}

/// A compact progress ring in the toolbar while a job runs, visible from every game.
private struct JobToolbarIndicator: View {
    let job: Job
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            if let id = job.gameID { model.selectedGameID = id } else { model.showsActivity = true }
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
                .disabled(!model.canStartJob)
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
        ContentUnavailableView {
            Label("Add Your Games", systemImage: "gamecontroller")
        } description: {
            Text("Choose the folder that holds your games, one folder per game with the base game, its update and DLC (.nsp, .xci, .nsz or .xcz).")
        } actions: {
            Button("Choose Library Folder…") { model.chooseLibraryFolder() }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct NoGamesFoundView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Games Found", systemImage: "magnifyingglass")
        } description: {
            if let failure = model.scanFailure {
                Text(failure)
            } else {
                Text("Put each game in its own folder inside a library folder, with its packages or an archive of them.")
            }
        } actions: {
            Button("Rescan") { model.rescan() }
            SettingsLink { Text("Library Settings…") }
        }
    }
}
