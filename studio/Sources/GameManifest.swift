import Foundation

/// `game.json` in a game's folder of iCloud Drive › AetherNX: what the iPhone and iPad companion lists the game by, its name and picture rather than
/// its title ID (docs/companion.md, game.json). Studio is its only writer: after every library scan and when a game's cloud folder is chosen.
enum GameManifest {
    static let fileName = "game.json"
    static let format = 1

    struct Contents: Codable, Equatable {
        var format: Int
        var name: String
        var titleId: String
        var version: String?
        var icon: String?
        var bundleId: String?
    }

    /// What one game's folder gets, taken on the main actor and written off it.
    struct Item: Sendable {
        var folder: String
        var contents: Contents
        /// The picture to copy beside it, as Studio shows it.
        var iconSource: String?
    }

    /// The game's folder in iCloud Drive › AetherNX, or nil when it has none. `macSetting` is its Mac app's cloud saves setting (nil when the game is
    /// not built for this Mac): that folder when it is a game folder of AetherNX. A game with no Mac app takes the folder the library's setting gives it.
    static func folder(macSetting: CloudSaves.Setting?, libraryFolder: String, gameName: String, home: String = NSHomeDirectory()) -> String? {
        let aether = CloudSaves.aetherFolder(home: home)
        let candidate: String
        if let macSetting {
            guard let folder = macSetting.folder else { return nil }
            candidate = folder
        } else {
            candidate = CloudSaves.libraryTarget(libraryFolder, gameName: gameName, home: home)
        }
        let path = (candidate as NSString).standardizingPath
        return !candidate.isEmpty && (path as NSString).deletingLastPathComponent == aether ? path : nil
    }

    /// The file's bytes: sorted keys, so two Macs with the same library write the same file.
    static func encode(_ contents: Contents) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return ((try? encoder.encode(contents)) ?? Data()) + Data("\n".utf8)
    }

    /// The picture's name in the game's folder: icon.jpg or icon.png, after the source's kind.
    static func iconName(for source: String) -> String {
        ["png"].contains((source as NSString).pathExtension.lowercased()) ? "icon.png" : "icon.jpg"
    }

    /// Writes the picture and the file where they changed; returns whether anything was written. Nothing is written when the content is the same,
    /// so iCloud carries nothing new while the library stays the same.
    @discardableResult
    static func write(_ item: Item) -> Bool {
        let fm = FileManager.default
        guard (try? fm.createDirectory(atPath: item.folder, withIntermediateDirectories: true)) != nil else { return false }
        var contents = item.contents
        var changed = false
        if let source = item.iconSource, let picture = try? Data(contentsOf: URL(filePath: source)), !picture.isEmpty {
            let name = iconName(for: source)
            let dest = (item.folder as NSString).appendingPathComponent(name)
            if (try? Data(contentsOf: URL(filePath: dest))) != picture {
                changed = (try? picture.write(to: URL(filePath: dest), options: .atomic)) != nil || changed
            }
            for other in ["icon.jpg", "icon.png"] where other != name {
                try? fm.removeItem(atPath: (item.folder as NSString).appendingPathComponent(other))
            }
            contents.icon = name
        } else {
            contents.icon = nil
        }
        let data = encode(contents)
        let file = URL(filePath: (item.folder as NSString).appendingPathComponent(fileName))
        if (try? Data(contentsOf: file)) != data {
            changed = (try? data.write(to: file, options: .atomic)) != nil || changed
        }
        return changed
    }
}

extension AppModel {
    /// The game.json of every game with a folder in iCloud Drive › AetherNX, written off the main thread (a file iCloud has not downloaded yet makes
    /// its read wait).
    func publishManifests(_ only: [Game]? = nil) {
        let library = UserDefaults.standard.string(forKey: Pref.cloudSavesFolder) ?? ""
        var items: [GameManifest.Item] = []
        for game in only ?? games {
            guard let id = game.titleId, game.macApp != nil || game.deviceInstall != nil || !game.ipas.isEmpty else { continue }
            let setting = game.macApp == nil ? nil : CloudSaves.domain(for: game).map { CloudSaves.setting(domain: $0) }
            if game.macApp != nil && setting == nil { continue }
            guard let folder = GameManifest.folder(macSetting: setting, libraryFolder: library, gameName: game.name) else { continue }
            // A game installed only on a device: its folder, with Mods and Cheats, made the first time (applyCloudSavesFolder makes the Mac apps')
            if game.macApp == nil, !FileManager.default.fileExists(atPath: folder) { GameExtras.prepare(folder: folder, game: game) }
            let contents = GameManifest.Contents(format: GameManifest.format, name: game.name, titleId: id.uppercased(), version: game.displayVersion,
                                                 icon: nil, bundleId: game.deviceInstall?.bundleId)
            items.append(.init(folder: folder, contents: contents, iconSource: artwork.icon(for: game)))
        }
        guard !items.isEmpty else { return }
        Task.detached(priority: .utility) {
            for item in items { GameManifest.write(item) }
        }
    }
}
