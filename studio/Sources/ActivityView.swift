import AppKit
import SwiftUI

/// The output of the commands the app ran, newest at the bottom.
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Activity")
                    .font(.headline)
                if let job = model.job, job.isRunning {
                    Text(job.stageLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.activity.map(\.text).joined(separator: "\n"), forType: .string)
                }
                .disabled(model.activity.isEmpty)
                Button("Clear") { model.clearActivity() }
                    .disabled(model.activity.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.activity) { line in
                            Text(line.text)
                                .foregroundStyle(color(for: line.kind))
                                .fontWeight(line.kind == .command ? .medium : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .overlay {
                    if model.activity.isEmpty {
                        Text("Builds and other commands show their output here.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onChange(of: model.activity.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .background(.background)
    }

    private func color(for kind: LogLine.Kind) -> some ShapeStyle {
        switch kind {
        case .output: AnyShapeStyle(.secondary)
        case .error: AnyShapeStyle(.red)
        case .info: AnyShapeStyle(.primary)
        case .command: AnyShapeStyle(.primary)
        }
    }
}

/// `./aethernx doctor`, readable: what is there, what is missing and how to get it.
struct SetupCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup Check")
                        .font(.title2.weight(.semibold))
                    if let report = model.setupReport {
                        Text(report.ok ? "Everything a build needs is in place." : "Some things a build needs are missing.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.isCheckingSetup { ProgressView().controlSize(.small) }
            }
            .padding(20)
            Divider()
            if let report = model.setupReport {
                List {
                    ForEach(groups(report), id: \.self) { group in
                        Section(group) {
                            ForEach(report.checks.filter { $0.group == group }) { check in
                                CheckRow(check: check)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            } else if model.engine == nil {
                ContentUnavailableView("AetherNX folder not set", systemImage: "shippingbox", description: Text("Choose it in Settings → General."))
            } else if let error = model.setupError, !model.isCheckingSetup {
                ContentUnavailableView {
                    Label("No setup report", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: error).textSelection(.enabled)
                }
            } else {
                ProgressView("Checking…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                if let report = model.setupReport, report.checks.contains(where: { $0.group == "Python" && !$0.ok }) {
                    Button("Install Python Packages") { model.installPythonPackages() }
                        .disabled(!model.canStartJob)
                        .help("Runs ./aethernx setup: a Python environment in the AetherNX folder with the packages the build needs")
                }
                Spacer()
                Button("Check Again") { model.runSetupCheck() }
                    .disabled(model.isCheckingSetup || model.engine == nil)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 560)
        .onAppear { model.runSetupCheck() }
    }

    private func groups(_ report: SetupReport) -> [String] {
        var seen: [String] = []
        for check in report.checks where !seen.contains(check.group) { seen.append(check.group) }
        return seen
    }
}

struct CheckRow: View {
    let check: SetupReport.Check

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: check.ok ? "checkmark.circle.fill" : check.required ? "xmark.circle.fill" : "minus.circle")
                .foregroundStyle(check.ok ? AnyShapeStyle(.green) : check.required ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .accessibilityLabel(check.ok ? "Found" : check.required ? "Missing" : "Optional, not found")
            VStack(alignment: .leading, spacing: 3) {
                Text(check.name)
                if !check.ok && !check.fix.isEmpty {
                    HStack(spacing: 6) {
                        Text(check.fix)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(check.fix, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                } else if check.ok && !check.detail.isEmpty {
                    Text(check.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
