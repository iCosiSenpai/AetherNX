import CryptoKit
import Foundation
import Network
import Observation
import dnssd

// The phone's end of the live link (docs/companion.md, How it talks to the Mac): it finds AetherNX Studio on the local network, pairs with the
// six digits the Mac shows, then follows the Mac's builds and installs and asks for an install. No UIKit or SwiftUI here: companion/tests runs
// it on a Mac against Studio's own server (studio/Sources/CompanionServer.swift), over the loopback interface.

/// A Mac this device paired with: the key its connections are protected by, and the token that tells the Mac which device this is.
struct MacPairing: Codable, Equatable, Identifiable, Sendable {
    var id: String { mac }
    /// The Mac's own ID, from its service's TXT record: a renamed Mac is still this one.
    var mac: String
    var name: String
    var key: Data
    var token: String
    var paired: Date
}

/// Where the pairings are kept: the Keychain in the app, memory in the tests.
protocol PairingStore: AnyObject {
    func load() -> [MacPairing]
    func save(_ pairings: [MacPairing])
}

final class MemoryPairingStore: PairingStore {
    private var pairings: [MacPairing]

    init(_ pairings: [MacPairing] = []) {
        self.pairings = pairings
    }

    func load() -> [MacPairing] { pairings }
    func save(_ pairings: [MacPairing]) { self.pairings = pairings }
}

/// A Mac whose AetherNX Studio advertises the service on this network.
struct FoundMac: Identifiable, Equatable {
    /// The Mac's own ID from the TXT record, else its service name.
    var id: String
    var name: String
    /// It shows a code now: its listener takes the code's key, not the link's.
    var isPairing: Bool
    var endpoint: NWEndpoint
}

@MainActor
@Observable
final class MacLink {
    enum Status: Equatable {
        /// Not looking: the app is not at the front, or the link was never started.
        case off
        case looking
        case connecting(String)
        case connected(String)
    }

    /// Why the last try did not work, for the app to say in the person's words.
    enum Problem: Equatable {
        /// iOS does not let the app use the local network (Settings › Privacy & Security › Local Network).
        case localNetworkDenied
        case network(String)
        /// The Mac's listener did not take the code's key.
        case wrongCode
        /// The Mac shows no code now.
        case macNotPairing
        /// The Mac did not take this device's key: it shows a code to another device now, or its key changed.
        case keyRefused
        /// The Mac no longer knows this device: its pairing here was removed with it.
        case unpaired
        /// The Mac speaks another format: one of the two apps is older.
        case format
        case lost
    }

    enum PairingState: Equatable {
        case idle, working
        case done(String)
        case failed(Problem)
    }

    /// What the Mac did with an install request: sent (no answer yet), asked (it shows the request), started, queued, declined, refused (`why`).
    struct Answer: Equatable {
        var state: String
        var why: String?
    }

    private(set) var status: Status = .off
    private(set) var problem: Problem?
    private(set) var macs: [FoundMac] = []
    private(set) var pairings: [MacPairing]
    private(set) var pairing: PairingState = .idle
    /// The Mac ID of the connection.
    private(set) var connectedMac: String?
    /// The job the Mac runs, or the last one it ended.
    private(set) var job: BuildProgress?
    /// The answers to this device's install requests, by title ID.
    private(set) var answers: [String: Answer] = [:]

    /// A job that was running here ended: for a notification.
    @ObservationIgnored var onJobEnded: ((BuildProgress) -> Void)?
    let phoneID: String
    @ObservationIgnored var deviceName: String
    @ObservationIgnored var deviceKind: String
    private let store: PairingStore
    @ObservationIgnored private var browser: NWBrowser?
    /// Looking for Macs: the browser runs, or the Macs in sight were given by hand (`look(at:)`).
    @ObservationIgnored private var isLooking = false
    @ObservationIgnored private var channel: LinkChannel?
    @ObservationIgnored private var pairingChannel: LinkChannel?
    /// Finds a service's host and port, and returns what stops the search. The tests give their own, which needs no Bonjour.
    @ObservationIgnored var resolve: (_ service: NWEndpoint, _ done: @escaping (NWEndpoint?) -> Void) -> () -> Void = ServiceResolver.resolve
    /// Stops the search for the Mac a connection is about to be made to; nil when none runs.
    @ObservationIgnored private var stopLocating: (() -> Void)?
    @ObservationIgnored private var searches = 0
    /// The Mac the connection being made is for, from the Bonjour lookup on: connectedMac is set only once that Mac has said hello.
    @ObservationIgnored private var connectingMac: String?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var requests: [String: String] = [:]
    @ObservationIgnored private var retry: Task<Void, Never>?

    /// How many tries in a row fail before the link waits for something to change (the Macs in sight, the app coming to the front).
    private static let maxFailures = 5

    init(store: PairingStore, phoneID: String, deviceName: String, deviceKind: String) {
        self.store = store
        self.phoneID = phoneID
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        pairings = store.load()
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    /// This device's pairing with a Mac in sight, or nil when it never paired with it.
    func known(_ mac: FoundMac) -> MacPairing? {
        pairings.first { $0.mac == mac.id }
    }

    // MARK: Looking

    /// Looks for Macs and connects to a paired one once it is in sight. The app calls it when it comes to the front.
    func start() {
        guard browser == nil else { return }
        problem = nil
        failures = 0
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: LinkWire.serviceType, domain: nil), using: NWParameters())
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.browserChanged(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.found(results)
            }
        }
        self.browser = browser
        isLooking = true
        status = .looking
        browser.start(queue: .main)
    }

    /// The Macs in sight given by hand, with no Bonjour: the tests' way in (a listener on the loopback interface advertises nothing).
    func look(at macs: [FoundMac]) {
        isLooking = true
        if status == .off { status = .looking }
        self.macs = macs
        failures = 0
        connectIfPaired()
    }

    /// Stops looking and closes the connection: the app left the front, and iOS gives a suspended app no network.
    func stop() {
        retry?.cancel()
        retry = nil
        browser?.cancel()
        browser = nil
        isLooking = false
        dropChannels()
        macs = []
        connectedMac = nil
        status = .off
        if case .working = pairing { pairing = .idle }
    }

    private func dropChannels() {
        let old = [channel, pairingChannel]
        channel = nil
        pairingChannel = nil
        for channel in old { channel?.close() }   // their callbacks find another channel in their place and say nothing
        stopLocating?()
        stopLocating = nil
        connectingMac = nil
        searches += 1   // an answer on its way finds another search in its place and says nothing
    }

    /// Where to connect to for a Mac in sight: its service's host and port, asked of Bonjour first. A connection made to the service itself
    /// never says that its handshake failed (Network.framework keeps it preparing), so a wrong code would look like a Mac that does not answer.
    /// One made to a host and a port fails at once. An endpoint that is no service (the tests') is taken as it is. nil: the service was not found.
    private func locate(_ mac: FoundMac, then: @escaping (NWEndpoint?) -> Void) {
        guard case .service = mac.endpoint else {
            then(mac.endpoint)
            return
        }
        stopLocating?()
        searches += 1
        let search = searches
        stopLocating = resolve(mac.endpoint) { [weak self] endpoint in
            guard let self, self.searches == search else { return }
            self.stopLocating = nil
            then(endpoint)
        }
    }

    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .waiting(let error), .failed(let error):
            if case .dns(let code) = error, Int(code) == -65570 {   // kDNSServiceErr_PolicyDenied
                problem = .localNetworkDenied
            } else {
                problem = .network(error.localizedDescription)
            }
            if case .failed = state {
                browser?.cancel()
                browser = nil
                isLooking = false
                macs = []
                if !isConnected { status = .off }
            }
        case .ready:
            if problem == .localNetworkDenied { problem = nil }
        default:
            break
        }
    }

    private func found(_ results: Set<NWBrowser.Result>) {
        var seen: [String: FoundMac] = [:]
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            var id = name, isPairing = false
            if case .bonjour(let record) = result.metadata {
                if let mac = record[LinkWire.txtMac], !mac.isEmpty { id = mac }
                isPairing = record[LinkWire.txtPairing] == "1"
            }
            seen[id] = FoundMac(id: id, name: name, isPairing: isPairing, endpoint: result.endpoint)
        }
        macs = seen.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        failures = 0   // something changed on the network: worth trying again
        connectIfPaired()
    }

    // MARK: The connection

    /// Tries the paired Mac again now (the person's Try Again).
    func reconnect() {
        failures = 0
        problem = nil
        if isLooking { connectIfPaired() } else { start() }
    }

    private func connectIfPaired() {
        guard isLooking, channel == nil, pairingChannel == nil, stopLocating == nil, pairing != .working, failures < Self.maxFailures else { return }
        for mac in macs where !mac.isPairing {
            if let pairing = known(mac) {
                connect(mac, pairing)
                return
            }
        }
    }

    private func connect(_ mac: FoundMac, _ pairing: MacPairing) {
        status = .connecting(mac.name)
        connectingMac = pairing.mac
        locate(mac) { [weak self] endpoint in
            guard let self else { return }
            guard self.pairings.contains(pairing) else {   // forgotten while it was looked up
                self.connectingMac = nil
                self.status = self.isLooking ? .looking : .off
                return
            }
            guard let endpoint else {
                self.lost(nil, wasReady: false, notFound: true)
                return
            }
            self.connect(to: endpoint, pairing)
        }
    }

    private func connect(to endpoint: NWEndpoint, _ pairing: MacPairing) {
        let parameters = LinkTransport.parameters(key: pairing.key, identity: LinkTransport.linkIdentity)
        let channel = LinkChannel(NWConnection(to: endpoint, using: parameters))
        self.channel = channel
        channel.onReady = { [weak self, weak channel] in
            guard let self, let channel, self.channel === channel else { return }
            var hello = LinkLine.phone("hello")
            hello.format = LinkWire.format
            hello.phone = self.phoneID
            hello.name = self.deviceName
            hello.token = pairing.token
            channel.send(hello)
        }
        channel.onLine = { [weak self, weak channel] text in
            guard let self, let channel, self.channel === channel else { return }
            self.received(text, from: pairing)
        }
        channel.onClose = { [weak self, weak channel] error, wasReady in
            guard let self, let channel, self.channel === channel else { return }
            self.channel = nil
            self.lost(error, wasReady: wasReady)
        }
        channel.start(timeout: 10)
    }

    private func received(_ text: String, from pairing: MacPairing) {
        switch LinkMessage.parse(text) {
        case .event(let event)?:
            job?.apply(event)
        case .line(let line)?:
            switch line.link {
            case "hello":
                failures = 0
                problem = nil
                let name = line.name ?? pairing.name
                connectedMac = pairing.mac
                connectingMac = nil
                status = .connected(name)
                if let index = pairings.firstIndex(where: { $0.mac == pairing.mac }), pairings[index].name != name {
                    pairings[index].name = name
                    store.save(pairings)
                }
            case "refused":
                // the Mac closes the connection after this line; what it said decides whether trying again can help
                if line.why == "unpaired" {
                    pairings.removeAll { $0.mac == pairing.mac }
                    store.save(pairings)
                    problem = .unpaired
                } else {
                    problem = line.why == "format" ? .format : .network(line.why ?? "")
                }
                failures = Self.maxFailures
            case "job":
                jobLine(line)
            case "answer":
                if let id = line.id, let title = requests[id], let state = line.state {
                    answers[title] = Answer(state: state, why: line.why)
                    if state != "asked" { requests[id] = nil }   // a final answer: nothing more comes for this request
                }
            default:
                break
            }
        case nil:
            break
        }
    }

    private func jobLine(_ line: LinkLine) {
        if var current = job, current.id == line.id {
            let wasRunning = current.isRunning
            current.update(line)
            job = current
            if wasRunning, !current.isRunning { onJobEnded?(current) }
        } else if let fresh = BuildProgress(line) {
            job = fresh   // one that had ended before this device connected is shown, and not announced
        }
    }

    /// Puts away a job that ended (the person read its result). A running one stays.
    func dismissJob() {
        if job?.isRunning == false { job = nil }
    }

    /// `notFound`: Bonjour did not say where the Mac's service is, so no connection was tried.
    private func lost(_ error: NWError?, wasReady: Bool, notFound: Bool = false) {
        let wasConnected = isConnected
        connectedMac = nil
        connectingMac = nil
        status = isLooking ? .looking : .off
        guard failures < Self.maxFailures else { return }   // refused: the Mac said why
        failures += 1
        if notFound {
            problem = .network("")
        } else if !wasReady, MacLink.isHandshakeFailure(error) {
            problem = .keyRefused
        } else if let error {
            problem = .network(error.localizedDescription)
        } else if wasConnected {
            problem = .lost
        }
        scheduleRetry()
    }

    private func scheduleRetry() {
        retry?.cancel()
        guard isLooking, failures < Self.maxFailures else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.connectIfPaired()
        }
    }

    /// Whether a connection that never became ready failed at its handshake, the other end not holding the same key, rather than on its way there.
    nonisolated static func isHandshakeFailure(_ error: NWError?) -> Bool {
        guard let error else { return true }
        switch error {
        case .tls: return true
        case .posix(let code): return code == .ECONNRESET || code == .EPIPE || code == .ENOTCONN
        default: return false
        }
    }

    // MARK: Pairing

    /// Pairs with a Mac that shows a code: `typed` is what the person typed, with or without spaces.
    func pair(with mac: FoundMac, typed: String) {
        guard pairingChannel == nil, pairing != .working else { return }
        guard let code = LinkKeys.code(typed: typed) else {
            pairing = .failed(.wrongCode)
            return
        }
        retry?.cancel()
        dropChannels()
        connectedMac = nil
        status = isLooking ? .looking : .off
        pairing = .working
        locate(mac) { [weak self] endpoint in
            guard let self, self.pairing == .working, self.pairingChannel == nil else { return }
            guard let endpoint else {
                self.pairing = .failed(.network(""))
                self.connectIfPaired()
                return
            }
            self.pair(to: endpoint, mac, code: code)
        }
    }

    private func pair(to endpoint: NWEndpoint, _ mac: FoundMac, code: String) {
        let mine = LinkPairing.newKey()
        let parameters = LinkTransport.parameters(key: LinkKeys.pairingKey(code: code), identity: LinkTransport.pairingIdentity)
        let channel = LinkChannel(NWConnection(to: endpoint, using: parameters))
        pairingChannel = channel
        channel.onReady = { [weak self, weak channel] in
            guard let self, let channel, self.pairingChannel === channel else { return }
            var line = LinkLine.phone("pair")
            line.format = LinkWire.format
            line.phone = self.phoneID
            line.name = self.deviceName
            line.pub = mine.publicKey.rawRepresentation.base64EncodedString()
            channel.send(line)
        }
        channel.onLine = { [weak self, weak channel] text in
            guard let self, let channel, self.pairingChannel === channel, case .line(let line)? = LinkMessage.parse(text) else { return }
            if line.link == "paired" {
                guard let id = line.mac, let pub = line.pub.flatMap({ Data(base64Encoded: $0) }), let box = line.box.flatMap({ Data(base64Encoded: $0) }),
                      let secret = try? LinkPairing.open(box, mine: mine, theirs: pub, code: code) else {
                    self.endPairing(channel, .failed(.wrongCode))
                    return
                }
                let name = line.name ?? mac.name
                self.pairings.removeAll { $0.mac == id }
                self.pairings.append(MacPairing(mac: id, name: name, key: secret.key, token: secret.token, paired: Date()))
                self.store.save(self.pairings)
                self.failures = 0
                self.problem = nil
                self.endPairing(channel, .done(name))
            } else if line.link == "refused" {
                self.endPairing(channel, .failed(line.why == "format" ? .format : .wrongCode))
            }
        }
        channel.onClose = { [weak self, weak channel] error, wasReady in
            guard let self, let channel, self.pairingChannel === channel else { return }
            self.pairingChannel = nil
            if wasReady {
                self.pairing = .failed(.lost)
            } else if MacLink.isHandshakeFailure(error) {
                self.pairing = .failed(mac.isPairing ? .wrongCode : .macNotPairing)
            } else {
                self.pairing = .failed(.network(error?.localizedDescription ?? ""))
            }
            self.connectIfPaired()
        }
        channel.start(timeout: 10)
    }

    private func endPairing(_ channel: LinkChannel, _ state: PairingState) {
        pairingChannel = nil
        pairing = state
        channel.close()
        scheduleRetry()   // the Mac's listener takes the link's key again in a moment: the first try may come too soon
    }

    /// The pairing sheet closed: its result is not shown again.
    func clearPairing() {
        if case .working = pairing { return }
        pairing = .idle
    }

    /// Forgets a Mac: its key goes, and the connection to it with it. The Mac keeps this device in its list until it is removed there.
    func forget(_ mac: String) {
        pairings.removeAll { $0.mac == mac }
        store.save(pairings)
        if connectedMac == mac || connectingMac == mac {   // connected, or still connecting: the handshake must not end in a hello from a Mac forgotten
            let old = channel
            channel = nil
            old?.close()
            stopLocating?()
            stopLocating = nil
            searches += 1
            connectingMac = nil
            connectedMac = nil
            status = isLooking ? .looking : .off
        }
    }

    // MARK: Requests

    /// Asks the connected Mac to install a game on this device (`{"do": "install", …}`). false when no Mac is connected.
    @discardableResult
    func requestInstall(titleId: String) -> Bool {
        guard isConnected else { return false }
        let title = titleId.uppercased()
        guard let channel else {
            answers[title] = Answer(state: "asked", why: nil)   // the scripted Mac of `play`: as if it showed the request
            return true
        }
        let id = LinkKeys.newID()
        var line = LinkLine.phone("install")
        line.id = id
        line.titleId = title
        line.device = deviceName
        line.deviceKind = deviceKind
        requests[id] = title
        answers[title] = Answer(state: "sent", why: nil)
        channel.send(line)
        return true
    }

    // MARK: Without a Mac

    /// Shows what these lines would, as if a Mac of this name had sent them: the demo library's Mac, and the tests. No connection is involved.
    func play(_ lines: [String], from name: String) {
        connectedMac = "demo"
        status = .connected(name)
        let pairing = MacPairing(mac: "demo", name: name, key: Data(), token: "", paired: Date())
        for line in lines { received(line, from: pairing) }
    }
}

/// Asks Bonjour where a service is: the name of its host and its port. Everything here runs on the main queue.
final class ServiceResolver: @unchecked Sendable {
    private var ref: DNSServiceRef?
    private var done: ((NWEndpoint?) -> Void)?

    /// How long Bonjour is given to answer. On a local network it takes a moment.
    static let timeout: TimeInterval = 5

    /// Finds the host and port of a service endpoint, as `NWBrowser` gives it. `done` is called once on the main queue: with the host and port,
    /// or with nil when Bonjour gave none in time. The closure returned stops the search, and `done` is then not called.
    static func resolve(_ service: NWEndpoint, _ done: @escaping (NWEndpoint?) -> Void) -> () -> Void {
        let resolver = ServiceResolver()
        resolver.start(service, done)
        return { resolver.finish(nil, tell: false) }
    }

    private func start(_ service: NWEndpoint, _ done: @escaping (NWEndpoint?) -> Void) {
        self.done = done
        guard case .service(let name, let type, let domain, _) = service else {
            DispatchQueue.main.async { self.finish(nil) }
            return
        }
        // The context is this object, kept alive by `done`'s owner until the search ends (`finish` lets go of the reference Bonjour holds)
        let context = Unmanaged.passRetained(self).toOpaque()
        let reply: DNSServiceResolveReply = { _, _, _, error, _, host, port, _, _, context in
            guard let context else { return }
            let resolver = Unmanaged<ServiceResolver>.fromOpaque(context).takeUnretainedValue()
            var found: NWEndpoint?
            if error == kDNSServiceErr_NoError, let host, let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: port)) {
                var name = String(cString: host)
                if name.hasSuffix(".") { name.removeLast() }
                if !name.isEmpty { found = .hostPort(host: NWEndpoint.Host(name), port: port) }
            }
            resolver.finish(found)
        }
        var ref: DNSServiceRef?
        guard DNSServiceResolve(&ref, 0, 0, name, type, domain.isEmpty ? "local." : domain, reply, context) == kDNSServiceErr_NoError, let ref,
              DNSServiceSetDispatchQueue(ref, .main) == kDNSServiceErr_NoError else {
            if let ref { DNSServiceRefDeallocate(ref) }
            Unmanaged<ServiceResolver>.fromOpaque(context).release()
            DispatchQueue.main.async { self.finish(nil) }
            return
        }
        self.ref = ref
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in self?.finish(nil) }
    }

    /// Ends the search once: the first answer, the time running out, or the owner stopping it.
    private func finish(_ endpoint: NWEndpoint?, tell: Bool = true) {
        let done = self.done
        self.done = nil
        if let ref {
            self.ref = nil
            DNSServiceRefDeallocate(ref)   // no answer comes after this
            Unmanaged.passUnretained(self).release()
        }
        if tell { done?(endpoint) }
    }
}
