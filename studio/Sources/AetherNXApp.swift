import SwiftUI
import AppKit
import Foundation

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

struct DiscoveredGame: Identifiable, Codable, Hashable, Sendable {
    var id: String { title_id + "::" + directory }
    let directory: String
    let title_id: String
    let name: String
    let has_base: Bool
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
}

enum PipelineTab: String, CaseIterable, Identifiable {
    case studio = "Library & Porting"
    case decomp = "Decomp & Recomp"
    case skills = "AI Skills (15)"
    case ecosystem = "Ecosystem & Credits (31 Repos)"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .studio: return "gamecontroller.fill"
        case .decomp: return "cpu.fill"
        case .skills: return "sparkles"
        case .ecosystem: return "shippingbox.fill"
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
        "[AetherNX] Universal Switch Decomp • Static Recomp • Native Apple Silicon Studio initialized.",
        "[AetherNX] Tri-Pipeline ready: COMP (HorizonNative/Mach-O) | RECOMP (nxrt/SwitchRecomp/mush8) | DECOMP (open-ead/sead/nnheaders)."
    ]
    @Published var gpuBackend: String = "none"
    @Published var customLibraryPath: String = "~/Games"
    @Published var prodKeysPath: String = "~/.switch/prod.keys"

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

    let repositories: [RepoEntry] = [
        RepoEntry(name: "HorizonNative / nxnative", upstream: "UnknownSoldier1945/HorizonNative", fork: "iCosiSenpai/HorizonNative", category: "Native Engine (COMP)", license: "GPL-3.0", role: "ARM64 NSO->Mach-O rewriter, HOS kernel/service emulation, Maxwell->Metal shader compiler"),
        RepoEntry(name: "mush8", upstream: "Catchingalls/mush8", fork: "iCosiSenpai/mush8", category: "Static Recomp (RECOMP)", license: "MIT / Apache-2.0", role: "Rust static NSO lifter, HLE runtime, NVN->wgpu/Metal backend"),
        RepoEntry(name: "SwitchRecomp", upstream: "bgyss/SwitchRecomp", fork: "iCosiSenpai/SwitchRecomp", category: "Static Recomp (RECOMP)", license: "MIT", role: "N64Recomp-style ARM64 Switch static recompiler to C++20/Metal"),
        RepoEntry(name: "nxrt", upstream: "fedebuonco/nxrt", fork: "iCosiSenpai/nxrt", category: "Static Recomp (RECOMP)", license: "Unlicense", role: "Universal C11 runtime for statically recompiled Switch binaries"),
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
        scanGames()
    }

    func appendLog(_ text: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        consoleLines.append(contentsOf: lines)
        if consoleLines.count > 600 {
            consoleLines.removeFirst(consoleLines.count - 600)
        }
    }

    func scanGames() {
        guard !isScanning else { return }
        isScanning = true
        let cli = "\(rootDir)/aethernx"
        let libPath = customLibraryPath

        Task {
            let result: Result<[DiscoveredGame], Error> = await Task.detached {
                let proc = Process()
                let outPipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: cli)
                proc.arguments = ["scan", libPath, "--json"]
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
                self.appendLog("[Scan] Found \(decoded.count) Switch title(s) in \(libPath).")
            case .failure(let error):
                self.isScanning = false
                self.appendLog("[Error] Failed to scan library: \(error.localizedDescription)")
            }
        }
    }

    func runPipelineCommand(title: String, args: [String]) {
        guard !isRunningJob else {
            appendLog("[Warn] Another pipeline job is currently active: \(activeJobTitle)")
            return
        }
        isRunningJob = true
        activeJobTitle = title
        appendLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        appendLog("▶ Starting Job: \(title)")
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
                self.appendLog("✔ Job Finished (exit code \(finishedProc.terminationStatus))")
                self.scanGames()
            }
        }

        do {
            try proc.run()
        } catch {
            isRunningJob = false
            activeJobTitle = ""
            appendLog("[Error] Could not start job: \(error.localizedDescription)")
        }
    }

    func cancelRunningJob() {
        runningProcess?.terminate()
        appendLog("[Warn] Sent SIGTERM to running job.")
    }

    func buildMacApp(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Build Native macOS App (\(game.name))",
            args: ["build-mac", game.directory, "-k", prodKeysPath, "--gpu", gpuBackend, "--progress", "lines"]
        )
    }

    func buildIOSIPA(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Build Native iOS/iPadOS IPA (\(game.name))",
            args: ["build-ios", game.directory, "-k", prodKeysPath, "--gpu", gpuBackend, "--progress", "lines"]
        )
    }

    func prepareXcode(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Prepare Xcode Project (\(game.name))",
            args: ["prepare-xcode", game.directory, "-k", prodKeysPath, "--gpu", gpuBackend, "--progress", "lines"]
        )
    }

    func initDecompWorkspace(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Generate Decomp & Static Recomp Workspace (\(game.name))",
            args: ["decomp-init", game.directory]
        )
    }

    func runStaticLifter(for game: DiscoveredGame) {
        runPipelineCommand(
            title: "Lift ExeFS/main to C11 via nxrt (\(game.name))",
            args: ["lift", game.directory, "--module", "main"]
        )
    }

    func runDoctorAudit() {
        runPipelineCommand(
            title: "AetherNX Full Repository & Toolchain Audit",
            args: ["doctor"]
        )
    }

    func launchMacApp(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = AetherNXViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(vm: vm)
                .frame(minWidth: 275)
        } detail: {
            VStack(spacing: 0) {
                TopHeaderBar(vm: vm)
                Divider()
                switch vm.selectedTab {
                case .studio:
                    StudioMainView(vm: vm)
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
        .frame(minWidth: 1140, minHeight: 750)
    }
}

struct SidebarView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        List(selection: $vm.selectedGameID) {
            Section("Navigation") {
                ForEach(PipelineTab.allCases) { tab in
                    Button {
                        vm.selectedTab = tab
                    } label: {
                        HStack {
                            Image(systemName: tab.icon)
                                .foregroundStyle(vm.selectedTab == tab ? Color.accentColor : Color.secondary)
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .fontWeight(vm.selectedTab == tab ? .semibold : .regular)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }

            Section("Switch Titles (\(vm.games.count))") {
                ForEach(vm.games) { game in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(game.name)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            if game.mac_app != nil {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .help("Native macOS .app built")
                            }
                        }
                        Text(game.title_id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        HStack(spacing: 5) {
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
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(game.id)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct TopHeaderBar: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("AETHERNX STUDIO")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                    BadgePill(text: "COMP • RECOMP • DECOMP", color: .indigo)
                }
                Text("Universal Nintendo Switch Decompilation, Static Recompilation & Apple Silicon Porting Suite")
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
                vm.runDoctorAudit()
            } label: {
                Label("Audit / Doctor", systemImage: "stethoscope")
            }
            .disabled(vm.isRunningJob)
            Button {
                vm.scanGames()
            } label: {
                Label("Rescan Library", systemImage: "arrow.clockwise")
            }
            Button {
                vm.revealInFinder(vm.rootDir)
            } label: {
                Label("switch-comp", systemImage: "folder")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct StudioMainView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        if let game = vm.selectedGame {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Hero Card
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [.green.opacity(0.75), .teal.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 88, height: 88)
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.white)
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
                                BadgePill(text: game.has_base ? "Base Game Ready" : "Missing Base", color: game.has_base ? .blue : .red)
                                BadgePill(text: game.update_versions.isEmpty ? "No Update (v0)" : "Update v\(game.update_versions.max() ?? 0) Merged", color: .purple)
                                BadgePill(text: "\(game.dlc_ids.count) DLC Pack(s) Mounted", color: .orange)
                                BadgePill(text: "\(game.shader_count) Maxwell Shaders -> Metal", color: .mint)
                                if let chunks = game.lifted_chunks, chunks > 0 {
                                    BadgePill(text: "\(chunks) C11 Recomp Chunks", color: .pink)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            if let macApp = game.mac_app {
                                Button {
                                    vm.launchMacApp(macApp)
                                } label: {
                                    Label("Launch Native Mac App", systemImage: "play.fill")
                                        .font(.headline)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.large)
                            }
                            Button {
                                vm.revealInFinder(game.directory)
                            } label: {
                                Label("Open Game Folder", systemImage: "folder.fill")
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                    // Tri-Pipeline Action Cards
                    HStack(alignment: .top, spacing: 14) {
                        PipelineActionCard(
                            title: "1. Native Porting (COMP)",
                            subtitle: "HorizonNative AArch64 NSO->Mach-O binary rewriter + Metal shader compiler + HOS kernel",
                            icon: "apple.logo",
                            accent: .blue
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("GPU Backend", selection: $vm.gpuBackend) {
                                    Text("Native NVN -> Metal (Default)").tag("none")
                                    Text("Ryujinx/Vulkan Bridge").tag("ryujinx")
                                }
                                .pickerStyle(.menu)

                                HStack(spacing: 8) {
                                    Button {
                                        vm.buildMacApp(for: game)
                                    } label: {
                                        Label("Build macOS .app", systemImage: "desktopcomputer")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(vm.isRunningJob)

                                    Button {
                                        vm.buildIOSIPA(for: game)
                                    } label: {
                                        Label("Build iOS/iPadOS .ipa", systemImage: "ipad.and.iphone")
                                    }
                                    .disabled(vm.isRunningJob)
                                }
                                Button {
                                    vm.prepareXcode(for: game)
                                } label: {
                                    Label("Generate Xcode Project Only", systemImage: "hammer")
                                }
                                .disabled(vm.isRunningJob)
                            }
                        }

                        PipelineActionCard(
                            title: "2. Static Recompiler (RECOMP)",
                            subtitle: "nxrt C11 Runtime + SwitchRecomp C++20 Lifter + mush8 Rust Crates",
                            icon: "memorychip.fill",
                            accent: .purple
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Lifts AArch64 NSO modules into static C11 translation units (\(game.lifted_chunks ?? 0) chunks ready).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button {
                                        vm.runStaticLifter(for: game)
                                    } label: {
                                        Label("Run Static Lifter (nxrt)", systemImage: "bolt.horizontal.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                    .disabled(vm.isRunningJob)

                                    if (game.lifted_chunks ?? 0) > 0 {
                                        Button {
                                            vm.revealInFinder("\(game.directory)/\(game.title_id)_build/decomp_workspace/recomp/lifted_c")
                                        } label: {
                                            Label("Open C11 Chunks", systemImage: "doc.text.magnifyingglass")
                                        }
                                    }
                                }
                            }
                        }

                        PipelineActionCard(
                            title: "3. Clean-Room Decomp (DECOMP)",
                            subtitle: "open-ead/nnheaders + sead + Capstone Function Harvester + 15 AI Skills",
                            icon: "magnifyingglass.circle.fill",
                            accent: .teal
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let manifest = game.decomp_manifest {
                                    Text("Mapped \(manifest.total_functions ?? 0) functions and \(manifest.total_dynamic_symbols ?? 0) symbols across \(manifest.modules?.count ?? 0) NSO modules.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Extracts full function bounds, dynamic symbols, CMake targets, and DECOMP_REPORT.md.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button {
                                        vm.selectedTab = .decomp
                                    } label: {
                                        Label("Open Decomp Explorer", systemImage: "list.bullet.rectangle")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.teal)

                                    if game.decomp_ready {
                                        Button {
                                            vm.revealInFinder("\(game.directory)/\(game.title_id)_build/decomp_workspace")
                                        } label: {
                                            Label("Open Workspace", systemImage: "folder")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Package Composition (Base + Update + DLC)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Base Game, Update & DLC Composition")
                            .font(.headline)
                        HStack(spacing: 16) {
                            StatBox(label: "Base NSP", value: game.has_base ? "Present (v0)" : "Missing", icon: "opticaldisc.fill")
                            StatBox(label: "Merged Update", value: game.update_versions.isEmpty ? "None" : "v\(game.update_versions.max() ?? 0)", icon: "arrow.triangle.merge")
                            StatBox(label: "Mounted DLCs (AOC)", value: game.dlc_ids.isEmpty ? "0" : "\(game.dlc_ids.count) (\(game.dlc_ids.joined(separator: ", ")))", icon: "puzzlepiece.extension.fill")
                            StatBox(label: "NSO Modules", value: game.modules.isEmpty ? "Pending Extract" : game.modules.joined(separator: ", "), icon: "shippingbox")
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("No Switch Game Selected", systemImage: "gamecontroller", description: Text("Add a game folder with .nsp/.xci files to ~/Games and click Rescan Library."))
        }
    }
}

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
                            Text("Path: \(game.directory)/\(game.title_id)_build/decomp_workspace")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.initDecompWorkspace(for: game)
                        } label: {
                            Label("Refresh Decomp Workspace", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunningJob)
                    }

                    if let manifest = game.decomp_manifest, let modules = manifest.modules {
                        HStack(spacing: 16) {
                            StatBox(label: "Total Functions Discovered", value: "\(manifest.total_functions ?? 0)", icon: "function")
                            StatBox(label: "Dynamic ELF Symbols", value: "\(manifest.total_dynamic_symbols ?? 0)", icon: "link")
                            StatBox(label: "Static C11 Chunks Lifted", value: "\(game.lifted_chunks ?? 0)", icon: "bolt.horizontal.fill")
                            StatBox(label: "SDK Headers Linked", value: "nnheaders + open-ead/sead", icon: "books.vertical.fill")
                        }

                        Text("NSO Module Breakdown")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            GridRow {
                                Text("Module").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Code Size (.text)").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Functions (BL/Entry)").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Dynamic Symbols").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("Artifacts").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            Divider()
                            ForEach(modules, id: \.name) { mod in
                                GridRow {
                                    Text(mod.name).font(.body.monospaced().bold())
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(mod.code_size ?? 0), countStyle: .file))
                                        .font(.body.monospaced())
                                    Text("\(mod.functions ?? 0)").font(.body.monospaced())
                                    Text("\(mod.dynamic_symbols ?? 0)").font(.body.monospaced())
                                    Button("Reveal TSV") {
                                        vm.revealInFinder("\(game.directory)/\(game.title_id)_build/decomp_workspace/functions/\(mod.name)_functions.tsv")
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView(
                            "Decomp Workspace Not Initialized Yet",
                            systemImage: "cpu",
                            description: Text("Click 'Refresh Decomp Workspace' to analyze NSO modules, harvest functions & dynamic symbols, and scaffold CMake + nxrt descriptors.")
                        )
                    }
                }
                .padding(18)
            }
        }
    }
}

struct SkillsCatalogView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Integrated AI Agent Skills (15 Skills)")
                            .font(.title2.bold())
                        Text("Installed in ~/AetherNX/skills and linked in .claude/skills for Claude Code, Codex & Antigravity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.revealInFinder("\(vm.rootDir)/skills")
                    } label: {
                        Label("Open skills/ Folder", systemImage: "folder")
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
                                Button("Open SKILL.md") {
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

struct EcosystemCreditsView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unified Open-Source Ecosystem & Copyright Registry (31 Forked Repositories)")
                            .font(.title2.bold())
                        Text("Every repository has been forked to @iCosiSenpai and attributed in COPYRIGHT.md & PROVENANCE.md.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.revealInFinder("\(vm.rootDir)/COPYRIGHT.md")
                    } label: {
                        Label("Open COPYRIGHT.md", systemImage: "doc.text")
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

struct ConsoleDrawerView: View {
    @ObservedObject var vm: AetherNXViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Pipeline Console Output", systemImage: "terminal.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
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
        .frame(height: 155)
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
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("AetherNX Studio — Universal Switch Decomp • Recomp • Native Porting") {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
