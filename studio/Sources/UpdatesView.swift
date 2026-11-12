import AppKit
import SwiftUI

/// The Updates page: what can be newer and what each update does. AetherNX is two things that update apart: the app (this window), from its
/// GitHub releases, and the engine, the AetherNX folder that builds the games, from its Git remote, so an engine change does not wait for a
/// new version of the app. nxnative, the project the engine comes from, is shown for what it has that AetherNX has not taken yet. The launch
/// notice opens this page when something new turns up.
struct UpdatesPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.checkUpdatesAtLaunch) private var checkAtLaunch = true

    var body: some View {
        let updates = model.updates
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Updates")
                            .font(.largeTitle.weight(.bold))
                        Text("AetherNX has two parts that update on their own: the app you are using, and the engine that builds your games. The engine updates in a few seconds, without a new version of the app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    if updates.isChecking { ProgressView().controlSize(.small) }
                    Button("Check Now") { model.checkForUpdates(userInitiated: true) }
                        .disabled(updates.isChecking || updates.phase != .idle)
                }
                AppUpdateCard()
                EngineUpdateCard()
                UpstreamCard()
                HStack {
                    Toggle("Check at launch", isOn: $checkAtLaunch)
                    Spacer()
                    if let date = updates.lastChecked {
                        Text("Checked \(date.formatted(.relative(presentation: .named)))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Updates")
    }
}

/// A card of the Updates page: an icon, a title, what stands now, and below what the update brings.
private struct UpdateCard<Body: View, Actions: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let status: Text
    var highlighted = false
    @ViewBuilder let content: Body
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    status
                        .font(.callout.weight(highlighted ? .semibold : .regular))
                        .foregroundStyle(highlighted ? .primary : .secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 12)
                actions
            }
            content
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(highlighted ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(.clear), lineWidth: 1))
    }
}

private struct AppUpdateCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates
        let release = updates.appRelease
        UpdateCard(systemImage: release == nil ? "app" : "app.badge", title: "AetherNX app",
                   subtitle: "The library, the settings and this window. Its versions come from GitHub releases, signed and notarized.",
                   status: release.map { Text("Version \($0.version) is out. You have \(UpdateCenter.currentVersion).") }
                       ?? updates.appError.map { Text($0) } ?? Text("Version \(UpdateCenter.currentVersion) is the newest."),
                   highlighted: release != nil) {
            if let release {
                VStack(alignment: .leading, spacing: 8) {
                    if case .installing(let step) = updates.phase {
                        Label(step, systemImage: "arrow.down.circle")
                            .font(.callout)
                    }
                    Text("What is new")
                        .font(.headline)
                    ScrollView {
                        Text(Self.notes(release.notes))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                    Text(updates.isRelease
                         ? "Install and Relaunch downloads the release, checks its checksum and its Apple signature, puts it in place of this app and opens it. Your library, settings and games stay as they are."
                         : "This copy was built on this Mac, so it does not replace itself: Download opens the release page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            if let release {
                if updates.isRelease {
                    Button("Install and Relaunch") { updates.installApp() }
                        .buttonStyle(.borderedProminent)
                        .disabled(updates.phase != .idle || model.job?.isRunning == true)
                        .help(model.job?.isRunning == true ? Text("Wait for the build to finish") : Text("Downloads the release, checks its checksum and signature, and replaces this app"))
                } else {
                    Button("Download") { NSWorkspace.shared.open(release.page) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    /// The release's notes as written (Markdown), with its headings as plain lines.
    static func notes(_ markdown: String) -> AttributedString {
        let cleaned = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            while l.hasPrefix("#") { l.removeFirst() }
            return l.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cleaned)
    }
}

private struct EngineUpdateCard: View {
    @Environment(AppModel.self) private var model
    @State private var showsAll = false

    var body: some View {
        let updates = model.updates
        if model.engine == nil {
            UpdateCard(systemImage: "shippingbox", title: "AetherNX engine",
                       subtitle: "The tools that build your games: the HorizonNative engine, the shader translator, the packers.",
                       status: Text("Not set: choose or download it in Settings → General.")) { EmptyView() } actions: {
                Button("Settings…") { model.showSettings(.general) }
            }
        } else if let tools = updates.tools, tools.behind > 0 {
            UpdateCard(systemImage: "shippingbox.fill", title: "AetherNX engine",
                       subtitle: "The tools that build your games: the HorizonNative engine, the shader translator, the packers.",
                       status: Text(tools.newestVersion.map { String(localized: "\(tools.behind) new changes (version \($0)). You have \(model.engineVersion ?? "?").") }
                                    ?? String(localized: "\(tools.behind) new changes.")),
                       highlighted: true) {
                VStack(alignment: .leading, spacing: 10) {
                    impact(tools)
                    let shown = showsAll ? tools.newCommits : Array(tools.newCommits.prefix(6))
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(shown) { commit in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(commit.date)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 78, alignment: .leading)
                                Text(commit.subject)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                        if tools.newCommits.count > 6 {
                            Button(showsAll ? "Show Fewer" : "Show All \(tools.newCommits.count)") { showsAll.toggle() }
                                .buttonStyle(.link)
                                .font(.callout)
                        }
                    }
                    if !tools.canUpdate {
                        Label("This folder has changes of its own (branch \(tools.branch)): update it from Terminal with git.", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            } actions: {
                Button("Update Engine") { model.updateEngine() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!tools.canUpdate || !model.canStartJob)
                    .help("Brings the AetherNX folder to the newest version (git pull). Games you built keep working as they are.")
            }
        } else {
            UpdateCard(systemImage: "shippingbox", title: "AetherNX engine",
                       subtitle: "The tools that build your games: the HorizonNative engine, the shader translator, the packers.",
                       status: updates.toolsError.map { Text($0) }
                           ?? (updates.tools == nil ? Text("Not checked yet.") : Text("Version \(model.engineVersion ?? "?") is the newest."))) {
                if let tools = updates.tools, tools.ahead > 0 {
                    Text("\(tools.ahead) changes of this folder are not in \(tools.tracking).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } actions: { EmptyView() }
        }
    }

    @ViewBuilder
    private func impact(_ tools: UpdateCenter.Tools) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if tools.touchesEngine {
                Label("Engine changes: rebuild a game to give it the fixes. Games you built keep working until then.", systemImage: "hammer")
            }
            if tools.touchesShaderChain {
                Label("The shader translator changed: the next build of each game translates its shaders again, which takes longer once.", systemImage: "sparkles")
            }
            if tools.touchesApp {
                Label("Some changes are for the app itself: they arrive with its next release.", systemImage: "app.badge")
            }
            if !tools.touchesEngine && !tools.touchesShaderChain && !tools.touchesApp {
                Label("Documentation and tools only: nothing to rebuild.", systemImage: "doc.text")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct UpstreamCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates
        let upstream = updates.upstream
        UpdateCard(systemImage: "arrow.triangle.branch", title: "nxnative",
                   subtitle: "The open-source project the AetherNX engine is built on (seedds/nxnative). Nothing to install here.",
                   status: upstream.map { u in
                       u.aheadBy > 0 ? Text("\(u.aheadBy) changes since AetherNX took it last (\(u.syncedDate ?? u.synced)).")
                                     : Text("AetherNX's engine has all of its changes.")
                   } ?? updates.upstreamError.map { Text($0) } ?? Text("Not checked yet.")) {
            if let upstream, upstream.aheadBy > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AetherNX reviews and takes these changes in a sync; they then reach you as an engine update above.")
                    if let subject = upstream.newestSubject {
                        Text("Newest: \(subject)")
                            .lineLimit(2)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } actions: {
            if let upstream, upstream.aheadBy > 0 {
                Button("Show Changes") { NSWorkspace.shared.open(upstream.page) }
            }
        }
    }
}

// MARK: - Menu bar

/// The menu bar item: update state at a glance, the running build, and the main actions.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let updates = model.updates
        Text("AetherNX \(UpdateCenter.currentVersion)")
        if let job = model.job, job.isRunning {
            Text(job.fraction.map { "\(job.title): \(Int($0 * 100)) %" } ?? job.title)
        }
        Divider()
        if let release = updates.appRelease {
            Button("Install AetherNX \(release.version)…") { show(); }
        } else {
            Text("AetherNX Studio is up to date")
        }
        if let tools = updates.tools, tools.behind > 0 {
            Button(tools.canUpdate ? "Update the Tools (\(tools.behind) changes)" : "Tools: \(tools.behind) new changes…") {
                if tools.canUpdate { model.updateEngine() } else { show() }
            }
            .disabled(!model.canStartJob)
        } else if updates.tools != nil {
            Text("The tools are up to date")
        }
        if let upstream = updates.upstream, upstream.aheadBy > 0 {
            Button("nxnative: \(upstream.aheadBy) New Changes…") { NSWorkspace.shared.open(upstream.page) }
        } else if updates.upstream != nil {
            Text("nxnative: nothing new")
        }
        Button(updates.isChecking ? "Checking…" : "Check for Updates") { model.checkForUpdates(userInitiated: true) }
            .disabled(updates.phase != .idle)
        Divider()
        Button("Open AetherNX") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Console Mode") {
            openWindow(id: "console")
            NSApp.activate()
        }
        Divider()
        Button("Quit AetherNX") { NSApp.terminate(nil) }
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate()
        model.showsUpdates = true
    }
}

/// The menu bar item's picture: a down arrow while something can be installed.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.updates.hasUpdates {
            Image(systemName: "arrow.down.circle.fill")
        } else if model.job?.isRunning == true {
            Image(systemName: "hammer.fill")
        } else {
            Image(systemName: "gamecontroller")
        }
    }
}
