import AppKit
import Foundation
import Observation

/// How long and when each game was played: its Mac app's runs while AetherNX is open, from AetherNX, Finder or the Dock.
struct PlayRecord: Codable, Equatable {
    var seconds: Double = 0
    var sessions = 0
    var lastPlayed: Date?
}

@MainActor
@Observable
final class PlayLog {
    private(set) var records: [String: PlayRecord]
    /// Mac app bundle path → the key of its game (title ID, else the game's folder); kept current by each scan.
    @ObservationIgnored var knownApps: [String: String] = [:]
    @ObservationIgnored private var running: [pid_t: (key: String, start: Date)] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private static let defaultsKey = "playLog"

    init() {
        records = (UserDefaults.standard.data(forKey: Self.defaultsKey)).flatMap { try? JSONDecoder().decode([String: PlayRecord].self, from: $0) } ?? [:]
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.launched(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.ended(pid: pid) }
        })
    }

    static func key(for game: Game) -> String { game.titleId ?? game.id }

    func record(for game: Game) -> PlayRecord? { records[Self.key(for: game)] }

    /// After the scan: games already running count from now.
    func setKnownApps(_ apps: [String: String]) {
        knownApps = apps
        for app in NSWorkspace.shared.runningApplications where running[app.processIdentifier] == nil { launched(app) }
    }

    func launched(_ app: NSRunningApplication) {
        guard let path = app.bundleURL?.standardizedFileURL.path, let key = knownApps[path], running[app.processIdentifier] == nil else { return }
        running[app.processIdentifier] = (key, app.launchDate ?? .now)
        var record = records[key] ?? PlayRecord()
        record.sessions += 1
        record.lastPlayed = .now
        records[key] = record
        save()
    }

    private func ended(pid: pid_t) {
        guard let run = running.removeValue(forKey: pid) else { return }
        add(Date().timeIntervalSince(run.start), to: run.key)
    }

    /// AetherNX quits while games run: their time so far is kept.
    func flush() {
        for (_, run) in running { add(Date().timeIntervalSince(run.start), to: run.key) }
        running.removeAll()
    }

    func isRunning(_ game: Game) -> Bool { running.values.contains { $0.key == Self.key(for: game) } }

    func forget(_ game: Game) {
        records[Self.key(for: game)] = nil
        save()
    }

    private func add(_ seconds: TimeInterval, to key: String) {
        guard seconds > 0 else { return }
        var record = records[key] ?? PlayRecord()
        record.seconds += seconds
        record.lastPlayed = .now
        records[key] = record
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }
}

extension PlayRecord {
    /// "3 h 20 min played · last played yesterday"
    var summary: String {
        var parts: [String] = []
        if seconds >= 60 {
            let time = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
            parts.append(String(localized: "\(time) played"))
        }
        if let lastPlayed {
            let when = lastPlayed.formatted(.relative(presentation: .named))
            parts.append(String(localized: "last played \(when)"))
        }
        return parts.joined(separator: " · ")
    }
}
