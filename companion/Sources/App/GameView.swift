import SwiftUI

/// A game's page: open its app, and its saves, mods and cheats as its folder holds them.
struct GameView: View {
    let id: GameFolder.ID
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var notAnswering = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        if let game = store.game(id) {
            ScrollViewReader { proxy in
                List {
                    header(game)
                    SavesSection(game: game).id("saves")
                    ModsSection(game: game, editMode: $editMode).id("mods")
                    CheatsSections(game: game).id("cheats")
                    folderSection(game).id("folder")
                }
                .onAppear {
                    // `-section saves|mods|cheats|folder` scrolls there (screenshots, and checking a page in the Simulator)
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-section"), i + 1 < args.count {
                        let section = args[i + 1]
                        Task { try? await Task.sleep(for: .milliseconds(300)); proxy.scrollTo(section, anchor: .top) }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(game.name)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.reload() }
            .alert("This game's app does not answer yet", isPresented: $notAnswering) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open it from the Home Screen. Game apps built by a later AetherNX open from here: they learn the link aethernx-\(game.titleId?.lowercased() ?? "…")://.")
            }
        } else {
            ContentUnavailableView("This Game Is Gone", systemImage: "questionmark.folder", description: Text("Its folder is no longer in the library."))
        }
    }

    private func header(_ game: GameFolder) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    GameIcon(game: game)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.name)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        if let version = game.manifest?.version {
                            Text("Version \(version)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Label(game.manifest?.bundleId != nil ? "Installed on iPhone or iPad" : "Not on iPhone or iPad yet",
                              systemImage: game.manifest?.bundleId != nil ? "iphone" : "macbook")
                            .labelStyle(CompactLabel())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    play(game)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(game.titleId == nil)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
    }

    private func play(_ game: GameFolder) {
        guard let id = game.titleId, let url = URL(string: "aethernx-\(id.lowercased())://play") else { return }
        openURL(url) { accepted in
            if !accepted { notAnswering = true }
        }
    }

    private func folderSection(_ game: GameFolder) -> some View {
        Section {
            LabeledContent("Folder") {
                Text(store.isDemo ? String(localized: "Demo › \(game.url.lastPathComponent)") : String(localized: "iCloud Drive › \(store.title) › \(game.url.lastPathComponent)"))
                    .multilineTextAlignment(.trailing)
            }
            if let id = game.titleId {
                LabeledContent("Title ID") { Text(verbatim: id).font(.callout.monospaced()) }
            }
            if !game.pending.isEmpty {
                LabeledContent("Coming from iCloud") { Text(verbatim: game.pending.joined(separator: ", ")).multilineTextAlignment(.trailing) }
            }
        } header: {
            Text("This game's folder")
        } footer: {
            if !game.isDescribed {
                Text("No game.json here: AetherNX on the Mac writes it at its next library scan, with the game's name, version and picture.")
            }
        }
    }
}

// MARK: - Saves

private struct SavesSection: View {
    let game: GameFolder
    @Environment(LibraryStore.self) private var store
    @State private var working = false

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: game.save == nil ? "icloud.slash" : "icloud")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("In iCloud")
                        .font(.body.weight(.medium))
                    ForEach(lines, id: \.self) { line in
                        Text(line).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            Button {
                working = true
                Task { await store.backUp(game); working = false }
            } label: {
                Label("Back Up Now", systemImage: "clock.arrow.circlepath")
            }
            .disabled(game.save == nil || game.save?.pending == true || working)
            ForEach(game.backups) { backup in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backup.header.map { $0.saved.formatted(date: .abbreviated, time: .shortened) } ?? backup.url.deletingPathExtension().lastPathComponent)
                        Text(backup.header.map { String(localized: "From \($0.deviceKind) · \(backup.size.formatted(.byteCount(style: .file)))") }
                             ?? backup.size.formatted(.byteCount(style: .file)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLink(item: backup.url) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Saves")
        } footer: {
            Text("Backups are copies of the cloud's save in this game's Backups folder. Each device also keeps the save a sync replaced. Restoring a backup from here comes later: the engine would take an older copy for an older save.")
        }
    }

    private var lines: [String] {
        guard let save = game.save else {
            return [String(localized: "No save in the cloud yet. The game sends one after it next saves, once its Cloud saves folder is this game's folder.")]
        }
        if save.pending { return [String(localized: "On its way from iCloud: read again in a moment.")] }
        guard let header = save.header else { return [String(localized: "save.dmsync is there, but it is not a save the engine wrote.")] }
        return [
            String(localized: "Saved \(header.saved.formatted(date: .abbreviated, time: .shortened)) on \(header.deviceKind) (\(header.device))"),
            String(localized: "\(Int(header.entries)) files and folders · \(save.size.formatted(.byteCount(style: .file)))"),
        ]
    }
}

// MARK: - Mods

private struct ModsSection: View {
    let game: GameFolder
    @Binding var editMode: EditMode
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let mods = game.orderedMods
        Section {
            if mods.isEmpty {
                Text("No mods. Add them on the Mac (the game's page → Mods → Add…), or put a mod's folder, with a romfs folder inside, in Mods with the Files app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(mods) { mod in
                Toggle(isOn: Binding(get: { game.isOn(mod) }, set: { on in Task { await store.setMod(mod, on: on, in: game) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: mod.name)
                        if !mod.usable {
                            Text(mod.hasCode ? "Patches the game's code (exefs): the engine does not run code mods." : "No romfs folder inside: not a mod the engine can use.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else if mod.hasCode {
                            Text("Its file changes are used; its code patches are not.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!mod.usable)
            }
            .onMove { from, to in Task { await store.moveMods(from: from, to: to, in: game) } }
        } header: {
            HStack {
                Text("Mods")
                Spacer()
                if mods.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
                }
            }
        } footer: {
            if !mods.isEmpty {
                Text("Higher mods win when two change the same file. The Mac app uses them from its next start, once AetherNX on the Mac has read this list. The iPhone and iPad apps do not read mods yet.")
            }
        }
    }
}

// MARK: - Cheats

private struct CheatsSections: View {
    let game: GameFolder
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Section {
            if game.cheats.isEmpty {
                Text("No cheat files. Put Atmosphère cheat files, named by the game's build ID (<build ID>.txt), in this game's Cheats folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Toggle(isOn: Binding(get: { game.cheatsMasterOn }, set: { on in Task { await store.setCheatsMaster(on: on, in: game) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All Cheats")
                        Text("\(game.cheatsOnCount) of \(game.cheatCount) on")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Cheats")
        } footer: {
            if !game.cheats.isEmpty {
                Text("Turned off here, no cheat of the game runs, and each one keeps its switch for later.")
            }
        }
        ForEach(game.cheats) { file in
            Section {
                ForEach(file.entries) { entry in
                    row(entry, file: file)
                }
            } header: {
                Text("Build \(file.buildId)")
                    .font(.footnote.monospaced())
            } footer: {
                if file.id == game.cheats.last?.id {
                    Text("Cheats fit one version of the game: the file's name is its build ID. The game reads them when it starts; while it runs, use its Reload Cheats. The iPhone and iPad apps do not read this folder yet.")
                }
            }
            .disabled(!game.cheatsMasterOn)
        }
    }

    @ViewBuilder
    private func row(_ entry: CheatFile.Entry, file: CheatFile) -> some View {
        switch entry.kind {
        case .cheat:
            Toggle(entry.key, isOn: Binding(get: { game.cheatsOn.contains(file.buildId + "/" + entry.key) },
                                            set: { on in Task { await store.setCheat(entry, on: on, file: file, in: game) } }))
        case .master:
            LabeledContent(entry.key) { Text("Always on") }
        case .label:
            Text(verbatim: entry.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        case .broken:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                Text("Its lines are not code: the engine skips it.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
