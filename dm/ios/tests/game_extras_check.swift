// The game folder's mods and cheats (dm/ios/Sources/GameExtras.swift), run by test_game_extras.py on macOS against synthetic folders: Studio's mod rules, Mods/mods.json,
// files iCloud has not brought yet, the cheat file for the build, the variables a start gets and who wins them, and the Play link. Argument: an empty scratch folder
import Foundation

@main struct Check {
    static func main() {
        var failed = 0
        func expect(_ c: Bool, _ what: String) { print((c ? "PASS " : "FAIL ") + what); if !c { failed += 1 } }
        let fm = FileManager.default
        let root = CommandLine.arguments[1]
        let tid = "0100ABCD12340000", build = "0123456789ABCDEF"
        func make(_ path: String, _ text: String = "x") {
            try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try! text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        func env(_ k: String) -> String? { getenv(k).map { String(cString: $0) } }

        // Where things are
        expect(GameExtras.iCloudDrive(home: "/private/var/mobile/Containers/Data/Application/1F2E3D4C") == "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs", "iCloud Drive on a device, from the app's container")
        expect(GameExtras.iCloudDrive(home: "/Users/p/Library/Developer/CoreSimulator/Devices/D/data/Containers/Data/Application/A/") == "/Users/p/Library/Developer/CoreSimulator/Devices/D/data/Library/Mobile Documents/com~apple~CloudDocs", "iCloud Drive in the Simulator")
        expect(GameExtras.iCloudDrive(home: "/Users/p") == "/Users/p/Library/Mobile Documents/com~apple~CloudDocs", "iCloud Drive on a Mac")
        expect(GameExtras.folderName(for: " Zelda: Breath / Wild. ") == "Zelda- Breath - Wild" && GameExtras.folderName(for: "...") == "Game", "a game's folder name, as Studio names it")
        expect(GameExtras.suggestedFolder(gameName: "Starfall: Tactics", home: "/var/mobile/Containers/Data/Application/U").path == "/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/AetherNX/Starfall- Tactics", "the picker opens at the game's folder in iCloud Drive › AetherNX")
        let drive = root + "/Mobile Documents/com~apple~CloudDocs"
        let game = drive + "/AetherNX/Starfall Tactics", shared = drive + "/My Saves"
        expect(GameExtras.isOwnFolder(game, titleID: tid) && GameExtras.isOwnFolder(game + "/", titleID: tid) && GameExtras.base(cloud: game, titleID: tid) == game, "a folder of iCloud Drive › AetherNX is the game's own")
        expect(GameExtras.isOwnFolder(shared + "/0100abcd12340000", titleID: tid) && GameExtras.base(cloud: shared + "/" + tid, titleID: tid) == shared + "/" + tid, "a folder named by the title ID is the game's own")
        expect(!GameExtras.isOwnFolder(shared, titleID: tid) && GameExtras.base(cloud: shared, titleID: tid.lowercased()) == shared + "/" + tid, "a folder every game shares: the game's folder in it, as Studio has it")
        expect(GameExtras.gameFolderAbove(game + "/" + tid, titleID: tid) == game && GameExtras.gameFolderAbove(shared + "/" + tid, titleID: tid) == nil && GameExtras.gameFolderAbove(game, titleID: tid) == nil, "a pick of the save's own folder in a game folder is noticed")
        expect(GameExtras.displayName(game) == "iCloud Drive › AetherNX › Starfall Tactics" && GameExtras.displayName("/a/Mobile Documents/iCloud~io~github~icosisenpai~horizonnative/Documents/\(tid)") == "iCloud Drive › HorizonNative › \(tid)", "folders by their iCloud Drive names")

        // A game folder as Studio and the companion leave it
        make("\(game)/\(tid)/save.dmsync")
        make("\(game)/Mods/HD Textures/romfs/a.bin")
        make("\(game)/Mods/Big Head Mode/atmosphere/contents/\(tid)/romfs/b.bin")
        make("\(game)/Mods/Code Only/exefs/main.npdm")
        make("\(game)/Mods/Both/romfs/c.bin"); make("\(game)/Mods/Both/exefs/x.ips")
        make("\(game)/Mods/Not a Mod/readme.txt")
        make("\(game)/Mods/Pending/romfs/sub/.d.bin.icloud")   // iCloud listed it, it is not here yet
        make("\(game)/Mods/.Hidden/romfs/e.bin")
        make("\(game)/Mods/stray file.zip")
        make("\(game)/Mods/mods.json", #"{ "format" : 1, "off" : ["Both"], "order" : ["Big Head Mode", "HD Textures", "Gone"] }"#)
        make("\(game)/Cheats/\(build).txt", "{Master}\n040A0000 00000000 00000001\n[Max HP]\n04000000 00000000 00000063\n[Money]\n04000000 00000004 0000FFFF\n")
        make("\(game)/Cheats/\(build).enabled", "Max HP\n\n")
        var f = GameExtras.read(cloud: game, titleID: tid.lowercased(), buildID: build, fetch: false)
        expect(f.base == game && f.hasMods, "the game folder and its Mods")
        expect(f.mods.map(\.name) == ["Big Head Mode", "HD Textures", "Both", "Code Only", "Not a Mod", "Pending"], "mods in mods.json's order, the rest by name; hidden folders and files are not mods")
        expect(f.mods[0].romfs == "\(game)/Mods/Big Head Mode/atmosphere/contents/\(tid)/romfs" && f.mods[1].romfs == "\(game)/Mods/HD Textures/romfs", "romfs found in both of Studio's layouts")
        expect(f.mods[2].off && f.mods[2].hasCode && !f.mods[2].used, "a mod mods.json turns off is not used")
        expect(f.mods[3].romfs == nil && f.mods[3].hasCode && f.mods[4].romfs == nil && !f.mods[4].hasCode, "a code mod and a folder without romfs are not used")
        expect(f.mods[5].waiting == 1 && !f.mods[5].used, "a mod with a file still in iCloud waits")
        expect(f.overlay == [f.mods[0].romfs!, f.mods[1].romfs!], "the overlay: the mods used, first wins")
        expect(f.cheats == "\(game)/Cheats" && f.cheatFile == "\(game)/Cheats/\(build).txt" && f.cheatsOn == 1 && !f.cheatsOff && !f.cheatWaiting, "the cheats folder, this build's file and the cheats on")
        expect(GameExtras.read(cloud: game, titleID: tid, buildID: nil, fetch: false).cheatFile == nil, "no build ID: no file is named")
        expect(GameExtras.read(cloud: game, titleID: tid, buildID: "FEDCBA9876543210", fetch: false).cheatFile == nil, "another build's file is not this one's")
        make("\(game)/Cheats/.cheats-off-\(tid)", "")
        expect(GameExtras.read(cloud: game, titleID: tid, buildID: build, fetch: false).cheatsOff, "the master switch turns them all off")
        try! fm.removeItem(atPath: "\(game)/Cheats/.cheats-off-\(tid)")
        make("\(game)/Cheats/..cheats-off-\(tid).icloud", "")
        expect(GameExtras.read(cloud: game, titleID: tid, buildID: build, fetch: false).cheatsOff, "so does the master switch iCloud has only listed")
        try! fm.removeItem(atPath: "\(game)/Cheats/..cheats-off-\(tid).icloud")

        try! fm.moveItem(atPath: "\(game)/Mods/mods.json", toPath: "\(game)/Mods/.mods.json.icloud")
        f = GameExtras.read(cloud: game, titleID: tid, buildID: build, fetch: false)
        expect(f.stateWaiting && f.overlay.isEmpty, "mods.json still in iCloud: no mod is used, so none the player turned off runs")
        try! fm.removeItem(atPath: "\(game)/Mods/.mods.json.icloud")
        make("\(game)/Mods/mods.json", #"{ "format" : 2, "off" : ["HD Textures"] }"#)
        f = GameExtras.read(cloud: game, titleID: tid, buildID: build, fetch: false)
        expect(f.stateUnread && f.mods.map(\.name).prefix(3) == ["Big Head Mode", "Both", "Code Only"] && f.overlay.count == 3, "a later mods.json is not read (as Studio): the mods by name, all on")
        try! fm.removeItem(atPath: "\(game)/Mods/mods.json")
        f = GameExtras.read(cloud: game, titleID: tid, buildID: build, fetch: false)
        expect(!f.stateUnread && f.overlay == ["\(game)/Mods/Big Head Mode/atmosphere/contents/\(tid)/romfs", "\(game)/Mods/Both/romfs", "\(game)/Mods/HD Textures/romfs"], "no mods.json: every mod with romfs is on, by name")

        // The Atmosphère tree of cheats, its file named in lower case
        let tree = shared + "/" + tid
        make("\(tree)/Mods/Only/romfs/f.bin")
        make("\(tree)/Cheats/atmosphere/contents/\(tid)/cheats/\(build.lowercased()).txt", "[A]\n04000000 00000000 00000001\n")
        f = GameExtras.read(cloud: shared, titleID: tid, buildID: build, fetch: false)
        expect(f.base == tree && f.overlay == ["\(tree)/Mods/Only/romfs"] && f.cheatFile == "\(tree)/Cheats/atmosphere/contents/\(tid)/cheats/\(build.lowercased()).txt" && f.cheatsOn == 0, "a shared folder: the game's folder in it, the Atmosphère tree of cheats")
        expect(GameExtras.read(cloud: root + "/nowhere", titleID: tid, buildID: build, fetch: false) == GameExtras.Folder(base: root + "/nowhere/" + tid), "a folder without Mods or Cheats gives nothing")

        // The names of a build's file, and the build ID from main's rewriter table
        expect(GameExtras.isBuildFile("\(build).txt", build: build) && GameExtras.isBuildFile("\(build.lowercased()).TXT", build: build) && GameExtras.isBuildFile("\(build).v2.txt", build: build), "this build's file, in any case")
        expect(!GameExtras.isBuildFile("\(build)0.txt", build: build) && !GameExtras.isBuildFile("readme.txt", build: build) && !GameExtras.isBuildFile("\(build).enabled", build: build), "not another name")
        make(root + "/dm/main.fixups.tsv", "# TEXT_END\t0x4000\n# BUILD_ID\t0123456789abcdef0011223344556677\n0x10\tabs\n# BUILD_ID\tFFFFFFFFFFFFFFFF\n")
        expect(GameExtras.buildID(fixups: root + "/dm/main.fixups.tsv") == build, "the build ID: the header's, its first 16 hex digits in upper case")
        make(root + "/dm/other.fixups.tsv", "# TEXT_END\t0x4000\n0x10\tabs\n")
        expect(GameExtras.buildID(fixups: root + "/dm/other.fixups.tsv") == nil && GameExtras.buildID(fixups: root + "/none.tsv") == nil, "no build ID without the header line")

        // A start: the variables, and who wins them
        unsetenv("DM_ROMFS_OVERLAY"); unsetenv("DM_CHEATS")
        var lines: [String] = []
        GameExtras.apply(cloud: game, titleID: tid, buildID: build) { lines.append($0) }
        expect(env("DM_ROMFS_OVERLAY") == "\(game)/Mods/Big Head Mode/atmosphere/contents/\(tid)/romfs:\(game)/Mods/Both/romfs:\(game)/Mods/HD Textures/romfs" && env("DM_CHEATS") == "\(game)/Cheats", "Play sets the overlay and the cheats folder")
        expect(lines.contains { $0.hasPrefix("[RED] launcher: mod Code Only left out") } && lines.contains { $0.hasPrefix("[RED] launcher: mod Pending left out: 1 of its files") } && lines.contains { $0.contains("3 mod(s) on") }, "it logs what it left out, and why")
        make("\(game)/Mods/mods.json", #"{ "format" : 1, "off" : ["Big Head Mode", "Both", "HD Textures"] }"#)
        GameExtras.apply(cloud: game, titleID: tid, buildID: build) { _ in }
        expect(env("DM_ROMFS_OVERLAY") == nil && env("DM_CHEATS") == "\(game)/Cheats", "with every mod off, the overlay it set goes")
        GameExtras.apply(cloud: nil, titleID: tid, buildID: build) { _ in }
        expect(env("DM_CHEATS") == nil, "cloud saves off: the cheats folder it set goes")
        setenv("DM_CHEATS", "cheats", 1)   // Documents/env.txt
        try! fm.removeItem(atPath: "\(game)/Mods/mods.json")
        lines = []
        GameExtras.apply(cloud: game, titleID: tid, buildID: build) { lines.append($0) }
        expect(env("DM_CHEATS") == "cheats" && env("DM_ROMFS_OVERLAY") != nil && lines.contains { $0.contains("DM_CHEATS is set by an env file") }, "an env file's DM_CHEATS wins")
        GameExtras.apply(cloud: "icloud", titleID: tid, buildID: build) { _ in }
        expect(env("DM_CHEATS") == "cheats" && env("DM_ROMFS_OVERLAY") == nil, "DM_SAVE_SYNC=icloud (no folder here): no game folder, and the env file's value stays")
        make("\(root)/a:b/\(tid)/Mods/Colon/romfs/g.bin")
        let colon = GameExtras.read(cloud: "\(root)/a:b", titleID: tid, buildID: nil, fetch: false)
        expect(colon.base == "\(root)/a:b/\(tid)" && colon.mods.count == 1 && colon.mods[0].hasColon && !colon.mods[0].used && colon.overlay.isEmpty, "a mod whose path has ':' is left out: the overlay's separator")

        // The Mac app's launcher: the mods of mods.json before Studio's mods.folders
        let home = root + "/home"
        expect(GameExtras.macCloud(saveSync: nil, titleID: tid.lowercased(), home: home) == home + "/Library/Application Support/HorizonNative/\(tid)" && GameExtras.macCloud(saveSync: "0", titleID: tid, home: home) == home + "/Library/Application Support/HorizonNative/\(tid)", "the Mac app without cloud saves: its own folder in Application Support")
        expect(GameExtras.macCloud(saveSync: "icloud", titleID: tid, home: home) == home + "/Library/Mobile Documents/com~apple~CloudDocs/HorizonNative Saves" && GameExtras.macCloud(saveSync: game, titleID: tid, home: home) == game, "the Mac app's cloud folder")
        expect(GameExtras.macOverlay(saveSync: game, titleID: tid, home: home) { _ in } == nil, "no mods.json: the launcher keeps mods.folders")
        make("\(game)/Mods/mods.json", #"{ "format" : 1, "off" : ["Both"], "order" : ["HD Textures"] }"#)
        lines = []
        expect(GameExtras.macOverlay(saveSync: game, titleID: tid, home: home) { lines.append($0) } == ["\(game)/Mods/HD Textures/romfs", "\(game)/Mods/Big Head Mode/atmosphere/contents/\(tid)/romfs"], "mods.json: the mods on, in its order")
        expect(lines.contains { $0.hasPrefix("launcher: mods from \(game)/Mods/mods.json: HD Textures, Big Head Mode") } && lines.contains { $0.hasPrefix("[RED] launcher: mod Pending left out") }, "and says so")
        make("\(game)/Mods/mods.json", #"{ "format" : 1, "off" : ["Both", "HD Textures", "Big Head Mode"] }"#)
        expect(GameExtras.macOverlay(saveSync: game, titleID: tid, home: home) { _ in } == [], "every mod off in mods.json: none, and not mods.folders either")
        make("\(game)/Mods/mods.json", #"{ "format" : 3 }"#)
        expect(GameExtras.macOverlay(saveSync: game, titleID: tid, home: home) { _ in } == nil, "a later mods.json: the launcher keeps mods.folders, Studio's reading of it")
        let local = home + "/Library/Application Support/HorizonNative/\(tid)"
        make("\(local)/Mods/Local/romfs/h.bin"); make("\(local)/Mods/mods.json", #"{ "format" : 1 }"#)
        expect(GameExtras.macOverlay(saveSync: nil, titleID: tid, home: home) { _ in } == ["\(local)/Mods/Local/romfs"], "the Mac app's own folder, with cloud saves off")

        // The link
        let link = "aethernx-\(tid.lowercased())"
        expect(GameExtras.linkPlays("\(link)://play") && GameExtras.linkPlays("\(link)://PLAY") && GameExtras.linkPlays("\(link):play") && GameExtras.linkPlays("\(link):///play"), "…://play presses Play")
        expect(!GameExtras.linkPlays("\(link)://") && !GameExtras.linkPlays("\(link):") && !GameExtras.linkPlays("\(link)://open") && !GameExtras.linkPlays("\(link)://player"), "…:// only opens the app")

        print("game extras: \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
