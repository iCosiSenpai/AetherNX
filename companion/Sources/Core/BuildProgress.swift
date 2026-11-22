import Foundation

/// A build or an install running on the Mac, as the phone shows it: made from the link's `job` line, then kept current by the events of the build
/// and install scripts, read as AetherNX Studio reads them (docs/frontends.md: `stage`, `step`, `progress`, `stage_end`, `say`).
struct BuildProgress: Equatable, Identifiable, Sendable {
    enum State: String, Sendable {
        case running, succeeded, failed, cancelled
    }

    /// A stage that ended: its name as the script gives it, how long it took and what it said.
    struct Stage: Equatable, Identifiable, Sendable {
        var id: Int { index }
        let index: Int
        let name: String
        let ok: Bool
        let summary: String
        let seconds: Double
    }

    let id: String
    var state: State
    /// install or build, and the build's target (device, mac, ios, ios-slim, xcode).
    var kind: String
    var target: String?
    var titleId: String?
    var game: String?
    /// The job's title in the Mac's own words ("Installing on Alessio's iPhone").
    var title: String
    private(set) var stageIndex = 0
    private(set) var stageCount = 0
    private(set) var stageName = ""
    private(set) var stepName = ""
    private(set) var stageFraction: Double?
    private(set) var eta: Double?
    private(set) var lastMessage = ""
    /// Why it stopped: the Mac's own words when the job line has them, else the script's last `[RED] ` message.
    private(set) var failure: String?
    private(set) var finished: [Stage] = []

    /// nil for a line that is no job, or one in a state this build does not know.
    init?(_ line: LinkLine) {
        guard line.link == "job", let id = line.id, let state = line.state.flatMap(State.init(rawValue:)) else { return nil }
        self.id = id
        self.state = state
        kind = line.kind ?? "build"
        target = line.target
        titleId = line.titleId?.uppercased()
        game = line.game
        title = line.title ?? ""
        failure = line.message
    }

    var isRunning: Bool { state == .running }
    var isInstall: Bool { kind == "install" }

    /// Overall progress from the stage counter; nil while it is unknown.
    var fraction: Double? {
        guard stageCount > 0, stageIndex > 0 else { return nil }
        let done = Double(stageIndex - 1) + (stageFraction ?? 0)
        return min(max(done / Double(stageCount), 0), 1)
    }

    /// The same job in a later state: what the events built so far is kept.
    mutating func update(_ line: LinkLine) {
        guard line.link == "job", line.id == id, let state = line.state.flatMap(State.init(rawValue:)) else { return }
        self.state = state
        if let title = line.title, !title.isEmpty { self.title = title }
        if let message = line.message, !message.isEmpty { failure = message }
        if state == .succeeded {
            failure = nil
            stageFraction = 1
        }
    }

    /// One event of the script. One this build does not know changes nothing.
    mutating func apply(_ event: [String: Any]) {
        func number(_ key: String) -> Double? { (event[key] as? NSNumber)?.doubleValue }
        switch event["ev"] as? String {
        case "stage":
            stageIndex = event["k"] as? Int ?? stageIndex
            stageCount = event["n"] as? Int ?? stageCount
            stageName = event["name"] as? String ?? ""
            stepName = event["step"] as? String ?? ""
            stageFraction = 0
            eta = nil
        case "step":
            stepName = event["step"] as? String ?? ""
            stageFraction = 0
        case "progress":
            stageFraction = number("frac")
            eta = number("eta")
            if let step = event["step"] as? String { stepName = step }
        case "stage_end":
            stageFraction = 1
            eta = nil
            let index = event["k"] as? Int ?? stageIndex
            finished.removeAll { $0.index == index }
            finished.append(Stage(index: index, name: event["name"] as? String ?? stageName, ok: event["ok"] as? Bool ?? true,
                                  summary: event["summary"] as? String ?? "", seconds: number("elapsed") ?? 0))
        case "say":
            let message = (event["msg"] as? String ?? "").replacingOccurrences(of: #"^\[[0-9:]+\] "#, with: "", options: .regularExpression)
            if message.hasPrefix("[RED] ") { failure = String(message.dropFirst(6)) }
            lastMessage = message
        default:
            break
        }
    }
}
