import SwiftUI
import UIKit

/// The Mac's page: the Macs whose AetherNX is on this network, pairing with one, and the build or install it runs.
struct MacView: View {
    @Environment(MacLink.self) private var link
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var pairingWith: FoundMac?

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if let job = link.job {
                    Section {
                        JobProgressView(job: job)
                            .padding(.vertical, 2)
                    } header: {
                        Text(job.isRunning ? "Running on the Mac" : "Last on the Mac")
                    }
                }
                foundSection
                if !away.isEmpty { awaySection }
            }
            .navigationTitle("Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $pairingWith) { mac in PairView(mac: mac) }
        }
        .onAppear { link.pageOpened() }
        .onDisappear { link.pageClosed() }
    }

    /// The Macs this device paired with that are not on this network now.
    private var away: [MacPairing] {
        link.pairings.filter { pairing in !link.macs.contains { $0.id == pairing.mac } }
    }

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: link.isConnected ? "macbook.and.iphone" : "macbook")
                    .font(.title3)
                    .foregroundStyle(link.isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(LinkText.status(link))
                        .font(.body.weight(.medium))
                    if MacLink.isScripted {
                        Text("A scripted Mac, for the demo: nothing here is on the network.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            if let problem = link.problem {
                Label(LinkText.problem(problem), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                if problem == .localNetworkDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else if !link.isConnected {
                    Button("Try Again") { link.reconnect() }
                }
            }
        }
    }

    private var foundSection: some View {
        Section {
            if link.macs.isEmpty {
                Text(MacLink.isScripted ? "The demo looks for no Mac." : "No Mac found yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(link.macs) { mac in
                let known = link.known(mac) != nil
                HStack(spacing: 12) {
                    Image(systemName: "macbook")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: mac.name)
                            .font(.body.weight(.medium))
                        Text(state(of: mac, known: known))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !known {
                        Button("Pair") { pairingWith = mac }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions {
                    if known {
                        Button("Forget", role: .destructive) { link.forget(mac.id) }
                    }
                }
            }
        } header: {
            Text("On this network")
        } footer: {
            Text("On the Mac, open AetherNX → Devices and turn on AetherNX Companion. The Mac and this device must be on the same network. Swipe a paired Mac to forget it.")
        }
    }

    private func state(of mac: FoundMac, known: Bool) -> String {
        if link.connectedMac == mac.id { return String(localized: "Connected") }
        if known { return String(localized: "Paired") }
        return mac.isPairing ? String(localized: "It shows a pairing code") : String(localized: "Not paired")
    }

    private var awaySection: some View {
        Section {
            ForEach(away) { pairing in
                HStack(spacing: 12) {
                    Image(systemName: "macbook")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: pairing.name)
                            .font(.body.weight(.medium))
                        Text("Paired \(pairing.paired.formatted(date: .abbreviated, time: .omitted))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions {
                    Button("Forget", role: .destructive) { link.forget(pairing.mac) }
                }
            }
        } header: {
            Text("Paired, not on this network now")
        }
    }
}

/// Pairing with a Mac: the six digits it shows, typed here.
private struct PairView: View {
    let mac: FoundMac
    @Environment(MacLink.self) private var link
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code", text: $code, prompt: Text(verbatim: "123 456"))
                        .keyboardType(.numberPad)
                        .font(.system(.title, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .focused($typing)
                } header: {
                    Text("The code on the Mac")
                } footer: {
                    Text("On \(mac.name), open AetherNX → Devices and choose Pair an iPhone or iPad. Type the six digits it shows: they are good for two minutes.")
                }
                if case .failed(let problem) = link.pairing {
                    Section {
                        Label(LinkText.problem(problem), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Pair with \(mac.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if link.pairing == .working {
                        ProgressView()
                    } else {
                        // the Mac as the network shows it now: whether it shows a code decides what a refusal means
                        Button("Pair") { link.pair(with: link.macs.first(where: { $0.id == mac.id }) ?? mac, typed: code) }
                            .disabled(LinkKeys.code(typed: code) == nil)
                    }
                }
            }
            .onAppear {
                link.clearPairing()
                typing = true
            }
            .onChange(of: link.pairing) { _, state in
                if case .done = state {
                    JobNotice.askPermission()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A job of the Mac as the phone follows it: the game, the step it is at and how far, or how it ended.
struct JobProgressView: View {
    let job: BuildProgress

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: job.game ?? job.title)
                    .font(.body.weight(.medium))
                if job.game != nil, !job.title.isEmpty {
                    Text(verbatim: job.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if job.isRunning {
                    ProgressView(value: job.fraction ?? 0)
                        .padding(.vertical, 3)
                    Text(LinkText.progress(job))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let eta = job.eta, eta >= 45 {
                        Text("About \(Int((eta / 60).rounded(.up))) min left in this step")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(LinkText.result(job))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch job.state {
        case .running: job.isInstall ? "arrow.down.app" : "hammer"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle"
        }
    }

    private var tint: AnyShapeStyle {
        switch job.state {
        case .running: AnyShapeStyle(.tint)
        case .succeeded: AnyShapeStyle(.green)
        case .failed: AnyShapeStyle(.red)
        case .cancelled: AnyShapeStyle(.secondary)
        }
    }
}

/// The Mac's job above the library's games: tap it for the Mac's page. One that ended stays until it is put away.
struct JobBanner: View {
    let job: BuildProgress
    let open: () -> Void
    @Environment(MacLink.self) private var link

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            JobProgressView(job: job)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(perform: open)
                .accessibilityAddTraits(.isButton)
            if !job.isRunning {
                Button {
                    link.dismissJob()
                } label: {
                    Label("Put Away", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// On a game's page: asks the connected Mac to install the game on this device, and says what the Mac did with it.
struct InstallFromMac: View {
    let titleId: String
    @Environment(MacLink.self) private var link

    var body: some View {
        let answer = link.answers[titleId.uppercased()]
        let job = link.job.flatMap { $0.titleId == titleId.uppercased() && $0.isRunning ? $0 : nil }
        VStack(alignment: .leading, spacing: 6) {
            Button {
                JobNotice.askPermission()
                link.requestInstall(titleId: titleId)
            } label: {
                Label("Install from the Mac", systemImage: "macbook.and.iphone")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!link.isConnected || job != nil || answer?.state == "sent" || answer?.state == "asked")
            Text(caption(answer: answer, job: job))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(answer: MacLink.Answer?, job: BuildProgress?) -> String {
        if let job { return LinkText.progress(job) }
        guard link.isConnected else { return String(localized: "Your Mac is not connected: open AetherNX on it, on the same network as this device.") }
        if let answer { return LinkText.answer(answer) }
        return String(localized: "The Mac builds the game if it has to and installs it on this device. It asks for your OK there the first time.")
    }
}
