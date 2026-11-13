import Foundation
@testable import AetherNXStudio

// Checks of AetherNX Studio's own logic, against its sources compiled as a library. test_studio.py makes the folders and archives and
// passes their folder; there is no window, network or game file here.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

let root = CommandLine.arguments[1]
let title = "0100000000990000"

// MARK: The Danger Zone's removal plan

// A game whose packages lie at the top of a library folder, beside the app of another game, an archive and an IPA
func names(_ plan: RemovalPlan, _ kind: RemovalPlan.Kind) -> [String] {
    (plan.item(kind)?.paths ?? []).map { URL(filePath: $0).lastPathComponent }.sorted()
}
let lib = "\(root)/dz/lib"
let gameJSON = """
{"id": "\(lib)", "kind": "packages", "title_id": "\(title)", "name": "Stray", "folder": "\(lib)",
 "base": {"name": "Stray [\(title)].nsp", "path": "\(lib)/Stray [\(title)].nsp", "size": 4},
 "archives": [{"name": "random.zip", "path": "\(lib)/random.zip", "size": 2}], "work_dir": "\(lib)/\(title)_build",
 "mac_apps": ["\(lib)/Game.app", "\(lib)/Other.app"], "ipas": ["\(lib)/some.ipa"],
 "save_dir": "\(root)/dz/save/\(title)", "log_file": "\(root)/dz/logs/\(title).log"}
"""
let game = try JSONDecoder.snakeCase.decode(Game.self, from: Data(gameJSON.utf8))

let shared = RemovalPlan.make(for: game, libraryFolders: [lib])
expect(names(shared, .gameFiles) == ["Stray [\(title)].nsp"], "a library folder as the game's folder: the game files are its packages, no archive \(names(shared, .gameFiles))")
expect(names(shared, .apps) == ["Game.app", "Game.app.key"], "a library folder as the game's folder: the app naming its title ID, no IPA \(names(shared, .apps))")
expect(names(shared, .buildFolder) == ["\(title)-work"], "the build folders that exist \(names(shared, .buildFolder))")
expect(names(shared, .saves) == [title], "the save folder \(names(shared, .saves))")
expect(names(shared, .logsAndSettings) == ["\(title).log", "\(title).prev.log"], "the log and the previous run's log \(names(shared, .logsAndSettings))")
expect(!shared.items.flatMap(\.paths).contains { $0.contains("Other.app") }, "another game's app is never in the plan")

let own = RemovalPlan.make(for: game, libraryFolders: [URL(filePath: lib).deletingLastPathComponent().path])
expect(names(own, .gameFiles) == ["Stray [\(title)].nsp", "random.zip"], "the game's own folder: the archive it came in goes too \(names(own, .gameFiles))")
expect(names(own, .apps) == ["Game.app", "Game.app.key", "some.ipa"], "the game's own folder: its app and its IPA, still not the other app \(names(own, .apps))")

let viaLink = RemovalPlan.make(for: game, libraryFolders: ["\(root)/dz/link-to-lib"])
expect(names(viaLink, .gameFiles) == ["Stray [\(title)].nsp"], "a library folder named through a link is the same folder \(names(viaLink, .gameFiles))")

let parts = "\(root)/parts"
func volumes(_ name: String) -> [String] { RemovalPlan.archiveParts("\(parts)/\(name)").map { URL(filePath: $0).lastPathComponent } }
expect(volumes("Big.part1.rar").sorted() == ["Big.part1.rar", "Big.part10.rar", "Big.part2.rar"], "the volumes of a .partN.rar set, not another set's \(volumes("Big.part1.rar"))")
expect(volumes("Old.rar").sorted() == ["Old.r00", "Old.r01", "Old.rar"], "the volumes of an old-style .rar set \(volumes("Old.rar"))")
expect(volumes("Set.7z.001").sorted() == ["Set.7z.001", "Set.7z.002"], "the volumes of a split .7z \(volumes("Set.7z.001"))")
expect(volumes("Single.zip") == ["Single.zip"], "an archive of one volume \(volumes("Single.zip"))")

// MARK: Folders never removed whole

let home = FileManager.default.homeDirectoryForCurrentUser.path
for (path, safe) in [(home, false), ("\(home)/Downloads", false), ("\(home)/Documents", false), ("\(home)/Desktop", false), ("\(home)/Library", false),
                     ("/Users", false), ("/Volumes/Drive", false), ("/Applications", false), ("\(home)/Games/Zelda", true), (lib, true)] {
    expect(AppModel.isSafeToRemove(path) == safe, "isSafeToRemove(\(path)) is \(safe)")
}

// MARK: The build command

let split: [(String, [String]?)] = [
    ("", []), ("  --a   b ", ["--a", "b"]), ("--name 'two words'", ["--name", "two words"]),
    (#"--x "a \"q\" b""#, ["--x", #"a "q" b"#]), (#"a\ b"#, ["a b"]), ("'it''s'", ["its"]), (#"'a\b'"#, [#"a\b"#]),
    (#""a\nb""#, [#"a\nb"#]), ("''", [""]), (#"a\"#, [#"a\"#]), ("'open", nil), (#""open"#, nil),
]
for (text, words) in split {
    expect(AppModel.splitArguments(text) == words, "splitArguments(\(text)) is \(words.map { "\($0)" } ?? "nil")")
}

func build(_ target: BuildTarget, keys: String? = nil, keepExtracted: Bool = false, language: String? = nil, pipelineArchive: Bool = true,
           showFPS: Bool = false, identity: String? = nil, extra: String = "") -> [String]? {
    AppModel.buildArguments(folder: "/g", target: target, keys: keys, keepExtracted: keepExtracted, language: language, pipelineArchive: pipelineArchive,
                            showFPS: showFPS, macSigningIdentity: identity, extra: extra)
}
let base = ["build", "/g", "--target"]
expect(build(.iosSlim) == base + ["ios-slim", "--progress", "json", "--keep-extracted", "--no-show-fps"],
       "game files separate: the build keeps the extracted files it copies to the phone \(build(.iosSlim) ?? [])")
expect(build(.xcode)?.contains("--keep-extracted") == true, "an Xcode project keeps the extracted files it builds from")
expect(build(.ios, showFPS: true) == base + ["ios", "--progress", "json", "--no-keep-extracted", "--show-fps"], "iPhone: the frame rate overlay \(build(.ios, showFPS: true) ?? [])")
let mac = build(.mac, keys: "/k/prod.keys", language: "it", pipelineArchive: false, identity: "Developer ID Application: A B (X)", extra: "--foo 'a b' --bar")
expect(mac == base + ["mac", "--progress", "json", "-k", "/k/prod.keys", "--no-keep-extracted", "--language", "it", "--gpu", "none",
                      "--mac-sign", "Developer ID Application: A B (X)", "--foo", "a b", "--bar"], "Mac: every setting, and the extra options split as a shell would \(mac ?? [])")
expect(build(.mac, extra: "--foo 'open") == nil, "an extra option with a quote not closed gives no command")

// MARK: Install on a device

let onDevice = InstallOptions(device: "00008150-0000000000000001", team: "A1B2C3D4E5")
func install(_ options: InstallOptions?, keys: String? = nil, keepExtracted: Bool = false, showFPS: Bool = false, extra: String = "") -> [String]? {
    AppModel.buildArguments(folder: "/g", target: .device, keys: keys, keepExtracted: keepExtracted, language: "it", pipelineArchive: true, showFPS: showFPS,
                            macSigningIdentity: "Developer ID Application: A B (X)", extra: extra, install: options)
}
let installBase = ["install", "/g", "--progress", "json", "--device", "00008150-0000000000000001", "--team", "A1B2C3D4E5", "--files"]
expect(install(onDevice, keys: "/k/prod.keys", extra: "--allow-damaged") == installBase + ["auto", "-k", "/k/prod.keys", "--language", "it", "--no-show-fps", "--allow-damaged"],
       "an install: the device, the team, the files where the device allows; no keep-extracted of its own and no Mac signing identity \(install(onDevice, keys: "/k/prod.keys", extra: "--allow-damaged") ?? [])")
var inApp = onDevice
inApp.files = "bundle"
expect(install(inApp)?.contains("bundle") == true, "the files in the app, when chosen")
var slim = onDevice
slim.files = "separate"; slim.launch = true; slim.iCloudContainer = "iCloud.com.example.saves"
expect(install(slim, showFPS: true) == installBase + ["separate", "--launch", "--icloud-container", "iCloud.com.example.saves", "--language", "it", "--show-fps"],
       "an install with the game files separate, opened afterwards, with an iCloud container \(install(slim, showFPS: true) ?? [])")
expect(install(nil) == nil, "an install without a device and a team gives no command")
expect(!(install(onDevice, keepExtracted: false) ?? []).contains("--no-keep-extracted"), "an install never drops the extracted files its Xcode project builds from")
expect(AppModel.signingEnvironment(keyPath: "", keyID: "K", issuer: "I").isEmpty, "no API key file: nothing about a key in the environment")
expect(AppModel.signingEnvironment(keyPath: "/k/AuthKey_K.p8", keyID: "", issuer: "I") == ["AETHERNX_ASC_KEY": "/k/AuthKey_K.p8", "AETHERNX_ASC_ISSUER": "I"],
       "an API key goes to the install in its environment, the key ID left to the file's name")

let listJSON = """
{"version": 1, "devices": [
 {"udid": "U1", "identifier": "I1", "name": "Phone", "model": "iPhone 17 Pro", "kind": "iPhone", "os": "27.2", "connection": "network", "paired": true, "developer_mode": true},
 {"udid": "U2", "identifier": "I2", "name": "Tablet", "model": "iPad Pro", "kind": "iPad", "os": "26.6", "connection": "none", "paired": true, "developer_mode": null}],
 "teams": [{"id": "A1B2C3D4E5", "name": "Jane Doe", "identity": "Apple Development: Jane Doe (Z9Y8X7W6V5)"}]}
"""
let list = try JSONDecoder.snakeCase.decode(DeviceList.self, from: Data(listJSON.utf8))
expect(list.devices.map(\.udid) == ["U1", "U2"] && list.devices[0].isReachable && !list.devices[1].isReachable && list.devices[1].developerMode == nil,
       "the device list of ./aethernx devices --json is read")
expect(list.devices[1].systemImage == "ipad" && list.devices[0].summary.contains("iPhone 17 Pro"), "a device's picture and summary \(list.devices[0].summary)")
expect(DeviceCenter.device(chosen: "", among: list.devices)?.udid == "U1", "no device chosen: the only one reachable")
expect(DeviceCenter.device(chosen: "U2", among: list.devices)?.udid == "U2", "the chosen device, reachable or not (the install then says it is not connected)")
expect(DeviceCenter.device(chosen: "GONE", among: list.devices) == nil, "a chosen device this Mac no longer lists is not replaced by another")
var two = list.devices
two[1].connection = "cable"
expect(DeviceCenter.device(chosen: "", among: two) == nil, "two reachable devices and none chosen: none")
expect(DeviceCenter.team(chosen: "", among: list.teams) == "A1B2C3D4E5", "no team chosen: the only one with a certificate")
expect(DeviceCenter.team(chosen: " z9y8x7w6v5 ", among: list.teams) == "Z9Y8X7W6V5", "a team ID typed in is taken as it is")
expect(DeviceCenter.team(chosen: "", among: list.teams + list.teams) == nil && DeviceCenter.team(chosen: "nonsense", among: []) == nil, "several teams or none, and no valid choice: none")

let installedJSON = """
{"id": "/g", "kind": "packages", "title_id": "\(title)", "name": "Stray", "folder": "/g",
 "device_install": {"team": "A1B2C3D4E5", "bundle_id": "io.example.game", "device": "U1", "device_name": "Phone", "installed": "2026-11-12T10:30:00Z"}}
"""
let installed = try JSONDecoder.snakeCase.decode(Game.self, from: Data(installedJSON.utf8))
expect(installed.deviceInstall?.deviceName == "Phone" && installed.deviceInstall?.date != nil, "a scan's record of the last install on a device")
expect(game.deviceInstall == nil, "a game never installed has none")
expect(BuildTarget.menuOrder.contains(.device) && BuildTarget(rawValue: "device") == .device, "the install is one of the Build button's targets")

// MARK: Cloud saves

let cloudHome = "/Users/jane"
let drive = "\(cloudHome)/Library/Mobile Documents/com~apple~CloudDocs"
expect(CloudSaves.displayName(CloudSaves.automaticFolder(home: cloudHome), home: cloudHome) == "iCloud Drive › HorizonNative", "the iCloud container's folder by its name in iCloud Drive")
expect(CloudSaves.displayName("\(drive)/Games/My Saves", home: cloudHome) == "iCloud Drive › Games › My Saves", "an iCloud Drive folder as the Finder shows it")
expect(CloudSaves.displayName(CloudSaves.driveFolder(home: cloudHome), home: cloudHome) == "iCloud Drive › HorizonNative Saves", "the folder DM_SAVE_SYNC=icloud names")
expect(CloudSaves.displayName("\(cloudHome)/Saves", home: cloudHome) == "~/Saves" && CloudSaves.displayName("/Volumes/Drive/Saves", home: cloudHome) == "/Volumes/Drive/Saves",
       "another folder from the home folder, or whole")
expect(CloudSaves.cloudFile(folder: "/c/Saves", titleID: title) == "/c/Saves/\(title)/save.dmsync", "a game's file in a folder for every game")
expect(CloudSaves.cloudFile(folder: "/c/Saves/\(title.lowercased())", titleID: title) == "/c/Saves/\(title.lowercased())/save.dmsync", "a folder that is already the game's own")
let envText = "# comment\nDM_FPS_TARGET=30\nDM_SAVE_SYNC=/a\n  export DM_SAVE_SYNC = \"/b c\" \n#DM_SAVE_SYNC=/no\nDM_SAVE_SYNC_CHOICE=ask\n"
expect(CloudSaves.envValue("DM_SAVE_SYNC", in: envText) == "/a", "an env file's value: the name whole, a spaced or commented line is not one \(CloudSaves.envValue("DM_SAVE_SYNC", in: envText) ?? "nil")")
expect(CloudSaves.envValue("DM_SAVE_SYNC", in: "DM_SAVE_SYNC=/a\nexport DM_SAVE_SYNC='/b c'\n") == "/b c", "the last line wins, quotes and export taken off")
expect(CloudSaves.envValue("DM_SAVE_SYNC", in: "DM_FPS_TARGET=30\n") == nil, "a file without the variable")
let logText = "[dm] boot: cloud saves through /c (the picked folder)\n[dm] save sync: the cloud's save is newer: brought in\n[dm] frame 60\n[dm] save sync: sent (3 files, 1.2 MB)\n[dm] quit\n"
expect(CloudSaves.lastNote(inLog: logText) == CloudSaves.LogNote(text: "sent (3 files, 1.2 MB)", isError: false), "the last thing a session said about the sync")
expect(CloudSaves.lastNote(inLog: logText + "[dm] [RED] save sync: writing /c to the cloud failed: offline\n")?.isError == true, "a red line is an error")
expect(CloudSaves.lastNote(inLog: "[dm] frame 60\n") == nil, "a log that says nothing about it")
let sentTo = "sent: 8 files, to \(CloudSaves.automaticFolder(home: cloudHome))/\(title)/save.dmsync"
expect(CloudSaves.shortened(sentTo, folder: CloudSaves.automaticFolder(home: cloudHome), home: cloudHome) == "sent: 8 files, to iCloud Drive › HorizonNative/\(title)/save.dmsync",
       "a log line names the cloud folder as the Finder does")
expect(CloudSaves.shortened("kept in \(cloudHome)/Library/x", folder: "/c", home: cloudHome) == "kept in ~/Library/x", "and the home folder as ~")

// The store: a throwaway preferences domain, removed afterwards
let cloudDomain = "io.github.icosisenpai.aethernx.studio-check.\(UUID().uuidString)"
let otherDomain = cloudDomain + ".other"
func forget(_ domain: String) {
    for key in [CloudSaves.folderKey, CloudSaves.inheritedKey] { CFPreferencesSetAppValue(key as CFString, nil, domain as CFString) }
    CFPreferencesAppSynchronize(domain as CFString)
}
expect(CloudSaves.setting(domain: cloudDomain) == .unset, "a game with no choice")
expect(CloudSaves.applyLibraryFolder("/c/Library", domains: [cloudDomain, otherDomain, cloudDomain]) == 2, "the library's folder reaches the games with no choice, each once")
expect(CloudSaves.setting(domain: cloudDomain) == .folder("/c/Library", inherited: true), "it is marked as the library's")
CloudSaves.choose("/c/Own", domain: otherDomain)
expect(CloudSaves.setting(domain: otherDomain) == .folder("/c/Own", inherited: false), "a game's own folder")
expect(CloudSaves.applyLibraryFolder("/c/Moved", domains: [cloudDomain, otherDomain]) == 1, "a new library folder moves only the games that follow it")
expect(CloudSaves.setting(domain: cloudDomain).folder == "/c/Moved" && CloudSaves.setting(domain: otherDomain).folder == "/c/Own", "the game's own choice stays")
CloudSaves.choose(nil, domain: otherDomain)
expect(CloudSaves.setting(domain: otherDomain) == .off, "off for one game")
expect(CloudSaves.applyLibraryFolder("/c/Moved", domains: [otherDomain]) == 0 && CloudSaves.setting(domain: otherDomain) == .off, "a game turned off stays off under a library folder")
expect(CloudSaves.applyLibraryFolder("", domains: [cloudDomain, otherDomain]) == 1 && CloudSaves.setting(domain: cloudDomain) == .unset, "the library turned off: the games that followed it have no folder")
CloudSaves.followLibrary("/c/Library", domain: otherDomain)
expect(CloudSaves.setting(domain: otherDomain) == .folder("/c/Library", inherited: true), "a game goes back to the library's setting")
forget(cloudDomain); forget(otherDomain)
expect(CloudSaves.setting(domain: otherDomain) == .unset, "the throwaway domains are gone")
expect(CloudSaves.domain(for: game) == "io.github.icosisenpai.horizonnative.\(title)", "a game's domain is its built app's bundle ID \(CloudSaves.domain(for: game) ?? "nil")")

// MARK: Commands the app waits for

let started = Date()
let slow = await CommandRunner.capture(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], directory: nil, timeout: 0.5)
let waited = Date().timeIntervalSince(started)
expect(waited < 10 && slow.status != 0, "a command still running at its timeout is ended (\(Int(waited * 1000)) ms, status \(slow.status))")
let both = await CommandRunner.capture(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' e >&2; echo out; exit 3"], directory: nil)
expect(both.status == 3 && String(decoding: both.stdout, as: UTF8.self) == "out\n" && both.stderr.count == 300_000,
       "a full stderr does not block stdout, and both come back with the status (\(both.status), \(both.stderr.count) bytes of stderr)")
let missing = await CommandRunner.capture(executable: URL(filePath: "\(root)/no-such-command"), arguments: [], directory: nil)
expect(missing.status == -1 && !missing.stderr.isEmpty, "a command that cannot start says why (\(missing.stderr))")

// MARK: Updates

for (a, b, newer) in [("0.3.0", "0.2.9", true), ("0.2.10", "0.2.9", true), ("1.0", "1.0.0", false), ("0.2.0", "0.10.0", false), ("1.0.1", "1.0", true)] {
    expect(UpdateCenter.isVersion(a, newerThan: b) == newer, "\(a) is \(newer ? "" : "not ")newer than \(b)")
}

// Release archives: good-*.zip are unpacked, bad-*.zip refused before ditto sees them
let archives = "\(root)/archives"
for name in try FileManager.default.contentsOfDirectory(atPath: archives).sorted() where name.hasSuffix(".zip") {
    let data = try Data(contentsOf: URL(filePath: "\(archives)/\(name)"))
    let accepted = UpdateCenter.isSafeAppArchive(data)
    expect(accepted == name.hasPrefix("good-"), "\(name) is \(accepted ? "accepted" : "refused")")
}
let release = UpdateCenter.zipEntries(try Data(contentsOf: URL(filePath: "\(archives)/good-ditto.zip"))) ?? []
let modes = Dictionary(release.map { ($0.name, $0.mode) }, uniquingKeysWith: { first, _ in first })
expect(modes["AetherNX.app/"].map { $0 & 0o170000 == 0o040000 } == true, "ditto's archive: the app is a folder")
expect(modes["AetherNX.app/Contents/MacOS/AetherNX"] == 0o100755, "ditto's archive: the executable keeps its mode")
expect(release.contains { $0.name.hasPrefix("__MACOSX/") }, "ditto's archive: the metadata copy is listed (\(release.count) entries)")

// MARK: iCloud Drive › AetherNX, mods and cheats

let aether = CloudSaves.aetherFolder(home: cloudHome)
expect(CloudSaves.libraryTarget(aether, gameName: "Fire Emblem: Fortune's Weave", home: cloudHome) == aether + "/Fire Emblem- Fortune's Weave",
       "with AetherNX as the library's folder each game takes a folder named after it, without what a file name cannot hold")
expect(CloudSaves.libraryTarget("/c/Saves", gameName: "X", home: cloudHome) == "/c/Saves" && CloudSaves.libraryTarget("", gameName: "X", home: cloudHome) == "",
       "another library folder is every game's, and none is none")
expect(CloudSaves.folderName(for: " ../ ") == "-" || !CloudSaves.folderName(for: " ../ ").contains("/"), "a name never makes a path")
expect(GameExtras.isOwnFolder(aether + "/Game", titleID: title, home: cloudHome) && GameExtras.isOwnFolder("/c/\(title)", titleID: title, home: cloudHome)
       && !GameExtras.isOwnFolder("/c/Saves", titleID: title, home: cloudHome), "a game's own folder: AetherNX › its name, or one named by its title ID")
expect(CloudSaves.displayName(CloudSaves.automaticFolder(home: cloudHome) + "/\(title)/Mods", home: cloudHome) == "iCloud Drive › HorizonNative › \(title) › Mods",
       "a folder inside the iCloud container, by its names in iCloud Drive")
let modsRoot = "\(root)/mods-check/Mods"
let fm = FileManager.default
for (name, sub) in [("B Music", "romfs/sound"), ("A Skin", "atmosphere/contents/\(title)/romfs/model"), ("C Code", "exefs"), ("D Both", "romfs/x")] {
    try? fm.createDirectory(atPath: "\(modsRoot)/\(name)/\(sub)", withIntermediateDirectories: true)
}
try? fm.createDirectory(atPath: "\(modsRoot)/D Both/exefs", withIntermediateDirectories: true)
let mods = GameExtras.mods(in: modsRoot, order: ["B Music"], titleID: title)
expect(mods.map(\.name) == ["B Music", "A Skin", "C Code", "D Both"], "the chosen order first, the new mods after it by name \(mods.map(\.name))")
expect(mods.first { $0.name == "A Skin" }?.romfs?.hasSuffix("atmosphere/contents/\(title)/romfs") == true, "Atmosphère's layout is a mod too")
expect(mods.first { $0.name == "C Code" }.map { $0.romfs == nil && $0.hasCode } == true && mods.first { $0.name == "D Both" }?.hasCode == true, "code mods are told apart")
let overlay = GameExtras.overlay(mods, off: ["A Skin"])
expect(overlay == ["\(modsRoot)/B Music/romfs", "\(modsRoot)/D Both/romfs"], "the overlay: the mods on that have a romfs, in order \(overlay)")
try? fm.createDirectory(atPath: "\(root)/mods-check/Cheats", withIntermediateDirectories: true)
try? "[Infinite HP]\n04000000 00000000 00000063\n{Master}\n[Max Gold]\n".write(toFile: "\(root)/mods-check/Cheats/0123456789ABCDEF.txt", atomically: true, encoding: .utf8)
expect(GameExtras.cheatFiles(in: "\(root)/mods-check/Cheats", titleID: title).map(\.cheats) == [3], "a cheat file and how many cheats it has")

// Mods/mods.json: the order and the mods off for every device, written by Studio and the companion (docs/companion.md)
let modDomain = "io.github.icosisenpai.aethernx.studio-check.mods.\(UUID().uuidString)"
GameExtras.set(["A Skin"], for: GameExtras.ordersKey, domain: modDomain)
expect(GameExtras.modState(modsFolder: modsRoot, domain: modDomain) == .init(order: ["A Skin"], off: []), "without mods.json, the preference keys")
GameExtras.saveState(.init(order: ["D Both", "B Music"], off: ["B Music", "B Music"]), modsFolder: modsRoot, domain: modDomain)
expect(GameExtras.readState(modsFolder: modsRoot) == .init(order: ["D Both", "B Music"], off: ["B Music"]), "a change goes into mods.json")
expect(GameExtras.strings(GameExtras.offKey, domain: modDomain) == ["B Music"] && GameExtras.strings(GameExtras.ordersKey, domain: modDomain) == ["D Both", "B Music"],
       "and into the preference keys")
try? #"{"format": 1, "order": ["C Code"], "off": ["A Skin"], "from": "the companion"}"#.write(toFile: "\(modsRoot)/mods.json", atomically: true, encoding: .utf8)
expect(GameExtras.modState(modsFolder: modsRoot, domain: modDomain) == .init(order: ["C Code"], off: ["A Skin"]), "a mods.json the companion wrote wins over the keys")
expect(GameExtras.mods(in: modsRoot, order: ["C Code"], titleID: title).map(\.name) == ["C Code", "A Skin", "B Music", "D Both"], "mods.json is no mod")
try? #"{"format": 2, "order": []}"#.write(toFile: "\(modsRoot)/mods.json", atomically: true, encoding: .utf8)
expect(GameExtras.readState(modsFolder: modsRoot) == nil, "a later format is not read")
CFPreferencesSetAppValue(GameExtras.ordersKey as CFString, nil, modDomain as CFString)
CFPreferencesSetAppValue(GameExtras.offKey as CFString, nil, modDomain as CFString)
CFPreferencesAppSynchronize(modDomain as CFString)

// game.json: what the companion lists a game by (docs/companion.md)
let fireFolder = aether + "/Fire Emblem- Fortune's Weave"
expect(GameManifest.folder(macSetting: nil, libraryFolder: aether, gameName: "Fire Emblem: Fortune's Weave", home: cloudHome) == fireFolder,
       "a game with no Mac app takes the library's game folder")
expect(GameManifest.folder(macSetting: .folder(fireFolder, inherited: false), libraryFolder: "", gameName: "X", home: cloudHome) == fireFolder,
       "a Mac app's own game folder of AetherNX")
expect(GameManifest.folder(macSetting: .folder("\(drive)/HorizonNative Saves", inherited: true), libraryFolder: aether, gameName: "X", home: cloudHome) == nil
       && GameManifest.folder(macSetting: .off, libraryFolder: aether, gameName: "X", home: cloudHome) == nil
       && GameManifest.folder(macSetting: nil, libraryFolder: "\(drive)/HorizonNative Saves", gameName: "X", home: cloudHome) == nil
       && GameManifest.folder(macSetting: .folder(aether, inherited: false), libraryFolder: "", gameName: "X", home: cloudHome) == nil,
       "no game.json outside a game folder of iCloud Drive › AetherNX, nor in the AetherNX folder itself")
let manifestFolder = "\(root)/manifest-check/AetherNX/Starfall Tactics"
let iconSource = "\(root)/manifest-check/icon-source.png"
try? fm.createDirectory(atPath: "\(root)/manifest-check", withIntermediateDirectories: true)
try? Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]).write(to: URL(filePath: iconSource))
let manifestItem = GameManifest.Item(folder: manifestFolder, contents: .init(format: 1, name: "Starfall Tactics", titleId: title, version: "1.2.0", icon: nil,
                                                                            bundleId: "io.github.icosisenpai.horizonnative.\(title.lowercased())"), iconSource: iconSource)
expect(GameManifest.write(manifestItem), "the first write makes the folder, game.json and the icon")
let written = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: "\(manifestFolder)/game.json")))) as? [String: Any]
expect(written?["name"] as? String == "Starfall Tactics" && written?["titleId"] as? String == title && written?["version"] as? String == "1.2.0"
       && written?["icon"] as? String == "icon.png" && written?["format"] as? Int == 1 && fm.fileExists(atPath: "\(manifestFolder)/icon.png"),
       "game.json names the game, its title ID, version and the icon beside it")
expect(!GameManifest.write(manifestItem), "the same game writes nothing again")
var noIcon = manifestItem
noIcon.iconSource = nil
expect(GameManifest.write(noIcon) && ((try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: "\(manifestFolder)/game.json")))) as? [String: Any])?["icon"] == nil,
       "without a picture, no icon key")
expect(String(decoding: GameManifest.encode(manifestItem.contents), as: UTF8.self).contains("\"bundleId\" : \"io.github.icosisenpai.horizonnative."),
       "sorted keys, slashes as they are")

// MARK: What a build stage does, and what an engine update means

expect(StageGuide.entry(for: "extract base") != nil && StageGuide.entry(for: "iOS shaders") != nil && StageGuide.entry(for: "Pipeline archive") != nil
       && StageGuide.entry(for: "sign for the device") != nil && StageGuide.entry(for: "copy the game files") != nil, "the build's and the install's stages are explained")
expect(StageGuide.entry(for: "something new") == nil && StageGuide.title(for: "something new") == "something new", "a stage it does not know shows by its own name")
expect(UpdateCenter.impact(of: ["studio/Sources/App.swift"]) == (false, false, true), "a change of the app's sources only")
expect(UpdateCenter.impact(of: ["dm/host/hle_fs.c", "dm/gfx/nvn/dmsh_chain.h"]) == (true, true, false), "an engine change and a new shader chain")
expect(UpdateCenter.impact(of: ["docs/playing.md"]) == (false, false, false), "documentation only")

// MARK: Builds and Mac apps on another disk (Settings → Library, aethernx move-build)

expect(Storage.volume(of: "\(root)/x").isThisMac && Storage.volume(of: "/Users/someone/Games/x_build").isConnected, "a folder of this Mac's own disk")
let gone = Storage.volume(of: "/Volumes/AetherNX check drive that is not there/Builds/x_build")
expect(!gone.isThisMac && !gone.isConnected && gone.name == "AetherNX check drive that is not there", "a drive that is not connected, by its name")
expect(StageGuide.entry(for: "copy the build to /Volumes/NAS/AetherNX/Game") != nil && StageGuide.entry(for: "check the copy") != nil
       && StageGuide.entry(for: "remove the original") != nil, "move-build's stages are explained")
let elsewhereJSON = """
{"id": "\(lib)", "kind": "packages", "title_id": "\(title)", "name": "Stray", "folder": "\(lib)", "work_dir": "/Volumes/NAS/AetherNX/Stray/\(title)_build",
 "work_reachable": false, "work_moves_to": null}
"""
let elsewhere = try JSONDecoder.snakeCase.decode(Game.self, from: Data(elsewhereJSON.utf8))
expect(!elsewhere.workReachable && elsewhere.workMovesTo == nil, "a build on a disk that is not connected, as the scan tells it")
expect(game.workReachable && game.workMovesTo == nil, "an older scan without the fields: the build is reachable and stays where it is")

print("studio check: \(failures) failed")
exit(failures == 0 ? 0 : 1)
