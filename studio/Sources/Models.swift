import Foundation
import SwiftUI

/// What `./aethernx scan --json` prints.
struct ScanResult: Decodable {
    var games: [Game]
    var errors: [ScanError]
}

struct ScanError: Decodable, Hashable {
    var folder: String
    var message: String
}

struct PackageFile: Decodable, Hashable, Identifiable {
    var name: String
    var path: String
    var size: Int64
    var id: String { path }
}

struct UpdatePackage: Decodable, Hashable, Identifiable {
    var name: String
    var path: String
    var size: Int64
    var version: Int
    var id: String { path }
}

struct DLCPackage: Decodable, Hashable, Identifiable {
    var name: String
    var path: String
    var size: Int64
    var titleId: String
    var index: Int
    var id: String { path + "#" + titleId }
}

/// The last install on a device from this Mac (`<build folder>/xcode/install.json`, written by `./aethernx install`).
struct DeviceInstall: Decodable, Hashable {
    var team: String?
    var bundleId: String?
    var device: String?
    var deviceName: String?
    /// ISO 8601, UTC.
    var installed: String?

    var date: Date? { installed.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

struct Game: Decodable, Hashable, Identifiable {
    enum Kind: String, Decodable {
        case packages, dump, archives
    }

    var id: String
    var kind: Kind
    var titleId: String?
    var name: String
    var folder: String
    var profile: Bool
    var base: PackageFile?
    var updates: [UpdatePackage]
    var dlc: [DLCPackage]
    var compressed: [String]
    var archives: [PackageFile]
    var workDir: String?
    /// The disk that holds the build folder is there (a drive or a share holding the builds may be unplugged).
    var workReachable: Bool
    /// Where `aethernx move-build` would put the build: the builds folder of Settings → Library, or back beside the game; nil when it is there already.
    var workMovesTo: String?
    var extractedVersions: [String]
    var displayVersion: String?
    var icon: String?
    var macApps: [String]
    var ipas: [String]
    var deviceInstall: DeviceInstall?
    var saveDir: String?
    var logFile: String?
    var decompDir: String?
    var liftedFiles: Int
    var notes: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        titleId = try c.decodeIfPresent(String.self, forKey: .titleId)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decode(String.self, forKey: .folder)
        profile = try c.decodeIfPresent(Bool.self, forKey: .profile) ?? false
        base = try c.decodeIfPresent(PackageFile.self, forKey: .base)
        updates = try c.decodeIfPresent([UpdatePackage].self, forKey: .updates) ?? []
        dlc = try c.decodeIfPresent([DLCPackage].self, forKey: .dlc) ?? []
        compressed = try c.decodeIfPresent([String].self, forKey: .compressed) ?? []
        archives = try c.decodeIfPresent([PackageFile].self, forKey: .archives) ?? []
        workDir = try c.decodeIfPresent(String.self, forKey: .workDir)
        workReachable = try c.decodeIfPresent(Bool.self, forKey: .workReachable) ?? true
        workMovesTo = try c.decodeIfPresent(String.self, forKey: .workMovesTo)
        extractedVersions = try c.decodeIfPresent([String].self, forKey: .extractedVersions) ?? []
        displayVersion = try c.decodeIfPresent(String.self, forKey: .displayVersion)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        macApps = try c.decodeIfPresent([String].self, forKey: .macApps) ?? []
        ipas = try c.decodeIfPresent([String].self, forKey: .ipas) ?? []
        deviceInstall = try c.decodeIfPresent(DeviceInstall.self, forKey: .deviceInstall)
        saveDir = try c.decodeIfPresent(String.self, forKey: .saveDir)
        logFile = try c.decodeIfPresent(String.self, forKey: .logFile)
        decompDir = try c.decodeIfPresent(String.self, forKey: .decompDir)
        liftedFiles = try c.decodeIfPresent(Int.self, forKey: .liftedFiles) ?? 0
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, titleId, name, folder, profile, base, updates, dlc, compressed, archives, workDir, workReachable, workMovesTo, extractedVersions
        case displayVersion, icon, macApps, ipas, deviceInstall, saveDir, logFile, decompDir, liftedFiles, notes
    }

    var isBuildable: Bool { kind != .archives }
    var macApp: String? { macApps.first }
    var ipa: String? { ipas.first }
    var latestUpdate: UpdatePackage? { updates.max { $0.version < $1.version } }
    var isExtracted: Bool { !extractedVersions.isEmpty }
    /// Switch 2 games have title IDs that start with 04 (Switch games: 01).
    var isSwitch2: Bool { titleId?.hasPrefix("04") == true }

    /// About what a first build needs free, as the build script measures it: the game's image (the base game with its
    /// newest update, or a dump's newest version) and 6 GB for the shaders.
    var firstBuildSpace: Int64 {
        let image = kind == .dump ? (latestUpdate?.size ?? base?.size ?? 0) : (base?.size ?? 0) + (latestUpdate?.size ?? 0)
        return image + 6 * 1_073_741_824
    }

    var totalSize: Int64 {
        (base?.size ?? 0) + updates.reduce(0) { $0 + $1.size } + dlc.reduce(0) { $0 + $1.size } + archives.reduce(0) { $0 + $1.size }
    }

    /// One short line for the sidebar.
    var summary: String {
        if kind == .archives { return String(localized: "Archive, not unpacked") }
        var parts: [String] = []
        if let displayVersion { parts.append(displayVersion) } else if let update = latestUpdate { parts.append("v\(update.version)") } else { parts.append(String(localized: "Base game")) }
        if !dlc.isEmpty { parts.append(String(localized: "\(dlc.count) DLC")) }
        return parts.joined(separator: " · ")
    }
}

enum BuildTarget: String, CaseIterable, Identifiable {
    case mac
    case device
    case ios
    case iosSlim = "ios-slim"
    case xcode

    var id: String { rawValue }
    static let menuOrder: [BuildTarget] = [.mac, .device, .ios, .iosSlim, .xcode]

    var title: LocalizedStringKey {
        switch self {
        case .mac: "Mac App"
        case .device: "iPhone or iPad, Installed"
        case .ios: "iPhone & iPad"
        case .iosSlim: "iPhone & iPad, Game Files Separate"
        case .xcode: "Xcode Project"
        }
    }

    var commandTitle: LocalizedStringKey {
        switch self {
        case .mac: "Build Mac App"
        case .device: "Install on iPhone or iPad"
        case .ios: "Build for iPhone & iPad"
        case .iosSlim: "Build for iPhone & iPad (Game Files Separate)"
        case .xcode: "Prepare Xcode Project"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .mac: "A Mac app you open from Finder, next to the game files."
        case .device: "Builds the game, signs it with your Apple team and installs it on the device chosen in Settings → iPhone & iPad."
        case .ios: "An unsigned IPA with the game inside, to install with a sideloading tool."
        case .iosSlim: "A small IPA without the game files: copy them to the app afterwards. For games too big to install."
        case .xcode: "An Xcode project, to sign and install with your developer account."
        }
    }

    var systemImage: String {
        switch self {
        case .mac: "macbook"
        case .device: "arrow.down.app"
        case .ios: "iphone"
        case .iosSlim: "iphone.and.arrow.forward"
        case .xcode: "hammer"
        }
    }

    var shortcut: (key: KeyEquivalent, modifiers: EventModifiers) {
        switch self {
        case .mac: ("b", .command)
        case .device: ("i", [.command, .shift])
        case .ios: ("b", [.command, .shift])
        case .iosSlim: ("b", [.command, .shift, .option])
        case .xcode: ("b", [.command, .option])
        }
    }

    var jobTitle: String {
        switch self {
        case .mac: String(localized: "Building Mac app")
        case .device: String(localized: "Installing on iPhone or iPad")
        case .ios, .iosSlim: String(localized: "Building for iPhone & iPad")
        case .xcode: String(localized: "Preparing Xcode project")
        }
    }
}

/// Languages the packing script accepts for `--language`.
enum GameLanguage {
    static let all: [(code: String, name: String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("it", "Italiano"), ("fr", "Français"), ("fr-CA", "Français (Canada)"),
        ("de", "Deutsch"), ("es", "Español"), ("es-419", "Español (Latinoamérica)"), ("nl", "Nederlands"), ("pt", "Português"),
        ("pt-BR", "Português (Brasil)"), ("ru", "Русский"), ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ]
}

/// Results of `./aethernx doctor --json`.
struct SetupReport: Decodable {
    struct Check: Decodable, Identifiable, Hashable {
        var group: String
        var name: String
        var ok: Bool
        var required: Bool
        var detail: String
        var fix: String
        /// A stable name for the check, what it is for (English) and how a front end installs it: "brew:…", "cask:…", "run:…", "open:…" or empty.
        var key: String?
        var why: String?
        var install: String?
        var id: String { group + "/" + name }
    }

    var version: String
    var ok: Bool
    var checks: [Check]
}
