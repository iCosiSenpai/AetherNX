import Foundation
@testable import CompanionCore

// Checks of the companion's game-folder logic (companion/Sources/Core), compiled for the Mac. test_companion.py passes a scratch folder;
// there is no window, iCloud or game file here.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

let root = URL(filePath: CommandLine.arguments[1])
let fm = FileManager.default
let title = "0100A1B2C3D40000"

// MARK: game.json

let studioJSON = """
{
  "bundleId" : "io.github.icosisenpai.horizonnative.0100abcd12340000",
  "format" : 1,
  "icon" : "icon.jpg",
  "name" : "Starfall Tactics",
  "titleId" : "0100abcd12340000",
  "version" : "1.2.0"
}
"""
let manifest = GameManifest.decode(Data(studioJSON.utf8))
expect(manifest?.name == "Starfall Tactics" && manifest?.titleId == "0100ABCD12340000" && manifest?.version == "1.2.0" && manifest?.icon == "icon.jpg",
       "the game.json Studio writes, its title ID in upper case")
expect(GameManifest.decode(Data(#"{"format": 2, "name": "X", "titleId": "0100ABCD12340000"}"#.utf8)) == nil, "a later format is not read")
expect(GameManifest.decode(Data(#"{"format": 1, "name": "X", "titleId": "0100ABCD"}"#.utf8)) == nil
       && GameManifest.decode(Data(#"{"format": 1, "name": " ", "titleId": "0100ABCD12340000"}"#.utf8)) == nil, "no title ID or no name: not a description")
expect(GameManifest.decode(Data(#"{"format": 1, "name": "X", "titleId": "0100ABCD12340000", "icon": "../x.png"}"#.utf8))?.icon == nil,
       "the icon is a file of the folder, never a path")

// MARK: The save header (dm/host/save_sync.c)

let saved = Date(timeIntervalSince1970: 1_800_000_000)
var packed = SaveHeader.encode(entries: 7, hash: String(repeating: "ab", count: 16), saved: saved, titleId: title, device: "iPhone17,1")
expect(packed.count == SaveHeader.size && SaveHeader.size == 144, "a header is 144 bytes")
packed.append(Data("DMSYNCE\n".utf8))
let header = SaveHeader(packed)
expect(header?.entries == 7 && header?.saved == saved && header?.titleId == title && header?.device == "iPhone17,1" && header?.hash == String(repeating: "ab", count: 16),
       "every field read back")
expect(header?.deviceKind == "iPhone" && SaveHeader(SaveHeader.encode(entries: 0, hash: "", saved: saved, titleId: title, device: "Mac16,9"))?.deviceKind == "Mac",
       "the kind of device it came from")
expect(SaveHeader(Data("DMSYNC2\n".utf8) + packed.dropFirst(8)) == nil && SaveHeader(packed.prefix(100)) == nil, "another magic or a cut header is no save")

// MARK: Cheat files (dm/host/hle_cheats.c, parse_file)

let cheatText = """
prose before any header
{Master}
580F0000 01234560
[-- Section --]
[Infinite HP]
04000000 01234568 00000063
[Max Gold] 04000000 0123456C 0098967F
[Max Gold]
04000000 01234570 0098967F
[Typo]
this is not code
[]
04000000 00000000 00000001
[\(String(repeating: "é", count: 70))]
04000000 00000000 00000002
"""
let entries = CheatFile.parse(cheatText)
expect(entries.map(\.kind) == [.master, .label, .cheat, .cheat, .cheat, .broken, .cheat], "masters, labels, cheats and a broken one \(entries.map(\.kind))")
expect(entries.map(\.key).prefix(5) == ["Master", "-- Section --", "Infinite HP", "Max Gold", "Max Gold #2"], "a duplicate's key counts the earlier entries of its name")
expect(entries.last.map { $0.name.utf8.count <= 127 && $0.name.allSatisfy { $0 == "é" } } == true, "a long name is cut at 127 bytes, on a character")
expect(CheatFile.buildId(ofFileNamed: "0123456789abcdef.txt") == "0123456789ABCDEF" && CheatFile.buildId(ofFileNamed: "notes.txt") == nil
       && CheatFile.buildId(ofFileNamed: "0123456789ABCDEF.enabled") == nil, "a cheat file is named by its build ID")
let cheatFile = CheatFile(buildId: "0123456789ABCDEF", url: root, entries: entries)
let previous: Set<String> = ["Infinite HP", "From another build"]
let written = String(decoding: cheatFile.enabledData(on: ["Max Gold #2", "Infinite HP", "From another build"], previous: previous), as: UTF8.self)
expect(written == "Infinite HP\nMax Gold #2\nFrom another build\n", "<build ID>.enabled: the file's order, then keys it does not have \(written.debugDescription)")
expect(CheatFile.enabled(in: Data("A\r\n\nB #2\n".utf8)) == ["A", "B #2"] && CheatFile.enabled(in: nil).isEmpty, "the toggles read back; no file, none on")

// MARK: A library folder (the demo library, written as Studio and the engine write a real one)

let library = root.appending(path: "AetherNX")
try! DemoLibrary.write(to: library, now: saved)
try? fm.createDirectory(at: library.appending(path: "Holiday Photos"), withIntermediateDirectories: true)
try? fm.createDirectory(at: library.appending(path: ".Trash"), withIntermediateDirectories: true)
var games = LibraryReader.read(root: library)
expect(games.map(\.name) == ["Echo Garden", "Lantern Keep", "Moonlit Kart", "Starfall Tactics"], "the game folders, by name; other folders are none \(games.map(\.name))")
let echo = games.first { $0.name == "Echo Garden" }
expect(echo?.isDescribed == false && echo?.titleId == "0100BEEF12340000" && echo?.save?.header?.deviceKind == "iPad",
       "a folder with no game.json: its folder's name, the title ID from its save folder")
var star = games.first { $0.name == "Starfall Tactics" }!
expect(star.iconURL?.lastPathComponent == "icon.png" && star.manifest?.version == "1.2.0", "game.json and the picture beside it")
expect(star.save?.header?.saved == saved.addingTimeInterval(-2 * 3600) && star.save?.header?.device == "Mac16,9", "when and where the cloud's save was made")
expect(star.orderedMods.map(\.name) == ["HD Portraits", "Classic Soundtrack", "Speed Patch"] && star.modsOn == 1, "mods in mods.json's order, one on")
expect(star.mods.first { $0.name == "Speed Patch" }.map { !$0.usable && $0.hasCode } == true, "a code mod is not usable")
expect(games.first { $0.name == "Lantern Keep" }?.mods.first?.usable == true, "Atmosphère's layout is a mod too")
expect(star.cheatCount == 4 && star.cheatsOnCount == 2 && star.cheatsMasterOn, "the cheats and the ones on")

// MARK: Changes

GameActions.setMod("HD Portraits", on: false, in: star)
star = LibraryReader.readGame(star.url)!
expect(star.modsOn == 0 && star.modState.off == ["Classic Soundtrack", "HD Portraits"], "a mod turned off goes into mods.json")
let modsJSON = (try? JSONSerialization.jsonObject(with: Data(contentsOf: star.modsFolder.appending(path: "mods.json")))) as? [String: Any]
expect(modsJSON?["format"] as? Int == 1 && (modsJSON?["order"] as? [String])?.first == "HD Portraits", "mods.json as Studio reads it")
GameActions.orderMods(["Speed Patch", "Classic Soundtrack", "HD Portraits"], in: star)
star = LibraryReader.readGame(star.url)!
expect(star.orderedMods.map(\.name) == ["Speed Patch", "Classic Soundtrack", "HD Portraits"], "a new order")
let file = star.cheats[0]
GameActions.setCheat("Unlock All Classes", on: true, file: file, in: star)
GameActions.setCheat("Infinite HP", on: false, file: file, in: star)
star = LibraryReader.readGame(star.url)!
expect(star.cheatsOn == [file.buildId + "/Max Gold #2", file.buildId + "/Unlock All Classes"], "cheats on and off in <build ID>.enabled \(star.cheatsOn)")
GameActions.setCheatsMaster(on: false, in: star)
star = LibraryReader.readGame(star.url)!
expect(!star.cheatsMasterOn && fm.fileExists(atPath: star.cheatsFolder.appending(path: ".cheats-off-\(title)").path), "the master switch is the host's flag file")
GameActions.setCheatsMaster(on: true, in: star)
star = LibraryReader.readGame(star.url)!
expect(star.cheatsMasterOn && star.cheatsOnCount == 2, "on again, each cheat's switch kept")
let backup = GameActions.backUp(star)
expect(backup.map { fm.fileExists(atPath: $0.path) && $0.deletingLastPathComponent().lastPathComponent == "Backups" } == true, "a backup in the game's Backups folder")
expect(GameActions.backUp(star) == backup, "the same save is backed up once")
star = LibraryReader.readGame(star.url)!
expect(star.backups.count == 1 && star.backups.first?.header?.device == "Mac16,9", "the backups listed, with their header")

// MARK: iCloud Drive's placeholders

let pending = library.appending(path: "Faraway")
try? fm.createDirectory(at: pending.appending(path: "0100DDDD00000000"), withIntermediateDirectories: true)
try? Data().write(to: pending.appending(path: ".game.json.icloud"))
try? Data().write(to: pending.appending(path: "0100DDDD00000000/.save.dmsync.icloud"))
let faraway = LibraryReader.readGame(pending)
expect(faraway?.pending == ["game.json", "0100DDDD00000000/save.dmsync"] && faraway?.save?.pending == true && faraway?.name == "Faraway",
       "files not on the device yet: listed, asked for, named by the folder meanwhile \(faraway?.pending ?? [])")

print("companion check: \(failures) failed")
exit(failures == 0 ? 0 : 1)
