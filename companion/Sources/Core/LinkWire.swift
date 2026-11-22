import CryptoKit
import Foundation

// The live link between AetherNX Studio on the Mac and the companion (docs/companion.md, How it talks to the Mac): the lines that go over it and
// the keys that protect it. Studio compiles this file too (studio/build.sh takes it from here), so both ends read one format. Nothing here opens
// a connection: LinkTransport.swift does, for MacLink.swift on the phone and studio/Sources/CompanionServer.swift on the Mac.

enum LinkWire {
    /// The Bonjour service Studio advertises and the companion looks for.
    static let serviceType = "_aethernx._tcp"
    /// The format this build speaks. The phone names its own in `hello` and `pair`; the Mac refuses one it does not speak (`refused`, `why: format`).
    static let format = 1
    /// No line is longer: one that is ends the connection.
    static let maxLine = 64 * 1024
    /// How long the six digits the Mac shows stay good, and how many failed tries they survive.
    static let codeLifetime: TimeInterval = 120
    static let codeTries = 5
    /// The service's TXT record: the format, the Mac's own ID (a renamed Mac is still the paired one), and `1` while it shows a code.
    static let txtFormat = "v"
    static let txtMac = "id"
    static let txtPairing = "pair"
}

/// One line of the link that is not a build event: a JSON object on a line of its own. From the Mac it has `link` (`hello`, `paired`, `refused`,
/// `job`, `answer`); from the phone, `do` (`hello`, `pair`, `install`). A reader ignores the keys it does not know, and a line whose `link` or `do`
/// it does not know, so format 1 can grow by keys and by lines.
struct LinkLine: Codable, Equatable, Sendable {
    /// What the Mac says.
    var link: String?
    /// What the phone asks for.
    var `do`: String?
    var format: Int?
    /// The Mac's own ID, and the phone's: random, made once by each.
    var mac: String?
    var phone: String?
    /// The sender's name, as its owner sees it ("Alessio's MacBook Air", "iPhone").
    var name: String?
    /// The Mac app's version.
    var app: String?
    /// `hello`: the token the Mac gave this phone when it paired.
    var token: String?
    /// `pair` and `paired`: each end's X25519 public key, and the link's key and the token sealed for the phone (LinkPairing), all base64.
    var pub: String?
    var box: String?
    /// `job`: the job's ID. `install` and its `answer`: the request's.
    var id: String?
    /// `answer`: the request it answers (`install`).
    var to: String?
    /// `job`: running, succeeded, failed, cancelled. `answer`: asked, started, queued, declined, refused.
    var state: String?
    /// `refused`, and an `answer` that is `refused`: unpaired, format, no-game, no-device, no-engine, busy, mac.
    var why: String?
    /// `job`: install or build, and the build's target (device, mac, ios, ios-slim, xcode).
    var kind: String?
    var target: String?
    var titleId: String?
    /// `job`: the game's name, and the job's title in the Mac's own words and language ("Installing on Alessio's iPhone").
    var game: String?
    var title: String?
    /// `job`, once it failed: why, as Studio shows it.
    var message: String?
    /// `install`: the asking device's name and kind (iPhone or iPad), for the Mac to find it among the devices it installs on.
    var device: String?
    var deviceKind: String?

    static func mac(_ link: String) -> LinkLine {
        var line = LinkLine()
        line.link = link
        return line
    }

    static func phone(_ action: String) -> LinkLine {
        var line = LinkLine()
        line.`do` = action
        return line
    }

    /// The line's text, without its newline: sorted keys, so the same line is the same bytes.
    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// What a line is: an event of the build or install script, forwarded as the script wrote it (docs/frontends.md: `stage`, `step`, `progress`,
/// `stage_end`, `say`, …), or one of the link's own lines.
enum LinkMessage {
    case event([String: Any])
    case line(LinkLine)

    /// nil for a line that is not a JSON object, or has none of `ev`, `link` and `do`: a reader skips it.
    static func parse(_ text: String) -> LinkMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if object["ev"] is String { return .event(object) }
        guard object["link"] is String || object["do"] is String, let line = try? JSONDecoder().decode(LinkLine.self, from: data) else { return nil }
        return .line(line)
    }
}

/// Cuts what arrives into lines.
struct LineBuffer {
    private var pending = Data()

    /// Adds what arrived and returns the lines it completed, without their newlines and without empty ones. nil once a line is longer than
    /// `LinkWire.maxLine`: the connection is then closed.
    mutating func append(_ chunk: Data) -> [String]? {
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            if line.count > LinkWire.maxLine { return nil }
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
            pending = Data(pending[pending.index(after: newline)...])
        }
        return pending.count > LinkWire.maxLine ? nil : lines
    }
}

/// The link's keys. A pairing connection is protected by a key made from the six digits the Mac shows; every later connection by the Mac's own
/// link key, 32 random bytes the Mac hands over while pairing (LinkPairing).
enum LinkKeys {
    /// The pre-shared key of a pairing connection.
    static func pairingKey(code: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("AetherNX Companion pairing 1".utf8), using: SymmetricKey(data: Data(code.utf8))))
    }

    /// Six digits, every one of the million codes as likely as another (SystemRandomNumberGenerator).
    static func newCode() -> String {
        let digits = String(Int.random(in: 0..<1_000_000))
        return String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// The digits of what the person typed ("123 456" is 123456), or nil when they are not six.
    static func code(typed text: String) -> String? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        return digits.count == 6 ? digits : nil
    }

    static func randomBytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }

    static func newKey() -> Data { randomBytes(32) }
    static func newToken() -> String { randomBytes(18).base64EncodedString() }
    static func newID() -> String { UUID().uuidString }

    /// Compares two tokens without stopping at the first byte that differs.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// How the Mac hands the link's key to a phone that typed its code. Six digits are few: someone who recorded the pairing connection could try all
/// million and read it. So each end makes an X25519 key for this pairing alone, and the link key travels sealed under what the two agree on:
/// reading the connection later gives the two public keys and nothing to open the seal with.
enum LinkPairing {
    /// What the phone keeps of a Mac: the key its later connections are protected by, and the token that says which phone it is.
    struct Secret: Codable, Equatable, Sendable {
        var key: Data
        var token: String
    }

    static func newKey() -> Curve25519.KeyAgreement.PrivateKey { Curve25519.KeyAgreement.PrivateKey() }

    static func seal(_ secret: Secret, mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, code: String) throws -> Data {
        try ChaChaPoly.seal(JSONEncoder().encode(secret), using: sealingKey(mine: mine, theirs: theirs, code: code)).combined
    }

    static func open(_ box: Data, mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, code: String) throws -> Secret {
        let plain = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: box), using: sealingKey(mine: mine, theirs: theirs, code: code))
        return try JSONDecoder().decode(Secret.self, from: plain)
    }

    private static func sealingKey(mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, code: String) throws -> SymmetricKey {
        let shared = try mine.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs))
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(code.utf8), sharedInfo: Data("AetherNX Companion link key 1".utf8), outputByteCount: 32)
    }
}
