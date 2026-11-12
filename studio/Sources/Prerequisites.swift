import AppKit
import Foundation
import SwiftUI

/// What each check of the setup is for, in the player's language, by the key `./aethernx doctor --json` gives it (scripts/aethernx_cli.py, WHY);
/// a check this app does not know shows the doctor's own English sentence.
enum CheckGuide {
    static func why(_ key: String?) -> String? {
        switch key ?? "" {
        case "xcode": String(localized: "Apple's developer app: it compiles the engine and the Metal shaders, and signs and installs the iPhone and iPad apps. Free from the App Store.")
        case "xcode-select": String(localized: "The command-line tools must be Xcode's own, not the smaller Command Line Tools package, which has no Metal compiler and no iOS SDK.")
        case "xcode-license": String(localized: "Xcode does nothing from the command line until its license is accepted and its first-launch components are installed.")
        case "metal-toolchain": String(localized: "Compiles the translated shaders into Metal libraries for Apple GPUs. Xcode downloads it as a separate component.")
        case "metal-compiler": String(localized: "The shaders are tested with one version of Apple's Metal compiler: another one could make wrong pictures, so the build checks it.")
        case "ios-sdk": String(localized: "Needed only for iPhone and iPad builds: the system libraries the app is compiled against.")
        case "git": String(localized: "Downloads AetherNX and its updates, and the engine's parts kept in other repositories. It comes with Xcode.")
        case "homebrew": String(localized: "The package manager that installs the open-source tools below (Python, zstd, glslang…) with one command, and updates them.")
        case "python": String(localized: "The build scripts are written in Python: it unpacks the game, rewrites its code and translates the shaders.")
        case "python-arm64": String(localized: "An Intel Python runs under Rosetta and is several times slower at the long steps.")
        case "lz4": String(localized: "Decompresses the code modules of the games.")
        case "fonttools": String(localized: "Converts the system fonts the games ask for.")
        case "capstone": String(localized: "Disassembles the game code, so the rewriter knows what it is changing.")
        case "zstd-python": String(localized: "Reads and writes zstd-compressed data in the game files and the shader cache.")
        case "nsz": String(localized: "Only for compressed packages (.nsz, .xcz): turns them into plain ones.")
        case "zbic": String(localized: "Decrypts the files of games made with the console's system 22.0.0 or later; the build uses it for every game.")
        case "dotnet": String(localized: "Runs the shader translator of this engine version.")
        case "zstd": String(localized: "Compresses and decompresses the game data and the caches quickly.")
        case "glslang": String(localized: "Checks and compiles the shaders of games that use Vulkan or OpenGL.")
        case "xcodegen": String(localized: "Only for iPhone and iPad builds: writes the Xcode project the app is signed with.")
        case "archives": String(localized: "Only for games kept in RAR or 7z archives: extracts them (zip and tar work without it).")
        case "afcclient": String(localized: "Optional, for iPhone and iPad: copies a large game to the device over the cable at full speed, once, so later installs do not copy it again.")
        case "signing": String(localized: "Optional, for iPhone and iPad: the certificate that signs the apps with your own Apple team. Xcode makes it when you sign in with your Apple ID.")
        case "keys": String(localized: "Your prod.keys, dumped from your own Switch: they decrypt the game packages. Never uploaded, never put in the apps.")
        case "nxrt", "nnheaders", "sead", "unicorn": String(localized: "For developers only: the tools of the decompilation work.")
        default: nil
        }
    }

    /// The button that installs a check's missing piece, by its `install` field ("brew:…", "cask:…", "run:…", "open:…").
    static func actionTitle(_ install: String) -> LocalizedStringKey? {
        if install.hasPrefix("brew:") || install.hasPrefix("cask:") { return "Install with Homebrew" }
        if install.hasPrefix("run:") { return "Install" }
        if install.hasPrefix("open:macappstore:") { return "Open the App Store" }
        if install.hasPrefix("open:") { return "Open the Website" }
        return nil
    }
}

/// The few things this Mac needs before AetherNX itself can be downloaded and its own check can run (that check is Python): Xcode, its tools
/// selected, Git, Homebrew and a Python. Read without running anything that would pop up a system dialog (the /usr/bin stubs of Git and Python
/// offer to install the Command Line Tools when they are missing, so they are not run).
enum MacPrerequisites {
    static func check() async -> [SetupReport.Check] {
        await Task.detached(priority: .userInitiated) { () -> [SetupReport.Check] in
            let fm = FileManager.default
            var out: [SetupReport.Check] = []
            func add(_ key: String, _ name: String, _ ok: Bool, detail: String, fix: String, required: Bool = true, install: String = "") {
                out.append(SetupReport.Check(group: "This Mac", name: name, ok: ok, required: required, detail: detail, fix: fix, key: key, why: nil, install: ok ? "" : install))
            }
            let selected = run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let xcodeApps = ((try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []).filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }.sorted()
            add("xcode", "Xcode", !xcodeApps.isEmpty, detail: xcodeApps.joined(separator: ", "),
                fix: String(localized: "Install Xcode from the App Store and open it once."), install: "open:macappstore://apps.apple.com/app/id497799835")
            add("xcode-select", String(localized: "Xcode's command-line tools selected"), selected.contains(".app/"), detail: selected.isEmpty ? String(localized: "none") : selected,
                fix: "sudo xcode-select -s /Applications/Xcode.app")
            add("git", "Git", !selected.isEmpty, detail: selected.isEmpty ? String(localized: "not found") : "/usr/bin/git", fix: "xcode-select --install")
            let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { fm.isExecutableFile(atPath: $0) }
            add("homebrew", "Homebrew", brew != nil, detail: brew ?? String(localized: "not found"),
                fix: String(localized: "Install it from brew.sh: one command in Terminal, which asks for your password."), install: "open:https://brew.sh")
            let pythons = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"].filter { fm.isExecutableFile(atPath: $0) }
            let version = pythons.first.map { run($0, ["-c", "import sys; print('%d.%d' % sys.version_info[:2])"]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let parts = version.split(separator: ".").compactMap { Int($0) }
            let recent = parts.count == 2 && (parts[0], parts[1]) >= (3, 12)
            add("python", version.isEmpty ? "Python 3" : "Python \(version)", recent, detail: pythons.first ?? String(localized: "not found"),
                fix: "brew install python", install: brew != nil ? "brew:python" : "")
            return out
        }.value
    }

    nonisolated static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
    }
}

extension AppModel {
    static let homebrew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Installs what one check is missing, as its `install` field says, then checks again.
    func installPrerequisite(_ check: SetupReport.Check) {
        guard let install = check.install, !install.isEmpty else { return }
        installPrerequisites([install], title: String(localized: "Installing \(check.name)"))
    }

    /// Installs everything a report says can be installed without a terminal: the Homebrew packages in one go, then the rest in turn.
    func installMissing(_ report: SetupReport) {
        let specs = report.checks.filter { !$0.ok && ($0.required || ["afcclient", "xcodegen", "ios-sdk"].contains($0.key ?? "")) }
            .compactMap(\.install).filter { !$0.isEmpty && !$0.hasPrefix("open:") }
        installPrerequisites(specs, title: String(localized: "Installing what the builds need"))
    }

    private func installPrerequisites(_ specs: [String], title: String) {
        let safe = #/^[A-Za-z0-9@._+\-]+$/#
        var formulas: [String] = [], casks: [String] = [], commands: [[String]] = []
        for spec in specs {
            if spec.hasPrefix("open:"), let url = URL(string: String(spec.dropFirst(5))) { NSWorkspace.shared.open(url); continue }
            if spec.hasPrefix("brew:"), (try? safe.wholeMatch(in: String(spec.dropFirst(5)))) != nil { formulas.append(String(spec.dropFirst(5))); continue }
            if spec.hasPrefix("cask:"), (try? safe.wholeMatch(in: String(spec.dropFirst(5)))) != nil { casks.append(String(spec.dropFirst(5))); continue }
            if spec.hasPrefix("run:") {
                let words = spec.dropFirst(4).split(separator: " ").map(String.init)
                if !words.isEmpty, !commands.contains(words) { commands.append(words) }
            }
        }
        var steps: [[String]] = []
        if !formulas.isEmpty || !casks.isEmpty {
            guard let brew = Self.homebrew else {
                errorMessage = String(localized: "Homebrew is not installed: install it from brew.sh first (one command in Terminal), then try again.")
                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                return
            }
            if !formulas.isEmpty { steps.append([brew, "install"] + formulas) }
            if !casks.isEmpty { steps.append([brew, "install", "--cask"] + casks) }
        }
        for words in commands {
            if words.first == "./aethernx", let engine { steps.append([engine.appending(path: "aethernx").path] + words.dropFirst()) } else { steps.append(["/usr/bin/env"] + words) }
        }
        guard !steps.isEmpty, job?.isRunning != true else { return }
        // One job, the steps one after the other: a shell runs them, each word quoted, and stops at the first that fails
        let script = steps.map { $0.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ") }.joined(separator: " && ")
        startSetupJob(Job(title: title, gameID: nil, target: nil), script: script)
    }
}
