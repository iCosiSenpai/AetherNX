import AppKit
import SwiftUI

/// Everything one game puts on the Mac, grouped by what removing it costs. Built off the main thread: folder sizes walk the trees.
struct RemovalPlan: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case gameFiles, buildFolder, apps, saves, iCloudSaves, logsAndSettings
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .gameFiles: "Game files"
            case .buildFolder: "Build folder"
            case .apps: "Built apps"
            case .saves: "Saves and pipeline cache"
            case .iCloudSaves: "iCloud saves"
            case .logsAndSettings: "Log, caches and launcher settings"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .gameFiles: "The base game, updates and DLC, or the archive or dump they came in."
            case .buildFolder: "Extracted game files and the shader cache. The next build starts from scratch."
            case .apps: "The Mac app and the IPAs built from the game."
            case .saves: "Your progress on this Mac, and the shader pipelines the game made while you played."
            case .iCloudSaves: "The saves the game shares through iCloud: removed from every device."
            case .logsAndSettings: "The game's log, its caches and the choices made in its launcher."
            }
        }

        var systemImage: String {
            switch self {
            case .gameFiles: "shippingbox"
            case .buildFolder: "hammer"
            case .apps: "app.badge"
            case .saves: "externaldrive"
            case .iCloudSaves: "icloud"
            case .logsAndSettings: "doc.text"
            }
        }

        /// Ticked when the whole game goes; iCloud saves reach other devices, so they are left unless chosen.
        var inEverything: Bool { self != .iCloudSaves }
    }

    struct Item: Identifiable, Equatable {
        var kind: Kind
        var paths: [String]
        var size: Int64
        /// Preference domains (the game app's bundle IDs) to forget with the logs and settings.
        var domains: [String] = []
        var id: Kind { kind }
    }

    var items: [Item]
    var gameFolder: String

    func item(_ kind: Kind) -> Item? { items.first { $0.kind == kind } }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }

    nonisolated static func make(for game: Game) -> RemovalPlan {
        let fm = FileManager.default
        let folder = URL(filePath: game.folder)
        func existing(_ paths: [String]) -> [String] {
            var seen = Set<String>()
            return paths.filter { fm.fileExists(atPath: $0) && seen.insert(URL(filePath: $0).standardizedFileURL.path).inserted }
        }
        func item(_ kind: Kind, _ paths: [String], domains: [String] = []) -> Item? {
            let found = existing(paths)
            guard !found.isEmpty || !domains.isEmpty else { return nil }
            return Item(kind: kind, paths: found, size: found.reduce(0) { $0 + Storage.size(of: $1) }, domains: domains)
        }

        // Game files: the packages, or a dump's version folders, or the archive with all its parts
        var files: [String] = game.archives.flatMap { archiveParts($0.path) }
        switch game.kind {
        case .packages:
            if let base = game.base { files.append(base.path) }
            files += game.updates.map(\.path)
            files += game.dlc.map(\.path)
            files += game.compressed
        case .dump:
            files += ["base", "updates", "dlc", "exefs", "romfs"].map { folder.appending(path: $0).path }
        case .archives:
            if game.archives.isEmpty, game.id != game.folder { files += archiveParts(game.id) }
        }

        // The build folder, and the survey a build without a profile writes beside it
        var builds: [String] = [game.workDir].compactMap { $0 }
        if let id = game.titleId {
            builds += [folder.appending(path: "\(id)_survey").path, folder.appending(path: "\(id)-work").path]
        }

        var apps: [String] = []
        for app in game.macApps { apps += [app, app + ".key"] }
        for ipa in game.ipas { apps += [ipa, ipa + ".idx"] }

        var domains: [String] = []
        for app in game.macApps {
            if let id = Bundle(path: app)?.bundleIdentifier { domains.append(id) }
        }
        if let id = game.titleId { domains.append("io.github.icosisenpai.horizonnative.\(id.lowercased())") }
        domains = Array(NSOrderedSet(array: domains)) as? [String] ?? domains
        let home = fm.homeDirectoryForCurrentUser
        var logs: [String] = [game.logFile].compactMap { $0 }
        for domain in domains {
            logs.append(home.appending(path: "Library/Preferences/\(domain).plist").path)
            logs.append(home.appending(path: "Library/Saved Application State/\(domain).savedState").path)
            logs.append(home.appending(path: "Library/Caches/\(domain)").path)
            if let cache = Storage.userCacheDirectory { logs.append(cache.appending(path: domain).path) }
        }
        let knownDomains = domains.filter { fm.fileExists(atPath: home.appending(path: "Library/Preferences/\($0).plist").path) }

        var cloud: [String] = []
        if let id = game.titleId {
            cloud.append(home.appending(path: "Library/Mobile Documents/iCloud~io~github~icosisenpai~horizonnative/Documents/\(id)").path)
        }

        let items = [
            item(.gameFiles, files),
            game.kind == .archives ? nil : item(.buildFolder, builds),
            item(.apps, apps),
            item(.saves, [game.saveDir].compactMap { $0 }),
            item(.iCloudSaves, cloud),
            item(.logsAndSettings, logs, domains: knownDomains),
        ].compactMap { $0 }
        return RemovalPlan(items: items, gameFolder: game.folder)
    }

    /// An archive and the rest of its volumes: Game.part1.rar → Game.part2.rar…, Game.rar → Game.r00…, Game.7z.001 → Game.7z.002…
    nonisolated static func archiveParts(_ path: String) -> [String] {
        let url = URL(filePath: path)
        let name = url.lastPathComponent
        let folder = url.deletingLastPathComponent()
        let patterns: [String]
        if let range = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) {
            patterns = ["^" + NSRegularExpression.escapedPattern(for: String(name[..<range.lowerBound])) + #"\.part\d+\.rar$"#]
        } else if let range = name.range(of: #"\.\d{3}$"#, options: .regularExpression) {
            patterns = ["^" + NSRegularExpression.escapedPattern(for: String(name[..<range.lowerBound])) + #"\.\d{3}$"#]
        } else if let range = name.range(of: #"\.rar$"#, options: [.regularExpression, .caseInsensitive]) {
            patterns = ["^" + NSRegularExpression.escapedPattern(for: String(name[..<range.lowerBound])) + #"\.r(ar|\d{2})$"#]
        } else {
            return [path]
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let parts = names.filter { n in patterns.contains { n.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil } }
        return ([name] + parts.filter { $0 != name }).map { folder.appending(path: $0).path }
    }
}

// MARK: - The game page's section

struct DangerZoneSection: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let plan = model.removalPlans[game.id]
        let busy = model.jobFor(game)?.isRunning == true || model.removingGameID == game.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Label("Danger Zone", systemImage: "exclamationmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                if let plan {
                    Text("\(plan.total.fileSize) on this Mac")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.bottom, 10)
            ForEach([RemovalPlan.Kind.buildFolder, .apps, .saves], id: \.self) { kind in
                if let item = plan?.item(kind), item.size > 0 || !item.paths.isEmpty {
                    row(title: kind.title, detail: kind.detail, size: item.size) {
                        Button("Remove…") { model.removalRequest = RemovalRequest(game: game, kinds: [kind]) }
                            .disabled(busy)
                    }
                    Divider()
                }
            }
            row(title: "Remove everything", detail: "The game's files, build folder, apps, saves, log and settings: AetherNX forgets the game.", size: plan?.items.filter(\.kind.inEverything).reduce(0) { $0 + $1.size }) {
                Button("Remove Everything…", role: .destructive) {
                    model.removalRequest = RemovalRequest(game: game, kinds: Set(RemovalPlan.Kind.allCases.filter(\.inEverything)))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(busy || plan == nil)
            }
        }
        .padding(16)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.55), lineWidth: 1))
        .task(id: game) { model.measure(game) }
    }

    private func row<Action: View>(title: LocalizedStringKey, detail: LocalizedStringKey, size: Int64?, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if let size, size > 0 {
                        Text(size.fileSize).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action()
        }
        .padding(.vertical, 8)
    }
}

/// What the confirmation sheet removes: one game, the kinds ticked first.
struct RemovalRequest: Identifiable {
    let id = UUID()
    let game: Game
    let kinds: Set<RemovalPlan.Kind>
}

// MARK: - Confirmation

struct RemovalSheet: View {
    let request: RemovalRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<RemovalPlan.Kind> = []
    @State private var confirmsPermanent = false

    private var plan: RemovalPlan? { model.removalPlans[request.game.id] }
    private var isEverything: Bool { request.kinds.count > 1 }
    private var shown: [RemovalPlan.Item] {
        guard let plan else { return [] }
        return isEverything ? plan.items : plan.items.filter { request.kinds.contains($0.kind) }
    }
    private var selectedSize: Int64 { shown.filter { chosen.contains($0.kind) }.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                GameIcon(game: request.game, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEverything ? "Remove everything of \(request.game.name)?" : "Remove from \(request.game.name)?")
                        .font(.title3.weight(.semibold))
                    Text("Move to Trash lets you put things back, and frees the space when you empty the Trash. Delete Permanently frees it now and cannot be undone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if plan == nil {
                ProgressView("Measuring…").frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { item in
                        Toggle(isOn: Binding(get: { chosen.contains(item.kind) }, set: { on in if on { chosen.insert(item.kind) } else { chosen.remove(item.kind) } })) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: item.kind.systemImage).frame(width: 18).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.kind.title)
                                    Text(item.kind.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Text(item.size.fileSize).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 7)
                        .help(item.paths.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
                        if item.id != shown.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack {
                Text("\(selectedSize.fileSize) selected")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") { run(permanently: false) }
                    .disabled(chosen.isEmpty || plan == nil)
                Button("Delete Permanently", role: .destructive) { confirmsPermanent = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(chosen.isEmpty || plan == nil)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            chosen = request.kinds
            model.measure(request.game)
        }
        .confirmationDialog("Delete \(selectedSize.fileSize) permanently?", isPresented: $confirmsPermanent) {
            Button("Delete Permanently", role: .destructive) { run(permanently: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func run(permanently: Bool) {
        guard let plan else { return }
        let items = plan.items.filter { chosen.contains($0.kind) }
        let removesGame = isEverything && chosen.contains(.gameFiles)
        model.remove(items, of: request.game, permanently: permanently, forgetsGame: removesGame)
        dismiss()
    }
}
