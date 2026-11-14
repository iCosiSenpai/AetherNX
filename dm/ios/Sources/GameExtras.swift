// Mods and cheats from the game's folder (docs/frontends.md, Mods and cheats; docs/companion.md, The game folder). AetherNX Studio keeps a game's mods in a
// Mods folder beside its cloud save, one folder per mod, and its Atmosphère cheat files in Cheats beside it; Mods/mods.json holds the mods turned off and
// their order, which Studio and AetherNX Companion write. Before the game starts, the mods that are on become DM_ROMFS_OVERLAY and the Cheats folder
// DM_CHEATS (the iPhone app: Launcher.swift dm_game_extras_env, from front_ios.m startGame); the Mac app's launcher takes the mods from mods.json the same way
// (dm/mac/Launcher.swift dm_mac_game_mods, from launcher.c). The rules are Studio's (studio/Sources/Mods.swift GameExtras), so the player's devices use the
// same mods. Foundation only: dm/ios/tests/game_extras_check.swift runs it on the Mac.
import Foundation

enum GameExtras {
    // MARK: Where the folder is

    /// iCloud Drive's own folder on this device, `<the user's home>/Library/Mobile Documents/com~apple~CloudDocs`. An iOS app's home is its container,
    /// `<user>/Containers/Data/Application/<UUID>`, where the user is `/private/var/mobile` on a device and the Simulator's data folder in the Simulator.
    static func iCloudDrive(home: String = NSHomeDirectory()) -> String {
        var parts = (home as NSString).pathComponents
        if parts.last == "/" { parts.removeLast() }
        if parts.count > 4, Array(parts[(parts.count - 4)..<(parts.count - 1)]) == ["Containers", "Data", "Application"] { parts.removeLast(4) }
        return (NSString.path(withComponents: parts) as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    /// iCloud Drive › AetherNX, where Studio keeps a folder per game (studio/Sources/CloudSaves.swift aetherFolder), by the end of its path: a picked
    /// folder's path may start with /private/var or /var.
    static let aetherSuffix = "/Mobile Documents/com~apple~CloudDocs/AetherNX"

    /// A game's folder name in iCloud Drive › AetherNX: its name without what a file name cannot hold (Studio's CloudSaves.folderName).
    static func folderName(for name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Game" : String(cleaned.prefix(120))
    }

    /// The folder the Cloud saves picker opens at: the game's own folder in iCloud Drive › AetherNX, named after the game as Studio names it.
    static func suggestedFolder(gameName: String, home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: iCloudDrive(home: home) + "/AetherNX/" + folderName(for: gameName), isDirectory: true)
    }

    /// A cloud folder that is the game's alone (Studio's GameExtras.isOwnFolder): a folder of iCloud Drive › AetherNX, or one named by the title ID.
    static func isOwnFolder(_ folder: String, titleID: String) -> Bool {
        let path = folder.count > 1 && folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        if (path as NSString).lastPathComponent.caseInsensitiveCompare(titleID) == .orderedSame { return true }
        return (path as NSString).deletingLastPathComponent.hasSuffix(aetherSuffix)
    }

    /// The folder a game's Mods and Cheats are in, for the cloud folder its save syncs through (Studio's GameExtras.folder): the cloud folder when it is the
    /// game's alone, else the game's folder in it, `<cloud folder>/<title ID>`, where its save is too.
    static func base(cloud: String, titleID: String) -> String {
        isOwnFolder(cloud, titleID: titleID) ? cloud : (cloud as NSString).appendingPathComponent(titleID.uppercased())
    }

    /// The game folder above a picked save folder: `iCloud Drive › AetherNX › <name> › <title ID>` was picked, whose own Mods and Cheats are one level up,
    /// out of the picked folder's reach. nil for any other folder.
    static func gameFolderAbove(_ cloud: String, titleID: String) -> String? {
        let path = cloud.count > 1 && cloud.hasSuffix("/") ? String(cloud.dropLast()) : cloud
        guard (path as NSString).lastPathComponent.caseInsensitiveCompare(titleID) == .orderedSame else { return nil }
        let up = (path as NSString).deletingLastPathComponent
        return isOwnFolder(up, titleID: titleID) && !(up as NSString).lastPathComponent.isEmpty ? up : nil
    }

    /// A folder as the Files app names it: iCloud Drive's by their names there.
    static func displayName(_ path: String) -> String {
        let drive = "/Mobile Documents/com~apple~CloudDocs", container = "/Mobile Documents/iCloud~io~github~icosisenpai~horizonnative/Documents"
        for (root, name) in [(drive, "iCloud Drive"), (container, "iCloud Drive › HorizonNative")] {
            guard let r = path.range(of: root) else { continue }
            let rest = path[r.upperBound...].split(separator: "/")
            return ([name] + rest.map(String.init)).joined(separator: " › ")
        }
        return (path as NSString).lastPathComponent
    }

    // MARK: What it holds

    /// What a folder holds, by the names iCloud Drive gives them: a file iCloud has listed but not brought to this device yet is `.<name>.icloud`
    /// (or, kept by the file provider, a file with no data yet), given under its own name in `pending`. With `onDemand` (a Mac, whose file provider
    /// brings a file in when it is read) only the `.icloud` placeholders are pending.
    struct Listing {
        var names: [String] = []
        var pending: Set<String> = []
    }

    static func list(_ folder: String, onDemand: Bool = false) -> Listing {
        var listing = Listing()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
            if let real = placeholderName(name) {
                listing.names.append(real); listing.pending.insert(real)
            } else {
                listing.names.append(name)
                if !onDemand && isDataless(URL(fileURLWithPath: (folder as NSString).appendingPathComponent(name))) { listing.pending.insert(name) }
            }
        }
        listing.names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return listing
    }

    /// `.<name>.icloud` → `<name>`
    static func placeholderName(_ name: String) -> String? {
        name.hasPrefix(".") && name.hasSuffix(".icloud") && name.count > 8 ? String(name.dropFirst().dropLast(7)) : nil
    }

    static func isDataless(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), v.isUbiquitousItem == true else { return false }
        return v.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Asks iCloud to bring a listed file to this device; a later read finds it.
    static func fetch(_ path: String) {
        do { try FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path)) }
        catch { fputs("launcher: iCloud did not take the download of \(path): \(error.localizedDescription)\n", stderr) }
    }

    static func isDirectory(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    // MARK: Mods

    /// `Mods/mods.json` (docs/companion.md): the mods turned off and their order, highest priority first; mods it does not list come after, by name.
    struct ModState: Decodable, Equatable {
        var format = 1
        var order: [String] = []
        var off: [String] = []

        init(order: [String] = [], off: [String] = []) { self.order = order; self.off = off }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
            order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
            off = try c.decodeIfPresent([String].self, forKey: .off) ?? []
        }
        private enum CodingKeys: String, CodingKey { case format, order, off }

        /// nil for a file that is not one, or of a later format than 1 (Studio's readState).
        static func decode(_ data: Data) -> ModState? {
            guard let state = try? JSONDecoder().decode(ModState.self, from: data), state.format <= 1 else { return nil }
            return state
        }
    }

    /// One mod of the Mods folder, by Studio's rules: a folder with a `romfs` folder inside (or Atmosphère's layout). Code mods (`exefs`) do not run.
    struct Mod: Equatable {
        let name: String
        let path: String
        /// The folder that replaces the game's files; nil when the mod has none (a code-only mod, or a folder that is not a mod).
        let romfs: String?
        let hasCode: Bool
        /// Turned off in mods.json.
        var off = false
        /// Its files iCloud has listed but not brought to this device yet, counted for a mod that is on: it waits for them.
        var waiting = 0
        /// DM_ROMFS_OVERLAY separates its folders with ':'.
        var hasColon: Bool { romfs?.contains(":") ?? false }
        /// Used at this start.
        var used: Bool { romfs != nil && !off && waiting == 0 && !hasColon }
    }

    static func mods(in modsFolder: String, state: ModState, titleID: String) -> [Mod] {
        let fm = FileManager.default
        let candidates = ["romfs", "atmosphere/contents/\(titleID)/romfs", "atmosphere/contents/\(titleID.lowercased())/romfs", "contents/\(titleID)/romfs", "\(titleID)/romfs"]
        let code = ["exefs", "atmosphere/contents/\(titleID)/exefs", "atmosphere/exefs_patches"]
        var found: [Mod] = []
        for name in (try? fm.contentsOfDirectory(atPath: modsFolder)) ?? [] where !name.hasPrefix(".") {
            let path = (modsFolder as NSString).appendingPathComponent(name)
            guard isDirectory(path) else { continue }
            let romfs = candidates.map { (path as NSString).appendingPathComponent($0) }.first { fm.fileExists(atPath: $0) }
            found.append(Mod(name: name, path: path, romfs: romfs, hasCode: code.contains { fm.fileExists(atPath: (path as NSString).appendingPathComponent($0)) },
                             off: state.off.contains(name)))
        }
        return found.sorted { a, b in
            let ia = state.order.firstIndex(of: a.name) ?? Int.max, ib = state.order.firstIndex(of: b.name) ?? Int.max
            return ia != ib ? ia < ib : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The files under a folder iCloud has not brought to this device yet; with `fetch`, each is asked for (`onDemand`: as in `list`).
    static func waitingFiles(under folder: String, fetch: Bool, onDemand: Bool = false) -> Int {
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let walk = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys) else { return 0 }
        var n = 0
        for case let url as URL in walk {
            if let real = placeholderName(url.lastPathComponent) {
                n += 1
                if fetch { Self.fetch(url.deletingLastPathComponent().appendingPathComponent(real).path) }
            } else if !onDemand && isDataless(url) {
                n += 1
                if fetch { Self.fetch(url.path) }
            }
        }
        return n
    }

    // MARK: Cheats

    /// The name of the main module's cheat file: the first 16 hex digits of its build ID in upper case (hle_cheats.c g_build), from the header of its
    /// rewriter table (`# BUILD_ID`, which the loader reads: dm/host/loader.c). nil without one.
    static func buildID(fixups: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: fixups) else { return nil }
        defer { try? h.close() }
        let head = String(decoding: h.readData(ofLength: 64 << 10), as: UTF8.self)
        for line in head.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("#") else { break }
            let words = line.dropFirst().split(whereSeparator: { $0 == " " || $0 == "\t" })
            if words.count >= 2, words[0] == "BUILD_ID", words[1].count >= 16, words[1].prefix(16).allSatisfy(\.isHexDigit) { return words[1].prefix(16).uppercased() }
        }
        return nil
    }

    /// Does a file name hold this build ID (16 hex digits, any case), as the host picks it (hle_cheats.c name_is_build)?
    static func isBuildFile(_ name: String, build: String) -> Bool {
        guard name.lowercased().hasSuffix(".txt"), name.count >= 16, build.count >= 16 else { return false }
        let n = Array(name), b = Array(build)
        return String(n[0..<16]).lowercased() == String(b[0..<16]).lowercased() && (n.count == 16 || n[16] == ".")
    }

    // MARK: The whole folder

    struct Folder: Equatable {
        /// The folder the Mods and Cheats folders are in.
        var base: String
        /// `base/Mods` is there.
        var hasMods = false
        /// The mods, highest priority first.
        var mods: [Mod] = []
        /// mods.json is listed but not on this device yet: no mod is used until it is, so none the player turned off runs.
        var stateWaiting = false
        /// mods.json is there but of a later format, or not one: the mods are taken in their default order, all on (as Studio does).
        var stateUnread = false
        /// `base/Cheats`, when it is there: DM_CHEATS.
        var cheats: String?
        /// The cheat file for this build in it, in the host's places (nil: none, or the build is not known).
        var cheatFile: String?
        /// That file is listed but not on this device yet.
        var cheatWaiting = false
        /// Names in `<build ID>.enabled`: the cheats on (masters are always on and not listed).
        var cheatsOn = 0
        /// `.cheats-off-<title ID>`: no cheat runs while it exists.
        var cheatsOff = false

        /// The RomFS folders DM_ROMFS_OVERLAY takes, first wins.
        var overlay: [String] { stateWaiting ? [] : mods.filter(\.used).compactMap(\.romfs) }
    }

    /// Reads the game's folder for a cloud folder. With `fetch`, asks iCloud for what it has listed and not brought yet (mods.json, the files of the mods that
    /// are on, the cheat file), so a later read finds them. `onDemand`: a Mac's (`list`).
    static func read(cloud: String, titleID: String, buildID: String?, fetch: Bool, onDemand: Bool = false) -> Folder {
        let tid = titleID.uppercased()
        var f = Folder(base: base(cloud: cloud, titleID: tid))
        let modsFolder = (f.base as NSString).appendingPathComponent("Mods")
        f.hasMods = isDirectory(modsFolder)
        if f.hasMods {
            let listing = list(modsFolder, onDemand: onDemand)
            let stateFile = (modsFolder as NSString).appendingPathComponent("mods.json")
            var state = ModState()
            if listing.pending.contains("mods.json") {
                f.stateWaiting = true
                if fetch { Self.fetch(stateFile) }
            } else if let data = FileManager.default.contents(atPath: stateFile) {
                if let s = ModState.decode(data) { state = s } else { f.stateUnread = true }
            }
            f.mods = mods(in: modsFolder, state: state, titleID: tid)
            if !f.stateWaiting {
                for i in f.mods.indices where f.mods[i].romfs != nil && !f.mods[i].off {
                    f.mods[i].waiting = waitingFiles(under: f.mods[i].romfs!, fetch: fetch, onDemand: onDemand)
                }
            }
        }
        let cheats = (f.base as NSString).appendingPathComponent("Cheats")
        guard isDirectory(cheats) else { return f }
        f.cheats = cheats
        f.cheatsOff = [".cheats-off-\(tid)", "..cheats-off-\(tid).icloud"].contains { FileManager.default.fileExists(atPath: (cheats as NSString).appendingPathComponent($0)) }   // the flag, or iCloud's placeholder of it
        guard let build = buildID?.uppercased(), build.count >= 16 else { return f }
        for dir in [cheats, "\(cheats)/atmosphere/contents/\(tid)/cheats", "\(cheats)/contents/\(tid)/cheats"] {
            let listing = list(dir, onDemand: onDemand)
            guard let name = listing.names.first(where: { isBuildFile($0, build: build) }) else { continue }
            f.cheatFile = (dir as NSString).appendingPathComponent(name)
            f.cheatWaiting = listing.pending.contains(name)
            if f.cheatWaiting && fetch { Self.fetch(f.cheatFile!) }
            break
        }
        let enabled = (cheats as NSString).appendingPathComponent("\(String(build.prefix(16))).enabled")   // the host's: in the folder itself, named in upper case
        if let text = FileManager.default.contents(atPath: enabled).map({ String(decoding: $0, as: UTF8.self) }) {
            f.cheatsOn = text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        } else if list(cheats, onDemand: onDemand).pending.contains("\(String(build.prefix(16))).enabled"), fetch { Self.fetch(enabled) }
        return f
    }

    // MARK: The start

    /// The variables this sets (DM_ROMFS_OVERLAY, DM_CHEATS) as opposed to an env file's or the launch environment's, which win (as on the Mac: launcher.c mods_and_cheats).
    private(set) static var setHere: Set<String> = []

    /// Sets DM_ROMFS_OVERLAY and DM_CHEATS for a start from the game's folder of the cloud folder in use (an absolute path; nil or another value: none),
    /// and logs what it chose. Values an earlier call set are replaced or taken away. Returns the folder read, nil without one.
    @discardableResult
    static func apply(cloud: String?, titleID: String, buildID: String?, log: (String) -> Void = { fputs($0 + "\n", stderr) }) -> Folder? {
        func put(_ key: String, _ value: String?) {
            if getenv(key) != nil && !setHere.contains(key) {
                if value != nil { log("launcher: \(key) is set by an env file or at launch: the game folder's is not used") }
                return
            }
            if let value { setenv(key, value, 1); setHere.insert(key) } else if setHere.remove(key) != nil { unsetenv(key) }
        }
        guard let cloud, cloud.hasPrefix("/") else { put("DM_ROMFS_OVERLAY", nil); put("DM_CHEATS", nil); return nil }
        let f = read(cloud: cloud, titleID: titleID, buildID: buildID, fetch: true)
        if f.stateWaiting { log("[RED] launcher: \(f.base)/Mods/mods.json is not on this device yet (iCloud): no mod is used at this start") }
        if f.stateUnread { log("[RED] launcher: \(f.base)/Mods/mods.json cannot be read (not a mods.json, or a later format): every mod is on, by name") }
        report(f, log: log)
        let overlay = f.overlay
        put("DM_ROMFS_OVERLAY", overlay.isEmpty ? nil : overlay.joined(separator: ":"))
        if !overlay.isEmpty { log("launcher: \(overlay.count) mod(s) on from \(f.base)/Mods: \(f.mods.filter(\.used).map(\.name).joined(separator: ", "))") }
        put("DM_CHEATS", f.cheats)
        if let c = f.cheats { log("launcher: cheats from \(c)\(f.cheatsOff ? " (all off: .cheats-off-\(titleID.uppercased()))" : "")") }
        if f.cheatWaiting, let file = f.cheatFile { log("[RED] launcher: \(file) is not on this device yet (iCloud): asked for, no cheat runs at this start") }
        return f
    }

    /// Logs each mod left out of a start, and why.
    static func report(_ f: Folder, log: (String) -> Void) {
        for m in f.mods where !f.stateWaiting {
            if m.romfs == nil { log("\(m.hasCode ? "[RED] " : "")launcher: mod \(m.name) left out: \(m.hasCode ? "it patches the game's code (exefs), which the engine does not run" : "it has no romfs folder")") }
            else if m.off { log("launcher: mod \(m.name) is off") }
            else if m.waiting > 0 { log("[RED] launcher: mod \(m.name) left out: \(m.waiting) of its files are not on this device yet (iCloud); asked for") }
            else if m.hasColon { log("[RED] launcher: mod \(m.name) left out: DM_ROMFS_OVERLAY separates folders with ':', and its path has one") }
            else if m.hasCode { log("[RED] launcher: mod \(m.name): its file changes are used, its code patches (exefs) are not") }
        }
    }

    // MARK: The Mac app

    /// The folder the Mac app's game folder is found from, as Studio has it (GameExtras.folder): the cloud folder DM_SAVE_SYNC names, iCloud Drive ›
    /// HorizonNative Saves for `icloud`, else, with cloud saves off, the app's own folder in Application Support (`<home>/Library/Application Support/HorizonNative/<title ID>`,
    /// its own by its name).
    static func macCloud(saveSync: String?, titleID: String, home: String = NSHomeDirectory()) -> String {
        if let s = saveSync, s.hasPrefix("/") { return s }
        if saveSync == "icloud" { return home + "/Library/Mobile Documents/com~apple~CloudDocs/HorizonNative Saves" }
        return home + "/Library/Application Support/HorizonNative/" + titleID.uppercased()
    }

    /// The Mac app's mods from its game folder's mods.json (dm/mac/launcher.c mods_and_cheats): the RomFS folders, first wins, or nil when the folder has
    /// no mods.json it can use (none, one of a later format, or one iCloud has not brought yet), so the launcher keeps Studio's `mods.folders`.
    static func macOverlay(saveSync: String?, titleID: String, home: String = NSHomeDirectory(), log: (String) -> Void = { fputs($0 + "\n", stderr) }) -> [String]? {
        let f = read(cloud: macCloud(saveSync: saveSync, titleID: titleID, home: home), titleID: titleID, buildID: nil, fetch: true, onDemand: true)
        let state = (f.base as NSString).appendingPathComponent("Mods/mods.json")
        guard f.hasMods, !f.stateWaiting, !f.stateUnread, FileManager.default.fileExists(atPath: state) else { return nil }
        report(f, log: log)
        log("launcher: mods from \(state): \(f.overlay.isEmpty ? "none on" : f.mods.filter(\.used).map(\.name).joined(separator: ", "))")
        return f.overlay
    }

    // MARK: The link

    /// `aethernx-<title ID in lower case>://play` (AetherNX Companion's Play, docs/companion.md) also presses Play; `aethernx-<title ID>://` only opens the app.
    static func linkPlays(_ link: String) -> Bool {
        guard let u = URLComponents(string: link) else { return false }
        let first = (u.host?.isEmpty == false ? u.host : u.path.split(separator: "/").first.map(String.init)) ?? ""
        return first.lowercased() == "play"
    }
}
