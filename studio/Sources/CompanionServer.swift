import CryptoKit
import Foundation
import Network

// The Mac's end of the live link with AetherNX Companion (docs/companion.md, How it talks to the Mac). It listens on the local network, pairs a
// phone that types the six digits it shows, and sends every connected phone the job Studio runs and the script's events. It knows nothing of the
// app's windows or its library: CompanionLink.swift joins it to them, and companion/tests runs it against the phone's own client. The format and
// the keys are the companion's (companion/Sources/Core/LinkWire.swift, LinkTransport.swift), compiled into Studio as well.

/// An iPhone or iPad paired with this Mac's Studio.
struct PairedPhone: Codable, Equatable, Identifiable, Sendable {
    /// The phone's own ID, random, made once by its companion.
    var id: String
    var name: String
    /// What the phone says in its `hello`, so that removing one phone here ends that phone's access alone.
    var token: String
    var paired: Date
    /// An install it asks for starts without the Mac's own confirmation: the person chose Always Allow for it.
    var installsWithoutAsking: Bool
}

/// What this Mac keeps of the link: its own ID, the key paired phones connect with, and the phones. One file, readable by its owner alone.
struct LinkIdentity: Codable, Equatable, Sendable {
    static let currentFormat = 1

    var format: Int
    var id: String
    var key: Data
    var phones: [PairedPhone]

    static func new() -> LinkIdentity {
        LinkIdentity(format: currentFormat, id: LinkKeys.newID(), key: LinkKeys.newKey(), phones: [])
    }

    enum Loaded: Equatable {
        case identity(LinkIdentity)
        /// No file, or one that is not this format's: a new identity takes its place.
        case none
        /// A file of a later format, which a newer AetherNX wrote: it is kept aside, never written over.
        case later(Int)
    }

    static func load(_ url: URL) -> Loaded {
        guard let data = try? Data(contentsOf: url) else { return .none }
        if let identity = try? JSONDecoder().decode(LinkIdentity.self, from: data), identity.format == currentFormat, identity.key.count == 32, !identity.id.isEmpty {
            return .identity(identity)
        }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let format = object["format"] as? Int, format > currentFormat {
            return .later(format)
        }
        return .none
    }

    /// Writes the file whole, readable by its owner alone from the start (a temporary file made with that mode, then renamed over the old one).
    @discardableResult
    func save(_ url: URL) -> Bool {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return false }
        let temporary = folder.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        if rename(temporary.path, url.path) != 0 {
            try? fm.removeItem(at: temporary)
            return false
        }
        return true
    }
}

@MainActor
final class CompanionServer {
    enum State: Equatable {
        case off, starting, listening
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var identity: LinkIdentity
    /// The six digits on show, and when they stop being good; nil when the listener takes the link's key.
    private(set) var pairingCode: String?
    private(set) var pairingEnds: Date?
    /// The port the listener got, once it listens.
    private(set) var port: UInt16?

    /// Something a view shows changed: the state, the phones, who is connected, the code.
    var onChange: (() -> Void)?
    /// The identity changed and is to be kept.
    var onSave: ((LinkIdentity) -> Void)?
    var onPaired: ((PairedPhone) -> Void)?
    /// A paired, connected phone asked for something (`do`: `install`).
    var onRequest: ((PairedPhone, LinkLine) -> Void)?

    private final class Session {
        let channel: LinkChannel
        /// Accepted while the listener took the code's key: it may pair and nothing else.
        let pairing: Bool
        /// The paired phone's ID, once its `hello` was accepted.
        var phone: String?

        init(channel: LinkChannel, pairing: Bool) {
            self.channel = channel
            self.pairing = pairing
        }
    }

    private let name: String
    private let appVersion: String
    private let advertises: Bool
    private let loopbackOnly: Bool
    private var wantsOn = false
    private var listener: NWListener?
    /// The listener the last change of key put away, until it is gone: the next one starts then.
    private var closing: NWListener?
    private var sessions: [Session] = []
    private var pairingTries = 0
    private var pairingTimer: Task<Void, Never>?
    private var restart: Task<Void, Never>?
    /// The job running, or the last one that ended, with what a phone that connects later needs to show it.
    private var job: LinkLine?
    private var endedAt: Date?
    private var finishedStages: [String] = []
    private var lastStage: String?
    private var lastProgress: String?

    /// How long a job that ended is still told to a phone that connects.
    private static let endedJobLifetime: TimeInterval = 600

    /// `advertises` false and `loopbackOnly` true are the tests': no Bonjour, this Mac alone.
    init(identity: LinkIdentity, name: String, appVersion: String, advertises: Bool = true, loopbackOnly: Bool = false) {
        self.identity = identity
        self.name = name
        self.appVersion = appVersion
        self.advertises = advertises
        self.loopbackOnly = loopbackOnly
    }

    /// The phones connected now, by ID.
    var connectedPhones: Set<String> { Set(sessions.compactMap(\.phone)) }

    // MARK: Listening

    func start() {
        guard !wantsOn else { return }
        wantsOn = true
        listen()
        onChange?()
    }

    func stop() {
        wantsOn = false
        pairingCode = nil
        pairingEnds = nil
        pairingTimer?.cancel()
        pairingTimer = nil
        listen()
        for session in sessions { session.channel.close() }
        sessions = []
        state = .off
        onChange?()
    }

    /// A new listener in place of the old one, with the key of the moment: a listener takes one key, so showing a code and ending it both come here.
    /// Connections already accepted stay. The new one starts once the old one is gone, so its service has left the network first and the Mac's name
    /// is free for the new one (two services of one name at once, and Bonjour calls the second "name (2)").
    private func listen() {
        restart?.cancel()
        restart = nil
        port = nil
        if let old = listener {
            listener = nil
            closing = old
            old.newConnectionHandler = nil
            old.stateUpdateHandler = { [weak self, weak old] state in
                guard case .cancelled = state else { return }
                MainActor.assumeIsolated {
                    guard let self, let old, self.closing === old else { return }
                    self.closing = nil
                    self.open()
                    self.onChange?()
                }
            }
            old.cancel()
            Task { [weak self, weak old] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let old, self.closing === old else { return }
                self.closing = nil   // it never said it was gone: the next one does not wait for ever
                self.open()
                self.onChange?()
            }
        }
        if closing == nil { open() } else if wantsOn { state = .starting }
    }

    /// Starts the listener, unless the link is off or one is there already.
    private func open() {
        guard wantsOn, listener == nil else { return }
        let pairing = pairingCode != nil
        let key = pairingCode.map { LinkKeys.pairingKey(code: $0) } ?? identity.key
        let parameters = LinkTransport.parameters(key: key, identity: pairing ? LinkTransport.pairingIdentity : LinkTransport.linkIdentity, loopbackOnly: loopbackOnly)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        if advertises {
            var entries = [LinkWire.txtFormat: String(LinkWire.format), LinkWire.txtMac: identity.id]
            if pairing { entries[LinkWire.txtPairing] = "1" }
            listener.service = NWListener.Service(name: name, type: LinkWire.serviceType, txtRecord: NWTXTRecord(entries))
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.accept(connection, pairing: pairing)
            }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                self.listenerChanged(state, of: listener)
            }
        }
        self.listener = listener
        state = .starting
        listener.start(queue: .main)
    }

    private func listenerChanged(_ newState: NWListener.State, of listener: NWListener) {
        switch newState {
        case .ready:
            port = listener.port?.rawValue
            state = .listening
        case .waiting(let error):
            state = .failed(error.localizedDescription)   // no network now: the listener goes on by itself once there is one
        case .failed(let error):
            state = .failed(error.localizedDescription)
            restart = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.wantsOn else { return }
                self.listen()
                self.onChange?()
            }
        default:
            return
        }
        onChange?()
    }

    private func accept(_ connection: NWConnection, pairing: Bool) {
        let session = Session(channel: LinkChannel(connection), pairing: pairing)
        sessions.append(session)
        session.channel.onLine = { [weak self, weak session] text in
            guard let self, let session else { return }
            self.received(text, from: session)
        }
        session.channel.onClose = { [weak self, weak session] _, wasReady in
            guard let self, let session else { return }
            self.closed(session, wasReady: wasReady)
        }
        session.channel.start(timeout: 15)
        Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, let session, session.phone == nil, self.sessions.contains(where: { $0 === session }) else { return }
            session.channel.close()   // connected and never said who it is (a pairing takes a moment, and is over by now)
        }
    }

    private func closed(_ session: Session, wasReady: Bool) {
        sessions.removeAll { $0 === session }
        if session.pairing, !wasReady, pairingCode != nil {
            // a handshake that failed while a code shows: someone typed another code, or tried one
            pairingTries += 1
            if pairingTries >= LinkWire.codeTries {
                endPairing()
                return
            }
        }
        if session.phone != nil { onChange?() }
    }

    // MARK: What a phone says

    private func received(_ text: String, from session: Session) {
        // The Mac takes requests and nothing else: no line makes it run or forward anything by itself
        guard case .line(let line)? = LinkMessage.parse(text), let action = line.`do` else { return }
        if session.pairing {
            if action == "pair" { pair(line, session) }
            return
        }
        guard let id = session.phone else {
            if action == "hello" { hello(line, session) }
            return
        }
        guard let phone = identity.phones.first(where: { $0.id == id }) else {
            session.channel.close()   // removed since it connected
            return
        }
        if action == "install" { onRequest?(phone, line) }
    }

    private func hello(_ line: LinkLine, _ session: Session) {
        guard line.format == LinkWire.format else {
            refuse(session, "format")
            return
        }
        guard let id = line.phone, let token = line.token, let index = identity.phones.firstIndex(where: { $0.id == id }),
              LinkKeys.same(identity.phones[index].token, token) else {
            refuse(session, "unpaired")
            return
        }
        for other in sessions where other !== session && other.phone == id {   // a phone connects once: its older connection gives way
            other.phone = nil
            other.channel.close()
        }
        session.phone = id
        let phoneName = Self.clean(line.name ?? "")
        if !phoneName.isEmpty, phoneName != identity.phones[index].name {
            identity.phones[index].name = phoneName
            onSave?(identity)
        }
        var reply = LinkLine.mac("hello")
        reply.format = LinkWire.format
        reply.mac = identity.id
        reply.name = name
        reply.app = appVersion
        session.channel.send(reply)
        sendJob(to: session)
        onChange?()
    }

    private func pair(_ line: LinkLine, _ session: Session) {
        guard let code = pairingCode else {
            refuse(session, "unpaired")
            return
        }
        guard line.format == LinkWire.format else {
            refuse(session, "format")
            return
        }
        guard let id = line.phone, !id.isEmpty, id.count <= 64, let theirs = line.pub.flatMap({ Data(base64Encoded: $0) }) else {
            refuse(session, "format")
            return
        }
        let mine = LinkPairing.newKey()
        let token = LinkKeys.newToken()
        guard let box = try? LinkPairing.seal(LinkPairing.Secret(key: identity.key, token: token), mine: mine, theirs: theirs, code: code) else {
            refuse(session, "format")
            return
        }
        let phoneName = Self.clean(line.name ?? "")
        let phone = PairedPhone(id: id, name: phoneName.isEmpty ? "iPhone" : phoneName, token: token, paired: Date(), installsWithoutAsking: false)
        for other in sessions where other.phone == id {   // paired again: the token its older connection gave is gone
            other.phone = nil
            other.channel.close()
        }
        identity.phones.removeAll { $0.id == id }
        identity.phones.append(phone)
        onSave?(identity)
        var reply = LinkLine.mac("paired")
        reply.mac = identity.id
        reply.name = name
        reply.pub = mine.publicKey.rawRepresentation.base64EncodedString()
        reply.box = box.base64EncodedString()
        session.channel.send(reply)
        onPaired?(phone)
        endPairing()   // the code served once; the phone connects again with the link's key
    }

    private func refuse(_ session: Session, _ why: String) {
        var line = LinkLine.mac("refused")
        line.why = why
        let channel = session.channel
        channel.send(line) { channel.close() }
    }

    /// A name as a list shows it: one line, no control characters, 64 characters at most.
    nonisolated static func clean(_ name: String) -> String {
        let kept = name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
        return String(String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).prefix(64))
    }

    // MARK: Pairing

    /// Shows a code: until it is used, runs out or meets too many failed tries, the listener takes the code's key in place of the link's, so a paired
    /// phone that is not connected yet waits. Returns the code, or nil while the server is off.
    @discardableResult
    func beginPairing() -> String? {
        guard wantsOn else { return nil }
        let code = LinkKeys.newCode()
        pairingCode = code
        pairingTries = 0
        pairingEnds = Date().addingTimeInterval(LinkWire.codeLifetime)
        pairingTimer?.cancel()
        pairingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LinkWire.codeLifetime))
            guard !Task.isCancelled, let self, self.pairingCode == code else { return }
            self.endPairing()
        }
        listen()
        onChange?()
        return code
    }

    func endPairing() {
        guard pairingCode != nil else { return }
        pairingCode = nil
        pairingEnds = nil
        pairingTimer?.cancel()
        pairingTimer = nil
        listen()
        onChange?()
    }

    // MARK: The phones

    func remove(phone id: String) {
        identity.phones.removeAll { $0.id == id }
        onSave?(identity)
        for session in sessions where session.phone == id {
            session.phone = nil
            session.channel.close()
        }
        onChange?()
    }

    func setInstallsWithoutAsking(_ on: Bool, phone id: String) {
        guard let index = identity.phones.firstIndex(where: { $0.id == id }), identity.phones[index].installsWithoutAsking != on else { return }
        identity.phones[index].installsWithoutAsking = on
        onSave?(identity)
        onChange?()
    }

    /// A new key and no phones. A removed phone still holds the key every phone connects with (its token alone is refused), so this is what ends
    /// that too: every phone then pairs again.
    func reset() {
        identity.key = LinkKeys.newKey()
        identity.phones = []
        onSave?(identity)
        for session in sessions { session.channel.close() }
        sessions = []
        listen()
        onChange?()
    }

    // MARK: What the Mac says

    /// A build or an install started (`link`: `job`, `state`: `running`).
    func jobStarted(_ line: LinkLine) {
        job = line
        endedAt = nil
        finishedStages = []
        lastStage = nil
        lastProgress = nil
        broadcast(line.encoded())
    }

    /// One line the script wrote on its standard output. An event goes to the phones as it is; anything else stays on the Mac.
    func forward(event text: String) {
        guard job != nil, endedAt == nil else { return }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.utf8.count < LinkWire.maxLine, case .event(let event)? = LinkMessage.parse(line) else { return }
        switch event["ev"] as? String {
        case "stage":
            lastStage = line
            lastProgress = nil
        case "step", "progress":
            lastProgress = line
        case "stage_end":
            finishedStages.append(line)
            lastProgress = nil
        default:
            break
        }
        broadcast(line)
    }

    /// The job ended (`state`: `succeeded`, `failed` or `cancelled`).
    func jobEnded(_ line: LinkLine) {
        guard job?.id == line.id else { return }
        job = line
        endedAt = Date()
        lastProgress = nil
        broadcast(line.encoded())
    }

    /// The answer to a phone's request.
    func send(_ line: LinkLine, toPhone id: String) {
        for session in sessions where session.phone == id { session.channel.send(line) }
    }

    private func broadcast(_ line: String) {
        for session in sessions where session.phone != nil { session.channel.send(line) }
    }

    /// What a phone that connects during a job, or soon after one, needs to show it: the job, the stages that ended, and where it is now.
    private func sendJob(to session: Session) {
        guard let job else { return }
        if let endedAt, Date().timeIntervalSince(endedAt) > Self.endedJobLifetime { return }
        session.channel.send(job)
        for line in finishedStages { session.channel.send(line) }
        guard endedAt == nil else { return }
        if let lastStage { session.channel.send(lastStage) }
        if let lastProgress { session.channel.send(lastProgress) }
    }
}
