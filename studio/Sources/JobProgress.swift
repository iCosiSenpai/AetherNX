import SwiftUI

/// What each stage of a build or an install does, in the player's words. The build script names its stages in English (docs/frontends.md,
/// `stage` events: "extract base", "iOS shaders", "sign for the device"…); a stage is found by the start of its name, and one this list does not
/// know shows by that name alone.
enum StageGuide {
    struct Entry {
        let title: String
        let detail: String
    }

    static func entry(for stage: String) -> Entry? {
        let name = stage.lowercased()
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { name.hasPrefix($0) } }
        if starts("copy the build") {
            return Entry(title: String(localized: "Copying the build"),
                         detail: String(localized: "The build folder and the Mac app go to their new disk, file by file. The originals stay until the copy is checked."))
        }
        if starts("check the copy") {
            return Entry(title: String(localized: "Checking the copy"),
                         detail: String(localized: "Every file of the copy is compared with the original: names, links and sizes."))
        }
        if starts("remove the original") {
            return Entry(title: String(localized: "Freeing the old disk"),
                         detail: String(localized: "The original build folder and Mac app are deleted; the game now uses the copy."))
        }
        if starts("decompress") {
            return Entry(title: String(localized: "Decompressing the packages"),
                         detail: String(localized: "Compressed packages (.nsz, .xcz) are turned into plain ones, once: the next builds reuse them."))
        }
        if starts("build id lookup") {
            return Entry(title: String(localized: "Identifying the game version"),
                         detail: String(localized: "Reads the code modules to find the exact build of the game, which decides the profile and the patches it gets."))
        }
        if starts("survey") {
            return Entry(title: String(localized: "Studying the game"),
                         detail: String(localized: "A game without a profile is surveyed: its files, modules and what it asks of the system, to propose a starting profile."))
        }
        if name.contains("dlc") {
            return Entry(title: String(localized: "Add-on content"),
                         detail: String(localized: "The DLC is unpacked and packed like the game's own files, so the app finds it as the console would."))
        }
        if starts("extract", "unpack") {
            return Entry(title: String(localized: "Extracting the game files"),
                         detail: String(localized: "Your keys decrypt the package; its code (ExeFS) and data (RomFS) are copied out. Kept extracted files make the next build much faster."))
        }
        if starts("check ") {
            return Entry(title: String(localized: "Checking the game files"),
                         detail: String(localized: "The start of every file is read to be sure nothing is damaged or missing before the long steps."))
        }
        if starts("pack ") {
            return Entry(title: String(localized: "Packing the game data"),
                         detail: String(localized: "The game's data goes into one RomFS image, which the app reads quickly and which copies to a device in one piece."))
        }
        if starts("rewrite") {
            return Entry(title: String(localized: "Adapting the game code"),
                         detail: String(localized: "The game's ARM64 modules are rewritten for Apple's memory and process rules: the heart of making the game native."))
        }
        if name.hasSuffix("capture") || starts("ue shader decode") {
            return Entry(title: String(localized: "Collecting shaders"),
                         detail: String(localized: "The game runs for a moment on the Mac so the shaders it makes while running can be collected and translated ahead of time."))
        }
        if starts("heap check") {
            return Entry(title: String(localized: "Checking memory use"),
                         detail: String(localized: "A short start measures how much memory the game asks for, so the app reserves enough on the device."))
        }
        if starts("address regions") {
            return Entry(title: String(localized: "Mapping the address space"),
                         detail: String(localized: "Places the game's memory where Apple's systems allow it, as the console laid it out."))
        }
        if starts("shader split") {
            return Entry(title: String(localized: "Finding the shaders"),
                         detail: String(localized: "Every GPU program in the game files is found and sorted by kind. On a large game this reads hundreds of thousands of entries."))
        }
        if name.hasSuffix(" shaders") {
            return Entry(title: String(localized: "Translating the shaders to Metal"),
                         detail: String(localized: "The Switch GPU's shaders are translated for Apple's GPUs. The longest step the first time; later builds reuse the cache."))
        }
        if starts("pipeline") {
            return Entry(title: String(localized: "Prebuilding the graphics pipelines"),
                         detail: String(localized: "The pipelines are compiled now for the device's GPU, so a scene does not stutter the first time it appears. Minutes when the shaders changed."))
        }
        if starts("mac host", "build nx_extract") {
            return Entry(title: String(localized: "Building the engine"),
                         detail: String(localized: "Compiles HorizonNative, the engine that plays the game in place of the console's system, with this game's settings."))
        }
        if starts("mac app") {
            return Entry(title: String(localized: "Making the Mac app"),
                         detail: String(localized: "Puts the engine, the translated shaders and the game data together into an app you open from the Finder."))
        }
        if starts("ipa pack") {
            return Entry(title: String(localized: "Packing the IPA"),
                         detail: String(localized: "The iPhone and iPad app goes into one IPA file, ready to sideload."))
        }
        if starts("prepare xcode") {
            return Entry(title: String(localized: "Preparing the Xcode project"),
                         detail: String(localized: "Writes the project that Xcode signs for your device: the engine, the shaders, the icon and the game's own settings."))
        }
        if starts("app build") {
            return Entry(title: String(localized: "Building the app"),
                         detail: String(localized: "Compiles the iPhone and iPad app with Xcode's tools."))
        }
        if starts("sign for the device") {
            return Entry(title: String(localized: "Signing for your device"),
                         detail: String(localized: "Xcode signs the app with your Apple team for the chosen iPhone or iPad, and makes the provisioning profile it needs."))
        }
        if starts("install on the device") {
            return Entry(title: String(localized: "Installing on the device"),
                         detail: String(localized: "The app is copied to the device. A large game takes minutes: keep the device unlocked and near the Mac (a cable is the fastest)."))
        }
        if starts("copy the game files") {
            return Entry(title: String(localized: "Copying the game files to the device"),
                         detail: String(localized: "The game data goes to the app's own folder on the device, once: later installs of the app keep it there."))
        }
        return nil
    }

    static func title(for stage: String) -> String { entry(for: stage)?.title ?? stage }

    /// A step within a stage, as the scripts name it, in the player's words when it is one of the usual ones.
    static func step(_ step: String) -> String {
        switch step.lowercased() {
        case "compiling": String(localized: "compiling")
        case "linking": String(localized: "linking")
        case "signing": String(localized: "signing")
        case "provisioning": String(localized: "making the provisioning profile")
        case "copying the game files into the app": String(localized: "copying the game files into the app")
        case "starting xcodebuild", "starting": String(localized: "starting")
        case "building": String(localized: "building")
        case "checking the inputs": String(localized: "checking what changed since the last build")
        case "reading": String(localized: "reading")
        case "packing": String(localized: "packing")
        case "unpacking": String(localized: "unpacking")
        default: step
        }
    }
}

/// A job on the screen while it runs: the stage it is at ("Step 5 of 9"), what that stage does and why, the step within it, the time it
/// took so far and what is left, and the stages it already finished. A job that succeeds says so for a few seconds and goes (AppModel);
/// one that fails stays, with what went wrong and a way to try again.
struct JobCard: View {
    let job: Job
    var showsGameName: String? = nil
    @Environment(AppModel.self) private var model
    @State private var showsStages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch job.state {
            case .running:
                running
            case .succeeded:
                Label(doneText, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            case .failed:
                failed
            case .cancelled:
                Label("Stopped.", systemImage: "stop.circle")
                    .foregroundStyle(.secondary)
            }
            if !job.finishedStages.isEmpty {
                DisclosureGroup(isExpanded: $showsStages) {
                    stageList
                } label: {
                    Text("Finished steps (\(job.finishedStages.count))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(borderColor, lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: job.state)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.headline)
                if let showsGameName {
                    Text(showsGameName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if job.isRunning {
                time
                Button("Stop") { job.cancel() }
                    .help("Stop (⌘.)")
            } else {
                Button("Close") { model.dismissJob() }
            }
        }
    }

    @ViewBuilder
    private var running: some View {
        if let fraction = job.fraction {
            ProgressView(value: fraction)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
        if job.stageCount > 0 {
            let guide = StageGuide.entry(for: job.stageName)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Step \(job.stageIndex) of \(job.stageCount)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(guide?.title ?? job.stageName)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 8)
                    if let stage = job.stageFraction, stage > 0, stage < 1 {
                        Text(stage, format: .percent.precision(.fractionLength(0)))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = guide?.detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let now = nowText {
                    Label(now, systemImage: "gearshape.2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } else {
            Text(job.lastMessage.isEmpty ? String(localized: "Starting…") : job.lastMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// The step under way within the stage, else the last thing the build said.
    private var nowText: String? {
        if !job.stepName.isEmpty { return StageGuide.step(job.stepName) }
        let message = job.lastMessage
        return message.isEmpty || message.hasPrefix("{") ? nil : message
    }

    private var time: some View {
        Group {
            if let eta = job.eta, eta > 5 {
                Text("About \(Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))) left")
            } else {
                Text(job.started, style: .timer)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var failed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(job.failureMessage ?? String(localized: "Stopped with an error."))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            if job.stageCount > 0 {
                Text("At step \(job.stageIndex) of \(job.stageCount): \(StageGuide.title(for: job.stageName))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let retry = job.retry {
                    Button("Try Again") {
                        model.dismissJob()
                        retry()
                    }
                    .disabled(!model.canStartJob)
                }
                Button("Show Activity") { model.sidebarSelection = .page(.activity) }
            }
        }
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(job.finishedStages) { stage in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: stage.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(stage.ok ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(StageGuide.title(for: stage.name))
                        if !stage.summary.isEmpty {
                            Text(stage.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Duration.seconds(stage.seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(.top, 6)
    }

    private var doneText: String {
        let seconds = (job.ended ?? Date()).timeIntervalSince(job.started)
        let took = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return String(localized: "Done in \(took).")
    }

    private var background: AnyShapeStyle {
        switch job.state {
        case .succeeded: AnyShapeStyle(Color.green.opacity(0.08))
        case .failed: AnyShapeStyle(Color.orange.opacity(0.08))
        default: AnyShapeStyle(.background.secondary)
        }
    }

    private var borderColor: Color {
        switch job.state {
        case .succeeded: .green.opacity(0.35)
        case .failed: .orange.opacity(0.4)
        default: .clear
        }
    }
}
