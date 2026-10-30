// Launcher settings, validation and persistence. Shared by the iOS UI, the Mac app's settings window (dm/mac/Launcher.swift) and the native storage regression test.
import Foundation
import Combine

struct Setting: Decodable, Identifiable {
    let env, kind, label, note, def: String
    let section: String?   // heading on the settings screen; absent in older bundles
    let needs: String?     // "<VAR>=<value>": a sub-setting, drawn only while that setting has that value
    let level: String?     // "basic": shown first (the Mac window's Basic settings); any other or none: Advanced settings. The iPhone keeps one list
    let base: Base?        // render scale: the 3D views' size at 1.0, docked and handheld, for the size in pixels (the Mac window)
    struct Base: Decodable { let docked, handheld: [Int] }
    let options: [[String]]?   // choice: [value, label]
    let min, max, step: Double?   // range
    let on, off: String?   // toggle: the values the variable takes (1 / 0 when not given)
    var id: String { env }
    var sectionTitle: String { section ?? "Game" }
    var basic: Bool { level == "basic" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }
    func isDefault(_ v: String) -> Bool {   // a range compares as numbers (a slider writes 1.00 for 1.0)
        kind == "range" ? abs((Double(v) ?? .nan) - (Double(def) ?? .nan)) < 1e-6 : v == def
    }
    func accepts(_ v: String) -> Bool {   // a saved choice the game still offers
        switch kind {
        case "choice": return options?.contains { $0[0] == v } ?? false
        case "range":
            guard !v.contains(where: { $0 == "x" || $0 == "X" }), let n = Double(v), n.isFinite, let lo = min, let hi = max else { return false }   // no hex: launcher.c's check agrees
            return n >= lo && n <= hi
        case "toggle": return v == onValue || v == offValue
        default: return true
        }
    }
    enum CodingKeys: String, CodingKey { case env, kind, label, note, def = "default", section, needs, level, base, options, min, max, step, on, off }
}
struct SettingsFile: Decodable { let settings: [Setting] }

final class LauncherModel: ObservableObject {
    let settings: [Setting]
    let fixed: Set<String>      // set by an env file or by the launch environment: shown, not changed
    let fromLaunch: Set<String>   // of those, the ones the launch environment set (a front end's launch overrides, Xcode; DM_ENV_LAUNCH_KEYS from launcher.c or main.m)
    let ignoreSaved: Bool   // DM_SAVED_CHOICES=0: start from the defaults, and leave the saved choices as they are
    @Published var values: [String: String] = [:]

    private let defaults: UserDefaults

    init(_ settings: [Setting], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = settings
        let env = ProcessInfo.processInfo.environment
        fromLaunch = Set((env["DM_ENV_LAUNCH_KEYS"] ?? "").split(separator: " ").map(String.init))
        fixed = fromLaunch.union((env["DM_ENV_FILE_KEYS"] ?? "").split(separator: " ").map(String.init))
        ignoreSaved = env["DM_SAVED_CHOICES"] == "0"
        if ignoreSaved { fputs("launcher: saved choices ignored (DM_SAVED_CHOICES=0)\n", stderr) }
        for s in settings {
            if fixed.contains(s.env), let v = env[s.env] { values[s.env] = v; continue }
            let saved = ignoreSaved ? nil : defaults.object(forKey: "launcher." + s.env) as? String   // a string, as launcher.c reads it: not string(forKey:), which turns a number into one
            values[s.env] = saved.flatMap { s.accepts($0) ? $0 : nil } ?? s.def   // a saved choice the game no longer offers: its default
        }
    }

    var sections: [String] {
        settings.reduce(into: []) { if !$0.contains($1.sectionTitle) { $0.append($1.sectionTitle) } }
    }
    // A row with "needs" is a sub-setting of the row it names: drawn only while that setting has that value, so a
    // setting that cannot do anything is not offered (an upscaler's detail with the upscaler off, rumble strength
    // with rumble off). A row naming a setting this game does not have stays drawn, as it has nothing to hide behind
    func visible(_ s: Setting) -> Bool {
        guard let n = s.needs, let eq = n.firstIndex(of: "=") else { return true }
        let key = String(n[n.startIndex..<eq]), want = String(n[n.index(after: eq)...])
        guard let v = values[key] else { return true }
        return v == want
    }
    func rows(in section: String) -> [Setting] { settings.filter { $0.sectionTitle == section && visible($0) } }
    // The Mac window: Basic settings first, then Advanced settings, each in the list's sections and order
    func sections(basic: Bool) -> [String] {
        settings.filter { $0.basic == basic }.reduce(into: []) { if !$0.contains($1.sectionTitle) { $0.append($1.sectionTitle) } }
    }
    func rows(in section: String, basic: Bool) -> [Setting] { rows(in: section).filter { $0.basic == basic } }
    // A range's label: its percentage, with the size in pixels for the chosen console mode when the list has the base size (the render scale).
    // A value that is no number (DM_RENDER_SCALE=nan in an env file, shown fixed) is named as it is: converting it to Int would stop the app
    func rangeLabel(_ s: Setting, _ v: Double) -> String {
        guard v.isFinite, abs(v) < 1e6 else { return "–" }
        let p = "\(Int((v * 100).rounded())) %"
        guard let b = s.base else { return p }
        let size = (values["DM_OPMODE"] ?? "1") == "0" ? b.handheld : b.docked
        guard size.count == 2 else { return p }
        return "\(Int((Double(size[0]) * v).rounded())) × \(Int((Double(size[1]) * v).rounded())) (\(p))"
    }
    var changed: Bool { settings.contains { !fixed.contains($0.env) && !$0.isDefault(values[$0.env] ?? $0.def) } }

    func value(_ s: Setting) -> String { values[s.env] ?? s.def }
    // Differs from the tested default (fixed ones too: the screen shows what the game gets)
    func isChanged(_ s: Setting) -> Bool { !s.isDefault(value(s)) }
    // A fixed value this build does not offer (an env file's DM_RENDER_SCALE=nan, an option that was removed): the game still gets it, so the screen names it instead of drawing a control
    func isInvalid(_ s: Setting) -> Bool { fixed.contains(s.env) && !s.accepts(value(s)) }
    // The value as the player reads it: a choice's label, a range's percentage (or size in pixels), On or Off
    func valueLabel(_ s: Setting) -> String {
        let v = value(s)
        if isInvalid(s) { return v.isEmpty ? "(empty)" : v }
        switch s.kind {
        case "choice": return s.options?.first { $0.count > 1 && $0[0] == v }?[1] ?? v
        case "range": return rangeLabel(s, Double(v) ?? .nan)
        default: return v == s.onValue ? "On" : "Off"
        }
    }
    // The tested default as the player reads it ("Use tested default (60 fps)")
    func defaultLabel(_ s: Setting) -> String {
        switch s.kind {
        case "choice": return s.options?.first { $0.count > 1 && $0[0] == s.def }?[1] ?? s.def
        case "range": return rangeLabel(s, Double(s.def) ?? .nan)
        default: return s.def == s.onValue ? "On" : "Off"
        }
    }
    func useDefault(_ s: Setting) { if !fixed.contains(s.env) { values[s.env] = s.def } }
    // What the summary strip states: the basic settings while drawn, or the first four drawn when the list marks none basic
    var summary: [Setting] {
        let basic = settings.filter { $0.basic && visible($0) }
        return basic.isEmpty ? Array(settings.filter { visible($0) }.prefix(4)) : basic
    }
    // A controller or an arrow key moves a value one step: a choice to its neighbour (wrapping), a range by its step (clamped), a toggle on (+1) or off (-1)
    func step(_ s: Setting, by d: Int) {
        guard !fixed.contains(s.env) else { return }
        switch s.kind {
        case "choice":
            guard let o = s.options, !o.isEmpty else { return }
            let i = o.firstIndex { $0[0] == value(s) } ?? 0
            values[s.env] = o[((i + d) % o.count + o.count) % o.count][0]
        case "range":
            let lo = s.min ?? 0, hi = s.max ?? 1, st = s.step ?? 0.05
            let cur = Double(value(s)).flatMap { $0.isFinite ? $0 : nil } ?? lo
            values[s.env] = String(format: "%.2f", Swift.min(hi, Swift.max(lo, lo + (((cur - lo) / st).rounded() + Double(d)) * st)))
        default: values[s.env] = d > 0 ? s.onValue : s.offValue
        }
    }

    // Reset every launcher choice to the game's defaults on the screen; values fixed by an env file or at launch stay. The saved choices are forgotten when Play applies
    // the defaults (apply() keeps no default), so Quit after Reset keeps them, and a choice a launch override hides is kept
    func reset() {
        for s in settings where !fixed.contains(s.env) { values[s.env] = s.def }
        fputs("launcher: settings reset to the game's defaults\n", stderr)
    }

    // Before the game starts: every setting not set by an env file goes into the environment (DM_LANG replaces the packed language main.m set as a default). Only a choice that
    // differs from the game's default is stored: a setting the player left at its default follows the defaults of a later build (the settings it was tested with)
    func apply() {
        for s in settings {
            let v = values[s.env] ?? s.def
            if fixed.contains(s.env) { fputs("launcher: \(s.env) kept at \(v) (\(fromLaunch.contains(s.env) ? "launch environment" : "env file"))\n", stderr); continue }
            if !ignoreSaved { if s.isDefault(v) { defaults.removeObject(forKey: "launcher." + s.env) } else { defaults.set(v, forKey: "launcher." + s.env) } }
            setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v)\(s.isDefault(v) ? "" : " (changed)")\n", stderr)
        }
    }

    // DM_LAUNCHER=0: no screen, but the saved choices still apply (only DM_SAVED_CHOICES=0 ignores them); nothing is written
    func applySaved() {
        for s in settings where !fixed.contains(s.env) {
            let v = values[s.env] ?? s.def
            if !s.isDefault(v) { setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v) (saved choice)\n", stderr) }
        }
    }
}
