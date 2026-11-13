import SwiftUI
import UIKit

/// The games of the library folder, as cards: more columns as the screen grows (an iPad, an iPhone turned).
struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var picking = false
    @State private var path: [GameFolder.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if store.hasLoaded && store.games.isEmpty {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        summary
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 16)], spacing: 16) {
                            ForEach(store.games) { game in
                                NavigationLink(value: game.id) { GameCard(game: game) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .refreshable { await store.reload() }
            .navigationTitle(store.title)
            .navigationDestination(for: GameFolder.ID.self) { id in GameView(id: id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await store.reload() } } label: { Label("Read Again", systemImage: "arrow.clockwise") }
                        Divider()
                        Button { picking = true } label: { Label("Choose Another Folder…", systemImage: "folder") }
                        if !store.isDemo {
                            Button { store.useDemo() } label: { Label("Look at the Demo Library", systemImage: "sparkles") }
                        }
                        Button(role: .destructive) { store.forget() } label: { Label("Forget This Library", systemImage: "xmark.circle") }
                    } label: {
                        Label("Library", systemImage: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if store.isLoading && !store.hasLoaded { ProgressView() }
            }
            .onChange(of: store.games.count) {
                // `-game <folder name>` opens that game's page (screenshots, and checking a page in the Simulator)
                let args = ProcessInfo.processInfo.arguments
                if path.isEmpty, let i = args.firstIndex(of: "-game"), i + 1 < args.count, store.game(args[i + 1]) != nil { path = [args[i + 1]] }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.choose(url) }
        }
    }

    private var summary: some View {
        let onDevice = store.games.filter { $0.manifest?.bundleId != nil }.count
        return VStack(alignment: .leading, spacing: 2) {
            Label(store.isDemo ? String(localized: "Invented games, in this app's own folder") : String(localized: "iCloud Drive › \(store.title)"),
                  systemImage: store.isDemo ? "sparkles" : "icloud")
            Text("\(store.games.count) games · \(onDevice) on iPhone or iPad")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No Games Here Yet", systemImage: "gamecontroller")
        } description: {
            Text("A game appears once AetherNX on the Mac has made its folder here: choose iCloud Drive › AetherNX in its Settings → General → Cloud saves, then build or install the game.")
        } actions: {
            Button("Choose Another Folder…") { picking = true }
        }
        .padding(.top, 80)
    }
}

/// One game: its picture, name, version and what its save last did.
struct GameCard: View {
    let game: GameFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GameIcon(game: game)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Label(saveLine, systemImage: game.save == nil ? "icloud.slash" : "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .labelStyle(CompactLabel())
                HStack(spacing: 6) {
                    if let version = game.manifest?.version { Chip(text: Text(verbatim: version), systemImage: nil) }
                    if game.modsOn > 0 {
                        Chip(text: Text(verbatim: "\(game.modsOn)"), systemImage: "puzzlepiece.extension")
                            .accessibilityLabel(Text("\(game.modsOn) mods"))
                    }
                    if game.cheatsOnCount > 0 && game.cheatsMasterOn {
                        Chip(text: Text(verbatim: "\(game.cheatsOnCount)"), systemImage: "wand.and.stars")
                            .accessibilityLabel(Text("\(game.cheatsOnCount) cheats"))
                    }
                    if !game.isDescribed { Chip(text: Text("Not described"), systemImage: "questionmark") }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    /// Short, for a narrow card: when and from which kind of device, beside a cloud.
    private var saveLine: String {
        guard let save = game.save else { return String(localized: "No cloud save") }
        if save.pending { return String(localized: "Coming from iCloud…") }
        guard let header = save.header else { return String(localized: "Not the engine's save") }
        return "\(header.saved.formatted(.relative(presentation: .named))) · \(header.deviceKind)"
    }
}

/// Icon and title close together.
struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

struct Chip: View {
    let text: Text
    let systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            text
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
        .lineLimit(1)
    }
}

/// The game's picture from its folder, else its initials on a color made from its name.
struct GameIcon: View {
    let game: GameFolder

    var body: some View {
        GeometryReader { geo in
            Group {
                if let url = game.iconURL, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [hue(0), hue(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(verbatim: initials)
                            .font(.system(size: geo.size.width * 0.34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(.rect(cornerRadius: geo.size.width * 0.16, style: .continuous))
        }
    }

    private var initials: String {
        let words = game.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }

    private func hue(_ shift: Double) -> Color {
        let seed = game.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: (Double(seed % 360) / 360 + shift).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.72)
    }
}
