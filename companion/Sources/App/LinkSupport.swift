import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

// The live link as the app runs it (docs/companion.md, How it talks to the Mac). Core/MacLink.swift finds the Mac, pairs and follows its jobs;
// this file gives it what only the app has: the Keychain for its pairings, this device's name, the app coming to the front and leaving it, the
// notification at the end of a job, and the link's states in the person's words.

/// The pairings in the Keychain, on this device only: each holds the key its Mac's connections are protected by.
final class KeychainPairingStore: PairingStore {
    private static let service = "io.github.icosisenpai.aethernx.companion.link"
    private static let account = "pairings"
    /// What the Keychain would not take (a build with no signature may get none): kept for as long as the app runs, so a pairing still works.
    private var unsaved: [MacPairing]?

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
    }

    func load() -> [MacPairing] {
        if let unsaved { return unsaved }
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return [] }
        return (try? JSONDecoder().decode([MacPairing].self, from: data)) ?? []
    }

    func save(_ pairings: [MacPairing]) {
        SecItemDelete(query as CFDictionary)
        unsaved = nil
        guard !pairings.isEmpty, let data = try? JSONEncoder().encode(pairings) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) != errSecSuccess { unsaved = pairings }
    }
}

extension MacLink {
    /// `-demo` (screenshots, build.sh --run): a scripted Mac in place of the network, so nothing asks for the local network and a page has a job to show.
    static let isScripted = ProcessInfo.processInfo.arguments.contains("-demo")

    private static let phoneKey = "link.phone"

    /// The link of this device: its own ID made once, the name iOS gives the app ("iPhone", unless the app has the entitlement for the person's own
    /// name for it) and its kind, which is what the Mac matches against the devices it installs on.
    static func forThisDevice() -> MacLink {
        let defaults = UserDefaults.standard
        var phone = defaults.string(forKey: phoneKey) ?? ""
        if phone.isEmpty {
            phone = UUID().uuidString
            defaults.set(phone, forKey: phoneKey)
        }
        let device = UIDevice.current
        let link = MacLink(store: isScripted ? MemoryPairingStore() : KeychainPairingStore(), phoneID: phone, deviceName: device.name,
                           deviceKind: device.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        if isScripted { link.play(DemoLink.lines, from: DemoLink.macName) }
        return link
    }

    /// The app came to the front. A device that paired looks for its Mac; one that never did looks only while its Mac page is open, so iOS asks
    /// for the local network when the person goes there and not at the first launch.
    func appBecameActive() {
        guard !Self.isScripted, !pairings.isEmpty else { return }
        start()
    }

    func pageOpened() {
        guard !Self.isScripted else { return }
        start()
    }

    func pageClosed() {
        clearPairing()
        if !Self.isScripted, pairings.isEmpty { stop() }
    }
}

/// The scripted Mac of `-demo`: an install of the demo library's first game, at its third step of seven.
enum DemoLink {
    static let macName = "Demo Mac"
    static let lines = [
        #"{"link": "hello", "format": 1, "mac": "demo", "name": "Demo Mac", "app": "1.1.0"}"#,
        #"{"link": "job", "id": "demo-job", "state": "running", "kind": "install", "target": "device", "titleId": "0100A1B2C3D40000", "game": "Starfall Tactics", "title": "Installing on iPhone"}"#,
        #"{"ev": "stage_end", "k": 1, "name": "rewrite", "ok": true, "summary": "9 modules", "elapsed": 14.2}"#,
        #"{"ev": "stage_end", "k": 2, "name": "iOS shaders", "ok": true, "summary": "cached", "elapsed": 3.1}"#,
        #"{"ev": "stage", "k": 3, "n": 7, "name": "sign for the device", "step": ""}"#,
        #"{"ev": "progress", "k": 3, "name": "sign for the device", "step": "", "frac": 0.4, "eta": 95}"#,
    ]
}

/// The link through the app's life: started when the app comes to the front, stopped when it leaves (iOS gives a suspended app no network), and
/// the notification when a job the phone was following ends away from the front.
@MainActor
final class LinkLifecycle {
    let link: MacLink
    private var isActive = false
    private var grace = UIBackgroundTaskIdentifier.invalid

    init() {
        link = MacLink.forThisDevice()
        link.onJobEnded = { [weak self] job in self?.ended(job) }
    }

    func phaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            endGrace()
            link.appBecameActive()
        case .background:
            isActive = false
            guard !MacLink.isScripted else { return }
            // With a job running, the link is kept for the little time iOS gives an app that left the front: a job that ends then still gives
            // its notification. A longer one is learned of when the app comes back.
            if link.job?.isRunning == true, link.isConnected { beginGrace() } else { link.stop() }
        default:
            isActive = false
        }
    }

    private func ended(_ job: BuildProgress) {
        if !isActive { JobNotice.post(job) }
        if grace != .invalid {
            link.stop()
            endGrace()
        }
    }

    private func beginGrace() {
        endGrace()
        grace = UIApplication.shared.beginBackgroundTask(withName: "AetherNX Companion link") { [weak self] in
            MainActor.assumeIsolated {
                self?.link.stop()
                self?.endGrace()
            }
        }
        if grace == .invalid { link.stop() }
    }

    private func endGrace() {
        guard grace != .invalid else { return }
        let task = grace
        grace = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}

/// The notification at the end of a job the phone was following.
@MainActor
enum JobNotice {
    /// Asked when the person does something a notification answers (pairs, asks for an install), not at the first launch.
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ job: BuildProgress) {
        let content = UNMutableNotificationContent()
        content.title = job.game ?? job.title
        content.body = LinkText.result(job)
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "job-\(job.id)", content: content, trigger: nil))
    }
}

/// The link's states in the person's words.
@MainActor
enum LinkText {
    static func status(_ link: MacLink) -> String {
        switch link.status {
        case .off: String(localized: "Not looking for a Mac")
        case .looking: link.pairings.isEmpty ? String(localized: "Looking for Macs on this network…") : String(localized: "Looking for your Mac…")
        case .connecting(let name): String(localized: "Connecting to \(name)…")
        case .connected(let name): String(localized: "Connected to \(name)")
        }
    }

    static func problem(_ problem: MacLink.Problem) -> String {
        switch problem {
        case .localNetworkDenied:
            String(localized: "iOS does not let AetherNX use the local network. Turn it on in Settings › Privacy & Security › Local Network.")
        case .network(let message):
            message.isEmpty ? String(localized: "The Mac did not answer.") : String(localized: "The Mac did not answer: \(message)")
        case .wrongCode:
            String(localized: "That code did not work. Check the six digits on the Mac and type them again.")
        case .macNotPairing:
            String(localized: "This Mac shows no code now. On the Mac, open AetherNX → Devices and choose Pair an iPhone or iPad.")
        case .keyRefused:
            String(localized: "The Mac did not take this device now. It may be showing a pairing code to another device: try again in a moment, and pair again if it goes on.")
        case .unpaired:
            String(localized: "This device is no longer paired with the Mac. Pair it again.")
        case .format:
            String(localized: "AetherNX on the Mac and this app speak different versions of the link. Update both.")
        case .lost:
            String(localized: "The connection to the Mac was lost.")
        }
    }

    /// What the Mac did with an install this device asked for.
    static func answer(_ answer: MacLink.Answer) -> String {
        switch answer.state {
        case "sent": return String(localized: "Asking the Mac…")
        case "asked": return String(localized: "Waiting for your OK on the Mac.")
        case "started": return String(localized: "The Mac started the install.")
        case "queued": return String(localized: "Queued on the Mac: it starts when the running job ends.")
        case "declined": return String(localized: "Declined on the Mac.")
        default: break
        }
        switch answer.why {
        case "no-game": return String(localized: "The Mac's library does not have this game.")
        case "no-device": return String(localized: "The Mac does not see this device: connect it with a cable, or unlock it on the same network.")
        case "no-engine": return String(localized: "AetherNX on the Mac is not set up yet.")
        case "busy": return String(localized: "The Mac is showing another request: answer it there first.")
        default: return String(localized: "The Mac could not start the install: AetherNX on the Mac says why.")
        }
    }

    /// A stage of the build script in the person's words, as AetherNX Studio names it (studio/Sources/JobProgress.swift, StageGuide): found by
    /// the start of the script's own name, and one this list does not know shows by that name.
    static func stage(_ stage: String) -> String {
        let name = stage.lowercased()
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { name.hasPrefix($0) } }
        if starts("decompress") { return String(localized: "Decompressing the packages") }
        if starts("build id lookup") { return String(localized: "Identifying the game version") }
        if starts("survey") { return String(localized: "Studying the game") }
        if name.contains("dlc") { return String(localized: "Add-on content") }
        if starts("extract", "unpack") { return String(localized: "Extracting the game files") }
        if starts("check ") { return String(localized: "Checking the game files") }
        if starts("pack ") { return String(localized: "Packing the game data") }
        if starts("rewrite") { return String(localized: "Adapting the game code") }
        if name.hasSuffix("capture") || starts("ue shader decode") { return String(localized: "Collecting shaders") }
        if starts("heap check") { return String(localized: "Checking memory use") }
        if starts("address regions") { return String(localized: "Mapping the address space") }
        if starts("shader split") { return String(localized: "Finding the shaders") }
        if name.hasSuffix(" shaders") { return String(localized: "Translating the shaders to Metal") }
        if starts("pipeline") { return String(localized: "Prebuilding the graphics pipelines") }
        if starts("mac host", "build nx_extract") { return String(localized: "Building the engine") }
        if starts("mac app") { return String(localized: "Making the Mac app") }
        if starts("ipa pack") { return String(localized: "Packing the IPA") }
        if starts("prepare xcode") { return String(localized: "Preparing the Xcode project") }
        if starts("app build") { return String(localized: "Building the app") }
        if starts("sign for the device") { return String(localized: "Signing for your device") }
        if starts("install on the device") { return String(localized: "Installing on the device") }
        if starts("copy the game files") { return String(localized: "Copying the game files to the device") }
        return stage
    }

    /// "Step 3 of 7: Signing for your device"
    static func progress(_ job: BuildProgress) -> String {
        guard job.stageCount > 0, job.stageIndex > 0 else { return String(localized: "Starting…") }
        return String(localized: "Step \(job.stageIndex) of \(job.stageCount): \(stage(job.stageName))")
    }

    /// How a job ended.
    static func result(_ job: BuildProgress) -> String {
        switch job.state {
        case .running: return progress(job)
        case .succeeded: return job.isInstall ? String(localized: "The install is done.") : String(localized: "The build is done.")
        case .cancelled: return String(localized: "It was stopped on the Mac.")
        case .failed:
            if let failure = job.failure, !failure.isEmpty { return failure }
            return String(localized: "It stopped with an error: AetherNX on the Mac says why.")
        }
    }
}
