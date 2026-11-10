import Foundation
import Observation

/// One running command: a build, an unpack, a download. Builds report their progress as JSON lines (docs/frontends.md).
@MainActor
@Observable
final class Job: Identifiable {
    enum State: Equatable {
        case running, succeeded, failed, cancelled

        func summary(for title: String) -> String {
            switch self {
            case .running: String(localized: "\(title)…")
            case .succeeded: String(localized: "\(title): done.")
            case .failed: String(localized: "\(title): stopped with an error.")
            case .cancelled: String(localized: "\(title): stopped.")
            }
        }
    }

    let id = UUID()
    let title: String
    let gameID: Game.ID?
    let target: BuildTarget?
    let started = Date()
    var state: State = .running
    private(set) var stageIndex = 0
    private(set) var stageCount = 0
    private(set) var stageName = ""
    private(set) var stepName = ""
    private(set) var stageFraction: Double?
    private(set) var eta: Double?
    private(set) var lastMessage = ""
    var failureMessage: String?
    private var cancelRequested = false
    @ObservationIgnored var runner: CommandRunner?
    @ObservationIgnored private var lastErrorLines: [String] = []

    init(title: String, gameID: Game.ID?, target: BuildTarget?) {
        self.title = title
        self.gameID = gameID
        self.target = target
    }

    var isRunning: Bool { state == .running }

    /// Overall progress from the stage counter; nil while it is unknown.
    var fraction: Double? {
        guard stageCount > 0, stageIndex > 0 else { return nil }
        let done = Double(stageIndex - 1) + (stageFraction ?? 0)
        return min(max(done / Double(stageCount), 0), 1)
    }

    var stageLabel: String {
        guard stageCount > 0 else { return lastMessage }
        let name = stepName.isEmpty ? stageName : "\(stageName): \(stepName)"
        return String(localized: "Step \(stageIndex) of \(stageCount) · \(name)")
    }

    func cancel() {
        guard isRunning else { return }
        cancelRequested = true
        runner?.interrupt()
    }

    /// Reads one output line; returns the text for the activity log, or nil for a progress event.
    func handle(line: String, isError: Bool) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if isError {
            lastErrorLines.append(trimmed)
            if lastErrorLines.count > 20 { lastErrorLines.removeFirst() }
            return trimmed
        }
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let kind = event["ev"] as? String else {
            lastMessage = trimmed
            return trimmed
        }
        switch kind {
        case "stage":
            stageIndex = event["k"] as? Int ?? stageIndex
            stageCount = event["n"] as? Int ?? stageCount
            stageName = event["name"] as? String ?? ""
            stepName = event["step"] as? String ?? ""
            stageFraction = 0
            eta = nil
            return String(localized: "Step \(stageIndex) of \(stageCount): \(stageName)")
        case "step":
            stepName = event["step"] as? String ?? ""
            stageFraction = 0
            return nil
        case "progress":
            stageFraction = event["frac"] as? Double
            eta = event["eta"] as? Double
            if let step = event["step"] as? String { stepName = step }
            return nil
        case "stage_end":
            stageFraction = 1
            if let summary = event["summary"] as? String, !summary.isEmpty { return "  \(event["name"] as? String ?? ""): \(summary)" }
            return nil
        case "say":
            let message = event["msg"] as? String ?? ""
            let clean = message.replacingOccurrences(of: #"^\[[0-9:]+\] "#, with: "", options: .regularExpression)
            if clean.hasPrefix("[RED] ") { failureMessage = String(clean.dropFirst(6)) }
            lastMessage = clean
            return clean
        case "shaders_stale":
            return String(localized: "Shaders changed since the last build: rebuilding them.")
        default:
            return nil   // an event this app does not show (game: what was packed, for a front end that lists it); every message comes as say
        }
    }

    func finish(status: Int32) {
        runner = nil
        if cancelRequested || status == 130 {
            state = .cancelled
        } else if status == 0 {
            state = .succeeded
            failureMessage = nil
        } else {
            state = .failed
            if failureMessage == nil {
                failureMessage = lastErrorLines.last { !$0.hasPrefix("Traceback") && !$0.hasPrefix("File ") }
                    ?? String(localized: "Exit code \(status)")
            }
        }
    }
}
