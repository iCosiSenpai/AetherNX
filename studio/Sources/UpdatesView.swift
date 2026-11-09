import AppKit
import SwiftUI

/// The three things that can be newer: the app, the tools it drives, and nxnative under them. Shown at launch when
/// something new turns up, from AetherNX → Check for Updates, and from the menu bar item.
struct UpdatesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.checkUpdatesAtLaunch) private var checkAtLaunch = true

    var body: some View {
        let updates = model.updates
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Updates").font(.title2.weight(.semibold))
                    Group {
                        if updates.isChecking {
                            Text("Checking…")
                        } else if let date = updates.lastChecked {
                            Text("Checked \(date.formatted(.relative(presentation: .named)))")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if updates.isChecking { ProgressView().controlSize(.small) }
            }
            VStack(spacing: 0) {
                AppUpdateRow()
                Divider()
                ToolsUpdateRow()
                Divider()
                UpstreamRow()
            }
            .padding(.horizontal, 14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Toggle("Check at launch", isOn: $checkAtLaunch)
                Spacer()
                Button("Check Again") { model.checkForUpdates(userInitiated: true) }
                    .disabled(updates.isChecking || updates.phase != .idle)
                Button("Done") {
                    model.dismissUpdateNotice()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 580)
    }
}

private struct UpdateRow<Actions: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let status: Text
    var detail: Text?
    var highlighted = false
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                status.foregroundStyle(highlighted ? .primary : .secondary)
                if let detail {
                    detail.font(.footnote).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.vertical, 12)
    }
}

private struct AppUpdateRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates
        if let release = updates.appRelease {
            UpdateRow(systemImage: "app.badge", title: "AetherNX Studio",
                      status: Text("Version \(release.version) is available (you have \(UpdateCenter.currentVersion))."),
                      detail: installDetail(updates), highlighted: true) {
                if updates.isRelease {
                    Button("Install and Relaunch") { updates.installApp() }
                        .buttonStyle(.borderedProminent)
                        .disabled(updates.phase != .idle || model.job?.isRunning == true)
                        .help(model.job?.isRunning == true ? Text("Wait for the build to finish") : Text("Downloads the release, checks its checksum and signature, and replaces this app"))
                } else {
                    Button("Download") { NSWorkspace.shared.open(release.page) }
                        .buttonStyle(.borderedProminent)
                        .help("This copy was built on this Mac, so it is not replaced: the release page opens")
                }
            }
        } else {
            UpdateRow(systemImage: "app", title: "AetherNX Studio",
                      status: updates.appError.map { Text($0) } ?? Text("Version \(UpdateCenter.currentVersion) is the newest."),
                      detail: nil) { EmptyView() }
        }
    }

    private func installDetail(_ updates: UpdateCenter) -> Text? {
        if case .installing(let step) = updates.phase { return Text(step) }
        if let error = updates.appError { return Text(error) }
        guard let notes = updates.appRelease?.notes.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }) else { return nil }
        return Text(verbatim: notes.trimmingCharacters(in: CharacterSet(charactersIn: "-* ")))
    }
}

private struct ToolsUpdateRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates
        if model.engine == nil {
            UpdateRow(systemImage: "shippingbox", title: "AetherNX tools", status: Text("Not set: choose or download them in Settings → General."), detail: nil) { EmptyView() }
        } else if let tools = updates.tools, tools.behind > 0 {
            UpdateRow(systemImage: "shippingbox.fill", title: "AetherNX tools",
                      status: Text(tools.newestVersion.map { String(localized: "\(tools.behind) new changes, version \($0)") } ?? String(localized: "\(tools.behind) new changes")),
                      detail: tools.canUpdate ? tools.newestSubject.map { Text(verbatim: $0) }
                          : Text("This folder has changes of its own (branch \(tools.branch)): update it from Terminal with git."),
                      highlighted: true) {
                Button("Update") { model.updateEngine() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!tools.canUpdate || !model.canStartJob)
            }
        } else {
            UpdateRow(systemImage: "shippingbox", title: "AetherNX tools",
                      status: updates.toolsError.map { Text($0) } ?? (updates.tools == nil ? Text("Not checked yet.") : Text("Up to date.")),
                      detail: updates.tools.flatMap { $0.ahead > 0 ? Text("\($0.ahead) changes of this folder are not in \($0.tracking).") : nil }) { EmptyView() }
        }
    }
}

private struct UpstreamRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates
        if let upstream = updates.upstream, upstream.aheadBy > 0 {
            UpdateRow(systemImage: "arrow.triangle.branch", title: "nxnative",
                      status: Text("\(upstream.aheadBy) changes since AetherNX's engine (synced \(upstream.syncedDate ?? upstream.synced))."),
                      detail: Text(upstream.newestSubject.map { String(localized: "They reach AetherNX when its tools are next synced and updated. Newest: \($0)") }
                          ?? String(localized: "They reach AetherNX when its tools are next synced and updated.")),
                      highlighted: true) {
                Button("Show Changes") { NSWorkspace.shared.open(upstream.page) }
            }
        } else {
            UpdateRow(systemImage: "arrow.triangle.branch", title: "nxnative",
                      status: updates.upstreamError.map { Text($0) } ?? (updates.upstream == nil ? Text("Not checked yet.") : Text("AetherNX's engine has all of nxnative's changes.")),
                      detail: nil) { EmptyView() }
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
