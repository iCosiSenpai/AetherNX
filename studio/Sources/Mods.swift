import AppKit
import Foundation
import SwiftUI

/// What a game keeps beside its save: its mods and its cheats, in its folder of iCloud Drive › AetherNX (or of the cloud folder it uses), else on this Mac.
///
/// The Mac app reads two keys of its own preferences at every start (dm/mac/launcher.c, mods_and_cheats; docs/frontends.md, Mods and cheats):
/// `mods.folders`, the RomFS folders of the mods that are on, in priority order, which become DM_ROMFS_OVERLAY, and `cheats.folder`, which becomes
/// DM_CHEATS. Studio keeps the order and the mods turned off in `mods.order` and `mods.off`, and writes `mods.folders` from them and the folder's
/// contents whenever either changes. Engine semantics: a mod is a folder with a `romfs` folder in it (Atmosphère's layout, `atmosphere/contents/<title
/// ID>/romfs`, works too); files in it replace the game's own at the same path, the first mod that has a file wins. Code mods (`exefs`) do not run.
enum GameExtras {
    static let ordersKey = "mods.order"
    static let offKey = "mods.off"
    static let foldersKey = "mods.folders"
    static let cheatsKey = "cheats.folder"

    struct Mod: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let path: String
        /// The folder that replaces the game's files; nil when the mod has none (a code-only mod, or a folder that is not a mod).
        let romfs: String?
        let hasCode: Bool
    }

    struct CheatFile: Identifiable, Hashable {
        var id: String { path }
        let name: String
        let path: String
        let cheats: Int
    }

    /// The folder the game's Mods and Cheats are in.
    static func folder(for game: Game, home: String = NSHomeDirectory()) -> String? {
        guard let id = game.titleId else { return nil }
        if let domain = CloudSaves.domain(for: game), let cloud = CloudSaves.setting(domain: domain).folder {
            return isOwnFolder(cloud, titleID: id, home: home) ? cloud : (cloud as NSString).appendingPathComponent(id)
        }
        return home + "/Library/Application Support/HorizonNative/\(id)"
    }

    /// A cloud folder that is the game's alone (iCloud Drive › AetherNX › its name, or a folder named by its title ID), not one every game shares.
    static func isOwnFolder(_ folder: String, titleID: String, home: String = NSHomeDirectory()) -> Bool {
        let path = (folder as NSString).standardizingPath
        if (path as NSString).lastPathComponent.caseInsensitiveCompare(titleID) == .orderedSame { return true }
        return (path as NSString).deletingLastPathComponent == CloudSaves.aetherFolder(home: home)
    }

    static func modsFolder(in base: String) -> String { (base as NSString).appendingPathComponent("Mods") }

    /// The engine's own default on this Mac is `<DM_ROOT>/cheats`: a game's local folder keeps that name, so the cheats its Mac menu lists stay.
    static func cheatsFolder(in base: String, home: String = NSHomeDirectory()) -> String {
        (base as NSString).appendingPathComponent(base.hasPrefix(home + "/Library/Application Support/HorizonNative/") ? "cheats" : "Cheats")
    }

    /// Makes the Mods and Cheats folders of a game's folder, with a note on what goes where (once).
    static func prepare(folder: String, game: Game) {
        guard let id = game.titleId else { return }
        let base = isOwnFolder(folder, titleID: id) ? folder : (folder as NSString).appendingPathComponent(id)
        let fm = FileManager.default
        try? fm.createDirectory(atPath: modsFolder(in: base), withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: cheatsFolder(in: base), withIntermediateDirectories: true)
        let note = (base as NSString).appendingPathComponent(String(localized: "Read me.txt"))
        guard !fm.fileExists(atPath: note) else { return }
        let text = String(localized: """
        \(game.name) (\(id)), kept by AetherNX.

        • The save syncs through the folder \(id) here (on the iPhone or iPad, choose this folder in the game's Cloud saves).
        • Mods: one folder per mod in Mods, with a romfs folder inside (the files the mod replaces). Turn them on and off, and choose their order, on the game's page in AetherNX.
        • Cheats: Atmosphère cheat files (<build ID>.txt) in Cheats. Turn single cheats on and off while you play, from the game's Cheats menu.
        """)
        try? text.write(toFile: note, atomically: true, encoding: .utf8)
    }

    /// The mods in a Mods folder, in the order chosen (new ones last, by name).
    static func mods(in modsFolder: String, order: [String], titleID: String) -> [Mod] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: modsFolder) else { return [] }
        var found: [Mod] = []
        for name in names where !name.hasPrefix(".") {
            let path = (modsFolder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let candidates = ["romfs", "atmosphere/contents/\(titleID)/romfs", "atmosphere/contents/\(titleID.lowercased())/romfs", "contents/\(titleID)/romfs", "\(titleID)/romfs"]
            let romfs = candidates.map { (path as NSString).appendingPathComponent($0) }.first { fm.fileExists(atPath: $0) }
            let code = ["exefs", "atmosphere/contents/\(titleID)/exefs", "atmosphere/exefs_patches"].contains { fm.fileExists(atPath: (path as NSString).appendingPathComponent($0)) }
            found.append(Mod(name: name, path: path, romfs: romfs, hasCode: code))
        }
        return found.sorted { a, b in
            let ia = order.firstIndex(of: a.name) ?? Int.max, ib = order.firstIndex(of: b.name) ?? Int.max
            return ia != ib ? ia < ib : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The cheat files of a Cheats folder: `<build ID>.txt` at its top, or Atmosphère's tree under it.
    static func cheatFiles(in folder: String, titleID: String) -> [CheatFile] {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in [folder, "\(folder)/atmosphere/contents/\(titleID)/cheats", "\(folder)/atmosphere/contents/\(titleID.lowercased())/cheats"] {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.lowercased().hasSuffix(".txt") && !name.hasPrefix(".") {
                paths.append((dir as NSString).appendingPathComponent(name))
            }
        }
        return paths.map { path in
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let count = text.split(whereSeparator: \.isNewline).filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("{") && t.hasSuffix("}"))
            }.count
            return CheatFile(name: (path as NSString).lastPathComponent, path: path, cheats: count)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: The game app's preferences

    static func strings(_ key: String, domain: String) -> [String] {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [String] ?? []
    }

    static func set(_ value: Any?, for key: String, domain: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    /// The RomFS folders the Mac app overlays, from the mods on, in order.
    static func overlay(_ mods: [Mod], off: Set<String>) -> [String] {
        mods.filter { !off.contains($0.name) }.compactMap(\.romfs).filter { !$0.contains(":") }
    }
}

extension AppModel {
    /// Writes what the game's Mac app reads at its next start: its mods on, in order, and its cheats folder.
    func refreshExtras(_ game: Game) {
        guard let id = game.titleId, let domain = CloudSaves.domain(for: game), let base = GameExtras.folder(for: game) else { return }
        let mods = GameExtras.mods(in: GameExtras.modsFolder(in: base), order: GameExtras.strings(GameExtras.ordersKey, domain: domain), titleID: id)
        let off = Set(GameExtras.strings(GameExtras.offKey, domain: domain))
        let overlay = GameExtras.overlay(mods, off: off)
        GameExtras.set(overlay.isEmpty ? nil : overlay, for: GameExtras.foldersKey, domain: domain)
        let cheats = GameExtras.cheatsFolder(in: base)
        GameExtras.set(FileManager.default.fileExists(atPath: cheats) ? cheats : nil, for: GameExtras.cheatsKey, domain: domain)
        extrasRevision += 1
    }
}

// MARK: - The game's page

struct ModsSection: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var revision = 0

    var body: some View {
        let _ = (revision, model.extrasRevision)
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if let id = game.titleId, let domain = CloudSaves.domain(for: game), let base = GameExtras.folder(for: game) {
                    content(id: id, domain: domain, base: base)
                } else {
                    Text("Mods need the game's title ID: build the game once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 4)
        } label: {
            HStack {
                Text("Mods")
                Spacer()
                Link("Find Mods on GameBanana", destination: Self.gameBanana(game.name))
                    .font(.callout)
                    .help("Opens GameBanana's search for this game in your browser. File mods (romfs) work; mods that need a loader or patch the code do not.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in revision += 1 }
        .task(id: game.id) { model.refreshExtras(game) }
    }

    static func gameBanana(_ name: String) -> URL {
        var parts = URLComponents(string: "https://gamebanana.com/search")!
        parts.queryItems = [URLQueryItem(name: "_sSearchString", value: name)]
        return parts.url!
    }

    @ViewBuilder
    private func content(id: String, domain: String, base: String) -> some View {
        let folder = GameExtras.modsFolder(in: base)
        let order = GameExtras.strings(GameExtras.ordersKey, domain: domain)
        let off = Set(GameExtras.strings(GameExtras.offKey, domain: domain))
        let mods = GameExtras.mods(in: folder, order: order, titleID: id)
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mods.isEmpty ? String(localized: "No mods yet") : String(localized: "\(mods.filter { !off.contains($0.name) && $0.romfs != nil }.count) of \(mods.count) on"))
                Text(CloudSaves.displayName(folder))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder)
            }
            Spacer()
            RowButton("Add…", systemImage: "plus") { add(to: folder, domain: domain) }
            RowButton("Show in Finder", systemImage: "folder") {
                try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                Finder.reveal(folder)
            }
        }
        .padding(.vertical, 8)
        ForEach(Array(mods.enumerated()), id: \.element.id) { index, mod in
            Divider()
            ModRow(mod: mod, isOn: !off.contains(mod.name), isFirst: index == 0, isLast: index == mods.count - 1,
                   toggle: { on in setOn(mod, on, off: off, domain: domain) },
                   move: { delta in move(mod, by: delta, in: mods, domain: domain) },
                   remove: { trash(mod) })
        }
        if !mods.isEmpty {
            Text("Mods higher in the list win when two change the same file. Changes apply at the game's next start, with no rebuild.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    private func setOn(_ mod: GameExtras.Mod, _ on: Bool, off: Set<String>, domain: String) {
        var off = off
        if on { off.remove(mod.name) } else { off.insert(mod.name) }
        GameExtras.set(off.isEmpty ? nil : Array(off).sorted(), for: GameExtras.offKey, domain: domain)
        model.refreshExtras(game)
    }

    private func move(_ mod: GameExtras.Mod, by delta: Int, in mods: [GameExtras.Mod], domain: String) {
        var names = mods.map(\.name)
        guard let i = names.firstIndex(of: mod.name), names.indices.contains(i + delta) else { return }
        names.swapAt(i, i + delta)
        GameExtras.set(names, for: GameExtras.ordersKey, domain: domain)
        model.refreshExtras(game)
    }

    private func trash(_ mod: GameExtras.Mod) {
        model.confirmMoveToTrash(mod.path, title: String(localized: "Move the mod “\(mod.name)” to the Trash?"),
                                 message: String(localized: "The game no longer uses it from its next start. It stays in the Trash until you empty it.")) { [model, game] in
            model.refreshExtras(game)
        }
    }

    /// A mod folder (or a romfs folder, or a .zip of one) copied into the Mods folder.
    private func add(to folder: String, domain: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder, .zip]
        panel.message = String(localized: "Choose mod folders (each with a romfs folder inside) or .zip files of them. They are copied into the game's Mods folder.")
        panel.prompt = String(localized: "Add")
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task {
                let failures = await Task.detached(priority: .userInitiated) { ModInstaller.install(urls, into: folder) }.value
                for failure in failures { model.log(failure, kind: .error) }
                if failures.isEmpty { model.log(String(localized: "\(urls.count) mod(s) added to \(game.name): on at its next start."), kind: .info) }
                model.refreshExtras(game)
            }
        }
    }
}

private struct ModRow: View {
    let mod: GameExtras.Mod
    let isOn: Bool
    let isFirst: Bool
    let isLast: Bool
    let toggle: (Bool) -> Void
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isOn && mod.romfs != nil }, set: toggle)) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(mod.romfs == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if mod.romfs == nil {
                    Text(mod.hasCode ? "Patches the game's code (exefs): the engine does not run code mods." : "No romfs folder inside: not a mod the engine can use.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if mod.hasCode {
                    Text("Its file changes are used; its code patches (exefs) are not.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ControlGroup {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(isFirst)
                    .help("Higher: wins over the mods below")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(isLast)
                    .help("Lower")
            }
            .fixedSize()
            Menu {
                Button("Show in Finder") { Finder.reveal(mod.path) }
                Divider()
                Button("Move to Trash…", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 6)
    }
}

/// Copies mods into a game's Mods folder, off the main thread.
enum ModInstaller {
    static func install(_ urls: [URL], into folder: String) -> [String] {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        var failures: [String] = []
        for url in urls {
            var name = url.deletingPathExtension().lastPathComponent
            if url.lastPathComponent.lowercased() == "romfs" { name = url.deletingLastPathComponent().lastPathComponent }
            let dest = URL(filePath: folder).appending(path: name)
            if fm.fileExists(atPath: dest.path) {
                failures.append(String(localized: "A mod named \(name) is already there: remove it first, or rename the new one."))
                continue
            }
            do {
                if url.pathExtension.lowercased() == "zip" {
                    let p = Process()
                    p.executableURL = URL(filePath: "/usr/bin/ditto")
                    p.arguments = ["-x", "-k", url.path, dest.path]
                    try p.run(); p.waitUntilExit()
                    if p.terminationStatus != 0 { throw CocoaError(.fileReadCorruptFile) }
                    // A zip of one folder: its content is the mod
                    let inside = (try? fm.contentsOfDirectory(atPath: dest.path).filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }) ?? []
                    if inside.count == 1, inside[0].lowercased() != "romfs", let sub = Optional(dest.appending(path: inside[0])),
                       fm.fileExists(atPath: sub.appending(path: "romfs").path) {
                        let tmp = dest.deletingLastPathComponent().appending(path: ".\(name).tmp")
                        try fm.moveItem(at: sub, to: tmp)
                        try fm.removeItem(at: dest)
                        try fm.moveItem(at: tmp, to: dest)
                    }
                } else if url.lastPathComponent.lowercased() == "romfs" {
                    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                    try fm.copyItem(at: url, to: dest.appending(path: "romfs"))
                } else {
                    try fm.copyItem(at: url, to: dest)
                }
            } catch {
                failures.append(String(localized: "\(url.lastPathComponent) was not added: \(error.localizedDescription)"))
            }
        }
        return failures
    }
}

struct CheatsSection: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var revision = 0

    var body: some View {
        let _ = (revision, model.extrasRevision)
        GroupBox("Cheats") {
            VStack(alignment: .leading, spacing: 0) {
                if let id = game.titleId, let base = GameExtras.folder(for: game) {
                    let folder = GameExtras.cheatsFolder(in: base)
                    let files = GameExtras.cheatFiles(in: folder, titleID: id)
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(files.isEmpty ? String(localized: "No cheat files yet")
                                               : String(localized: "\(files.reduce(0) { $0 + $1.cheats }) cheats in \(files.count) file(s)"))
                            Text(CloudSaves.displayName(folder))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(folder)
                        }
                        Spacer()
                        RowButton("Add…", systemImage: "plus") { add(to: folder) }
                        RowButton("Show in Finder", systemImage: "folder") {
                            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                            Finder.reveal(folder)
                        }
                    }
                    .padding(.vertical, 8)
                    ForEach(files) { file in
                        Divider()
                        HStack {
                            Text(file.name)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(file.cheats) cheats")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    Text("Atmosphère cheat files, named by the game's build ID. Cheats change values while you play and fit one version of the game only. Turn single cheats on and off from the game's Cheats menu (⌘⇧C).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    Text("Cheats need the game's title ID: build the game once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in revision += 1 }
    }

    private func add(to folder: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText]
        panel.message = String(localized: "Choose Atmosphère cheat files (.txt, named by the game's build ID). They are copied into the game's Cheats folder.")
        panel.prompt = String(localized: "Add")
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            let fm = FileManager.default
            try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for url in panel.urls {
                let dest = URL(filePath: folder).appending(path: url.lastPathComponent)
                do {
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: url, to: dest)
                } catch {
                    model.log(String(localized: "\(url.lastPathComponent) was not added: \(error.localizedDescription)"), kind: .error)
                }
            }
            model.refreshExtras(game)
        }
    }
}
