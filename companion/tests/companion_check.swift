import CryptoKit
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

// MARK: The live link: its lines (docs/companion.md, How it talks to the Mac)

var helloLine = LinkLine.phone("hello")
helloLine.format = LinkWire.format
helloLine.phone = "P1"
helloLine.token = "t"
expect(helloLine.encoded() == #"{"do":"hello","format":1,"phone":"P1","token":"t"}"#, "a line is one JSON object: its keys sorted, the ones it does not have left out")
if case .line(let back)? = LinkMessage.parse(helloLine.encoded() + "\n") {
    expect(back == helloLine, "read back as it was written")
} else {
    expect(false, "a line of the link is read")
}
if case .line(let later)? = LinkMessage.parse(#"{"link": "hello", "format": 1, "name": "Mac", "a key of a later build": [1, 2]}"#) {
    expect(later.link == "hello" && later.name == "Mac", "a key this build does not know is skipped, the line kept")
} else {
    expect(false, "a line with a key of a later build is read")
}
if case .event(let event)? = LinkMessage.parse(#"{"ev": "stage", "k": 3, "n": 7, "name": "sign for the device", "step": "", "t": 12.5}"#) {
    expect(event["k"] as? Int == 3 && event["name"] as? String == "sign for the device", "an event of the script is kept as the script wrote it")
} else {
    expect(false, "an event of the script is read")
}
expect(LinkMessage.parse("[12:00:01] plain text") == nil && LinkMessage.parse(#"{"other": 1}"#) == nil && LinkMessage.parse(#"{"link": "job", "state": 5}"#) == nil,
       "plain text, an object that is no line, a key of the wrong kind: skipped")

var lineBuffer = LineBuffer()
expect(lineBuffer.append(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"], "a line is whole at its newline")
expect(lineBuffer.append(Data(":2}\n\n".utf8)) == ["{\"b\":2}"], "a line that came in two pieces; an empty line is none")
expect(lineBuffer.append(Data(repeating: 0x41, count: LinkWire.maxLine + 1)) == nil, "a line longer than the limit ends the connection")

// MARK: The live link: its keys

expect(LinkKeys.code(typed: " 123 456 ") == "123456" && LinkKeys.code(typed: "12345") == nil && LinkKeys.code(typed: "1234567") == nil
       && LinkKeys.code(typed: "\u{FF11}23456") == nil, "the code as typed: six ASCII digits, with or without spaces")
let codes = Set((0..<200).map { _ in LinkKeys.newCode() })
expect(codes.allSatisfy { $0.count == 6 && LinkKeys.code(typed: $0) == $0 } && codes.count > 150, "a new code is six digits, and not the same one each time")
expect(LinkKeys.pairingKey(code: "123456").count == 32 && LinkKeys.pairingKey(code: "123456") == LinkKeys.pairingKey(code: "123456")
       && LinkKeys.pairingKey(code: "123456") != LinkKeys.pairingKey(code: "123457"), "the pairing key comes from the code alone")
expect(LinkKeys.newKey().count == 32 && LinkKeys.newKey() != LinkKeys.newKey() && LinkKeys.same("abc", "abc") && !LinkKeys.same("abc", "abd") && !LinkKeys.same("abc", "abcd"),
       "the link key is 32 random bytes; tokens compared whole")
let macKey = LinkPairing.newKey(), phoneKey = LinkPairing.newKey()
let linkSecret = LinkPairing.Secret(key: LinkKeys.newKey(), token: LinkKeys.newToken())
let linkBox = try? LinkPairing.seal(linkSecret, mine: macKey, theirs: phoneKey.publicKey.rawRepresentation, code: "123456")
expect(linkBox != nil && linkBox.flatMap { try? LinkPairing.open($0, mine: phoneKey, theirs: macKey.publicKey.rawRepresentation, code: "123456") } == linkSecret,
       "the link key the Mac seals is opened by the phone that typed the code")
expect(linkBox.flatMap { try? LinkPairing.open($0, mine: phoneKey, theirs: macKey.publicKey.rawRepresentation, code: "123457") } == nil, "not with another code")
expect(linkBox.flatMap { try? LinkPairing.open($0, mine: LinkPairing.newKey(), theirs: macKey.publicKey.rawRepresentation, code: "123456") } == nil,
       "not by one who recorded the pairing and tries the right code: the phone's own private key is needed")

// MARK: The live link: a job as the phone follows it

var jobLine = LinkLine.mac("job")
jobLine.id = "J1"
jobLine.state = "running"
jobLine.kind = "install"
jobLine.target = "device"
jobLine.titleId = title.lowercased()
jobLine.game = "Starfall Tactics"
jobLine.title = "Installing on iPhone"
var unknownState = jobLine
unknownState.state = "paused"
expect(BuildProgress(LinkLine.mac("hello")) == nil && BuildProgress(unknownState) == nil, "another line, or a state this build does not know, is no job")
let stageLines = [
    #"{"ev": "stage_end", "k": 1, "name": "rewrite", "ok": true, "summary": "9 modules", "elapsed": 14.2}"#,
    #"{"ev": "stage_end", "k": 2, "name": "iOS shaders", "ok": true, "summary": "cached", "elapsed": 3.1}"#,
    #"{"ev": "stage", "k": 3, "n": 7, "name": "sign for the device", "step": "", "t": 20.0}"#,
]
func apply(_ lines: [String], to job: inout BuildProgress) {
    for line in lines {
        if case .event(let event)? = LinkMessage.parse(line) { job.apply(event) }
    }
}
if var followed = BuildProgress(jobLine) {
    expect(followed.isRunning && followed.isInstall && followed.titleId == title && followed.fraction == nil, "a job line: a running install, its title ID in upper case, no progress yet")
    apply(stageLines, to: &followed)
    expect(followed.stageIndex == 3 && followed.stageCount == 7 && followed.stageName == "sign for the device" && followed.finished.map(\.index) == [1, 2],
           "Step 3 of 7: sign for the device, two stages behind it")
    expect(followed.fraction.map { abs($0 - 2.0 / 7.0) < 0.0001 } == true, "two stages of seven done")
    apply([#"{"ev": "progress", "k": 3, "name": "sign for the device", "step": "", "done": 1, "total": 2, "frac": 0.5, "eta": 40}"#], to: &followed)
    expect(followed.fraction.map { abs($0 - 2.5 / 7.0) < 0.0001 } == true && followed.eta == 40, "and half of the third")
    apply([#"{"ev": "say", "msg": "[12:00:03] [RED] signing failed: no team"}"#, #"{"ev": "a later event", "x": 1}"#], to: &followed)
    expect(followed.failure == "signing failed: no team" && followed.lastMessage == "[RED] signing failed: no team" && followed.stageIndex == 3,
           "a [RED] line is why it stopped; an event this build does not know changes nothing")
    var endedLine = jobLine
    endedLine.state = "failed"
    endedLine.message = "The install stopped."
    followed.update(endedLine)
    expect(followed.state == .failed && followed.failure == "The install stopped." && followed.stageIndex == 3, "the job's end: the Mac's own words for why, what the events built kept")
    endedLine.id = "J2"
    endedLine.state = "succeeded"
    followed.update(endedLine)
    expect(followed.state == .failed, "another job's line changes nothing")
} else {
    expect(false, "a job line makes a job")
}

// MARK: The live link: the phone's end with a scripted Mac (no connection; link_check.swift has the real one)

let scripted = MacLink(store: MemoryPairingStore(), phoneID: "P1", deviceName: "iPhone", deviceKind: "iPhone")
var endedJobs: [BuildProgress] = []
scripted.onJobEnded = { endedJobs.append($0) }
expect(!scripted.isConnected && scripted.status == .off && !scripted.requestInstall(titleId: title), "no Mac: nothing to ask")
scripted.play([#"{"link": "hello", "format": 1, "mac": "M1", "name": "Studio Mac", "app": "1.1.0"}"#, jobLine.encoded()] + stageLines, from: "A Mac")
expect(scripted.status == .connected("Studio Mac") && scripted.job?.stageIndex == 3 && scripted.job?.game == "Starfall Tactics", "the Mac's name from its hello, its job and where it is")
expect(scripted.requestInstall(titleId: title.lowercased()) && scripted.answers[title]?.state == "asked", "an install asked of the scripted Mac")
var succeededLine = jobLine
succeededLine.state = "succeeded"
scripted.play([succeededLine.encoded(), succeededLine.encoded()], from: "A Mac")
expect(scripted.job?.state == .succeeded && endedJobs.map(\.id) == ["J1"], "a job that ends while it is followed is announced, once")
scripted.dismissJob()
expect(scripted.job == nil, "a job that ended is put away")

print("companion check: \(failures) failed")
exit(failures == 0 ? 0 : 1)
