import SwiftUI

/// The library's home: the game played last, with its picture, what stands where (tools, keys, devices, cloud, updates) and every game as a tile.
/// The grid takes as many columns as the window has room for, so a large or external display shows more games, not more empty space.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var lastPlayed: Game? {
        model.games.filter { $0.isBuildable }.max { a, b in
            (model.playLog.record(for: a)?.lastPlayed ?? .distantPast) < (model.playLog.record(for: b)?.lastPlayed ?? .distantPast)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if let job = model.job {
                    JobCard(job: job, showsGameName: job.gameID.flatMap { id in model.games.first { $0.id == id }?.name })
                }
                if let game = lastPlayed {
                    FeaturedGame(game: game)
                }
                StatusTiles()
                if !model.games.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("All Games")
                            .font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)], alignment: .leading, spacing: 18) {
                            ForEach(model.games) { game in
                                GameTile(game: game)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .measuringLayoutWidth()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Library")
                .font(.largeTitle.weight(.bold))
            Text(summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var summary: String {
        var parts = [model.games.count == 1 ? String(localized: "1 game") : String(localized: "\(model.games.count) games")]
        let seconds = model.games.compactMap { model.playLog.record(for: $0)?.seconds }.reduce(0, +)
        if seconds >= 60 {
            parts.append(String(localized: "\(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) played"))
        }
        let built = model.games.filter { $0.macApp != nil }.count
        if built > 0 { parts.append(String(localized: "\(built) ready on this Mac")) }
        let installed = model.games.filter { $0.deviceInstall != nil }.count
        if installed > 0 { parts.append(String(localized: "\(installed) on iPhone or iPad")) }
        return parts.joined(separator: " · ")
    }
}

/// The last game played, large: its banner behind, what it is, and the buttons to go on.
private struct FeaturedGame: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @Environment(\.layoutWidth) private var layoutWidth

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 18) {
                GameIcon(game: game, size: layoutWidth == .compact ? 72 : 104)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.playLog.record(for: game)?.lastPlayed == nil ? "Ready to Play" : "Continue Playing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)
                    Text(game.name)
                        .font(.system(size: layoutWidth == .compact ? 24 : 32, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let record = model.playLog.record(for: game), !record.summary.isEmpty {
                        Text(record.summary)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    if game.macApp != nil {
                        Button {
                            model.play(game)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Button("Open") { model.selectedGameID = game.id }
                        .controlSize(.large)
                }
            }
            .padding(22)
        }
        .frame(height: layoutWidth == .wide ? 300 : 240)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .contextMenu { GameContextMenu(game: game) }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let path = model.artwork.banner(for: game) ?? model.artwork.icon(for: game), let image = IconCache.backdrop(at: path) ?? IconCache.image(at: path) {
            Color.black.overlay {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.black.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Small tiles of what the app depends on, each opening the page where it is set.
private struct StatusTiles: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12)], alignment: .leading, spacing: 12) {
            tile(title: "AetherNX Engine", value: engineValue, systemImage: "shippingbox", ok: model.engine != nil && !model.updates.toolsUpdateAvailable) {
                model.sidebarSelection = .page(.updates)
            }
            tile(title: "Keys", value: model.keys.isUsable ? String(localized: "prod.keys ready") : String(localized: "Not set: builds need them"),
                 systemImage: "key", ok: model.keys.isUsable) { model.showSettings(.keys) }
            tile(title: "Devices", value: devicesValue, systemImage: "iphone.gen3", ok: model.devices.devices.contains(where: \.isReachable)) {
                model.sidebarSelection = .page(.devices)
            }
            tile(title: "Cloud", value: cloudValue, systemImage: "icloud", ok: !(UserDefaults.standard.string(forKey: Pref.cloudSavesFolder) ?? "").isEmpty) {
                model.showSettings(.cloud)
            }
            tile(title: "Updates", value: updatesValue, systemImage: "arrow.down.circle", ok: !model.updates.hasUpdates) {
                model.sidebarSelection = .page(.updates)
            }
        }
        .onAppear { if !model.devices.hasLoaded, model.engine != nil { model.devices.refresh(engine: model.engine) } }
    }

    private var engineValue: String {
        guard model.engine != nil else { return String(localized: "Not found") }
        if model.updates.toolsUpdateAvailable, let tools = model.updates.tools { return String(localized: "\(tools.behind) new changes to install") }
        return model.engineVersion.map { String(localized: "Version \($0), up to date") } ?? String(localized: "Ready")
    }

    private var devicesValue: String {
        let reachable = model.devices.devices.filter(\.isReachable)
        if let first = reachable.first { return reachable.count == 1 ? String(localized: "\(first.name) connected") : String(localized: "\(reachable.count) connected") }
        if !model.devices.devices.isEmpty { return String(localized: "\(model.devices.devices.count) paired, none connected") }
        return model.devices.hasLoaded ? String(localized: "None paired") : String(localized: "Looking…")
    }

    private var cloudValue: String {
        let folder = UserDefaults.standard.string(forKey: Pref.cloudSavesFolder) ?? ""
        return folder.isEmpty ? String(localized: "Saves stay on this Mac") : CloudSaves.displayName(folder)
    }

    private var updatesValue: String {
        if model.updates.isChecking { return String(localized: "Checking…") }
        if let release = model.updates.appRelease { return String(localized: "AetherNX \(release.version) is out") }
        if model.updates.toolsUpdateAvailable { return String(localized: "Engine changes to install") }
        if model.updates.upstreamChanges > 0 { return String(localized: "Up to date; nxnative has \(model.updates.upstreamChanges) new changes") }
        return String(localized: "Everything is up to date")
    }

    private func tile(title: LocalizedStringKey, value: String, systemImage: String, ok: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundStyle(ok ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(value)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A game in the home's grid: its picture, its name, where it is built, how long it was played.
private struct GameTile: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.selectedGameID = game.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    picture
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                        .shadow(color: .black.opacity(hovering ? 0.3 : 0.12), radius: hovering ? 12 : 5, y: hovering ? 6 : 2)
                    if let job = model.jobFor(game), job.isRunning {
                        ProgressView(value: job.fraction ?? 0)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                            .padding(8)
                    } else if game.isSwitch2 {
                        Switch2Badge().padding(8)
                    }
                }
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if game.macApp != nil { chip("Mac", systemImage: "laptopcomputer") }
                    if game.deviceInstall != nil { chip("iPhone", systemImage: "iphone") }
                    if game.macApp == nil && game.deviceInstall == nil { chip(game.kind == .archives ? "Archive" : "Not built", systemImage: "hammer") }
                    Spacer(minLength: 0)
                    if let record = model.playLog.record(for: game), record.seconds >= 60 {
                        Text(Duration.seconds(record.seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 1)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { GameContextMenu(game: game) }
        .help(game.name)
    }

    @ViewBuilder
    private var picture: some View {
        if let path = model.artwork.icon(for: game), let image = IconCache.image(at: path) {
            Color.clear.overlay {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }
            .task(id: model.artwork.lookupKey(for: game)) { model.artwork.request(game) }
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: game.kind == .archives ? "archivebox" : "gamecontroller")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                }
                .task(id: model.artwork.lookupKey(for: game)) { model.artwork.request(game) }
        }
    }

    private func chip(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
