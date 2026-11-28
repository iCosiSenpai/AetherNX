import AppKit
import Observation
import SwiftUI
import SystemConfiguration

// The live link with AetherNX Companion, as the app has it (docs/companion.md, How it talks to the Mac): CompanionServer.swift listens and pairs;
// this file joins it to the app. The job Studio runs and the script's events go to the paired phones, an install a phone asks for is shown to the
// person at the Mac, and the Devices page has the link's card.

/// An install a paired phone asked for, waiting for the person at the Mac.
struct InstallRequest: Identifiable {
    let id = UUID()
    let phone: PairedPhone
    /// The request's own ID, which its answers carry back.
    let requestID: String?
    let game: Game
    let device: AppleDevice

    var title: String { String(localized: "Install \(game.name) on \(device.name)?") }
    var message: String { String(localized: "\(phone.name) asked for it through AetherNX Companion. It is the same install as the Install button's.") }
}

@MainActor
@Observable
final class CompanionHost {
    private(set) var state: CompanionServer.State = .off
    /// This Mac's name, as the phones list it.
    private(set) var name = ""
    private(set) var phones: [PairedPhone] = []
    /// The phones connected now, by ID.
    private(set) var connected: Set<String> = []
    private(set) var pairingCode: String?
    /// The phone the code on show just paired, for the pairing sheet to say so.
    private(set) var justPaired: PairedPhone?
    /// The install a phone asked for, while its alert shows.
    private(set) var request: InstallRequest?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var server: CompanionServer?
    /// A link of its own in place of the app's, for studio/tools/snapshots.swift to draw the card with: nil is the app's own link.
    @ObservationIgnored var stand: Stand?
    @ObservationIgnored private var resolved: Set<UUID> = []

    /// Where the Mac keeps its link key and its paired phones (LinkIdentity): the app's own folder in Application Support.
    nonisolated static var identityFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.icosisenpai.aethernx").appending(path: "companion-link.json")
    }

    /// A link that is not the app's: its own identity file and name, on the loopback interface only and with no Bonjour, so the app's link key and
    /// phones are neither read nor shown on the network.
    struct Stand {
        var identityFile: URL
        var name: String
    }

    /// The computer's name from System Settings › General › Sharing.
    nonisolated static var macName: String {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty { return name }
        return ProcessInfo.processInfo.hostName
    }

    func attach(_ model: AppModel) {
        self.model = model
        if UserDefaults.standard.bool(forKey: Pref.companionLink) { setOn(true) }
    }

    /// Starts or stops listening. Off, nothing of the link runs: no listener, no service on the network.
    func setOn(_ on: Bool) {
        guard on != (server != nil) else { return }
        guard on else {
            server?.stop()
            server = nil
            request = nil
            refresh()
            return
        }
        let file = stand?.identityFile ?? Self.identityFile
        let identity: LinkIdentity
        let loaded = LinkIdentity.load(file)
        if case .identity(let kept) = loaded {
            identity = kept
        } else {
            if case .later(let format) = loaded {
                // A newer AetherNX wrote it: it is kept beside the new one, for that AetherNX to find again
                let aside = file.deletingPathExtension().appendingPathExtension("format\(format).json")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: file, to: aside)
            } else if loaded == .damaged {
                // Unreadable: kept beside the new one for a look. The phones paired with it have to pair again
                let aside = file.deletingPathExtension().appendingPathExtension("damaged.json")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: file, to: aside)
                model?.log(String(localized: "AetherNX Companion: the link's file could not be read. It is kept as \(aside.lastPathComponent), and each device has to pair again."), kind: .error)
            }
            identity = LinkIdentity.new()
            identity.save(file)
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let shown = stand?.name ?? Self.macName
        let server = CompanionServer(identity: identity, name: shown, appVersion: version, advertises: stand == nil, loopbackOnly: stand != nil)
        server.onSave = { identity in identity.save(file) }
        server.onChange = { [weak self] in self?.refresh() }
        server.onPaired = { [weak self] phone in self?.paired(phone) }
        server.onRequest = { [weak self] phone, line in self?.received(line, from: phone) }
        self.server = server
        name = shown
        server.start()
        if let job = model?.job, job.isRunning { jobStarted(job) }   // turned on during a build: the phones hear of it from here on
        refresh()
    }

    private func refresh() {
        state = server?.state ?? .off
        phones = server?.identity.phones ?? []
        connected = server?.connectedPhones ?? []
        pairingCode = server?.pairingCode
    }

    // MARK: Pairing and the phones

    /// Shows a code (the pairing sheet opened, or asked for another).
    func beginPairing() {
        justPaired = nil
        server?.beginPairing()
        refresh()
    }

    func endPairing() {
        server?.endPairing()
        refresh()
    }

    private func paired(_ phone: PairedPhone) {
        justPaired = phone
        model?.log(String(localized: "AetherNX Companion: \(phone.name) is paired with this Mac."), kind: .info)
    }

    func remove(_ phone: PairedPhone) {
        if let asked = request, asked.phone.id == phone.id { decline(asked) }   // its alert goes too: a phone that is no longer paired installs nothing
        server?.remove(phone: phone.id)
    }

    func setInstallsWithoutAsking(_ on: Bool, for phone: PairedPhone) {
        server?.setInstallsWithoutAsking(on, phone: phone.id)
    }

    // MARK: Jobs

    /// A job started. The phones hear of builds and installs, not of the app's other commands (an unpack, a setup step).
    func jobStarted(_ job: Job) {
        guard let server, job.target != nil else { return }
        server.jobStarted(line(for: job))
    }

    /// One line of the job's standard output: the server sends on the events among them, as the script wrote them.
    func forward(_ text: String, of job: Job) {
        guard let server, job.target != nil else { return }
        server.forward(event: text)
    }

    func jobEnded(_ job: Job) {
        guard let server, job.target != nil else { return }
        server.jobEnded(line(for: job))
    }

    private func line(for job: Job) -> LinkLine {
        var line = LinkLine.mac("job")
        line.id = job.id.uuidString
        switch job.state {
        case .running: line.state = "running"
        case .succeeded: line.state = "succeeded"
        case .failed: line.state = "failed"
        case .cancelled: line.state = "cancelled"
        }
        line.kind = job.target == .device ? "install" : "build"
        line.target = job.target?.rawValue
        line.title = job.title
        if let id = job.gameID, let game = model?.games.first(where: { $0.id == id }) {
            line.titleId = game.titleId?.uppercased()
            line.game = game.name
        }
        if job.state == .failed { line.message = job.failureMessage }
        return line
    }

    // MARK: Requests

    /// The device a phone's request means, among those this Mac installs on: the reachable one with the phone's name; else the only reachable one
    /// of its kind; else the device chosen in Settings → iPhone & iPad, when it is of that kind (an iPad's request never goes to the chosen iPhone).
    /// iOS gives an app the device's own name only with an entitlement, and "iPhone" without it, so the name alone often decides nothing.
    nonisolated static func device(named name: String?, kind: String?, chosen: AppleDevice?, among devices: [AppleDevice]) -> AppleDevice? {
        let reachable = devices.filter(\.isReachable)
        if let name, !name.isEmpty {
            let named = reachable.filter { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if named.count == 1 { return named[0] }
        }
        if let kind, !kind.isEmpty {
            let ofKind = reachable.filter { $0.kind == kind }
            if ofKind.count == 1 { return ofKind[0] }
            if let chosen, chosen.kind != kind { return nil }
        }
        return chosen
    }

    private func answer(_ line: LinkLine, to phone: PairedPhone, _ state: String, why: String? = nil) {
        var reply = LinkLine.mac("answer")
        reply.to = line.`do`
        reply.id = line.id
        reply.state = state
        reply.why = why
        server?.send(reply, toPhone: phone.id)
    }

    private func received(_ line: LinkLine, from phone: PairedPhone) {
        guard let model, line.`do` == "install" else { return }
        guard let title = line.titleId?.uppercased(), let game = model.games.first(where: { $0.titleId?.uppercased() == title && $0.isBuildable }) else {
            answer(line, to: phone, "refused", why: "no-game")
            return
        }
        guard let engine = model.engine else {
            answer(line, to: phone, "refused", why: "no-engine")
            return
        }
        guard request == nil else {
            answer(line, to: phone, "refused", why: "busy")
            return
        }
        if model.devices.hasLoaded {
            consider(line, from: phone, game: game)
        } else {
            // The devices are read when first needed: a request that comes before the Devices page was ever opened
            model.devices.refresh(engine: engine) { [weak self] in self?.consider(line, from: phone, game: game) }
        }
    }

    private func consider(_ line: LinkLine, from phone: PairedPhone, game: Game) {
        guard let model, request == nil else {
            answer(line, to: phone, "refused", why: "busy")
            return
        }
        guard let device = Self.device(named: line.device, kind: line.deviceKind, chosen: model.devices.selectedDevice, among: model.devices.devices) else {
            answer(line, to: phone, "refused", why: "no-device")
            return
        }
        let asked = InstallRequest(phone: phone, requestID: line.id, game: game, device: device)
        model.log(String(localized: "AetherNX Companion: \(phone.name) asks to install \(game.name) on \(device.name)."), kind: .info)
        if phone.installsWithoutAsking {
            start(asked, line: line)
            return
        }
        request = asked
        answer(line, to: phone, "asked")
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
            if UserDefaults.standard.bool(forKey: Pref.notifyBuilds) {
                Notifier.post(title: asked.title, body: String(localized: "\(phone.name) asked for it. Open AetherNX to answer."))
            }
        }
    }

    /// Starts the install as the Install button does, and tells the phone what became of it: started, queued behind the running job, or not started
    /// (`refused`, `why: mac`: Studio says why on the Mac, as it would for the button).
    private func start(_ asked: InstallRequest, line: LinkLine) {
        guard let model, let game = model.games.first(where: { $0.id == asked.game.id }) else {
            answer(line, to: asked.phone, "refused", why: "no-game")
            return
        }
        let before = model.job
        model.build(game, target: .device, onDevice: asked.device.udid)
        if let job = model.job, job !== before, job.isRunning, job.gameID == game.id {
            answer(line, to: asked.phone, "started")
        } else if model.buildQueue.contains(where: { $0.gameID == game.id && $0.target == .device }) {
            answer(line, to: asked.phone, "queued")
        } else {
            answer(line, to: asked.phone, "refused", why: "mac")
        }
    }

    private func requestLine(_ asked: InstallRequest) -> LinkLine {
        var line = LinkLine.phone("install")
        line.id = asked.requestID
        return line
    }

    /// Install, or Always Allow: the install starts, and with Always Allow this phone's later requests start without the alert.
    func approve(_ asked: InstallRequest, always: Bool) {
        guard resolved.insert(asked.id).inserted else { return }
        if request?.id == asked.id { request = nil }
        guard phones.contains(where: { $0.id == asked.phone.id }) else { return }   // removed while its alert was open
        if always { server?.setInstallsWithoutAsking(true, phone: asked.phone.id) }
        start(asked, line: requestLine(asked))
    }

    func decline(_ asked: InstallRequest) {
        guard resolved.insert(asked.id).inserted else { return }
        if request?.id == asked.id { request = nil }
        answer(requestLine(asked), to: asked.phone, "declined")
    }

    /// The alert went away. Its buttons answer by themselves; this counts for a dismissal that pressed none, once theirs have run.
    func alertDismissed() {
        Task { [weak self] in
            guard let self, let asked = self.request else { return }
            self.decline(asked)
        }
    }
}

// MARK: - The Devices page

/// The link's card on the Devices page: the switch, this Mac's state on the network, the phones paired with it, and Pair.
struct CompanionCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.companionLink) private var isOn = false
    @State private var showsPairing = false

    var body: some View {
        let host = model.companion
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 34))
                    .foregroundStyle(host.state == .listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AetherNX Companion")
                        .font(.title3.weight(.semibold))
                    Text(summary(host))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Live link with AetherNX Companion", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if isOn {
                if case .failed(let why) = host.state {
                    Label(why, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if host.phones.isEmpty {
                    Text("No iPhone or iPad paired yet. Install AetherNX Companion on the device, then pair it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(host.phones) { phone in PairedPhoneRow(phone: phone) }
                    }
                }
                Button("Pair an iPhone or iPad…") { showsPairing = true }
                    .controlSize(.small)
                    .disabled(host.state != .listening)
            } else {
                Text("Turn it on to let AetherNX Companion on your iPhone or iPad find this Mac on the local network, follow its builds and installs as they run, and ask for an install. A device pairs once, with a code shown here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: isOn) { _, on in host.setOn(on) }
        .sheet(isPresented: $showsPairing) { PairingSheet() }
    }

    private func summary(_ host: CompanionHost) -> String {
        switch host.state {
        case .off: String(localized: "The live link is off")
        case .starting: String(localized: "Starting…")
        case .listening: String(localized: "On the local network as \(host.name)")
        case .failed: String(localized: "Not on the network now")
        }
    }
}

private struct PairedPhoneRow: View {
    let phone: PairedPhone
    @Environment(AppModel.self) private var model

    var body: some View {
        let host = model.companion
        let isConnected = host.connected.contains(phone.id)
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.title3)
                .foregroundStyle(isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(phone.name).lineLimit(1)
                Text(isConnected ? "Connected now" : "Paired \(phone.paired.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Installs without asking", isOn: Binding(get: { phone.installsWithoutAsking }, set: { host.setInstallsWithoutAsking($0, for: phone) }))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("An install this device asks for starts at once, without your OK on this Mac")
            Button("Forget") { host.remove(phone) }
                .controlSize(.small)
                .help("This device has to pair again before it connects")
        }
    }
}

/// The code a phone types to pair: shown while the sheet is open, good for one device and for two minutes.
struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let host = model.companion
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pair an iPhone or iPad")
                    .font(.title3.weight(.semibold))
                Text("In AetherNX Companion on the device, open Mac, choose \(host.name) and type this code. The device and this Mac must be on the same network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let code = host.pairingCode {
                Text(verbatim: String(code.prefix(3)) + " " + String(code.suffix(3)))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(Text(verbatim: code.map(String.init).joined(separator: " ")))
                Text("The code is good for one device and for two minutes. Paired devices that are not connected yet wait while it shows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let phone = host.justPaired {
                Label("\(phone.name) is paired.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Text("An install it asks for waits for your OK on this Mac, until you choose Always Allow for it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("This code is no longer good: its two minutes passed, or it met too many wrong tries.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                if host.pairingCode == nil && host.justPaired == nil {
                    Button("Show a New Code") { host.beginPairing() }
                }
                if host.pairingCode == nil && host.justPaired != nil {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear { host.beginPairing() }
        .onDisappear { host.endPairing() }
    }
}

/// The install a paired phone asked for, as an alert of the main window: Studio shows the request, and nothing starts without an answer here
/// until the person chose Always Allow for that phone.
struct CompanionRequestAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let host = model.companion
        content.alert(host.request?.title ?? "", isPresented: Binding(get: { host.request != nil }, set: { if !$0 { host.alertDismissed() } }),
                      presenting: host.request) { asked in
            Button("Install") { host.approve(asked, always: false) }
            Button("Always Allow \(asked.phone.name)") { host.approve(asked, always: true) }
            Button("Don't Install", role: .cancel) { host.decline(asked) }
        } message: { asked in
            Text(asked.message)
        }
    }
}
