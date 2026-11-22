import Foundation
import Network

// The link's connections (docs/companion.md, How it talks to the Mac): TCP on the local network under TLS with a pre-shared key, carrying lines.
// Studio compiles this file too, beside LinkWire.swift. Everything here runs on the main queue.

enum LinkTransport {
    /// The identities the two kinds of connection name their key by.
    static let pairingIdentity = "aethernx-pair-1"
    static let linkIdentity = "aethernx-link-1"

    /// TLS 1.2 with a pre-shared key, as Network.framework offers it: both ends hold the key, and no certificate is involved. A listener takes one
    /// key at a time, so the Mac's takes the code's key while it shows a code and the link's key the rest of the time (CompanionServer).
    static func parameters(key: Data, identity: String, loopbackOnly: Bool = false) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, keyData as __DispatchData, identityData as __DispatchData)
        // TLS_PSK_WITH_AES_128_GCM_SHA256 (RFC 5487), by its number: the one suite both ends offer
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: 0x00A8)!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        // No resumed sessions: a resumed handshake proves the earlier session, not the key, so an end that connected once would get in again with
        // any key for as long as the listener lives. Either end's switch is enough; both ends set it.
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 15
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        if loopbackOnly { parameters.requiredInterfaceType = .loopback }   // the tests: this Mac alone, no Bonjour and no local network prompt
        return parameters
    }
}

/// A connection that speaks lines: what arrives is cut into lines, and a line goes out whole. It is started on the main queue, so its callbacks
/// come there, and it ends once: `onClose` says why and whether the connection had been ready (a handshake that fails never was).
final class LinkChannel: @unchecked Sendable {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onLine: ((String) -> Void)?
    var onClose: ((_ error: NWError?, _ wasReady: Bool) -> Void)?
    private(set) var isReady = false
    private(set) var isClosed = false
    private var buffer = LineBuffer()

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// Starts the connection. One that is not ready after `timeout` seconds is closed as timed out.
    func start(timeout: TimeInterval) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !self.isReady, !self.isClosed else { return }
                self.isReady = true
                self.onReady?()
                self.receive()
            case .failed(let error), .waiting(let error):
                self.finish(error)   // no waiting for a better network here: the owner tries again
            case .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.isReady else { return }
            self.finish(.posix(.ETIMEDOUT))
        }
    }

    func send(_ line: String, then done: (() -> Void)? = nil) {
        guard !isClosed else { return }
        connection.send(content: Data((line + "\n").utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(error) }
            done?()
        })
    }

    func send(_ line: LinkLine, then done: (() -> Void)? = nil) {
        send(line.encoded(), then: done)
    }

    func close() {
        finish(nil)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                guard let lines = self.buffer.append(data) else {
                    self.finish(.posix(.EMSGSIZE))
                    return
                }
                for line in lines where !self.isClosed { self.onLine?(line) }
            }
            if self.isClosed { return }
            if isComplete || error != nil { self.finish(error) } else { self.receive() }
        }
    }

    private func finish(_ error: NWError?) {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let closed = onClose, wasReady = isReady
        onReady = nil
        onLine = nil
        onClose = nil
        closed?(error, wasReady)
    }
}
