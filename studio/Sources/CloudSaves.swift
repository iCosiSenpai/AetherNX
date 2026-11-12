import AppKit
import Foundation
import SwiftUI

/// Cloud saves of the Mac apps, through the engine's own store (docs/frontends.md, The cloud saves folder): each app reads `cloudSaves.folder` from its
/// preferences at every start and syncs its save through `<folder>/<title ID>/save.dmsync`. Studio writes that key, for one game or as the library's
/// default, and reads what the last session's log says about the sync. The app's own settings window shows and changes the same key.
///
/// The library's default and a game's own choice follow NX2Apple's save setup (LNPANDY/NX2Apple #864): a game without a choice of its own takes the
/// library's folder, marked with `cloudSaves.fromLibrary` so a later change of the default reaches it; a choice made for one game, off included, stays.
enum CloudSaves {
    static let folderKey = "cloudSaves.folder"
    static let inheritedKey = "cloudSaves.fromLibrary"

    /// What a game's Mac app is set to.
    enum Setting: Equatable {
        /// No choice for this game, and the library has no default: off.
        case unset
        /// Turned off for this game.
        case off
        case folder(String, inherited: Bool)

        var folder: String? { if case .folder(let path, _) = self { path } else { nil } }
    }

    /// The folder iPhone and iPad apps signed with the project's iCloud container sync through by themselves; iCloud Drive shows it as HorizonNative.
    static func automaticFolder(home: String = NSHomeDirectory()) -> String {
        home + "/Library/Mobile Documents/iCloud~io~github~icosisenpai~horizonnative/Documents"
    }

    /// iCloud Drive › HorizonNative Saves, the folder `DM_SAVE_SYNC=icloud` names: one to choose in the iPhone app's Cloud saves too.
    static func driveFolder(home: String = NSHomeDirectory()) -> String {
        home + "/Library/Mobile Documents/com~apple~CloudDocs/HorizonNative Saves"
    }

    /// A folder as the Finder names it: iCloud Drive's by their names there, others from the home folder.
    static func displayName(_ folder: String, home: String = NSHomeDirectory()) -> String {
        let path = (folder as NSString).standardizingPath
        if path == automaticFolder(home: home) { return "iCloud Drive › HorizonNative" }
        let drive = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path == drive { return "iCloud Drive" }
        if path.hasPrefix(drive + "/") { return "iCloud Drive › " + path.dropFirst(drive.count + 1).replacingOccurrences(of: "/", with: " › ") }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~/" + path.dropFirst(home.count + 1) : path
    }

    /// The preferences domain of a game's Mac app: the bundle ID of the app built from it, else the one a build gives it.
    static func domain(for game: Game) -> String? {
        guard let id = game.titleId else { return nil }
        for app in game.macApps {
            if let info = NSDictionary(contentsOf: URL(filePath: app).appending(path: "Contents/Info.plist")),
               (info["DMTitleID"] as? String)?.uppercased() == id.uppercased(), let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty {
                return bundle
            }
        }
        return "io.github.icosisenpai.horizonnative.\(id.lowercased())"
    }

    static func setting(domain: String) -> Setting {
        let domain = domain as CFString
        CFPreferencesAppSynchronize(domain)
        guard let value = CFPreferencesCopyAppValue(folderKey as CFString, domain) as? String else { return .unset }
        if value.isEmpty { return .off }
        return .folder(value, inherited: (CFPreferencesCopyAppValue(inheritedKey as CFString, domain) as? Bool) == true)
    }

    /// A choice for this game alone: a folder, or nil for off. It no longer follows the library's default.
    static func choose(_ folder: String?, domain: String) {
        write(folder ?? "", inherited: false, domain: domain)
    }

    /// Back to the library's default: its folder, marked as taken from it, or no key at all when the library has none.
    static func followLibrary(_ libraryFolder: String, domain: String) {
        if libraryFolder.isEmpty { write(nil, inherited: false, domain: domain) } else { write(libraryFolder, inherited: true, domain: domain) }
    }

    /// The library's default reaches every game that has no choice of its own. Returns how many games changed.
    @discardableResult
    static func applyLibraryFolder(_ libraryFolder: String, domains: [String]) -> Int {
        var changed = 0
        for domain in Set(domains) {
            switch setting(domain: domain) {
            case .unset:
                if !libraryFolder.isEmpty { followLibrary(libraryFolder, domain: domain); changed += 1 }
            case .folder(let path, inherited: true):
                if path != libraryFolder { followLibrary(libraryFolder, domain: domain); changed += 1 }
            case .off, .folder(_, inherited: false):
                break
            }
        }
        return changed
    }

    private static func write(_ folder: String?, inherited: Bool, domain: String) {
        let domain = domain as CFString
        CFPreferencesSetAppValue(folderKey as CFString, folder.map { $0 as CFString }, domain)
        CFPreferencesSetAppValue(inheritedKey as CFString, inherited ? kCFBooleanTrue : nil, domain)
        CFPreferencesAppSynchronize(domain)
    }

    /// `DM_SAVE_SYNC` in the game's own env.txt, which wins over the saved folder (docs/frontends.md): shown, since Studio's choice then has no effect.
    static func envOverride(titleID: String, home: String = NSHomeDirectory()) -> String? {
        guard let text = try? String(contentsOfFile: "\(home)/Library/Application Support/HorizonNative/\(titleID)/env.txt", encoding: .utf8) else { return nil }
        return envValue("DM_SAVE_SYNC", in: text)
    }

    /// The last value an env file gives a variable: `KEY=VALUE` lines, `#` comments, an optional `export`.
    static func envValue(_ name: String, in text: String) -> String? {
        var found: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix(name + "=") else { continue }
            var value = String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" { value = String(value.dropFirst().dropLast()) }
            found = value
        }
        return found
    }

    /// A game's file in a cloud folder: `<folder>/<title ID>/save.dmsync`, or `<folder>/save.dmsync` when the folder is already the game's own.
    static func cloudFile(folder: String, titleID: String) -> String {
        let own = (folder as NSString).lastPathComponent.caseInsensitiveCompare(titleID) == .orderedSame
        return own ? folder + "/save.dmsync" : folder + "/\(titleID)/save.dmsync"
    }

    struct LogNote: Hashable {
        var text: String
        var isError: Bool
    }

    /// What the last session said about the sync: the last `save sync:` line of the game's log, without its prefix.
    static func lastNote(inLog text: String) -> LogNote? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let range = line.range(of: "save sync: ") else { continue }
            let note = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if note.isEmpty { continue }
            return LogNote(text: note, isError: line.contains("[RED]"))
        }
        return nil
    }

    /// A log line for a narrow row: the cloud folder by its name in the Finder, the home folder as ~.
    static func shortened(_ note: String, folder: String, home: String = NSHomeDirectory()) -> String {
        note.replacingOccurrences(of: folder, with: displayName(folder, home: home)).replacingOccurrences(of: home, with: "~")
    }

    /// The end of a log file, enough for its sync lines (the host writes them at the start and the end of a session).
    static func tail(ofFile path: String, bytes: Int = 400_000) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - A game's saves

struct SavesSection: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.cloudSavesFolder) private var libraryFolder = ""
    /// Raised whenever the files may have changed: the section reads the save folder, the cloud folder and the log anew. Nothing here watches them, so
    /// it reads again when the game quits, when AetherNX comes to the front, after a build, and every half minute while its page shows.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        GroupBox("Saves") {
            VStack(spacing: 0) {
                localRow
                Divider()
                if let domain = CloudSaves.domain(for: game), game.macApp != nil {
                    cloudRow(domain: domain)
                } else {
                    Text("Cloud saves are set for the Mac app: build it first. An iPhone or iPad app chooses its folder in its own Cloud saves.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: model.playLog.isRunning(game)) { revision += 1 }
        .onChange(of: model.job?.isRunning) { revision += 1 }
        .onChange(of: libraryFolder) { revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in revision += 1 }
        .task(id: game.id) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                revision += 1
            }
        }
    }

    private var localRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("On this Mac")
                Text(localDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let saves = saveFolder {
                Button("Show in Finder") { Finder.reveal(saves) }
            }
        }
        .padding(.vertical, 8)
    }

    private var saveFolder: String? {
        guard let dir = game.saveDir else { return nil }
        let save = dir + "/save"
        return FileManager.default.fileExists(atPath: save) ? save : nil
    }

    private var localDetail: String {
        guard let save = saveFolder else { return String(localized: "No save yet: the game writes one when it first saves.") }
        guard let date = Self.newestChange(in: save) else { return String(localized: "An empty save folder.") }
        return String(localized: "Last saved \(date.formatted(date: .abbreviated, time: .shortened))")
    }

    @ViewBuilder
    private func cloudRow(domain: String) -> some View {
        let setting = CloudSaves.setting(domain: domain)
        let override = game.titleId.flatMap { CloudSaves.envOverride(titleID: $0) }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: setting.folder == nil ? "icloud.slash" : "icloud")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud saves")
                Text(title(of: setting))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(setting.folder ?? "")
                if let override {
                    Label("This game's env.txt sets DM_SAVE_SYNC=\(override), which wins over this choice.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if let folder = setting.folder {
                    ForEach(notes(folder: folder), id: \.self) { note in
                        Text(note.text)
                            .font(.footnote)
                            .foregroundStyle(note.isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            Spacer()
            Menu("Change") {
                if FileManager.default.fileExists(atPath: (CloudSaves.automaticFolder() as NSString).deletingLastPathComponent) {
                    Button { choose(CloudSaves.automaticFolder(), domain: domain) } label: { Text(verbatim: "iCloud Drive › HorizonNative") }
                }
                Button { choose(CloudSaves.driveFolder(), domain: domain) } label: { Text(verbatim: "iCloud Drive › HorizonNative Saves") }
                Button("Choose a Folder…") { pickFolder(domain: domain, from: setting.folder) }
                Divider()
                Button("Turn Off for This Game") { choose(nil, domain: domain) }
                    .disabled(setting == .off)
                Button("Use the Library's Setting") {
                    CloudSaves.followLibrary(libraryFolder, domain: domain)
                    revision += 1
                }
                .disabled({ if case .folder(_, inherited: true) = setting { true } else { setting == .unset } }())
            }
            .fixedSize()
            .disabled(model.playLog.isRunning(game))
            .help(model.playLog.isRunning(game) ? Text("Quit the game first: it reads the folder when it starts.") : Text("The game reads this at its next start."))
        }
        .padding(.vertical, 8)
    }

    private func title(of setting: CloudSaves.Setting) -> String {
        switch setting {
        case .unset: String(localized: "Off")
        case .off: String(localized: "Off for this game")
        case .folder(let path, let inherited):
            inherited ? String(localized: "\(CloudSaves.displayName(path)) (the library's setting)") : CloudSaves.displayName(path)
        }
    }

    /// When the cloud's copy last changed, and what the last session's log said.
    private func notes(folder: String) -> [CloudSaves.LogNote] {
        var notes: [CloudSaves.LogNote] = []
        if let id = game.titleId {
            let file = CloudSaves.cloudFile(folder: folder, titleID: id)
            if let date = (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date {
                notes.append(.init(text: String(localized: "In the cloud since \(date.formatted(date: .abbreviated, time: .shortened))"), isError: false))
            } else {
                notes.append(.init(text: String(localized: "Nothing in the cloud folder yet: the game sends its save after it next saves."), isError: false))
            }
        }
        if let log = game.logFile, let text = CloudSaves.tail(ofFile: log), let note = CloudSaves.lastNote(inLog: text) {
            notes.append(.init(text: String(localized: "Last session: \(CloudSaves.shortened(note.text, folder: folder))"), isError: note.isError))
        }
        return notes
    }

    private func choose(_ folder: String?, domain: String) {
        if let folder { try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
        CloudSaves.choose(folder, domain: domain)
        revision += 1
    }

    private func pickFolder(domain: String, from current: String?) {
        guard let url = CloudSavesPanel.pick(startingAt: current) else { return }
        choose(url.path, domain: domain)
    }

    /// The newest change of any file in a save folder.
    static func newestChange(in folder: String) -> Date? {
        guard let walker = FileManager.default.enumerator(at: URL(filePath: folder), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return nil }
        var newest: Date?
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }
        return newest
    }
}

enum CloudSavesPanel {
    /// A folder for cloud saves, opened in iCloud Drive: the one the iPhone app chose, or a new one.
    @MainActor
    static func pick(startingAt current: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Choose the iCloud Drive folder the saves sync through: the same one the iPhone or iPad app uses in its Cloud saves.")
        panel.prompt = String(localized: "Use Folder")
        let drive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
        panel.directoryURL = URL(filePath: current ?? drive)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - The library's default (Settings)

struct CloudSavesSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.cloudSavesFolder) private var libraryFolder = ""

    var body: some View {
        Section {
            Picker("Cloud saves", selection: Binding(get: { libraryFolder }, set: { set($0) })) {
                Text("Off").tag("")
                Divider()
                if FileManager.default.fileExists(atPath: (CloudSaves.automaticFolder() as NSString).deletingLastPathComponent) || libraryFolder == CloudSaves.automaticFolder() {
                    Text(verbatim: "iCloud Drive › HorizonNative").tag(CloudSaves.automaticFolder())
                }
                Text(verbatim: "iCloud Drive › HorizonNative Saves").tag(CloudSaves.driveFolder())
                if !libraryFolder.isEmpty, libraryFolder != CloudSaves.automaticFolder(), libraryFolder != CloudSaves.driveFolder() {
                    Text(verbatim: CloudSaves.displayName(libraryFolder)).tag(libraryFolder)
                }
            }
            Button("Choose a Folder…") {
                if let url = CloudSavesPanel.pick(startingAt: libraryFolder.isEmpty ? nil : libraryFolder) { set(url.path) }
            }
        } header: {
            Text("Saves")
        } footer: {
            Text("The folder every game's Mac app syncs its save through, unless a game has its own choice on its page. HorizonNative is the folder the iPhone and iPad apps you install from this Mac use by themselves when they are signed with an iCloud container; for other apps, choose the same iCloud Drive folder in the app's Cloud saves.")
        }
    }

    private func set(_ folder: String) {
        if !folder.isEmpty { try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
        libraryFolder = folder
        model.applyCloudSavesFolder()
    }
}
