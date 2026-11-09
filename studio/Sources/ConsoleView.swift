import AppKit
import SwiftUI

/// Console Mode: the library full screen, for the couch. Arrows or a controller move, A plays (or builds
/// a game not built yet), Y builds again, B goes back.
struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedID: Game.ID?
    @FocusState private var hasKeyboardFocus: Bool

    /// Built games first, the most recently played of them first; then the rest by name.
    private var games: [Game] {
        let log = model.playLog
        return model.games.filter(\.isBuildable).sorted { a, b in
            if (a.macApp != nil) != (b.macApp != nil) { return a.macApp != nil }
            let la = log.record(for: a)?.lastPlayed ?? .distantPast, lb = log.record(for: b)?.lastPlayed ?? .distantPast
            if la != lb { return la > lb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private var focused: Game? { games.first { $0.id == focusedID } ?? games.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConsoleTopBar(gamepad: model.gamepad)
            Spacer(minLength: 24)
            if let game = focused {
                ConsoleHero(game: game, job: model.jobFor(game), played: model.playLog.record(for: game))
                    .id(game.id)
                    .transition(.opacity)
                Spacer(minLength: 32)
                carousel
            } else {
                emptyState
                Spacer()
            }
            Spacer(minLength: 32)
            ConsoleHints(gamepad: model.gamepad, game: focused, canBuild: model.canStartJob)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ConsoleBackground(path: focused.flatMap { model.artwork.backdrop(for: $0) }) }
        .preferredColorScheme(.dark)
        .background(WindowFullScreen())
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(.leftArrow) { handle(.left); return .handled }
        .onKeyPress(.rightArrow) { handle(.right); return .handled }
        .onKeyPress(.return) { handle(.primary); return .handled }
        .onKeyPress(.escape) { handle(.back); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "yY")) { _ in handle(.secondary); return .handled }
        .onAppear {
            hasKeyboardFocus = true
            focusedID = focusedID ?? model.selectedGameID ?? games.first?.id
            model.consoleHandler = { event in handle(event) }
        }
        .onDisappear { model.consoleHandler = nil }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: focusedID)
    }

    private var carousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(games) { game in
                        ConsoleTile(game: game, icon: model.artwork.icon(for: game), isFocused: game.id == focused?.id, isBusy: model.jobFor(game)?.isRunning == true)
                            .task(id: game.titleId) { model.artwork.request(game) }
                            .id(game.id)
                            .onTapGesture(count: 2) { focusedID = game.id; handle(.primary) }
                            .onTapGesture { focusedID = game.id }
                    }
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 12)
            }
            .scrollClipDisabled()
            .onChange(of: focusedID) { _, id in
                guard let id else { return }
                if reduceMotion { proxy.scrollTo(id, anchor: .center) } else { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .frame(height: 280)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No games yet")
                .font(.system(size: 44, weight: .bold))
            Text("Add a library folder in the main window, then come back here to play from the couch.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func handle(_ event: Gamepad.Event) {
        let list = games
        let index = list.firstIndex { $0.id == focused?.id } ?? 0
        switch event {
        case .left: if index > 0 { focusedID = list[index - 1].id }
        case .right: if index + 1 < list.count { focusedID = list[index + 1].id }
        case .up, .down, .menu: break
        case .primary:
            guard let game = focused else { return }
            if game.macApp != nil { model.play(game) } else { model.build(game, target: .mac) }
        case .secondary:
            if let game = focused { model.build(game, target: .mac) }
        case .back:
            dismissWindow(id: "console")
        }
    }
}

// MARK: - Pieces

private struct ConsoleBackground: View {
    let path: String?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let path, let image = IconCache.backdrop(at: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .id(path)
                        .transition(.opacity)
                } else {
                    LinearGradient(colors: [Color(red: 0.14, green: 0.09, blue: 0.36), Color(red: 0.03, green: 0.03, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct ConsoleTopBar: View {
    let gamepad: Gamepad

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            Text("AetherNX")
                .font(.title2.weight(.semibold))
            Spacer()
            if let name = gamepad.name {
                Label {
                    Text(verbatim: name)
                } icon: {
                    Image(systemName: "gamecontroller.fill")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                if let level = gamepad.batteryLevel {
                    Image(systemName: level > 0.75 ? "battery.100" : level > 0.5 ? "battery.75" : level > 0.25 ? "battery.50" : "battery.25")
                        .accessibilityLabel(Text("Battery \(Int(level * 100)) percent"))
                }
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
    }
}

private struct ConsoleHero: View {
    let game: Game
    let job: Job?
    let played: PlayRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if game.isSwitch2 { Switch2Badge().scaleEffect(1.3, anchor: .leading) }
            Text(game.name)
                .font(.system(size: 52, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(details)
            .font(.title3)
            .foregroundStyle(.white.opacity(0.75))
            .monospacedDigit()
            if let job, job.isRunning {
                HStack(spacing: 12) {
                    if let fraction = job.fraction {
                        ProgressView(value: fraction).frame(width: 260)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(job.stageLabel)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 4)
            } else if game.macApp != nil {
                Label("Ready to play", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Label("Not built yet: the first build takes 30 to 60 minutes", systemImage: "hammer")
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
        .frame(maxWidth: 820, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if let version = game.displayVersion { parts.append(String(localized: "Version \(version)")) }
        if !game.dlc.isEmpty { parts.append(String(localized: "\(game.dlc.count) DLC")) }
        if let played, !played.summary.isEmpty { parts.append(played.summary) }
        return parts.joined(separator: " · ")
    }
}

private struct ConsoleTile: View {
    let game: Game
    let icon: String?
    let isFocused: Bool
    let isBusy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 44, style: .continuous)
        Group {
            if let icon, let image = IconCache.image(at: icon) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                // No picture online and none extracted yet: the name on a tile
                LinearGradient(colors: [Color(red: 0.24, green: 0.18, blue: 0.55), Color(red: 0.09, green: 0.07, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Text(game.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(20)
                            .minimumScaleFactor(0.6)
                    }
            }
        }
        .frame(width: 200, height: 200)
        .overlay(alignment: .bottom) {
            if game.macApp == nil {
                Group {
                    if isBusy { Label("Building", systemImage: "hourglass") } else { Label("Needs a build", systemImage: "hammer.fill") }
                }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 14)
            }
        }
        .clipShape(shape)
            .overlay {
                shape.inset(by: -7)
                    .strokeBorder(.white, lineWidth: 4)
                    .opacity(isFocused ? 1 : 0)
            }
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.3), radius: isFocused ? 24 : 10, y: isFocused ? 14 : 6)
            .scaleEffect(isFocused && !reduceMotion ? 1.12 : 1)
            .opacity(isFocused ? 1 : 0.7)
            .accessibilityElement()
            .accessibilityLabel(Text(game.name))
            .accessibilityValue(game.macApp != nil ? Text("Ready to play") : Text("Not built"))
            .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ConsoleHints: View {
    let gamepad: Gamepad
    let game: Game?
    let canBuild: Bool

    var body: some View {
        HStack(spacing: 28) {
            if let game {
                hint(gamepad.glyphs.primary, key: "↩", text: game.macApp != nil ? "Play" : "Build")
                if game.macApp != nil && canBuild {
                    hint(gamepad.glyphs.secondary, key: "Y", text: "Build again")
                }
            }
            hint(gamepad.glyphs.back, key: "esc", text: "Back")
            Spacer()
            if !gamepad.isConnected {
                Text("Connect a controller, or use the arrow keys")
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.title3.weight(.medium))
        .foregroundStyle(.white)
    }

    private func hint(_ glyph: String, key: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            if gamepad.isConnected {
                Image(systemName: glyph)
                    .font(.title2)
            } else {
                Text(verbatim: key)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(text)
        }
    }
}

/// Puts the console window in full screen once it appears.
private struct WindowFullScreen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
