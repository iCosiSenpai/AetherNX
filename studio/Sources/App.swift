import AppKit
import SwiftUI

@main
struct AetherNXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("AetherNX", id: "main") {
            ContentView()
                .environment(model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(model: model)
        }

        Window("Console Mode", id: "console") {
            ConsoleView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Asks before quitting while a build runs: quitting stops it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, let job = model.job, job.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop “\(job.title)” and quit?")
        alert.informativeText = String(localized: "The build stops where it is. The next build picks up the finished steps.")
        alert.addButton(withTitle: String(localized: "Stop and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        job.cancel()
        return .terminateNow
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("Add Library Folder…") { model.chooseLibraryFolder() }
                .keyboardShortcut("o")
            Button("Unpack Archive…") { model.chooseArchiveToUnpack() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!model.canStartJob)
            Divider()
            Button("Add Update or DLC…") { model.importPackagesIntoSelectedGame() }
                .keyboardShortcut("i")
                .disabled(model.selectedGame?.isBuildable != true)
        }

        CommandMenu("Game") {
            let game = model.selectedGame
            Button("Play") { if let game { model.play(game) } }
                .keyboardShortcut("r")
                .disabled(game?.macApp == nil)
            Divider()
            ForEach(BuildTarget.menuOrder) { target in
                Button(target.commandTitle) { if let game { model.build(game, target: target) } }
                    .keyboardShortcut(target.shortcut.key, modifiers: target.shortcut.modifiers)
                    .disabled(game?.isBuildable != true || !model.canStartJob)
            }
            Button("Unpack") { if let game { model.unpack(game) } }
                .disabled(game?.kind != .archives || !model.canStartJob)
            Button("Stop") { model.job?.cancel() }
                .keyboardShortcut(".")
                .disabled(model.job?.isRunning != true)
            Divider()
            Button("Show in Finder") { if let game { Finder.reveal(game.folder) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(game == nil)
            Button("Rescan Library") { model.rescan() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button(model.showsActivity ? "Hide Activity" : "Show Activity") { model.showsActivity.toggle() }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            Button("Console Mode") { openWindow(id: "console") }
                .keyboardShortcut("c", modifiers: [.command, .control])
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Check Setup…") { model.showsSetupCheck = true }
            Divider()
            Link("AetherNX on GitHub", destination: Links.repository)
            Link("Report a Problem", destination: Links.issues)
            Link("Release Notes", destination: Links.releases)
        }
    }
}

enum Links {
    static let repository = URL(string: "https://github.com/iCosiSenpai/AetherNX")!
    static let issues = URL(string: "https://github.com/iCosiSenpai/AetherNX/issues")!
    static let releases = URL(string: "https://github.com/iCosiSenpai/AetherNX/releases")!
    static let engineGit = "https://github.com/iCosiSenpai/AetherNX.git"
}
