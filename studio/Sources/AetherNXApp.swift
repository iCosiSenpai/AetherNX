import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Data Models

struct ScanResponse: Codable, Sendable {
    let games: [DiscoveredGame]
}

struct GameModuleInfo: Codable, Hashable, Sendable {
    let name: String
    let code_size: Int?
    let functions: Int?
    let dynamic_symbols: Int?
}

struct DecompManifest: Codable, Hashable, Sendable {
    let engine: String?
    let title_id: String?
    let total_functions: Int?
    let total_dynamic_symbols: Int?
    let modules: [GameModuleInfo]?
}

struct PackageBaseInfo: Codable, Hashable, Sendable {
    let name: String?
    let path: String?
    let size_bytes: Int64?
}

struct PackageUpdateInfo: Codable, Hashable, Sendable {
    let version: String
    let version_int: Int?
    let name: String
    let path: String
    let size_bytes: Int64
}

struct PackageDLCInfo: Codable, Hashable, Sendable {
    let title_id: String
    let index: Int
    let version: String
    let name: String
    let path: String
    let size_bytes: Int64
}

struct DiscoveredGame: Identifiable, Codable, Hashable, Sendable {
    var id: String { title_id + "::" + directory }
    let directory: String
    let work_dir: String?
    let save_dir: String?
    let log_file: String?
    let title_id: String
    let name: String
    let has_base: Bool
    let is_archived_only: Bool?
    let archive_files: [String]?
    let compressed_packages: [String]?
    let update_versions: [Int]
    let dlc_ids: [String]
    let build_exists: Bool
    let decomp_ready: Bool
    let recomp_ready: Bool?
    let lifted_chunks: Int?
    let mac_app: String?
    let ipa_file: String?
    let shader_count: Int
    let modules: [String]
    let decomp_manifest: DecompManifest?
    let base: PackageBaseInfo?
    let updates: [PackageUpdateInfo]?
    let dlcs: [PackageDLCInfo]?
}

enum PipelineTab: String, CaseIterable, Identifiable {
    case studio = "Libreria & Porting"
    case setup = "Chiavi, Firmware & File"
    case decomp = "Decomp & Static Recomp"
    case skills = "AI Skills (15)"
    case ecosystem = "Ecosistema & Copyright (31)"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .studio: return "gamecontroller.fill"
        case .setup: return "key.radiowaves.forward.fill"
        case .decomp: return "cpu.fill"
        case .skills: return "sparkles"
        case .ecosystem: return "shippingbox.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .studio: return "COMP • RECOMP • DECOMP"
        case .setup: return "prod.keys • Firmware • NSP/DLC"
        case .decomp: return "Funzioni • Simboli • C11/C++20"
        case .skills: return "15 Skill per Claude & Codex"
        case .ecosystem: return "31 Repo Forkate & Licenze"
        }
    }
}

struct RepoEntry: Identifiable {
    let id = UUID()
    let name: String
    let upstream: String
    let fork: String
    let category: String
    let license: String
    let role: String
}

struct SkillEntry: Identifiable {
    let id = UUID()
    let slug: String
    let title: String
    let source: String
    let summary: String
}

// MARK: - ViewModel

@MainActor
final class AetherNXViewModel: ObservableObject {
    @Published var games: [DiscoveredGame] = []
    @Published var selectedGameID: String?
    @Published var selectedTab: PipelineTab = .studio
    @Published var isScanning: Bool = false
    @Published var isRunningJob: Bool = false
    @Published var activeJobTitle: String = ""
    @Published var consoleLines: [String] = [
        "[AetherNX] Universal Switch Decomp • Static Recomp • Native Apple Silicon Studio v1.1 PRO initialized.",
        "[AetherNX] Tri-Pipeline ready: COMP (HorizonNative/Mach-O) | RECOMP (nxrt/SwitchRecomp/mush8) | DECOMP (open-ead/sead/nnheaders)."
    ]

    // Paths & Environment Configuration
    @Published var customLibraryPath: String = "~/Games"
    @Published var extraGamePaths: [String] = []
    @Published var prodKeysPath: String = "~/.switch/prod.keys"
    @Published var titleKeysPath: String = "~/.switch/title.keys"
    @Published var firmwarePath: String = "~/.switch/firmware.zip"

    // Advanced Build & Runtime Options
    @Published var gpuBackend: String = "none"
    @Published var packageOverride: String = "latest" // "latest" or "v0" or specific "vXXXXX"
    @Published var iosRomfsMode: String = "bundle"    // "bundle" (All-in-One IPA) or "separate" (Slim <250MB IPA for Free Apple ID / SideStore)
    @Published var gameLanguage: String = "en-US"
    @Published var enableMetalHUD: Bool = false
    @Published var keepExtracted: Bool = true
    @Published var forceReExtract: Bool = false
    @Published var forceReRewrite: Bool = false
    @Published var forceReTranslate: Bool = false

    let rootDir: String = {
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent().path
        if FileManager.default.isExecutableFile(atPath: "\(bundleParent)/aethernx") {
            return bundleParent
        }
        return "~/AetherNX"
    }()

    private var runningProcess: Process?

    var selectedGame: DiscoveredGame? {
        games.first(where: { $0.id == selectedGameID }) ?? games.first
    }

    var logoImage: NSImage? {
        if let resURL = Bundle.main.url(forResource: "aethernx-logo", withExtension: "png"),
           let img = NSImage(contentsOf: resURL) {
            return img
        }
        let fallbackPath = "\(rootDir)/assets/aethernx-logo.png"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return NSImage(contentsOfFile: fallbackPath)
        }
        return nil
    }

    var prodKeysStatus: (valid: Bool, count: Int, hasHeaderKey: Bool) {
        guard FileManager.default.isReadableFile(atPath: prodKeysPath),
              let content = try? String(contentsOfFile: prodKeysPath, encoding: .utf8) else {
            return (false, 0, false)
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") && $0.contains("=") }
        let hasHeader = lines.contains { $0.hasPrefix("header_key") }
        return (lines.count > 10 && hasHeader, lines.count, hasHeader)
    }

    var titleKeysStatus: (valid: Bool, count: Int) {
        guard FileManager.default.isReadableFile(atPath: titleKeysPath),
              let content = try? String(contentsOfFile: titleKeysPath, encoding: .utf8) else {
            return (false, 0)
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0.contains("=") }
        return (!lines.isEmpty, lines.count)
    }

    var firmwareStatus: (valid: Bool, label: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: firmwarePath) else {
            return (false, "Non configurato")
        }
        if let attrs = try? fm.attributesOfItem(atPath: firmwarePath),
           let sz = attrs[.size] as? Int64 {
            let formatted = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
            let name = URL(fileURLWithPath: firmwarePath).lastPathComponent
            return (true, "\(name) (\(formatted))")
        }
        return (true, URL(fileURLWithPath: firmwarePath).lastPathComponent)
    }

    let availableLanguages: [(code: String, label: String)] = [
        ("en-US", "English (US) — Default"),
        ("it", "Italiano (it)"),
        ("en-GB", "English (UK)"),
        ("ja", "日本語 (ja)"),
        ("fr", "Français (fr)"),
        ("de", "Deutsch (de)"),
        ("es", "Español (es)"),
        ("nl", "Nederlands (nl)"),
        ("ko", "한국어 (ko)"),
        ("zh-Hans", "简体中文 (zh-Hans)"),
        ("zh-Hant", "繁體中文 (zh-Hant)")
    ]

    let repositories: [RepoEntry] = [
        RepoEntry(name: "HorizonNative / nxnative", upstream: "seedds/nxnative", fork: "iCosiSenpai/HorizonNative", category: "Native Engine (COMP)", license: "MIT", role: "ARM64 NSO->Mach-O rewriter, HOS kernel/service emulation, Maxwell->Metal shader compiler"),
        RepoEntry(name: "nxrt", upstream: "fedebuonco/nxrt", fork: "iCosiSenpai/nxrt", category: "Static Recomp (RECOMP)", license: "Unlicense", role: "Universal C11 runtime & AArch64->C11 lifter for statically recompiled Switch binaries"),
        RepoEntry(name: "SwitchRecomp", upstream: "bgyss/SwitchRecomp", fork: "iCosiSenpai/SwitchRecomp", category: "Static Recomp (RECOMP)", license: "MIT", role: "N64Recomp-style ARM64 Switch static recompiler to C++20/Metal"),
        RepoEntry(name: "mush8", upstream: "Catchingalls/mush8", fork: "iCosiSenpai/mush8", category: "Static Recomp (RECOMP)", license: "MIT / Apache-2.0", role: "Rust static NSO lifter, HLE runtime, NVN->wgpu/Metal backend"),
        RepoEntry(name: "LASRecomp", upstream: "peiikai/LASRecomp", fork: "iCosiSenpai/LASRecomp", category: "Static Recomp Profile", license: "MIT", role: "Zelda: Link's Awakening Switch static recompilation profile & tools"),
        RepoEntry(name: "EoWRecomp", upstream: "Nycolazs/EoWRecomp", fork: "iCosiSenpai/EoWRecomp", category: "Static Recomp Profile", license: "MIT", role: "Zelda: Echoes of Wisdom Switch static recompilation profile & tools"),
        RepoEntry(name: "AC-Recomp", upstream: "swaymun/AC-Recomp", fork: "iCosiSenpai/AC-Recomp", category: "Static Recomp Profile", license: "MIT", role: "Astral Chain static recompilation tools (62,566 lifted functions)"),
        RepoEntry(name: "smo-recomp", upstream: "Coz-0/smo-recomp", fork: "iCosiSenpai/smo-recomp", category: "Static Recomp Profile", license: "MIT", role: "Super Mario Odyssey static recompilation profile"),
        RepoEntry(name: "SwitchStaticRecompiler", upstream: "kahoot-ut/SwitchStaticRecompiler", fork: "iCosiSenpai/SwitchStaticRecompiler", category: "Static Recomp (RECOMP)", license: "Source-Available", role: "Capstone/Keystone AArch64 instruction lifter"),
        RepoEntry(name: "OdysseyDecomp", upstream: "MonsterDruide1/OdysseyDecomp", fork: "iCosiSenpai/OdysseyDecomp", category: "Clean-Room Decomp", license: "MIT / Clean-Room", role: "Super Mario Odyssey matching C++17 decompilation infrastructure"),
        RepoEntry(name: "botw", upstream: "zeldaret/botw", fork: "iCosiSenpai/botw", category: "Clean-Room Decomp", license: "Unlicense", role: "Breath of the Wild Switch 1.5.0 matching C++ decompilation"),
        RepoEntry(name: "dread-decomp", upstream: "var-flotsam/dread-decomp", fork: "iCosiSenpai/dread-decomp", category: "Clean-Room Decomp", license: "MIT", role: "Metroid Dread matching decompilation & IDA/Ghidra tooling"),
        RepoEntry(name: "sead", upstream: "open-ead/sead", fork: "iCosiSenpai/sead", category: "SDK & Engine Headers", license: "MIT", role: "Open-source Nintendo EAD standard library headers & containers"),
        RepoEntry(name: "nnheaders", upstream: "open-ead/nnheaders", fork: "iCosiSenpai/nnheaders", category: "SDK & Engine Headers", license: "MIT", role: "Reverse-engineered Nintendo SDK (nn::*) C++ headers"),
        RepoEntry(name: "Game-Decompilation-Skill-For-Claude", upstream: "lemiur/Game-Decompilation-Skill-For-Claude", fork: "iCosiSenpai/Game-Decompilation-Skill-For-Claude", category: "AI Decomp Skill", license: "MIT", role: "Matching decompilation & native platform porting skill suite"),
        RepoEntry(name: "decomp-skills", upstream: "Ketbome/decomp-skills", fork: "iCosiSenpai/decomp-skills", category: "AI Decomp Skill", license: "MIT", role: "Multi-agent matching decomp skills (orchestrator, matcher, permuter)"),
        RepoEntry(name: "ns-game-apple-arm-port", upstream: "realskyrin/ns-game-apple-arm-port", fork: "iCosiSenpai/ns-game-apple-arm-port", category: "AI Porting Skill", license: "MIT", role: "End-to-end Switch NSP -> macOS/iOS native port automation skill"),
        RepoEntry(name: "switch-port-to-apple", upstream: "yokeyhh/switch-port-to-apple", fork: "iCosiSenpai/switch-port-to-apple", category: "AI Porting Skill", license: "MIT", role: "Automated Switch-to-Apple Silicon diagnosis & porting skill"),
        RepoEntry(name: "decompile-skill", upstream: "coyang/decompile-skill", fork: "iCosiSenpai/decompile-skill", category: "AI Decomp Skill", license: "MIT", role: "Evidence-driven C/C++ reconstruction from Ghidra/IDA exports"),
        RepoEntry(name: "re-skill", upstream: "vgrichina/re-skill", fork: "iCosiSenpai/re-skill", category: "AI Decomp Skill", license: "MIT", role: "Ghidra headless CLI reverse-engineering skill"),
        RepoEntry(name: "gba-matching-decomp-skill", upstream: "FacundoMainere/gba-matching-decomp-skill", fork: "iCosiSenpai/gba-matching-decomp-skill", category: "AI Decomp Skill", license: "MIT", role: "Byte-matching decomp loop patterns & asm-differ integration"),
        RepoEntry(name: "NX2Apple / NX Play", upstream: "LNPANDY/NX2Apple", fork: "iCosiSenpai/NX2Apple", category: "Frontend & Launcher", license: "GPL-3.0", role: "SwiftUI macOS launcher & compatibility badge browser"),
        RepoEntry(name: "LumaNX", upstream: "Xc1Ym/LumaNX", fork: "iCosiSenpai/LumaNX", category: "Frontend & Launcher", license: "MIT", role: "Cross-platform macOS & iOS SwiftUI game library manager"),
        RepoEntry(name: "NxLibrary", upstream: "Bium23/NxLibrary", fork: "iCosiSenpai/NxLibrary", category: "Frontend & Launcher", license: "MIT", role: "macOS native library frontend with Ryujinx fallback"),
        RepoEntry(name: "nx-os", upstream: "tripathishubham1/nx-os", fork: "iCosiSenpai/nx-os", category: "Frontend & Launcher", license: "MIT", role: "Switch OS style console launcher for macOS"),
        RepoEntry(name: "switch2mac", upstream: "azmasm/switch2mac", fork: "iCosiSenpai/switch2mac", category: "Native Wrapper", license: "GPL-3.0", role: "macOS helper wrapper for HorizonNative pipelines"),
        RepoEntry(name: "nx-native-wrapper", upstream: "varyform/nx-native-wrapper", fork: "iCosiSenpai/nx-native-wrapper", category: "Native Wrapper", license: "MIT", role: "Menu-driven interactive CLI wrapper for Switch ports"),
        RepoEntry(name: "nxnative-gui", upstream: "jamescastells/nxnative-gui", fork: "iCosiSenpai/nxnative-gui", category: "Frontend & Launcher", license: "MIT", role: "macOS GUI builder for HorizonNative"),
        RepoEntry(name: "MacNativeGames", upstream: "ly05010419/MacNativeGames", fork: "iCosiSenpai/MacNativeGames", category: "Community Database", license: "MIT", role: "Compatibility matrix & per-title configuration profiles"),
        RepoEntry(name: "kartnative", upstream: "pahorema/kartnative", fork: "iCosiSenpai/kartnative", category: "Title Profile", license: "GPL-3.0", role: "Mario Kart 8 Deluxe specialized native build scripts"),
        RepoEntry(name: "nxnative-tv-builder", upstream: "ltomo2/nxnative-tv-builder", fork: "iCosiSenpai/nxnative-tv-builder", category: "Apple TV Porting", license: "MIT", role: "Apple TV (tvOS ARM64) native build extension")
    ]

    let skills: [SkillEntry] = [
        SkillEntry(slug: "aethernx-universal", title: "AetherNX Universal Tri-Pipeline", source: "AetherNX Core", summary: "Master orchestrator combining COMP (Mach-O), RECOMP (nxrt/SwitchRecomp), and DECOMP (nnheaders/sead) with Base + Update + DLC merging."),
        SkillEntry(slug: "matching-decomp", title: "Matching Decompilation", source: "lemiur/Game-Decompilation-Skill-For-Claude", summary: "Byte-accurate C/C++ function matching workflow, compiler flag discovery, and object diffing."),
        SkillEntry(slug: "native-platform-porting", title: "Native Platform Porting", source: "lemiur/Game-Decompilation-Skill-For-Claude", summary: "Architecture for replacing proprietary SDK/graphics/audio layers with native Metal/SDL/CoreAudio backends."),
        SkillEntry(slug: "orchestrator", title: "Decomp Orchestrator", source: "Ketbome/decomp-skills", summary: "Coordinates multi-agent function decompilation queues and tracks TU matching percentages."),
        SkillEntry(slug: "matcher", title: "Function Matcher", source: "Ketbome/decomp-skills", summary: "Iterative assembly diffing and register allocation alignment for clang/LLVM targets."),
        SkillEntry(slug: "permute", title: "Decomp Permuter", source: "Ketbome/decomp-skills", summary: "Automated AST permutation to resolve stubborn instruction reordering mismatches."),
        SkillEntry(slug: "decomp-code-rules", title: "Decomp Code Rules", source: "Ketbome/decomp-skills", summary: "Enforces clean-room C++17 idioms, Nintendo EAD/sead naming conventions, and fixed-size types."),
        SkillEntry(slug: "helper-recovery", title: "Compiler Helper Recovery", source: "Ketbome/decomp-skills", summary: "Identifies compiler-generated intrinsics, soft-float helpers, and C++ ABI thunks."),
        SkillEntry(slug: "wall-identifier", title: "Decomp Wall Identifier", source: "Ketbome/decomp-skills", summary: "Detects inline header mismatches, struct layout shifts, and compiler version discrepancies."),
        SkillEntry(slug: "ns-game-apple-arm-port", title: "NS Game Apple ARM Port", source: "realskyrin/ns-game-apple-arm-port", summary: "Automates NSP extraction, NSO->Mach-O binary rewriting, and Metal shader compilation."),
        SkillEntry(slug: "switch-port-to-apple", title: "Switch Port to Apple", source: "yokeyhh/switch-port-to-apple", summary: "Diagnoses crash logs, missing HOS service stubs, and shader translation edge cases."),
        SkillEntry(slug: "switch-static-recomp", title: "Switch Static Recomp", source: "AetherNX / SwitchRecomp / nxrt", summary: "Generates C11/C++20 static recompilation workspaces and nxrt_game_desc descriptors."),
        SkillEntry(slug: "evidence-decompile", title: "Evidence-Driven Decompile", source: "coyang/decompile-skill", summary: "Reconstructs maintainable C/C++ from disassembly, call graphs, and string/xref tables."),
        SkillEntry(slug: "re-skill", title: "Headless Ghidra RE", source: "vgrichina/re-skill", summary: "Drives Ghidra headless analyzers to export symbols, vtables, and decompiled pseudocode."),
        SkillEntry(slug: "gba-matching-decomp-skill", title: "Matching Loop & Diff Patterns", source: "FacundoMainere/gba-matching-decomp-skill", summary: "Structured diffing strategies adaptable to ARM/AArch64 decompilation projects.")
    ]

    init() {
        autoDetectKeysAndFirmware()
        scanGames()
    }

    func appendLog(_ text: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        consoleLines.append(contentsOf: lines)
        if consoleLines.count > 800 {
            consoleLines.removeFirst(consoleLines.count - 800)
        }
    }

    func autoDetectKeysAndFirmware() {
        let fm = FileManager.default
        let prodCandidates = [
            "~/.switch/prod.keys",
            "\(NSHomeDirectory())/.switch/prod.keys"
        ]
        if let found = prodCandidates.first(where: { fm.isReadableFile(atPath: $0) }) {
            prodKeysPath = found
        }

        let titleCandidates = [
            "~/.switch/title.keys",
            "\(NSHomeDirectory())/.switch/title.keys"
        ]
        if let found = titleCandidates.first(where: { fm.isReadableFile(atPath: $0) }) {
            titleKeysPath = found
        }

        let fwDir = "~/.switch"
        if let items = try? fm.contentsOfDirectory(atPath: fwDir) {
            if let fwZip = items.sorted().last(where: { $0.lowercased().hasPrefix("firmware") }) {
                firmwarePath = "\(fwDir)/\(fwZip)"
            }
        }
    }

    // MARK: - File Dialogs & File Management

    func pickFile(title: String, allowedExtensions: [String] = [], canChooseDirectories: Bool = false, canChooseFiles: Bool = true) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false
        if !allowedExtensions.isEmpty {
            panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func browseProdKeys() {
        if let url = pickFile(title: "Seleziona il file prod.keys della tua Switch", canChooseDirectories: false, canChooseFiles: true) {
            prodKeysPath = url.path
            appendLog("[Config] Impostato prod.keys: \(url.path) (\(prodKeysStatus.count) chiavi rilevate)")
        }
    }

    func browseTitleKeys() {
        if let url = pickFile(title: "Seleziona il file title.keys (opzionale)", canChooseDirectories: false, canChooseFiles: true) {
            titleKeysPath = url.path
            appendLog("[Config] Impostato title.keys: \(url.path)")
        }
    }

    func browseFirmware() {
        if let url = pickFile(title: "Seleziona il Firmware Switch (.zip o cartella NCA estratta)", canChooseDirectories: true, canChooseFiles: true) {
            firmwarePath = url.path
            appendLog("[Config] Impostato Firmware Switch: \(url.path)")
        }
    }

    func browseLibraryFolder() {
        if let url = pickFile(title: "Seleziona la cartella principale dei giochi Switch", canChooseDirectories: true, canChooseFiles: false) {
            customLibraryPath = url.path
            appendLog("[Config] Impostata cartella libreria: \(url.path)")
            scanGames()
        }
    }

    func addGameFolder() {
        if let url = pickFile(title: "Aggiungi una cartella gioco Switch (.nsp / .xci / .nsz / .zip / .rar / .7z)", canChooseDirectories: true, canChooseFiles: false) {
            if !extraGamePaths.contains(url.path) {
                extraGamePaths.append(url.path)
            }
            appendLog("[Library] Aggiunta cartella gioco: \(url.path)")
            scanGames()
        }
    }

    func unpackArchivePrompt() {
        let panel = NSOpenPanel()
        panel.title = "Seleziona un archivio (.zip, .rar, .7z, .tar.*, .nsz, .xcz) o una cartella da scompattare nella Libreria"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            var args = ["unpack", url.path, "--decompress-nsz"]
            if FileManager.default.isReadableFile(atPath: prodKeysPath) {
                args += ["-k", prodKeysPath]
            }
            runPipelineCommand(
                title: "Unpack & Decompress (\(url.lastPathComponent))",
                args: args
            )
        }
    }

    func unpackGameArchives(for game: DiscoveredGame, decompressNSZ: Bool = true) {
        var args = ["unpack", game.directory]
        if decompressNSZ {
            args.append("--decompress-nsz")
        }
        if FileManager.default.isReadableFile(atPath: prodKeysPath) {
            args += ["-k", prodKeysPath]
        }
        runPipelineCommand(
            title: "Scompatta Archivi & NSZ (\(game.name))",
            args: args
        )
    }

    func importPackageIntoSelectedGame() {
        guard let game = selectedGame else {
            appendLog("[Warn] Seleziona prima un gioco nella sidebar per importare un file Base / Update / DLC.")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Importa file .nsp / .xci / .nsz (Base Game, Ultimo Update o DLC) in \(game.name)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let fm = FileManager.default
            var imported = 0
            for srcURL in panel.urls {
                let dstURL = URL(fileURLWithPath: game.directory).appendingPathComponent(srcURL.lastPathComponent)
                if srcURL.standardizedFileURL == dstURL.standardizedFileURL {
                    continue
                }
                do {
                    if fm.fileExists(atPath: dstURL.path) {
                        try fm.removeItem(at: dstURL)
                    }
                    try fm.copyItem(at: srcURL, to: dstURL)
                    imported += 1
                    appendLog("[File Manager] Copiato \(srcURL.lastPathComponent) -> \(game.directory)")
                } catch {
                    appendLog("[Errore] Impossibile copiare \(srcURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if imported > 0 {
                scanGames()
            }
        }
    }

    func cleanShaderCache(for game: DiscoveredGame) {
        let work = game.work_dir ?? "\(game.directory)/\(game.title_id)_build"
        let shaderCache = "\(work)/shader"
        do {
            if FileManager.default.fileExists(atPath: shaderCache) {
                try FileManager.default.removeItem(atPath: shaderCache)
                appendLog("[File Manager] Cache shader Metal rimossa: \(shaderCache)")
            } else {
                appendLog("[File Manager] Nessuna cache shader presente in \(shaderCache)")
            }
            scanGames()
        } catch {
            appendLog("[Errore] Impossibile pulire cache shader: \(error.localizedDescription)")
        }
    }

    func cleanBuildFolder(for game: DiscoveredGame) {
        let work = game.work_dir ?? "\(game.directory)/\(game.title_id)_build"
        do {
            if FileManager.default.fileExists(atPath: work) {
                try FileManager.default.removeItem(atPath: work)
                appendLog("[File Manager] Cartella build rimossa: \(work)")
            } else {
                appendLog("[File Manager] Nessuna cartella build presente in \(work)")
            }
            scanGames()
        } catch {
            appendLog("[Errore] Impossibile rimuovere cartella build: \(error.localizedDescription)")
        }
    }

    // MARK: - Library Scan & Pipeline Execution

    func scanGames() {
        guard !isScanning else { return }
        isScanning = true
        let cli = "\(rootDir)/aethernx"
        let scanDirs = [customLibraryPath] + extraGamePaths

        Task {
            let result: Result<[DiscoveredGame], Error> = await Task.detached {
                let proc = Process()
                let outPipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: cli)
                proc.arguments = ["scan"] + scanDirs + ["--json"]
                proc.standardOutput = outPipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    let response = try JSONDecoder().decode(ScanResponse.self, from: data)
                    return .success(response.games)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let decoded):
                self.games = decoded
                if self.selectedGameID == nil || !decoded.contains(where: { $0.id == self.selectedGameID }) {
                    self.selectedGameID = decoded.first?.id
                }
                self.isScanning = false
                self.appendLog("[Scan] Rilevati \(decoded.count) titoli Switch nella libreria.")
            case .failure(let error):
                self.isScanning = false
                self.appendLog("[Error] Scansione libreria fallita: \(error.localizedDescription)")
            }
        }
    }

    func runPipelineCommand(title: String, args: [String]) {
        guard !isRunningJob else {
            appendLog("[Warn] Un job è già in esecuzione: \(activeJobTitle)")
            return
        }
        isRunningJob = true
        activeJobTitle = title
        appendLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        appendLog("▶ Avvio Job: \(title)")
        appendLog("  $ ./aethernx \(args.joined(separator: " "))")

        let cli = "\(rootDir)/aethernx"
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: rootDir)
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.runningProcess = proc

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendLog(chunk)
            }
        }

        proc.terminationHandler = { [weak self] finishedProc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self = self else { return }
                self.isRunningJob = false
                self.activeJobTitle = ""
                self.runningProcess = nil
                self.appendLog("✔ Job completato (exit code \(finishedProc.terminationStatus))")
                self.scanGames()
            }
        }

        do {
            try proc.run()
        } catch {
            isRunningJob = false
            activeJobTitle = ""
            appendLog("[Error] Impossibile avviare il job: \(error.localizedDescription)")
        }
    }

    func cancelRunningJob() {
        runningProcess?.terminate()
        appendLog("[Warn] Inviato SIGTERM al processo in esecuzione.")
    }

    private func buildCommonFlags() -> [String] {
        var flags: [String] = ["-k", prodKeysPath, "--gpu", gpuBackend, "--progress", "lines"]
        if packageOverride != "latest" {
            flags += ["--package", packageOverride]
        }
        if keepExtracted {
            flags.append("--keep-extracted")
        }
        if forceReExtract {
            flags.append("--re-extract")
        }
        if forceReRewrite {
            flags.append("--re-rewrite")
        }
        if forceReTranslate {
            flags.append("--re-translate")
        }
        return flags
    }

    func buildMacApp(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Build Native macOS App (\(game.name))",
            args: ["build-mac", game.directory] + buildCommonFlags()
        )
    }

    func buildIOSIPA(for game: DiscoveredGame) {
        if iosRomfsMode == "separate" {
            buildIOSSlimIPA(for: game)
        } else {
            runPipelineCommand(
                title: "Build Native iOS/iPadOS All-in-One IPA (\(game.name))",
                args: ["build-ios", game.directory] + buildCommonFlags()
            )
        }
    }

    func buildIOSSlimIPA(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Build Slim Zero-JIT iOS/iPadOS IPA for Free Apple ID / SideStore (\(game.name))",
            args: ["build-ios-slim", game.directory] + buildCommonFlags()
        )
    }

    func prepareXcode(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Prepare Xcode Project (\(game.name))",
            args: ["prepare-xcode", game.directory] + buildCommonFlags()
        )
    }

    func initDecompWorkspace(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Generate Decomp & Static Recomp Workspace (\(game.name))",
            args: ["decomp-init", game.directory]
        )
    }

    func runStaticLifter(for game: DiscoveredGame, module: String = "main") {
        runPipelineCommand(
            title: "Lift ExeFS/\(module) to C11 via nxrt (\(game.name))",
            args: ["lift", game.directory, "--module", module]
        )
    }

    func runDoctorAudit() {
        runPipelineCommand(
            title: "AetherNX Full Repository & Toolchain Audit",
            args: ["doctor"]
        )
    }

    func launchMacApp(_ path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var env = ProcessInfo.processInfo.environment
        env["DM_LANG"] = gameLanguage
        if enableMetalHUD {
            env["MTL_HUD_ENABLED"] = "1"
        }
        proc.environment = env
        proc.arguments = [path]
        try? proc.run()
        appendLog("[Launch] Avviato \(URL(fileURLWithPath: path).lastPathComponent) (DM_LANG=\(gameLanguage), MetalHUD=\(enableMetalHUD ? "ON" : "OFF"))")
    }

    func revealInFinder(_ path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: URL(fileURLWithPath: path).deletingLastPathComponent().path)
        } else {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if fm.fileExists(atPath: parent) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parent)
            } else {
                appendLog("[Info] Il percorso non esiste ancora: \(path)")
            }
        }
    }
}

// MARK: - Root Split View

struct ContentView: View {
    @StateObject private var vm = AetherNXViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(vm: vm)
                .frame(minWidth: 300, idealWidth: 315, maxWidth: 350)
        } detail: {
            VStack(spacing: 0) {
                TopHeaderBar(vm: vm)
                Divider()
                switch vm.selectedTab {
                case .studio:
                    StudioMainView(vm: vm)
                case .setup:
                    SetupKeysFirmwareView(vm: vm)
                case .decomp:
                    DecompWorkspaceView(vm: vm)
                case .skills:
                    SkillsCatalogView(vm: vm)
                case .ecosystem:
                    EcosystemCreditsView(vm: vm)
                }
                Divider()
                ConsoleDrawerView(vm: vm)
            }
        }
        .frame(minWidth: 1200, minHeight: 780)
    }
}

// MARK: - Custom Sidebar (Fixed Active Tab Highlighting + Game Cards)

struct SidebarView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 1. Brand Logo Header
            HStack(spacing: 12) {
                if let logo = vm.logoImage {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .shadow(color: .cyan.opacity(0.35), radius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: "cpu.fill").font(.title2).foregroundStyle(.white))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AETHERNX")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        BadgePill(text: "PRO v1.1", color: .cyan)
                    }
                    Text("Switch Decomp • Recomp • Mac/iOS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(vm.prodKeysStatus.valid ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(vm.prodKeysStatus.valid ? "prod.keys (\(vm.prodKeysStatus.count))" : "keys mancanti")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(vm.firmwareStatus.valid ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(vm.firmwareStatus.valid ? "FW OK" : "No FW")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 2. Navigation Tabs (Explicit Active Pill Selection)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SEZIONI STUDIO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)

                        ForEach(PipelineTab.allCases) { tab in
                            let isSelected = (vm.selectedTab == tab)
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    vm.selectedTab = tab
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(isSelected ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.12))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: tab.icon)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tab.rawValue)
                                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        Text(tab.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            isSelected
                                            ? AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.blue], startPoint: .leading, endPoint: .trailing))
                                            : AnyShapeStyle(Color.clear)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.cyan.opacity(0.55) : Color.clear, lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    // 3. Switch Games Library Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("GIOCHI SWITCH (\(vm.games.count))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                vm.unpackArchivePrompt()
                            } label: {
                                Label("Scompatta", systemImage: "archivebox.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.orange)
                            .help("Scompatta archivi .zip / .rar / .7z / .nsz nella libreria")

                            Button {
                                vm.addGameFolder()
                            } label: {
                                Label("Aggiungi", systemImage: "plus.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .help("Aggiungi una cartella gioco Switch (.nsp / .xci / .nsz)")
                        }
                        .padding(.horizontal, 8)

                        ForEach(vm.games) { game in
                            let isGameSelected = (vm.selectedGame?.id == game.id)
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    vm.selectedGameID = game.id
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isGameSelected ? Color.cyan : Color.clear)
                                        .frame(width: 4, height: 48)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(game.name)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            if game.mac_app != nil {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundStyle(.green)
                                                    .help("App macOS nativa pronta")
                                            }
                                        }
                                        Text(game.title_id)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 4) {
                                            BadgePill(text: game.has_base ? "BASE" : "NO BASE", color: game.has_base ? .blue : .red)
                                            if let maxUpd = game.update_versions.max() {
                                                BadgePill(text: "UPD v\(maxUpd)", color: .purple)
                                            }
                                            if !game.dlc_ids.isEmpty {
                                                BadgePill(text: "\(game.dlc_ids.count) DLC", color: .orange)
                                            }
                                            if game.decomp_ready {
                                                BadgePill(text: "DECOMP", color: .teal)
                                            }
                                            if (game.lifted_chunks ?? 0) > 0 {
                                                BadgePill(text: "RECOMP", color: .pink)
                                            }
                                            if let cpkgs = game.compressed_packages, !cpkgs.isEmpty {
                                                BadgePill(text: "\(cpkgs.count) NSZ", color: .indigo)
                                            }
                                            if let arcs = game.archive_files, !arcs.isEmpty {
                                                BadgePill(text: "\(arcs.count) ZIP/RAR", color: .yellow)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isGameSelected ? Color.cyan.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isGameSelected ? Color.cyan.opacity(0.75) : Color.secondary.opacity(0.15), lineWidth: isGameSelected ? 1.5 : 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let appPath = game.mac_app {
                                    Button("Avvia App macOS Nativa") { vm.launchMacApp(appPath) }
                                    Divider()
                                }
                                Button("Importa File NSP/Update/DLC...") {
                                    vm.selectedGameID = game.id
                                    vm.importPackageIntoSelectedGame()
                                }
                                Button("Scompatta Archivi (.zip/.rar/.7z) & Decomprimi .NSZ") {
                                    vm.unpackGameArchives(for: game, decompressNSZ: true)
                                }
                                Button("Apri Cartella Gioco nel Finder") { vm.revealInFinder(game.directory) }
                                if let work = game.work_dir {
                                    Button("Apri Cartella Build (_build)") { vm.revealInFinder(work) }
                                }
                                if let save = game.save_dir {
                                    Button("Apri Cartella Salvataggi") { vm.revealInFinder(save) }
                                }
                                if let log = game.log_file {
                                    Button("Mostra Log di Gioco") { vm.revealInFinder(log) }
                                }
                                Divider()
                                Button("Pulisci Cache Shader Metal") { vm.cleanShaderCache(for: game) }
                                Button("Elimina Cartella Build Temporanea") { vm.cleanBuildFolder(for: game) }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Top Header Bar

struct TopHeaderBar: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(vm.selectedTab.rawValue.uppercased())
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    BadgePill(text: vm.selectedTab.subtitle, color: .indigo)
                }
                Text("Consigliato: usa sempre l'ultima versione di Gioco Base + Ultimo Update + tutti i DLC, con prod.keys e Firmware aggiornati.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isRunningJob {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(vm.activeJobTitle)
                        .font(.caption)
                        .lineLimit(1)
                    Button("Stop") {
                        vm.cancelRunningJob()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.1), in: Capsule())
            }
            Button {
                vm.selectedTab = .setup
            } label: {
                Label("Chiavi & Firmware", systemImage: "key.fill")
            }
            Button {
                vm.runDoctorAudit()
            } label: {
                Label("Audit / Doctor", systemImage: "stethoscope")
            }
            .disabled(vm.isRunningJob)
            Button {
                vm.scanGames()
            } label: {
                Label("Aggiorna Libreria", systemImage: "arrow.clockwise")
            }
            Button {
                vm.revealInFinder(vm.rootDir)
            } label: {
                Label("switch-comp", systemImage: "folder")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

// MARK: - Recommendation Callout Banner

struct BestPracticeBannerView: View {
    @ObservedObject var vm: AetherNXViewModel
    var showConfigureButton: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("Requisiti & Best Practice: Ultima Versione di Gioco, Update, DLC, prod.keys e Firmware Switch")
                    .font(.subheadline.bold())
                Text("Per garantire la massima compatibilità, il corretto funzionamento delle patch ExeFS/Mach-O, la compilazione degli shader Metal e il montaggio dei DLC, è sempre fortemente consigliato utilizzare il Gioco Base insieme all'ULTIMO Title Update disponibile e a tutti i DLC aggiornati, abbinati a prod.keys / title.keys e al Firmware della Switch aggiornati (es. 22.5.0). Tutti i file (gioco, update, DLC, chiavi e firmware) devono essere estratti o reperiti autonomamente dall'utente per conto proprio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showConfigureButton {
                Button {
                    vm.selectedTab = .setup
                } label: {
                    Label("Configura File & Chiavi", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color.indigo.opacity(0.14), Color.cyan.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Tab 1: Studio Main View (Library, Porting, Advanced Options & Quick File Management)

struct StudioMainView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        if let game = vm.selectedGame {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BestPracticeBannerView(vm: vm, showConfigureButton: true)

                    // Game Hero Card
                    HStack(alignment: .top, spacing: 16) {
                        if let logo = vm.logoImage {
                            Image(nsImage: logo)
                                .resizable()
                                .frame(width: 86, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(game.name)
                                    .font(.title.bold())
                                Text("[\(game.title_id)]")
                                    .font(.title3.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(game.directory)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                BadgePill(text: game.has_base ? "Base Game Ready" : "Base Mancante", color: game.has_base ? .blue : .red)
                                BadgePill(text: game.update_versions.isEmpty ? "Nessun Update (v0) — Consigliato Update!" : "Ultimo Update v\(game.update_versions.max() ?? 0) Attivo", color: game.update_versions.isEmpty ? .orange : .purple)
                                BadgePill(text: "\(game.dlc_ids.count) DLC Montati", color: .orange)
                                BadgePill(text: "\(game.shader_count) Shader Maxwell -> Metal", color: .mint)
                                if let chunks = game.lifted_chunks, chunks > 0 {
                                    BadgePill(text: "\(chunks) C11 Chunks", color: .pink)
                                }
                                if let cpkgs = game.compressed_packages, !cpkgs.isEmpty {
                                    BadgePill(text: "\(cpkgs.count) .NSZ/.XCZ Compressi", color: .indigo)
                                }
                                if let arcs = game.archive_files, !arcs.isEmpty {
                                    BadgePill(text: "\(arcs.count) Archivi (.zip/.rar/.7z)", color: .yellow)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            if let macApp = game.mac_app {
                                Button {
                                    vm.launchMacApp(macApp)
                                } label: {
                                    Label("Avvia App macOS Nativa", systemImage: "play.fill")
                                        .font(.headline)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.large)
                            }
                            HStack(spacing: 8) {
                                if !(game.archive_files ?? []).isEmpty || !(game.compressed_packages ?? []).isEmpty {
                                    Button {
                                        vm.unpackGameArchives(for: game, decompressNSZ: true)
                                    } label: {
                                        Label("Scompatta Archivi / .NSZ", systemImage: "archivebox.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .disabled(vm.isRunningJob)
                                }
                                Button {
                                    vm.importPackageIntoSelectedGame()
                                } label: {
                                    Label("+ Importa NSP/Update/DLC", systemImage: "plus.rectangle.on.folder.fill")
                                }
                                Button {
                                    vm.revealInFinder(game.directory)
                                } label: {
                                    Label("Cartella Gioco", systemImage: "folder.fill")
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                    // Tri-Pipeline Action Cards
                    HStack(alignment: .top, spacing: 14) {
                        PipelineActionCard(
                            title: "1. Porting Nativo Apple Silicon (COMP)",
                            subtitle: "HorizonNative AArch64 NSO->Mach-O + Metal + Zero-JIT su iOS/iPadOS",
                            icon: "apple.logo",
                            accent: .blue
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Button {
                                        vm.buildMacApp(for: game)
                                    } label: {
                                        Label("Compila App macOS (.app)", systemImage: "desktopcomputer")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(vm.isRunningJob)

                                    Button {
                                        vm.buildIOSIPA(for: game)
                                    } label: {
                                        Label("Compila IPA iOS/iPadOS", systemImage: "ipad.and.iphone")
                                    }
                                    .disabled(vm.isRunningJob)
                                }
                                HStack(spacing: 8) {
                                    Button {
                                        vm.buildIOSSlimIPA(for: game)
                                    } label: {
                                        Label("Slim IPA (<250MB • Free Apple ID)", systemImage: "iphone.and.arrow.forward")
                                    }
                                    .help("Genera un'IPA leggera Zero-JIT (<250 MB) per AltStore / SideStore / Sideloadly su account Apple gratuito; RomFS.img si copia via Finder/File")
                                    .disabled(vm.isRunningJob)

                                    Button {
                                        vm.prepareXcode(for: game)
                                    } label: {
                                        Label("Progetto Xcode", systemImage: "hammer.fill")
                                    }
                                    .disabled(vm.isRunningJob)
                                }
                            }
                        }

                        PipelineActionCard(
                            title: "2. Static Recompiler (RECOMP)",
                            subtitle: "nxrt C11 Lifter & Runtime + SwitchRecomp C++20 + mush8 Rust Crates",
                            icon: "memorychip.fill",
                            accent: .purple
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Traduce staticamente i moduli NSO AArch64 in unità C11 native (\(game.lifted_chunks ?? 0) chunk pronti).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button {
                                        vm.runStaticLifter(for: game, module: "main")
                                    } label: {
                                        Label("Lift ExeFS/main -> C11", systemImage: "bolt.horizontal.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                    .disabled(vm.isRunningJob)

                                    if (game.lifted_chunks ?? 0) > 0 {
                                        Button {
                                            vm.revealInFinder("\(game.directory)/\(game.title_id)_build/decomp_workspace/recomp/lifted_c")
                                        } label: {
                                            Label("Apri C11 Chunks", systemImage: "doc.text.magnifyingglass")
                                        }
                                    }
                                }
                            }
                        }

                        PipelineActionCard(
                            title: "3. Clean-Room Decomp (DECOMP)",
                            subtitle: "open-ead/nnheaders + sead + Capstone Harvester + 15 AI Skills",
                            icon: "magnifyingglass.circle.fill",
                            accent: .teal
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let manifest = game.decomp_manifest {
                                    Text("Mappate \(manifest.total_functions ?? 0) funzioni e \(manifest.total_dynamic_symbols ?? 0) simboli su \(manifest.modules?.count ?? 0) moduli NSO.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Estrae confini funzioni, simboli C++ demangled, CMakeLists.txt e DECOMP_REPORT.md.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button {
                                        vm.initDecompWorkspace(for: game)
                                    } label: {
                                        Label("Genera Decomp Workspace", systemImage: "gearshape.2.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.teal)
                                    .disabled(vm.isRunningJob)

                                    Button {
                                        vm.selectedTab = .decomp
                                    } label: {
                                        Label("Esplora Funzioni", systemImage: "list.bullet.rectangle")
                                    }
                                }
                            }
                        }
                    }

                    // Advanced Build & Runtime Options + File Management Bar
                    HStack(alignment: .top, spacing: 14) {
                        // Left: Build & Runtime Options
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Opzioni Avanzate di Compilazione & Avvio", systemImage: "slider.horizontal.3")
                                .font(.headline)

                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    Text("Backend GPU:").font(.caption.bold()).foregroundStyle(.secondary)
                                    Picker("", selection: $vm.gpuBackend) {
                                        Text("Nativo NVN -> Metal (Consigliato)").tag("none")
                                        Text("Ryujinx / Vulkan-on-Metal Bridge").tag("ryujinx")
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 260)
                                }
                                GridRow {
                                    Text("Versione Pacchetto:").font(.caption.bold()).foregroundStyle(.secondary)
                                    Picker("", selection: $vm.packageOverride) {
                                        Text("Automatico (Ultimo Update — Consigliato)").tag("latest")
                                        Text("Solo Gioco Base (v0)").tag("v0")
                                        ForEach(game.update_versions, id: \.self) { v in
                                            Text("Forza Update v\(v)").tag("v\(v)")
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 260)
                                }
                                GridRow {
                                    Text("Lingua Gioco (DM_LANG):").font(.caption.bold()).foregroundStyle(.secondary)
                                    Picker("", selection: $vm.gameLanguage) {
                                        ForEach(vm.availableLanguages, id: \.code) { item in
                                            Text(item.label).tag(item.code)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 260)
                                }
                                GridRow {
                                    Text("Modalità IPA iOS:").font(.caption.bold()).foregroundStyle(.secondary)
                                    Picker("", selection: $vm.iosRomfsMode) {
                                        Text("All-in-One IPA (Developer / Sideloadly)").tag("bundle")
                                        Text("Slim IPA <250MB (Free ID / SideStore / AltStore)").tag("separate")
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 260)
                                }
                            }

                            Divider()

                            HStack(spacing: 16) {
                                Toggle("Mostra Metal HUD", isOn: $vm.enableMetalHUD)
                                    .font(.caption)
                                Toggle("Mantieni Estratti", isOn: $vm.keepExtracted)
                                    .font(.caption)
                                Toggle("Forza Re-Extract", isOn: $vm.forceReExtract)
                                    .font(.caption)
                                Toggle("Forza Re-Rewrite", isOn: $vm.forceReRewrite)
                                    .font(.caption)
                                Toggle("Forza Re-Shader", isOn: $vm.forceReTranslate)
                                    .font(.caption)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                        // Right: Quick File & Directory Management
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Gestione Rapida File, Salvataggi & Cache", systemImage: "folder.badge.gearshape")
                                .font(.headline)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                Button {
                                    vm.revealInFinder(game.directory)
                                } label: {
                                    Label("Cartella NSP/DLC", systemImage: "opticaldisc.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    vm.revealInFinder(game.work_dir ?? "\(game.directory)/\(game.title_id)_build")
                                } label: {
                                    Label("Cartella _build", systemImage: "hammer.circle.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    vm.revealInFinder(game.save_dir ?? "\(NSHomeDirectory())/Library/Application Support/HorizonNative/\(game.title_id)")
                                } label: {
                                    Label("Salvataggi Gioco", systemImage: "externaldrive.fill.badge.checkmark")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    vm.revealInFinder(game.log_file ?? "\(NSHomeDirectory())/Library/Logs/HorizonNative/\(game.title_id).log")
                                } label: {
                                    Label("Log Runtime (.log)", systemImage: "doc.text.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    vm.cleanShaderCache(for: game)
                                } label: {
                                    Label("Pulisci Shader Cache", systemImage: "sparkles.rectangle.stack")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button(role: .destructive) {
                                    vm.cleanBuildFolder(for: game)
                                } label: {
                                    Label("Reset Build (_build)", systemImage: "trash")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(14)
                        .frame(width: 390, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Detailed Package File Breakdown (Base + Updates + DLCs)
                    PackageFilesBreakdownCard(vm: vm, game: game)
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView(
                "Nessun Gioco Switch Selezionato",
                systemImage: "gamecontroller",
                description: Text("Aggiungi una cartella con i tuoi file .nsp / .xci (Gioco Base + Ultimo Update + DLC) o clicca su 'Chiavi, Firmware & File'.")
            )
        }
    }
}

// MARK: - Package Files Breakdown Card

struct PackageFilesBreakdownCard: View {
    @ObservedObject var vm: AetherNXViewModel
    let game: DiscoveredGame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("File del Gioco Rilevati (Base Game + Ultimo Update + DLC)", systemImage: "shippingbox.and.arrow.backward.fill")
                    .font(.headline)
                Spacer()
                Button {
                    vm.importPackageIntoSelectedGame()
                } label: {
                    Label("Aggiungi File Update / DLC (.nsp/.xci)...", systemImage: "plus.circle")
                }
                .controlSize(.small)
            }

            VStack(spacing: 6) {
                // Base file row
                if let base = game.base, let baseName = base.name, let basePath = base.path {
                    PackageFileRow(
                        badge: "BASE v0",
                        badgeColor: .blue,
                        filename: baseName,
                        subtitle: "Title ID: \(game.title_id) • \(ByteCountFormatter.string(fromByteCount: base.size_bytes ?? 0, countStyle: .file))",
                        statusText: "Contenitore Base",
                        onReveal: { vm.revealInFinder(basePath) }
                    )
                }

                // Updates rows
                if let updates = game.updates, !updates.isEmpty {
                    let maxVer = updates.compactMap { $0.version_int }.max() ?? 0
                    ForEach(updates, id: \.path) { upd in
                        let isNewest = (upd.version_int == maxVer)
                        PackageFileRow(
                            badge: "UPDATE \(upd.version)",
                            badgeColor: isNewest ? .purple : .secondary,
                            filename: upd.name,
                            subtitle: "Patch RomFS/ExeFS • \(ByteCountFormatter.string(fromByteCount: upd.size_bytes, countStyle: .file))",
                            statusText: isNewest ? "✔ Ultimo Update (Attivo)" : "Versione precedente",
                            onReveal: { vm.revealInFinder(upd.path) }
                        )
                    }
                } else {
                    HStack {
                        Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                        Text("Nessun Title Update rilevato per questo gioco. È consigliato aggiungere l'ultimo Update .nsp disponibile per sbloccare tutte le ottimizzazioni e i DLC.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // DLC rows
                if let dlcs = game.dlcs, !dlcs.isEmpty {
                    ForEach(dlcs, id: \.path) { dlc in
                        PackageFileRow(
                            badge: "DLC #\(dlc.index)",
                            badgeColor: .orange,
                            filename: dlc.name,
                            subtitle: "Title ID: \(dlc.title_id) (\(dlc.version)) • \(ByteCountFormatter.string(fromByteCount: dlc.size_bytes, countStyle: .file))",
                            statusText: "Montato in aoc/\(dlc.index).img",
                            onReveal: { vm.revealInFinder(dlc.path) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PackageFileRow: View {
    let badge: String
    let badgeColor: Color
    let filename: String
    let subtitle: String
    let statusText: String
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BadgePill(text: badge, color: badgeColor)
                .frame(width: 95, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(statusText)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Button("Finder") {
                onReveal()
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Tab 2: Keys, Firmware & File Management View

struct SetupKeysFirmwareView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BestPracticeBannerView(vm: vm, showConfigureButton: false)

                // 1. Cryptographic Keys Section (prod.keys & title.keys)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.radiowaves.forward.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1. Chiavi Crittografiche Switch (prod.keys & title.keys)")
                                .font(.headline)
                            Text("Necessarie per decifrare i contenitori NCA, l'header_key e le key_area dei giochi, degli update e dei DLC (da estrarre autonomamente dalla propria console).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.autoDetectKeysAndFirmware()
                        } label: {
                            Label("Rileva Automaticamente", systemImage: "wand.and.stars")
                        }
                    }

                    Divider()

                    // prod.keys row
                    HStack(spacing: 10) {
                        BadgePill(
                            text: vm.prodKeysStatus.valid ? "PROD.KEYS OK (\(vm.prodKeysStatus.count) CHIAVI)" : "PROD.KEYS MANCANTE",
                            color: vm.prodKeysStatus.valid ? .green : .red
                        )
                        TextField("Percorso prod.keys...", text: $vm.prodKeysPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Sfoglia prod.keys...") {
                            vm.browseProdKeys()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Finder") {
                            vm.revealInFinder(vm.prodKeysPath)
                        }
                    }

                    // title.keys row
                    HStack(spacing: 10) {
                        BadgePill(
                            text: vm.titleKeysStatus.valid ? "TITLE.KEYS OK (\(vm.titleKeysStatus.count))" : "TITLE.KEYS OPZIONALE",
                            color: vm.titleKeysStatus.valid ? .teal : .secondary
                        )
                        TextField("Percorso title.keys (opzionale)...", text: $vm.titleKeysPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Sfoglia title.keys...") {
                            vm.browseTitleKeys()
                        }
                        Button("Finder") {
                            vm.revealInFinder(vm.titleKeysPath)
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                // 2. Switch System Firmware Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "memorychip.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("2. Firmware di Sistema Nintendo Switch (Consigliata l'Ultima Versione)")
                                .font(.headline)
                            Text("Fornisce i font di sistema (FontStandard), gli archivi condivisi e il supporto per i giochi e gli update più recenti (es. Firmware 22.5.0, da reperire autonomamente).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        BadgePill(text: vm.firmwareStatus.label, color: vm.firmwareStatus.valid ? .purple : .orange)
                    }

                    Divider()

                    HStack(spacing: 10) {
                        BadgePill(
                            text: vm.firmwareStatus.valid ? "FIRMWARE PRONTO" : "NON IMPOSTATO",
                            color: vm.firmwareStatus.valid ? .green : .orange
                        )
                        TextField("Percorso Firmware (.zip o cartella NCA)...", text: $vm.firmwarePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Sfoglia Firmware...") {
                            vm.browseFirmware()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        Button("Finder") {
                            vm.revealInFinder(vm.firmwarePath)
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                // 3. Game Library & Multi-Package Folder Management
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "externaldrive.fill.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("3. Libreria Giochi, Ultimi Update & DLC (.nsp / .xci / .nsz)")
                                .font(.headline)
                            Text("Organizza ogni gioco in una cartella contenente: 1) Gioco Base (v0), 2) Ultimo Title Update disponibile, 3) Tutti i DLC (anche in sottocartelle). AetherNX li fonde automaticamente.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.addGameFolder()
                        } label: {
                            Label("Aggiungi Cartella Gioco...", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    HStack(spacing: 10) {
                        Text("Libreria Principale:")
                            .font(.caption.bold())
                        TextField("Cartella Giochi...", text: $vm.customLibraryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Cambia Cartella...") {
                            vm.browseLibraryFolder()
                        }
                        Button("Scansiona Ora") {
                            vm.scanGames()
                        }
                        Button("Finder") {
                            vm.revealInFinder(vm.customLibraryPath)
                        }
                    }

                    if let game = vm.selectedGame {
                        Divider()
                        PackageFilesBreakdownCard(vm: vm, game: game)
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(18)
        }
    }
}

// MARK: - Tab 3: Decomp & Static Recomp Workspace View

struct DecompWorkspaceView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        if let game = vm.selectedGame {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Decompilation & Static Recompilation Workspace — \(game.name)")
                                .font(.title2.bold())
                            Text("Percorso: \(game.directory)/\(game.title_id)_build/decomp_workspace")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.runStaticLifter(for: game, module: "main")
                        } label: {
                            Label("Lift ExeFS/main -> C11 (nxrt)", systemImage: "bolt.horizontal.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(vm.isRunningJob)

                        Button {
                            vm.initDecompWorkspace(for: game)
                        } label: {
                            Label("Rigenera Decomp Workspace", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .disabled(vm.isRunningJob)
                    }

                    if let manifest = game.decomp_manifest, let modules = manifest.modules {
                        HStack(spacing: 16) {
                            StatBox(label: "Funzioni AArch64 Mappate", value: "\(manifest.total_functions ?? 0)", icon: "function")
                            StatBox(label: "Simboli Dinamici ELF", value: "\(manifest.total_dynamic_symbols ?? 0)", icon: "link")
                            StatBox(label: "Chunk C11 Static Recomp", value: "\(game.lifted_chunks ?? 0)", icon: "bolt.horizontal.fill")
                            StatBox(label: "Header SDK Collegati", value: "nnheaders + open-ead/sead", icon: "books.vertical.fill")
                        }

                        Text("Moduli Eseguibili NSO (ExeFS)")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            GridRow {
                                Text("Modulo").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Dimensione .text").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Funzioni (.eh_frame)").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Simboli Dinamici").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Azioni").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            Divider()
                            ForEach(modules, id: \.name) { mod in
                                GridRow {
                                    Text(mod.name).font(.body.monospaced().bold())
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(mod.code_size ?? 0), countStyle: .file))
                                        .font(.body.monospaced())
                                    Text("\(mod.functions ?? 0)").font(.body.monospaced())
                                    Text("\(mod.dynamic_symbols ?? 0)").font(.body.monospaced())
                                    HStack(spacing: 6) {
                                        Button("Funzioni TSV") {
                                            vm.revealInFinder("\(game.directory)/\(game.title_id)_build/decomp_workspace/functions/\(mod.name)_functions.tsv")
                                        }
                                        .controlSize(.small)
                                        Button("Simboli TSV") {
                                            vm.revealInFinder("\(game.directory)/\(game.title_id)_build/decomp_workspace/symbols/\(mod.name)_symbols.tsv")
                                        }
                                        .controlSize(.small)
                                        Button("Lift C11") {
                                            vm.runStaticLifter(for: game, module: mod.name)
                                        }
                                        .controlSize(.small)
                                        .disabled(vm.isRunningJob)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView(
                            "Decomp Workspace Non Ancora Inizializzato",
                            systemImage: "cpu",
                            description: Text("Clicca su 'Rigenera Decomp Workspace' per estrarre i confini delle funzioni, i simboli C++ demangled e lo scaffold CMake + nxrt.")
                        )
                    }
                }
                .padding(18)
            }
        }
    }
}

// MARK: - Tab 4: Skills Catalog View

struct SkillsCatalogView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Integrated AI Agent Skills (15 Skills)")
                            .font(.title2.bold())
                        Text("Installate in \(vm.rootDir)/skills e collegate in .claude/skills per Antigravity, Claude Code e Codex.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.revealInFinder("\(vm.rootDir)/skills")
                    } label: {
                        Label("Apri Cartella skills/", systemImage: "folder")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(vm.skills) { skill in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.indigo)
                                Text(skill.title)
                                    .font(.headline)
                                Spacer()
                            }
                            Text("skills/\(skill.slug)/SKILL.md")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(skill.summary)
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.85))
                            Spacer(minLength: 4)
                            HStack {
                                BadgePill(text: skill.source, color: .indigo)
                                Spacer()
                                Button("Mostra SKILL.md") {
                                    vm.revealInFinder("\(vm.rootDir)/skills/\(skill.slug)/SKILL.md")
                                }
                                .controlSize(.mini)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Tab 5: Ecosystem & Credits View

struct EcosystemCreditsView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unified Open-Source Ecosystem & Copyright Registry (31 Forked Repositories)")
                            .font(.title2.bold())
                        Text("Ogni repository è stato forkato su @iCosiSenpai e documentato in COPYRIGHT.md, PROVENANCE.md e README.md.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.revealInFinder("\(vm.rootDir)/COPYRIGHT.md")
                    } label: {
                        Label("Apri COPYRIGHT.md", systemImage: "doc.text")
                    }
                }

                ForEach(vm.repositories) { repo in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(repo.name)
                                    .font(.headline)
                                BadgePill(text: repo.category, color: .blue)
                                BadgePill(text: repo.license, color: .green)
                            }
                            Text(repo.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Upstream: \(repo.upstream)")
                                .font(.caption2.monospaced())
                            Text("Fork: \(repo.fork)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Console Drawer & Shared Components

struct ConsoleDrawerView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Pipeline Console Output", systemImage: "terminal.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Pulisci Console") {
                    vm.consoleLines.removeAll()
                }
                .controlSize(.mini)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(vm.consoleLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.9))
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.consoleLines.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 145)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PipelineActionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            content
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - App Entry

@main
struct AetherNXStudioApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "aethernx-logo", withExtension: "png"),
           let iconImg = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImg
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("AetherNX Studio PRO — Universal Switch Decomp • Recomp • Native Porting") {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
