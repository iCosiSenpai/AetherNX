import Foundation
import Observation

/// The library the app shows: the folder the person chose (iCloud Drive › AetherNX), kept as a security-scoped bookmark as the game apps keep
/// their Cloud saves folder, or the demo library in the app's own Documents.
@MainActor
@Observable
final class LibraryStore {
    enum Source: Equatable {
        case none
        case folder(URL)
        case demo(URL)

        var url: URL? {
            switch self {
            case .none: nil
            case .folder(let url), .demo(let url): url
            }
        }
    }

    private(set) var source: Source = .none
    private(set) var games: [GameFolder] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var message: String?

    @ObservationIgnored private var scoped: URL?
    @ObservationIgnored private var loads = 0

    private static let bookmarkKey = "library.bookmark"
    private static let demoKey = "library.demo"

    static var demoFolder: URL { URL.documentsDirectory.appending(path: "Demo") }

    init() {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-demo") {   // screenshots and the Simulator: build.sh --run passes it
            try? DemoLibrary.write(to: Self.demoFolder)
            source = .demo(Self.demoFolder)
        } else if let data = defaults.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { scoped = url }
                if stale, let fresh = try? url.bookmarkData() { defaults.set(fresh, forKey: Self.bookmarkKey) }
                source = .folder(url)
            } else {
                defaults.removeObject(forKey: Self.bookmarkKey)
                message = String(localized: "The library folder could not be found again: choose it once more.")
            }
        } else if defaults.bool(forKey: Self.demoKey) {
            source = .demo(Self.demoFolder)
        }
    }

    var title: String {
        switch source {
        case .none: String(localized: "AetherNX")
        case .folder(let url): url.lastPathComponent
        case .demo: String(localized: "Demo Library")
        }
    }

    var isDemo: Bool { if case .demo = source { true } else { false } }

    // MARK: Choosing the library

    /// The folder from the Files picker: its scope kept for as long as the app runs, its bookmark for the next launch.
    func choose(_ url: URL) {
        stopAccess()
        let granted = url.startAccessingSecurityScopedResource()
        guard let bookmark = try? url.bookmarkData() else {
            if granted { url.stopAccessingSecurityScopedResource() }
            message = String(localized: "iOS did not let the app remember this folder. Choose it again, or another one.")
            return
        }
        if granted { scoped = url }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        source = .folder(url)
        games = []
        Task { await reload() }
    }

    func useDemo() {
        stopAccess()
        try? DemoLibrary.write(to: Self.demoFolder)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        source = .demo(Self.demoFolder)
        games = []
        Task { await reload() }
    }

    func forget() {
        stopAccess()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        source = .none
        games = []
        hasLoaded = false
    }

    private func stopAccess() {
        scoped?.stopAccessingSecurityScopedResource()
        scoped = nil
    }

    // MARK: Reading

    /// Reads the folder again, off the main thread (a file iCloud is bringing in makes a read wait).
    func reload() async {
        guard let root = source.url else { return }
        loads += 1
        let load = loads
        isLoading = true
        let found = await Task.detached(priority: .userInitiated) { LibraryReader.read(root: root) }.value
        guard load == loads, source.url == root else { return }   // a later reload or another folder won
        games = found
        isLoading = false
        hasLoaded = true
    }

    func game(_ id: GameFolder.ID) -> GameFolder? { games.first { $0.id == id } }

    /// Reads one game again after a change.
    private func refresh(_ game: GameFolder) async {
        let url = game.url
        guard let fresh = await Task.detached(priority: .userInitiated, operation: { LibraryReader.readGame(url) }).value,
              let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = fresh
    }

    // MARK: Changes

    func setMod(_ mod: Mod, on: Bool, in game: GameFolder) async {
        await change(game) { GameActions.setMod(mod.name, on: on, in: game) }
    }

    func moveMods(from: IndexSet, to: Int, in game: GameFolder) async {
        var names = game.orderedMods.map(\.name)
        names.move(fromOffsets: from, toOffset: to)
        let order = names
        await change(game) { GameActions.orderMods(order, in: game) }
    }

    func setCheat(_ entry: CheatFile.Entry, on: Bool, file: CheatFile, in game: GameFolder) async {
        await change(game) { GameActions.setCheat(entry.key, on: on, file: file, in: game) }
    }

    func setCheatsMaster(on: Bool, in game: GameFolder) async {
        await change(game) { GameActions.setCheatsMaster(on: on, in: game) }
    }

    func backUp(_ game: GameFolder) async {
        let made = await Task.detached(priority: .userInitiated) { GameActions.backUp(game) }.value
        if made == nil { message = String(localized: "The save could not be copied: it may not be on this device yet.") }
        await refresh(game)
    }

    private func change(_ game: GameFolder, _ write: @escaping @Sendable () -> Bool) async {
        let ok = await Task.detached(priority: .userInitiated) { write() }.value
        if !ok { message = String(localized: "The change could not be written to the game's folder.") }
        await refresh(game)
    }
}
