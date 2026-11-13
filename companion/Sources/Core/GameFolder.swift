import Foundation

/// One mod of a game's Mods folder, by Studio's rules (studio/Sources/Mods.swift): a folder with a `romfs` folder inside, or Atmosphère's layout.
/// Code mods (`exefs`) do not run.
struct Mod: Identifiable, Equatable, Sendable {
    var name: String
    var url: URL
    var usable: Bool
    var hasCode: Bool
    var id: String { name }
}

/// A copy of the cloud save the companion made, in the game's Backups folder.
struct SaveBackup: Identifiable, Equatable, Sendable {
    var url: URL
    var header: SaveHeader?
    var size: Int64
    var id: String { url.lastPathComponent }
}

/// What the cloud has of a game's save.
struct CloudSave: Equatable, Sendable {
    var url: URL
    /// nil when the file is not on this device yet, or is not a packed save.
    var header: SaveHeader?
    var size: Int64
    var pending: Bool
}

/// A game folder of iCloud Drive › AetherNX, read whole.
struct GameFolder: Identifiable, Equatable, Sendable {
    var url: URL
    var manifest: GameManifest?
    var iconURL: URL?
    /// The title ID: game.json's, else the name of the folder the save is in.
    var titleId: String?
    var save: CloudSave?
    var backups: [SaveBackup] = []
    var mods: [Mod] = []
    var modState = ModState()
    var cheats: [CheatFile] = []
    var cheatsOn: Set<String> = []
    var cheatsMasterOn = true
    /// Files iCloud has not brought to this device yet (game.json, the icon, the save): asked for, read again later.
    var pending: [String] = []

    var id: String { url.lastPathComponent }
    /// Its name from game.json; without one, the folder's name (never the title ID alone).
    var name: String { manifest?.name ?? url.lastPathComponent }
    var isDescribed: Bool { manifest != nil }
    var modsFolder: URL { url.appending(path: "Mods") }
    var cheatsFolder: URL { url.appending(path: "Cheats") }
    var backupsFolder: URL { url.appending(path: "Backups") }

    /// The mods in their order: mods.json's first, the rest by name.
    var orderedMods: [Mod] {
        mods.sorted { a, b in
            let ia = modState.order.firstIndex(of: a.name) ?? Int.max, ib = modState.order.firstIndex(of: b.name) ?? Int.max
            return ia != ib ? ia < ib : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func isOn(_ mod: Mod) -> Bool { mod.usable && !modState.off.contains(mod.name) }
    var modsOn: Int { mods.filter(isOn).count }
    var cheatCount: Int { cheats.reduce(0) { $0 + $1.cheats.count } }
    var cheatsOnCount: Int { cheats.reduce(0) { total, file in total + file.cheats.filter { cheatsOn.contains(file.buildId + "/" + $0.key) }.count } }
}

enum LibraryReader {
    /// Every game folder of the library folder, by name.
    static func read(root: URL) -> [GameFolder] {
        let listing = FileAccess.list(root)
        return listing.names.compactMap { name -> GameFolder? in
            guard !name.hasPrefix("."), FileAccess.isDirectory(root.appending(path: name)) else { return nil }
            return readGame(root.appending(path: name))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One game folder, or nil for a folder that is none: no game.json, no save folder named by a title ID, no Mods or Cheats.
    static func readGame(_ url: URL) -> GameFolder? {
        let listing = FileAccess.list(url)
        var game = GameFolder(url: url)
        if listing.has(GameManifest.fileName) {
            let file = url.appending(path: GameManifest.fileName)
            if listing.pending.contains(GameManifest.fileName) { FileAccess.download(file); game.pending.append(GameManifest.fileName) }
            game.manifest = FileAccess.read(file).flatMap(GameManifest.decode)
        }
        let saveFolders = listing.names.filter { TitleID.isValid($0) && FileAccess.isDirectory(url.appending(path: $0)) }
        game.titleId = game.manifest?.titleId ?? saveFolders.first?.uppercased()
        guard game.manifest != nil || !saveFolders.isEmpty || listing.has("Mods") || listing.has("Cheats") else { return nil }
        if let icon = game.manifest?.icon, listing.has(icon) {
            let file = url.appending(path: icon)
            if listing.pending.contains(icon) { FileAccess.download(file); game.pending.append(icon) } else { game.iconURL = file }
        }
        if let id = game.titleId {
            let folder = saveFolders.first { $0.caseInsensitiveCompare(id) == .orderedSame } ?? id
            game.save = cloudSave(url.appending(path: folder))
            if game.save?.pending == true { game.pending.append("\(folder)/save.dmsync") }
        }
        game.backups = backups(in: game.backupsFolder)
        if let id = game.titleId {
            game.mods = mods(in: game.modsFolder, titleId: id)
            game.modState = FileAccess.read(game.modsFolder.appending(path: ModState.fileName)).flatMap(ModState.decode) ?? ModState()
            game.cheats = cheatFiles(in: game.cheatsFolder, titleId: id)
            for file in game.cheats {
                let on = CheatFile.enabled(in: FileAccess.read(CheatFile.enabledURL(cheatsFolder: game.cheatsFolder, buildId: file.buildId)))
                for key in on { game.cheatsOn.insert(file.buildId + "/" + key) }
            }
            game.cheatsMasterOn = !FileManager.default.fileExists(atPath: CheatFile.masterOffURL(cheatsFolder: game.cheatsFolder, titleId: id).path)
        }
        return game
    }

    static func cloudSave(_ folder: URL) -> CloudSave? {
        let listing = FileAccess.list(folder)
        guard listing.has("save.dmsync") else { return nil }
        let file = folder.appending(path: "save.dmsync")
        if listing.pending.contains("save.dmsync") {
            FileAccess.download(file)
            return CloudSave(url: file, header: nil, size: 0, pending: true)
        }
        return CloudSave(url: file, header: header(of: file), size: size(of: file), pending: false)
    }

    /// The first bytes of a packed save: the header only, never the whole file.
    static func header(of file: URL) -> SaveHeader? {
        var result: SaveHeader?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [.withoutChanges], error: &error) { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }
            result = (try? handle.read(upToCount: SaveHeader.size)).flatMap { SaveHeader($0) }
        }
        return result
    }

    static func size(of file: URL) -> Int64 {
        Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    static func backups(in folder: URL) -> [SaveBackup] {
        FileAccess.list(folder).names.filter { $0.lowercased().hasSuffix(".dmsync") && !$0.hasPrefix(".") }.map { name in
            let file = folder.appending(path: name)
            return SaveBackup(url: file, header: header(of: file), size: size(of: file))
        }
        .sorted { ($0.header?.saved ?? .distantPast) > ($1.header?.saved ?? .distantPast) }
    }

    static func mods(in folder: URL, titleId: String) -> [Mod] {
        let fm = FileManager.default
        return FileAccess.list(folder).names.compactMap { name -> Mod? in
            let mod = folder.appending(path: name)
            guard !name.hasPrefix("."), FileAccess.isDirectory(mod) else { return nil }
            let romfs = ["romfs", "atmosphere/contents/\(titleId)/romfs", "atmosphere/contents/\(titleId.lowercased())/romfs", "contents/\(titleId)/romfs", "\(titleId)/romfs"]
            let code = ["exefs", "atmosphere/contents/\(titleId)/exefs", "atmosphere/exefs_patches"]
            return Mod(name: name, url: mod, usable: romfs.contains { fm.fileExists(atPath: mod.appending(path: $0).path) },
                       hasCode: code.contains { fm.fileExists(atPath: mod.appending(path: $0).path) })
        }
    }

    /// `<build ID>.txt` at the top of the Cheats folder, or in Atmosphère's tree under it (the host's three places).
    static func cheatFiles(in folder: URL, titleId: String) -> [CheatFile] {
        var files: [String: CheatFile] = [:]
        for dir in [folder, folder.appending(path: "atmosphere/contents/\(titleId)/cheats"), folder.appending(path: "contents/\(titleId)/cheats")] {
            for name in FileAccess.list(dir).names {
                guard let build = CheatFile.buildId(ofFileNamed: name), files[build] == nil else { continue }
                let file = dir.appending(path: name)
                guard let data = FileAccess.read(file) else { continue }
                files[build] = CheatFile(buildId: build, url: file, entries: CheatFile.parse(String(decoding: data, as: UTF8.self)))
            }
        }
        return files.values.sorted { $0.buildId < $1.buildId }
    }
}

/// What the companion changes in a game folder: each a whole file, through FileAccess.
enum GameActions {
    /// A mod on or off.
    @discardableResult
    static func setMod(_ name: String, on: Bool, in game: GameFolder) -> Bool {
        var state = game.modState
        state.order = game.orderedMods.map(\.name)
        if on { state.off.removeAll { $0 == name } } else if !state.off.contains(name) { state.off.append(name) }
        return FileAccess.write(state.encoded(), to: game.modsFolder.appending(path: ModState.fileName))
    }

    /// The mods in this order, highest priority first.
    @discardableResult
    static func orderMods(_ names: [String], in game: GameFolder) -> Bool {
        var state = game.modState
        state.order = names
        return FileAccess.write(state.encoded(), to: game.modsFolder.appending(path: ModState.fileName))
    }

    /// One cheat on or off: `<build ID>.enabled` written again.
    @discardableResult
    static func setCheat(_ key: String, on: Bool, file: CheatFile, in game: GameFolder) -> Bool {
        let url = CheatFile.enabledURL(cheatsFolder: game.cheatsFolder, buildId: file.buildId)
        let previous = CheatFile.enabled(in: FileAccess.read(url))
        var now = previous
        if on { now.insert(key) } else { now.remove(key) }
        return FileAccess.write(file.enabledData(on: now, previous: previous), to: url)
    }

    /// All of a game's cheats on or off, with their toggles kept: the host's master switch.
    @discardableResult
    static func setCheatsMaster(on: Bool, in game: GameFolder) -> Bool {
        guard let id = game.titleId else { return false }
        let flag = CheatFile.masterOffURL(cheatsFolder: game.cheatsFolder, titleId: id)
        if on { return !FileManager.default.fileExists(atPath: flag.path) || FileAccess.remove(flag) }
        return FileAccess.write(Data(), to: flag)
    }

    /// A copy of the cloud save in Backups, named by when it was saved and the device it came from.
    static func backUp(_ game: GameFolder) -> URL? {
        guard let save = game.save, !save.pending else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let when = formatter.string(from: save.header?.saved ?? Date())
        let device = (save.header?.device ?? "").replacingOccurrences(of: "/", with: "-")
        var dest = game.backupsFolder.appending(path: device.isEmpty ? "\(when).dmsync" : "\(when) \(device).dmsync")
        if FileManager.default.fileExists(atPath: dest.path) {
            if let a = FileAccess.read(dest), let b = FileAccess.read(save.url), a == b { return dest }   // that save is backed up already
            dest = game.backupsFolder.appending(path: "\(when) \(device) \(UUID().uuidString.prefix(4)).dmsync")
        }
        return FileAccess.copy(save.url, to: dest) ? dest : nil
    }
}
