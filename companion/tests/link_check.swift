import Foundation
import Network
@testable import LinkLoopback

// The live link end to end on one Mac (docs/companion.md, How it talks to the Mac): Studio's own server (studio/Sources/CompanionServer.swift)
// and the companion's own client (companion/Sources/Core/MacLink.swift), compiled together by test_companion.py and joined over the loopback
// interface. No Bonjour, no local network, no device: the client is given the server's port by hand. The handshakes, the pairing and the lines
// are the real ones.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

/// Waits until `done` is true, for `seconds` at most. The main queue runs meanwhile, and the connections' callbacks with it.
@MainActor
func wait(_ seconds: Double = 10, until done: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !done() {
        if Date() > end { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

let folder = URL(filePath: CommandLine.arguments[1])
let title = "0100A1B2C3D40000"

// MARK: The Mac's identity file

let identityFile = folder.appending(path: "link/companion-link.json")
let identity = LinkIdentity.new()
expect(identity.save(identityFile) && LinkIdentity.load(identityFile) == .identity(identity), "the Mac's identity written, its folder made, and read back")
let attributes = try? FileManager.default.attributesOfItem(atPath: identityFile.path)
expect((attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o600, "readable by its owner alone")
let laterFile = folder.appending(path: "link/later.json")
try? Data(#"{"format": 2, "id": "x", "something": "new"}"#.utf8).write(to: laterFile)
expect(LinkIdentity.load(laterFile) == .later(2) && LinkIdentity.load(folder.appending(path: "link/none.json")) == LinkIdentity.Loaded.none,
       "a file of a later format is told apart from no file")

// MARK: Listening

let server = CompanionServer(identity: identity, name: "Test Mac", appVersion: "9.9", advertises: false, loopbackOnly: true)
var saved: [LinkIdentity] = []
var pairedPhones: [PairedPhone] = []
var requests: [(phone: PairedPhone, line: LinkLine)] = []
server.onSave = { saved.append($0) }
server.onPaired = { pairedPhones.append($0) }
server.onRequest = { requests.append((phone: $0, line: $1)) }
server.start()
expect(await wait { server.state == .listening && server.port != nil }, "the Mac listens (loopback only, no Bonjour): \(server.state)")

/// The Mac as the phone would find it, at the port its listener has now.
@MainActor
func mac(pairing: Bool) -> FoundMac {
    FoundMac(id: identity.id, name: "Test Mac", isPairing: pairing, endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port ?? 1)!))
}

/// A code on show, and the listener that takes its key ready.
@MainActor
func showCode() async -> String {
    let code = server.beginPairing() ?? ""
    _ = await wait { server.state == .listening && server.port != nil }
    return code
}

@MainActor
func isPaired(_ link: MacLink) -> Bool {
    if case .done = link.pairing { return true }
    return false
}

let store = MemoryPairingStore()
let phone = MacLink(store: store, phoneID: "PHONE-1", deviceName: "Test iPhone", deviceKind: "iPhone")

// MARK: Pairing

phone.pair(with: mac(pairing: false), typed: "123456")
expect(await wait { phone.pairing != .working } && phone.pairing == .failed(.macNotPairing), "the Mac shows no code: no pairing \(phone.pairing)")

var code = await showCode()
expect(code.count == 6 && server.pairingCode == code, "the Mac shows six digits")
let wrong = code == "000000" ? "000001" : "000000"
phone.pair(with: mac(pairing: true), typed: wrong)
expect(await wait { phone.pairing != .working } && phone.pairing == .failed(.wrongCode), "a wrong code: the handshake fails \(phone.pairing)")
expect(phone.pairings.isEmpty && server.identity.phones.isEmpty && server.pairingCode == code, "nothing is paired, and the code is still good")
for _ in 1..<LinkWire.codeTries {
    phone.pair(with: mac(pairing: true), typed: wrong)
    _ = await wait { phone.pairing != .working }
}
expect(await wait { server.pairingCode == nil }, "\(LinkWire.codeTries) wrong tries end the code")
expect(await wait { server.state == .listening && server.port != nil }, "the Mac listens with the link's key again")

code = await showCode()
phone.pair(with: mac(pairing: true), typed: String(code.prefix(3)) + " " + String(code.suffix(3)))
expect(await wait { isPaired(phone) }, "the right code, typed with its space, pairs \(phone.pairing)")
expect(phone.pairings.count == 1 && phone.pairings.first?.mac == identity.id && phone.pairings.first?.key == identity.key && phone.pairings.first?.name == "Test Mac",
       "the phone holds the Mac's ID, name and link key")
expect(server.identity.phones.map(\.id) == ["PHONE-1"] && server.identity.phones.first?.name == "Test iPhone" && server.identity.phones.first?.installsWithoutAsking == false,
       "the Mac holds the phone, which installs nothing without asking")
expect(server.identity.phones.first?.token == phone.pairings.first?.token && pairedPhones.count == 1 && saved.last?.phones.count == 1 && store.load() == phone.pairings,
       "one token for this phone at both ends, and both ends kept what they hold")
expect(await wait { server.pairingCode == nil && server.state == .listening && server.port != nil }, "the code served once: the Mac listens with the link's key again")

// MARK: Connecting, and following a job

phone.look(at: [mac(pairing: false)])
expect(await wait { phone.isConnected }, "the paired phone connects with the link's key and is greeted \(phone.status) \(String(describing: phone.problem))")
expect(phone.status == .connected("Test Mac") && phone.connectedMac == identity.id && server.connectedPhones == ["PHONE-1"], "each end knows the other")

var job = LinkLine.mac("job")
job.id = "JOB-1"
job.state = "running"
job.kind = "install"
job.target = "device"
job.titleId = title
job.game = "Starfall Tactics"
job.title = "Installing on Test iPhone"
server.jobStarted(job)
server.forward(event: #"{"ev": "stage", "k": 1, "n": 7, "name": "rewrite", "step": "", "t": 0.1}"#)
server.forward(event: "[12:00:01] plain text the script printed")
server.forward(event: #"{"link": "hello", "name": "not an event"}"#)
server.forward(event: #"{"ev": "stage_end", "k": 1, "name": "rewrite", "ok": true, "summary": "9 modules", "elapsed": 14.2}"#)
server.forward(event: #"{"ev": "stage_end", "k": 2, "name": "iOS shaders", "ok": true, "summary": "cached", "elapsed": 3.1}"#)
server.forward(event: #"{"ev": "stage", "k": 3, "n": 7, "name": "sign for the device", "step": "", "t": 20.0}"#)
server.forward(event: #"{"ev": "progress", "k": 3, "name": "sign for the device", "step": "", "done": 1, "total": 2, "frac": 0.5, "eta": 40}"#)
expect(await wait { phone.job?.stageIndex == 3 && phone.job?.stageFraction == 0.5 }, "the script's events reach the phone: Step 3 of 7, half done")
expect(phone.job?.id == "JOB-1" && phone.job?.game == "Starfall Tactics" && phone.job?.stageName == "sign for the device" && phone.job?.finished.map(\.index) == [1, 2]
       && phone.status == .connected("Test Mac"), "the job, its stages, and nothing that was not an event")

phone.stop()
expect(await wait { server.connectedPhones.isEmpty }, "the Mac sees the phone leave")
let again = MacLink(store: store, phoneID: "PHONE-1", deviceName: "Test iPhone", deviceKind: "iPhone")
again.look(at: [mac(pairing: false)])
expect(await wait { again.job?.stageIndex == 3 && again.job?.stageFraction == 0.5 }, "a phone that connects during the job is told where it is")
expect(again.job?.finished.map(\.index) == [1, 2] && again.job?.isRunning == true, "with the stages that ended before it came")

// MARK: An install the phone asks for

expect(again.requestInstall(titleId: title.lowercased()) && again.answers[title]?.state == "sent", "the phone asks for an install")
expect(await wait { requests.count == 1 }, "the request reaches the Mac")
expect(requests.first?.phone.id == "PHONE-1" && requests.first?.line.titleId == title && requests.first?.line.device == "Test iPhone" && requests.first?.line.deviceKind == "iPhone",
       "from the paired phone, with the game and the device it is for")
var answer = LinkLine.mac("answer")
answer.to = "install"
answer.id = requests.first?.line.id
answer.state = "asked"
server.send(answer, toPhone: "PHONE-1")
expect(await wait { again.answers[title]?.state == "asked" }, "the Mac's answer reaches the phone")

var endedJobs: [BuildProgress] = []
again.onJobEnded = { endedJobs.append($0) }
var ended = job
ended.state = "succeeded"
server.jobEnded(ended)
expect(await wait { again.job?.state == .succeeded } && endedJobs.map(\.id) == ["JOB-1"], "the job's end reaches the phone, which announces it once")

// MARK: Who is let in

let stranger = MacLink(store: MemoryPairingStore([MacPairing(mac: identity.id, name: "Test Mac", key: identity.key, token: "not a token of the Mac's", paired: Date())]),
                       phoneID: "PHONE-2", deviceName: "Stranger", deviceKind: "iPhone")
stranger.look(at: [mac(pairing: false)])
expect(await wait { stranger.problem == .unpaired }, "a device with the link's key and no token of its own is refused \(String(describing: stranger.problem))")
expect(stranger.pairings.isEmpty && !stranger.isConnected && server.connectedPhones == ["PHONE-1"], "it forgets the Mac, and the Mac never counted it")
stranger.stop()

let outsider = MacLink(store: MemoryPairingStore([MacPairing(mac: identity.id, name: "Test Mac", key: LinkKeys.newKey(), token: "x", paired: Date())]),
                       phoneID: "PHONE-3", deviceName: "Outsider", deviceKind: "iPhone")
outsider.look(at: [mac(pairing: false)])
expect(await wait { outsider.problem == .keyRefused }, "without the link's key the handshake fails \(String(describing: outsider.problem))")
outsider.stop()

server.remove(phone: "PHONE-1")
expect(await wait(15) { again.problem == .unpaired }, "a phone removed on the Mac is refused when it comes back \(String(describing: again.problem))")
expect(again.pairings.isEmpty && store.load().isEmpty && server.identity.phones.isEmpty && saved.last?.phones.isEmpty == true, "and both ends forget the pairing")

again.stop()
server.stop()
expect(server.state == .off && server.port == nil, "the link turned off: no listener")

print("link check: \(failures) failed")
exit(failures == 0 ? 0 : 1)
