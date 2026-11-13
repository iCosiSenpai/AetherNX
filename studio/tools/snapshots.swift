import AppKit
import SwiftUI
@testable import AetherNXStudio

// Pictures of AetherNX Studio's pages for the README and the website, drawn offscreen from the app's own views with the library and settings of this
// Mac (no window on screen, so it also runs while the screen is locked). studio/tools/snapshots.sh builds and runs it.
//   snapshots <output folder> [light|dark] [width] [height]

let arguments = CommandLine.arguments
let out = URL(filePath: arguments.count > 1 ? arguments[1] : ".")
let dark = arguments.count > 2 ? arguments[2] != "light" : true
let width = arguments.count > 3 ? Double(arguments[3]) ?? 1440 : 1440
let height = arguments.count > 4 ? Double(arguments[4]) ?? 900 : 900

/// A window that draws as the one in front (selected sidebar rows in the accent colour), with no screen to be in front of.
final class FrontWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor
func render(_ view: some View, name: String, size: NSSize) {
    let window = FrontWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    // the accent colour as the app has it in front (offscreen it resolves to grey)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 0.04, green: 0.52, blue: 1.0)))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    for _ in 0..<6 { host.layoutSubtreeIfNeeded(); pump(0.4) }   // async artwork and task(id:) loads land
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("no bitmap for \(name)"); return }
    host.cacheDisplay(in: host.bounds, to: rep)
    let file = out.appending(path: "\(name)-\(dark ? "dark" : "light").png")
    do { try rep.representation(using: .png, properties: [:])?.write(to: file); print("wrote \(file.path)") } catch { print("\(name): \(error)") }
}

MainActor.assumeIsolated {
    // The app's own settings, read into this program's domain (it has no bundle ID of its own); the artwork cache is found by the app's ID
    let domain = "io.github.icosisenpai.aethernx"
    for (key, value) in UserDefaults.standard.persistentDomain(forName: domain) ?? [:] where key != "AppleLanguages" { UserDefaults.standard.set(value, forKey: key) }
    UserDefaults.standard.set(true, forKey: Pref.setupCompleted)
    if let root = ProcessInfo.processInfo.environment["AETHERNX_ROOT"] { UserDefaults.standard.set(root, forKey: Pref.enginePath) }   // the app finds it beside itself
    UserDefaults.standard.set(false, forKey: Pref.checkUpdatesAtLaunch)
    NSApplication.shared.setActivationPolicy(.prohibited)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    let model = AppModel()
    model.snapshotMode = true
    model.showsSetupAssistant = false
    for _ in 0..<120 where !(model.hasScanned && !model.isScanning) { pump(0.5) }
    model.checkForUpdates(userInitiated: false)
    model.devices.refresh(engine: model.engine)
    for _ in 0..<40 where model.updates.isChecking || model.devices.isLoading { pump(0.5) }
    UserDefaults.standard.set(true, forKey: Pref.checkUpdatesAtLaunch)   // as the app is set up, for the Updates page's toggle
    print("engine: \(model.engine?.path ?? "none"), folders: \(model.libraryFolders.count), games: \(model.games.map(\.name))")
    let size = NSSize(width: width, height: height)
    @MainActor func page(_ name: String, _ select: () -> Void) {
        select()
        render(ContentView().environment(model), name: name, size: size)
    }
    page("home") { model.sidebarSelection = .home }
    if let game = model.games.first(where: { $0.isBuildable }) {
        page("game") { model.selectedGameID = game.id }
        render(ScrollView { GameDetailView(game: game) }.environment(model), name: "game-narrow", size: NSSize(width: 760, height: 1100))
    }
    page("updates") { model.sidebarSelection = .page(.updates) }
    page("settings") { model.showSettings(.cloud) }

    // The progress card of a build under way, from the events a build writes
    let job = Job(title: "Installing on iPhone", gameID: model.games.first?.id, target: .device)
    for line in [#"{"ev":"stage","k":1,"n":9,"name":"extract update","step":""}"#, #"{"ev":"stage_end","k":1,"name":"extract update","ok":true,"elapsed":42.1}"#,
                 #"{"ev":"stage","k":2,"n":9,"name":"rewrite","step":""}"#, #"{"ev":"stage_end","k":2,"name":"rewrite","ok":true,"elapsed":8.4}"#,
                 #"{"ev":"stage","k":3,"n":9,"name":"shader split","step":""}"#, #"{"ev":"stage_end","k":3,"name":"shader split","ok":true,"elapsed":131,"summary":"16,888 shaders"}"#,
                 #"{"ev":"stage","k":4,"n":9,"name":"iOS shaders","step":""}"#, #"{"ev":"stage_end","k":4,"name":"iOS shaders","ok":true,"elapsed":962}"#,
                 #"{"ev":"stage","k":5,"n":9,"name":"Pipeline archive","step":"applegpu_g18p: batch 7/24"}"#,
                 #"{"ev":"progress","k":5,"name":"Pipeline archive","step":"applegpu_g18p: batch 7 of 24","frac":0.29,"eta":150}"#] {
        _ = job.handle(line: line, isError: false)
    }
    render(VStack { JobCard(job: job, showsGameName: model.games.first?.name) }.padding(24).frame(width: 760).environment(model),
           name: "progress", size: NSSize(width: 808, height: 360))
}
