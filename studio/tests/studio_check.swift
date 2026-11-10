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

print("studio check: \(failures) failed")
exit(failures == 0 ? 0 : 1)
