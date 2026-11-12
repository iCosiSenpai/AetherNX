import AppKit
import Foundation
import Observation
import SwiftUI

/// An iPhone or iPad paired with this Mac, as `./aethernx devices --json` lists it.
struct AppleDevice: Decodable, Identifiable, Hashable {
    var udid: String
    var identifier: String
    var name: String
    var model: String
    var kind: String
    var os: String
    /// cable, network, or none (paired once, not reachable now).
    var connection: String
    var paired: Bool
    var developerMode: Bool?

    var id: String { udid }
    var isReachable: Bool { connection != "none" }

    var systemImage: String { kind == "iPad" ? "ipad" : "iphone" }

    /// "iPhone 17 Pro Max · iOS 27.2 · by cable"
    var summary: String {
        var parts: [String] = []
        if !model.isEmpty, model != name { parts.append(model) }
        if !os.isEmpty { parts.append(os) }
        switch connection {
        case "cable": parts.append(String(localized: "by cable"))
        case "network": parts.append(String(localized: "on the network"))
        default: parts.append(String(localized: "not connected"))
        }
        if developerMode == false { parts.append(String(localized: "Developer Mode off")) }
        return parts.joined(separator: " · ")
    }
}

/// An Apple team this Mac has a development certificate for.
struct SigningTeam: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var identity: String
}

struct DeviceList: Decodable {
    var devices: [AppleDevice]
    var teams: [SigningTeam]
}

/// What an install on a device needs beyond a build: where, signed by whom, and how the game files travel.
struct InstallOptions: Equatable {
    var device: String
    var team: String
    var separateFiles = false
    var launch = false
    var iCloudContainer = ""
}

/// The paired devices and the signing teams, read when the app needs them (a device comes and goes).
@MainActor
@Observable
final class DeviceCenter {
    private(set) var devices: [AppleDevice] = []
    private(set) var teams: [SigningTeam] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?

    func refresh(engine: URL?, then done: (@MainActor () -> Void)? = nil) {
        guard let engine, !isLoading else { return }
        isLoading = true
        Task {
            let result = await CommandRunner.capture(executable: engine.appending(path: "aethernx"), arguments: ["devices", "--json"], directory: engine, timeout: 90)
            isLoading = false
            hasLoaded = true
            if result.status == 0, let list = try? JSONDecoder.snakeCase.decode(DeviceList.self, from: result.stdout) {
                devices = list.devices
                teams = list.teams
                error = nil
            } else {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init)
                error = detail ?? String(localized: "The device list could not be read (exit code \(result.status)).")
            }
            done?()
        }
    }

    /// The device an install goes to: the one chosen in Settings while this Mac still knows it, else the only one reachable.
    nonisolated static func device(chosen: String, among devices: [AppleDevice]) -> AppleDevice? {
        if let saved = devices.first(where: { $0.udid == chosen }) { return saved }
        let reachable = devices.filter(\.isReachable)
        return chosen.isEmpty && reachable.count == 1 ? reachable[0] : nil
    }

    /// The team that signs: the one chosen (a team ID typed in counts too: Xcode may know a team this Mac has no certificate for yet), else the only one.
    nonisolated static func team(chosen: String, among teams: [SigningTeam]) -> String? {
        let typed = chosen.trimmingCharacters(in: .whitespaces).uppercased()
        if typed.count == 10, typed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return typed }
        return teams.count == 1 ? teams[0].id : nil
    }

    var selectedDevice: AppleDevice? {
        Self.device(chosen: UserDefaults.standard.string(forKey: Pref.installDevice) ?? "", among: devices)
    }

    var selectedTeam: String? {
        Self.team(chosen: UserDefaults.standard.string(forKey: Pref.signingTeam) ?? "", among: teams)
    }
}

// MARK: - Settings

struct DeviceSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.installDevice) private var installDevice = ""
    @AppStorage(Pref.signingTeam) private var signingTeam = ""
    @AppStorage(Pref.installSeparateFiles) private var separateFiles = false
    @AppStorage(Pref.installLaunch) private var launch = false
    @AppStorage(Pref.showFPS) private var showFPS = false
    @AppStorage(Pref.ascKeyPath) private var keyPath = ""
    @AppStorage(Pref.ascKeyID) private var keyID = ""
    @AppStorage(Pref.ascIssuer) private var issuer = ""
    @AppStorage(Pref.iCloudContainer) private var iCloudContainer = ""

    var body: some View {
        let center = model.devices
        Form {
            Section {
                Picker("Install on", selection: $installDevice) {
                    Text(center.devices.filter(\.isReachable).count == 1 ? "The connected device" : "Choose a device").tag("")
                    if !center.devices.isEmpty { Divider() }
                    ForEach(center.devices) { device in
                        Label { Text(verbatim: "\(device.name): \(device.summary)") } icon: { Image(systemName: device.systemImage) }.tag(device.udid)
                    }
                    if !installDevice.isEmpty, !center.devices.contains(where: { $0.udid == installDevice }) {
                        Text("A device this Mac no longer lists").tag(installDevice)
                    }
                }
                HStack {
                    status(center)
                    Spacer()
                    if center.isLoading { ProgressView().controlSize(.small) }
                    Button("Refresh") { center.refresh(engine: model.engine) }
                        .disabled(center.isLoading || model.engine == nil)
                }
            } header: {
                Text("Device")
            } footer: {
                Text("Connect the iPhone or iPad with a cable, unlock it and choose Trust; later it can also be on the same network. Turn on Developer Mode on the device in Settings › Privacy & Security.")
            }

            Section {
                Picker("Team", selection: $signingTeam) {
                    Text(center.teams.count == 1 ? "The only team on this Mac" : "Choose a team").tag("")
                    if !center.teams.isEmpty { Divider() }
                    ForEach(center.teams) { team in
                        Text(verbatim: "\(team.name) (\(team.id))").tag(team.id)
                    }
                    if !signingTeam.isEmpty, !center.teams.contains(where: { $0.id == signingTeam }) {
                        Text(verbatim: signingTeam).tag(signingTeam)
                    }
                }
                TextField("Team ID", text: $signingTeam, prompt: Text(verbatim: "A1B2C3D4E5"))
                    .autocorrectionDisabled()
            } header: {
                Text("Signing")
            } footer: {
                Text("The app is signed with your own Apple team, free or paid. The teams listed have a development certificate on this Mac: sign in with your Apple ID in Xcode › Settings › Accounts to get one. A free account's apps stop opening after 7 days: install again to renew them.")
            }

            Section {
                Toggle("Keep the game files out of the app", isOn: $separateFiles)
                Toggle("Open the game when it is installed", isOn: $launch)
                Toggle("Show the frame rate", isOn: $showFPS)
            } header: {
                Text("Install")
            } footer: {
                Text("Out of the app, the game files are copied to the device once and stay there across installs: for games too big to install whole, and for quick reinstalls. That copy needs a cable and afcclient (brew install libimobiledevice) for a large game.")
            }

            Section {
                LabeledContent("API key") {
                    HStack {
                        Text(keyPath.isEmpty ? String(localized: "No key") : (keyPath as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        if !keyPath.isEmpty { Button("Remove") { keyPath = ""; keyID = "" } }
                        Button("Choose…", action: chooseKey)
                    }
                }
                if !keyPath.isEmpty {
                    TextField("Key ID", text: $keyID, prompt: Text("From the file's name"))
                        .autocorrectionDisabled()
                    TextField("Issuer ID", text: $issuer, prompt: Text(verbatim: "00000000-0000-0000-0000-000000000000"))
                        .autocorrectionDisabled()
                }
                TextField("iCloud container", text: $iCloudContainer, prompt: Text(verbatim: "iCloud.com.example.saves"))
                    .autocorrectionDisabled()
            } header: {
                Text("Advanced")
            } footer: {
                Text("An App Store Connect API key (AuthKey_….p8, with its issuer ID) signs without an Apple ID in Xcode. An iCloud container your team owns gives the installed games automatic iCloud saves; without one, choose a folder in each game's Cloud saves. Neither leaves this Mac.")
            }
        }
        .formStyle(.grouped)
        .onAppear { if !center.hasLoaded { center.refresh(engine: model.engine) } }
    }

    @ViewBuilder
    private func status(_ center: DeviceCenter) -> some View {
        if let error = center.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if !center.hasLoaded {
            Text("Looking for devices…")
                .foregroundStyle(.secondary)
        } else if center.devices.isEmpty {
            Label("No paired iPhone or iPad.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let device = center.selectedDevice {
            if !device.isReachable {
                Label("\(device.name) is not connected now.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if device.developerMode == false {
                Label("Developer Mode is off on \(device.name).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Ready: \(device.name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            Text("Choose the device to install on.")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".appstoreconnect/private_keys")
        panel.message = String(localized: "Choose your App Store Connect API key (AuthKey_….p8).")
        if panel.runModal() == .OK, let url = panel.url { keyPath = url.path }
    }
}
