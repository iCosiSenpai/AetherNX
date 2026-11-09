import CoreImage
import SwiftUI

struct SidebarView: View {
    let search: String
    @Environment(AppModel.self) private var model

    private var filtered: [Game] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.games }
        return model.games.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.titleId ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedGameID) {
            Section {
                ForEach(filtered) { game in
                    GameRow(game: game, job: model.jobFor(game))
                        .tag(game.id)
                        .contextMenu { GameContextMenu(game: game) }
                }
            } header: {
                if !model.games.isEmpty { Text("Library") }
            }
            if !model.scanErrors.isEmpty {
                Section("Not Recognised") {
                    ForEach(model.scanErrors, id: \.folder) { error in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((error.folder as NSString).lastPathComponent)
                                Text(error.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        } icon: {
                            Image(systemName: "questionmark.folder")
                        }
                        .selectionDisabled()
                        .contextMenu { Button("Show in Finder") { Finder.reveal(error.folder) } }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !search.isEmpty && filtered.isEmpty { ContentUnavailableView.search(text: search) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }
}

private struct GameRow: View {
    let game: Game
    let job: Job?

    var body: some View {
        HStack(spacing: 10) {
            GameIcon(game: game, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.name)
                    .lineLimit(1)
                Group {
                    if let job, job.isRunning {
                        Text(job.title)
                    } else {
                        Text(game.summary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let job, job.isRunning {
                ProgressView().controlSize(.mini)
            } else if game.macApp != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Mac app built")
                    .accessibilityLabel("Mac app built")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct GameContextMenu: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        if game.macApp != nil {
            Button("Play") { model.play(game) }
            Divider()
        }
        if game.isBuildable {
            ForEach(BuildTarget.menuOrder) { target in
                Button(target.commandTitle) { model.build(game, target: target) }
                    .disabled(!model.canStartJob)
            }
        } else {
            Button("Unpack") { model.unpack(game) }
                .disabled(!model.canStartJob)
        }
        Divider()
        Button("Show in Finder") { Finder.reveal(game.kind == .archives ? game.id : game.folder) }
    }
}

/// Setup problems, kept out of the way until there is one.
private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.engine != nil && !model.keys.isUsable {
            VStack(alignment: .leading, spacing: 6) {
                Label("prod.keys not set", systemImage: "key")
                    .font(.callout.weight(.medium))
                Text("Builds need the keys from your own Switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsLink { Text("Open Settings…") }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(10)
        }
    }
}

/// The game's own icon once a build has extracted it, else a neutral tile.
struct GameIcon: View {
    let game: Game
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let path = game.icon, let image = IconCache.image(at: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(.quaternary)
                    .overlay {
                        Image(systemName: game.kind == .archives ? "archivebox" : "gamecontroller")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// Game icons read once per file and kept while the app runs.
@MainActor
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    private static let backdrops = NSCache<NSString, NSImage>()

    /// The icon blurred, saturated and darkened toward the bottom: Console Mode's background, made once per game.
    static func backdrop(at path: String) -> NSImage? {
        if let image = backdrops.object(forKey: path as NSString) { return image }
        guard let source = CIImage(contentsOf: URL(filePath: path)) else { return nil }
        let small = source.transformed(by: CGAffineTransform(scaleX: 256 / max(source.extent.width, 1), y: 256 / max(source.extent.height, 1)))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 22])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3, kCIInputBrightnessKey: -0.18])
            .cropped(to: small.extent)
        let shade = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 256), "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.4),
            "inputPoint1": CIVector(x: 0, y: 0), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0.85),
        ])?.outputImage?.cropped(to: small.extent)
        let final = shade.map { $0.composited(over: blurred) } ?? blurred
        guard let cg = CIContext().createCGImage(final, from: small.extent) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
        backdrops.setObject(image, forKey: path as NSString)
        return image
    }

    static func image(at path: String) -> NSImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
