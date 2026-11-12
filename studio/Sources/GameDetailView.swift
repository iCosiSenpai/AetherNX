import SwiftUI

struct GameDetailView: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            GamePageContent(game: game)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 1480, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .measuringLayoutWidth()
    }
}

/// The page in one column when the window is narrow, in two side by side when it is wide: what the game is and what was built on the left,
/// what it keeps (saves, mods, cheats) on the right.
private struct GamePageContent: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @Environment(\.layoutWidth) private var layoutWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GameBanner(game: game)
            GameHeader(game: game)
            GameFacts(game: game)
            if let job = model.jobFor(game) {
                JobCard(job: job)
            } else if let outcome = model.outcomes[game.id], !outcome.succeeded {
                OutcomeBanner(outcome: outcome, gameID: game.id)
            }
            if game.kind == .archives {
                ArchivesSection(game: game)
            } else if layoutWidth == .wide {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        FilesSection(game: game)
                        BuildsSection(game: game)
                        DeveloperSection(game: game)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 20) {
                        SavesSection(game: game)
                        ModsSection(game: game)
                        CheatsSection(game: game)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                FilesSection(game: game)
                BuildsSection(game: game)
                SavesSection(game: game)
                ModsSection(game: game)
                CheatsSection(game: game)
                DeveloperSection(game: game)
            }
            if !game.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(game.notes, id: \.self) { Text($0) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            DangerZoneSection(game: game)
        }
    }
}

/// A strip of small tiles with what there is to know at a glance: play time, the last session, the version, the size, the builds.
private struct GameFacts: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let facts = items
        if !facts.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(facts, id: \.label) { fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(fact.label, systemImage: fact.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fact.value)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .help(fact.value)
                }
            }
        }
    }

    private struct Fact { let label: String; let value: String; let systemImage: String }

    private var items: [Fact] {
        var out: [Fact] = []
        if let record = model.playLog.record(for: game), record.seconds > 0 {
            out.append(Fact(label: String(localized: "Play time"), value: Duration.seconds(record.seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)),
                            systemImage: "clock"))
            if let last = record.lastPlayed {
                out.append(Fact(label: String(localized: "Last played"), value: last.formatted(.relative(presentation: .named)), systemImage: "calendar"))
            }
        }
        if let version = game.displayVersion {
            out.append(Fact(label: String(localized: "Version"), value: version, systemImage: "number"))
        }
        let size = (game.base?.size ?? 0) + (game.latestUpdate?.size ?? 0) + game.dlc.reduce(0) { $0 + $1.size }
        if size > 0 { out.append(Fact(label: String(localized: "Game files"), value: size.fileSize, systemImage: "shippingbox")) }
        var built: [String] = []
        if game.macApp != nil { built.append("Mac") }
        if game.ipa != nil { built.append("IPA") }
        if game.deviceInstall != nil { built.append(game.deviceInstall?.deviceName ?? "iPhone") }
        out.append(Fact(label: String(localized: "Built for"), value: built.isEmpty ? String(localized: "Nothing yet") : built.joined(separator: " · "),
                        systemImage: "hammer"))
        if let success = model.lastSuccess[game.id] {
            out.append(Fact(label: String(localized: "Last job"), value: "\(success.title), \(success.date.formatted(date: .omitted, time: .shortened))",
                            systemImage: "checkmark.circle"))
        }
        return out
    }
}

// MARK: - Header

/// The game's wide banner from the internet, when a service has one.
private struct GameBanner: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.downloadArtwork) private var downloadArtwork = true   // redraws when the setting changes

    var body: some View {
        if let path = model.artwork.banner(for: game), let image = IconCache.image(at: path) {
            Color.clear
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                .accessibilityHidden(true)
        }
    }
}

private struct GameHeader: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                identity
                Spacer(minLength: 12)
                actions
            }
            VStack(alignment: .leading, spacing: 14) {
                identity
                actions
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 16) {
            GameIcon(game: game, size: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.title.weight(.bold))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
                if game.isBuildable {
                    HStack(spacing: 8) {
                        if game.isSwitch2 { Switch2Badge() }
                        ProfileLabel(hasProfile: game.profile)
                    }
                }
                if let record = model.playLog.record(for: game), !record.summary.isEmpty {
                    Label(record.summary, systemImage: model.playLog.isRunning(game) ? "play.circle.fill" : "clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let info = model.artwork.info(for: game) {
            if let publisher = info.publisher { parts.append(publisher) }
            if let year = info.releaseDate?.prefix(4), year.count == 4 { parts.append(String(year)) }
        }
        if let version = game.displayVersion { parts.append(String(localized: "Version \(version)")) }
        if let titleId = game.titleId { parts.append(titleId) }
        if parts.isEmpty { parts.append(game.kind == .archives ? String(localized: "Archive") : game.folder) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if game.kind == .archives {
                Button {
                    model.unpack(game)
                } label: {
                    Label("Unpack", systemImage: "archivebox")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canStartJob)
            } else {
                if game.macApp != nil {
                    Button {
                        model.play(game)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Open the Mac app (⌘R)")
                }
                BuildMenu(game: game, prominent: game.macApp == nil)
            }
            MoreMenu(game: game)
        }
    }
}

/// A small "Switch 2" tag for games of the newer console.
struct Switch2Badge: View {
    var body: some View {
        Text("Switch 2")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Color(red: 0.86, green: 0.12, blue: 0.2), in: Capsule())
            .help("A Nintendo Switch 2 game")
    }
}

private struct ProfileLabel: View {
    let hasProfile: Bool

    var body: some View {
        Group {
            if hasProfile {
                Label("Has a game profile", systemImage: "checkmark.seal")
                    .help("This game has a profile in the engine: settings, patches and shaders made for it.")
            } else {
                Label("No game profile: best-effort build", systemImage: "exclamationmark.triangle")
                    .help("Without a profile the build guesses the game's settings. The app may not start; the build writes a survey of the game.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct BuildMenu: View {
    let game: Game
    let prominent: Bool
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.defaultTarget) private var defaultTarget = BuildTarget.mac.rawValue

    private var target: BuildTarget { BuildTarget(rawValue: defaultTarget) ?? .mac }

    var body: some View {
        let menu = Menu {
            ForEach(BuildTarget.menuOrder) { option in
                Button {
                    model.build(game, target: option)
                } label: {
                    Label(option.commandTitle, systemImage: option.systemImage)
                }
            }
        } label: {
            Label(game.macApp == nil || target != .mac ? "Build" : "Rebuild", systemImage: "hammer")
        } primaryAction: {
            model.build(game, target: target)
        }
        .menuStyle(.button)
        .fixedSize()
        .controlSize(.large)
        .disabled(!model.canStartJob)
        .help(Text(target.detail))

        if prominent {
            menu.buttonStyle(.borderedProminent)
        } else {
            menu.buttonStyle(.bordered)
        }
    }
}

private struct MoreMenu: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button("Show in Finder") { Finder.reveal(game.kind == .archives ? game.id : game.folder) }
            if let work = game.workDir, FileManager.default.fileExists(atPath: work) {
                Button("Show Build Folder") { Finder.reveal(work) }
            }
            if let saves = game.saveDir, FileManager.default.fileExists(atPath: saves) {
                Button("Show Saves") { Finder.reveal(saves) }
            }
            if let log = game.logFile, FileManager.default.fileExists(atPath: log) {
                Button("Open Game Log") { Finder.open(log) }
            }
            if game.isBuildable, game.isExtracted {
                Button("Make Bug Report…") { model.makeBugReport(game) }
                    .disabled(!model.canStartJob)
            }
            if let work = game.workDir, FileManager.default.fileExists(atPath: work) {
                Divider()
                let shaders = (work as NSString).appendingPathComponent("shader")
                if FileManager.default.fileExists(atPath: shaders) {
                    Button("Move Shader Cache to Trash…") {
                        model.confirmMoveToTrash(shaders, title: String(localized: "Move the shader cache to the Trash?"),
                                                 message: String(localized: "The next build translates every shader again, which can take a long time."))
                    }
                }
                Button("Move Build Folder to Trash…") {
                    model.confirmMoveToTrash(work, title: String(localized: "Move the build folder of \(game.name) to the Trash?"),
                                             message: String(localized: "It holds the extracted game and the shader cache. The next build starts from scratch. Your game files and built apps stay."))
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("More actions")
        .disabled(model.job?.isRunning == true && model.job?.gameID == game.id)
    }
}

// MARK: - Progress

private struct OutcomeBanner: View {
    let outcome: JobOutcome
    let gameID: Game.ID
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(outcome.title) stopped")
                    .font(.headline)
                Text(outcome.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
            Spacer(minLength: 8)
            Button("Show Activity") { model.sidebarSelection = .page(.activity) }
            Button("Close") { model.dismissOutcome(gameID) }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Sections

private struct FilesSection: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var showsDLC = false

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                if let base = game.base {
                    FileRow(title: "Base game", value: game.kind == .dump ? String(localized: "Dump folder") : base.name, size: base.size)
                } else {
                    FileRow(title: "Base game", value: String(localized: "Missing"), size: nil, warning: true)
                }
                Divider()
                if let update = game.latestUpdate {
                    FileRow(title: "Game update", value: game.updates.count > 1 ? String(localized: "v\(update.version), newest of \(game.updates.count)") : "v\(update.version)", size: update.size)
                } else {
                    FileRow(title: "Game update", value: String(localized: "None. The newest update gives the best results."), size: nil)
                }
                Divider()
                if game.dlc.isEmpty {
                    FileRow(title: "DLC", value: String(localized: "None"), size: nil)
                } else {
                    DisclosureGroup(isExpanded: $showsDLC) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(game.dlc) { dlc in
                                HStack {
                                    Text(dlc.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(dlc.size.fileSize)
                                        .monospacedDigit()
                                }
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        FileRow(title: "DLC", value: String(localized: "\(game.dlc.count) add-ons"), size: game.dlc.reduce(0) { $0 + $1.size }, titleWidth: 85)
                    }
                    .padding(.vertical, 2)
                }
                if !game.compressed.isEmpty {
                    Divider()
                    Text("\(game.compressed.count) compressed package(s) (.nsz / .xcz): the first build converts them once.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 4)
        } label: {
            HStack {
                Text("Game Files")
                Spacer()
                Button("Add Update or DLC…") {
                    model.selectedGameID = game.id
                    model.importPackagesIntoSelectedGame()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }
}

private struct FileRow: View {
    let title: LocalizedStringKey
    let value: String
    let size: Int64?
    var warning = false
    var titleWidth: CGFloat = 96

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .frame(width: titleWidth, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(value)
            if let size {
                Text(size.fileSize)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct BuildsSection: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        GroupBox("Builds") {
            VStack(spacing: 0) {
                OutputRow(target: .mac, path: game.macApp) {
                    RowButton("Play", systemImage: "play.fill") { model.play(game) }
                }
                Divider()
                OutputRow(target: .ios, path: game.ipa) {
                    EmptyView()
                }
                Divider()
                DeviceRow(game: game)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// The game on an iPhone or iPad: where this Mac last installed it, and the button that builds, signs and installs it there.
private struct DeviceRow: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: BuildTarget.device.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("On iPhone or iPad")
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            RowButton("Devices", systemImage: "iphone.gen3") { model.sidebarSelection = .page(.devices) }
            RowButton(game.deviceInstall == nil ? "Install" : "Install Again", systemImage: "arrow.down.app") { model.build(game, target: .device) }
                .disabled(!model.canStartJob)
                .help("Builds the game, signs it with your Apple team and installs it on the device chosen in Devices.")
        }
        .padding(.vertical, 8)
    }

    private var detail: String {
        guard let last = game.deviceInstall, let name = last.deviceName else {
            return String(localized: "Not installed from this Mac")
        }
        guard let date = last.date else { return String(localized: "Installed on \(name)") }
        return String(localized: "Installed on \(name), \(date.formatted(date: .abbreviated, time: .shortened))")
    }
}

private struct OutputRow<Extra: View>: View {
    let target: BuildTarget
    let path: String?
    @ViewBuilder let extra: Extra

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                if let path {
                    Text((path as NSString).lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Not built")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let path {
                extra
                RowButton("Show in Finder", systemImage: "folder") { Finder.reveal(path) }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct DeveloperSection: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @AppStorage("showsDeveloperTools") private var expanded = false

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("For reverse engineering and decompilation work on your own copy. The results stay in the game's build folder; keep them private.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    Divider()
                    toolRow(title: "Function tables", status: game.decompDir != nil ? String(localized: "Made") : String(localized: "Not made yet"),
                            detail: "Functions and symbols of every module, with a C++ project that has the SDK headers.",
                            action: "Make", folder: game.decompDir) { model.generateFunctionTables(game) }
                    Divider()
                    toolRow(title: "C translation (nxrt)", status: game.liftedFiles > 0 ? String(localized: "\(game.liftedFiles) C files") : String(localized: "Not made yet"),
                            detail: "The main module translated to C by nxrt's static recompiler. Needs the unicorn package.",
                            action: "Translate", folder: game.liftedFiles > 0 ? game.decompDir.map { ($0 as NSString).appendingPathComponent("lifted") } : nil) { model.lift(game) }
                }
                .padding(.top, 4)
            } label: {
                Text("Developer Tools")
                    .font(.headline)
            }
            .padding(4)
        }
    }

    private func toolRow(title: LocalizedStringKey, status: String, detail: LocalizedStringKey, action: LocalizedStringKey, folder: String?, run: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    Text(status).foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let folder {
                Button("Show") { Finder.reveal(folder) }
            }
            Button(action, action: run)
                .disabled(!model.canStartJob || !game.isExtracted)
                .help(game.isExtracted ? Text("") : Text("Build the game once first: these tools read its extracted files."))
        }
        .padding(.vertical, 8)
    }
}

private struct ArchivesSection: View {
    let game: Game

    var body: some View {
        GroupBox("Archives") {
            VStack(alignment: .leading, spacing: 0) {
                Text("The game's packages are still in an archive. Unpack extracts them into a folder next to it; then build as usual.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                ForEach(game.archives) { archive in
                    Divider()
                    FileRow(title: "Archive", value: archive.name, size: archive.size)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
