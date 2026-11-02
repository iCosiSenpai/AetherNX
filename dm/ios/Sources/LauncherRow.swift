// The launcher's shared parts, used by the iOS screen (Launcher.swift) and the Mac app's settings window (dm/mac/Launcher.swift): the game's header, the summary strip
// that states what Play starts with, one setting as a row (a menu, a slider with its readout, a toggle), the game's tint taken from its icon, and the navigation by game
// controller. A row whose setting is fixed by an env file or by the launch environment is shown, locked, with where its value came from.
import SwiftUI
import GameController
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Connected controllers

struct ControllerInfo: Identifiable, Equatable {
    let id: ObjectIdentifier
    let name, kind, battery: String
    let player: Int   // zero based; -1 means the extended gamepad profile is unavailable or all players are taken
    let supported: Bool
    var detail: String { [kind, battery].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// A launcher owns session assignments until Play; the iOS in-game list reads the input view's actual slots instead.
/// GameController has no stable device identity or transport field: reconnects match names, and rows never guess Bluetooth versus USB.
@MainActor final class ControllerListModel: ObservableObject {
    @Published private(set) var rows: [ControllerInfo] = []
    let live: Bool
    @Published var merge = false
    private var slots = [GCController?](repeating: nil, count: 8)
    private var last = [String](repeating: "", count: 8)
    private var lit: [ObjectIdentifier: Int] = [:]
    init(live: Bool = false) { self.live = live }
    var firstPlayer: Int {
        #if os(macOS)
        return !merge && ProcessInfo.processInfo.environment["DM_KBD_PLAYER"] == "own" ? 1 : 0
        #else
        return 0
        #endif
    }
    private func player(_ c: GCController) -> Int {
        guard c.extendedGamepad != nil else { return -1 }
        if merge { return 0 }
        #if os(iOS)
        if live { return Int(dm_pad_controller_player(Unmanaged.passUnretained(c).toOpaque())) }
        #endif
        return slots.firstIndex { $0 === c } ?? -1
    }
    func refresh() {
        let now = GCController.controllers()
        if !live {
            if firstPlayer == 1 { slots[0] = nil; last[0] = "" }   // switching out of merge restores the keyboard's own player
            for p in slots.indices where slots[p].map({ c in !now.contains { $0 === c } }) ?? false { slots[p] = nil }
            for c in now where c.extendedGamepad != nil && !slots.contains(where: { $0 === c }) {
                let name = c.vendorName ?? "Controller", free = (firstPlayer..<8).filter { slots[$0] == nil }
                if let p = free.first(where: { last[$0] == name }) ?? free.first(where: { $0 == firstPlayer }) ?? free.first(where: { last[$0].isEmpty }) ?? free.first {
                    slots[p] = c; last[p] = name
                }
            }
            lit = lit.filter { id, _ in now.contains { ObjectIdentifier($0) == id } }
            for c in now where c.extendedGamepad != nil {
                let p = player(c), id = ObjectIdentifier(c)
                if p >= 0 && lit[id] != p { Self.lights(c, p); lit[id] = p }
            }
        }
        let updated = now.map { c in ControllerInfo(id: ObjectIdentifier(c), name: c.vendorName ?? "Controller", kind: Self.kind(c), battery: Self.battery(c), player: player(c), supported: c.extendedGamepad != nil) }
        if updated != rows { rows = updated }
    }
    func move(_ id: ObjectIdentifier, to p: Int) {
        guard !merge, (firstPlayer..<8).contains(p), let c = GCController.controllers().first(where: { ObjectIdentifier($0) == id }), c.extendedGamepad != nil else { return }
        #if os(iOS)
        if live { _ = dm_pad_controller_move(Unmanaged.passUnretained(c).toOpaque(), Int32(p)); refresh(); return }
        #endif
        guard let from = slots.firstIndex(where: { $0 === c }) else { return }
        slots.swapAt(from, p); last.swapAt(from, p)
        refresh()
    }
    func step(_ id: ObjectIdentifier, _ d: Int) {
        guard let row = rows.first(where: { $0.id == id }), row.player >= 0 else { return }
        let count = 8 - firstPlayer
        move(id, to: firstPlayer + (row.player - firstPlayer + d % count + count) % count)
    }
    func apply() {
        refresh()
        let now = GCController.controllers()
        let players: [[String: Any]] = slots.map { c in
            guard let c, let i = now.firstIndex(where: { $0 === c }) else { return [:] }
            return ["name": c.vendorName ?? "Controller", "category": c.productCategory, "index": i]
        }
        if let data = try? JSONSerialization.data(withJSONObject: players), let text = String(data: data, encoding: .utf8) { setenv("DM_PAD_PLAYERS", text, 1) }
    }
    private static func lights(_ c: GCController, _ p: Int) {
        c.playerIndex = GCControllerPlayerIndex(rawValue: p) ?? .indexUnset
        let rgb: [(Float, Float, Float)] = [(0,0.3,1), (1,0.1,0.1), (0.1,1,0.2), (1,0.4,0), (0.7,0.1,1), (0,1,1), (1,0.2,0.6), (1,1,1)]
        let v = rgb[p]; c.light?.color = GCColor(red: v.0, green: v.1, blue: v.2)
    }
    private static func kind(_ c: GCController) -> String {
        let k = c.productCategory, name = c.vendorName ?? ""
        if k == GCProductCategoryXboxOne { return "Xbox" }
        if k == GCProductCategoryDualSense { return "DualSense" }
        if k == GCProductCategoryDualShock4 { return "DualShock 4" }
        if k.contains("Joy-Con") || k.contains("JoyCon") { return "Joy-Con" }
        if k.contains("Switch Pro Controller") { return "Switch Pro Controller" }
        // Apple's category constants have no Nintendo entries; older drivers can expose only a vendor name.
        if name.contains("Joy-Con") || name.contains("JoyCon") { return "Joy-Con" }
        if (name.contains("Nintendo") && name.contains("Pro Controller")) || name == "Pro Controller" { return "Switch Pro Controller" }
        return "Other"
    }
    private static func battery(_ c: GCController) -> String {
        guard let b = c.battery else { return "" }
        var parts: [String] = []
        if b.batteryLevel.isFinite && (0...1).contains(b.batteryLevel) { parts.append("\(Int((b.batteryLevel * 100).rounded())) %") }
        if b.batteryState == .charging { parts.append("Charging") }
        if b.batteryState == .full { parts.append("Full") }
        return parts.joined(separator: " · ")
    }
}

struct ControllerSettingRow: View {
    let row: ControllerInfo
    @ObservedObject var controllers: ControllerListModel
    let tint: GameTint
    var focused = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name)
            Text(row.detail).font(.footnote).foregroundStyle(.secondary)
            if row.player >= 0 {
                Picker("Player", selection: Binding(get: { row.player }, set: { controllers.move(row.id, to: $0) })) {
                    ForEach(controllers.firstPlayer..<8, id: \.self) { Text("Player \($0 + 1)").tag($0) }
                }
                .disabled(controllers.merge)
            } else { Text(row.supported ? "All players are taken." : "No extended gamepad profile: not used.").font(.footnote).foregroundStyle(.secondary) }
        }
        .focusRing(focused, tint)
        .id("controller." + String(describing: row.id))
    }
}

struct ConnectedControllers: View {
    @ObservedObject var controllers: ControllerListModel
    let tint: GameTint
    let focused: (ObjectIdentifier) -> Bool
    var body: some View {
        if controllers.rows.isEmpty { Text("Pair a controller in the system's Bluetooth settings, or connect a USB cable where supported.").font(.footnote).foregroundStyle(.secondary) }
        ForEach(controllers.rows) { row in ControllerSettingRow(row: row, controllers: controllers, tint: tint, focused: focused(row.id)) }
    }
}

// MARK: - Tint

/// The one colour the launcher uses for what the player acts on: the game icon's dominant hue. `fill` sits behind white text (Play) with at least 4.5:1;
/// `mark` (the changed-value dot and the focus ring, nothing else: sliders, switches and menus keep the system's colours) is that dark tone on a light surface and a
/// lightened one on a dark surface, at least 3:1 against either.
/// A grey or unreadable icon gives the system accent.
struct GameTint {
    let fill: Color
    let mark: Color
    static let system = GameTint(fill: .accentColor, mark: .accentColor)

    static func from(_ image: CGImage?) -> GameTint {
        guard let image, let c = dominant(image) else { return .system }
        let dark = toLuminance(c, atMost: 0.17), light = toLuminance(c, atLeast: 0.32)
        return GameTint(fill: color(dark), mark: adaptive(light: dark, dark: light))
    }

    private typealias RGB = (r: Double, g: Double, b: Double)
    private static func color(_ c: RGB) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b) }
    private static func adaptive(light: RGB, dark: RGB) -> Color {
#if os(macOS)
        Color(nsColor: NSColor(name: nil) { ap in
            let c = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        })
#else
        Color(uiColor: UIColor { t in
            let c = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
#endif
    }
    private static func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double { 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b) }
    // Darkened (scaled towards black) or lightened (mixed with white), keeping the hue, until the WCAG luminance meets the bound
    private static func toLuminance(_ c: RGB, atMost: Double) -> RGB {
        if luminance(c) <= atMost { return c }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 { let f = (lo + hi) / 2; if luminance((c.r * f, c.g * f, c.b * f)) > atMost { hi = f } else { lo = f } }
        return (c.r * lo, c.g * lo, c.b * lo)
    }
    private static func toLuminance(_ c: RGB, atLeast: Double) -> RGB {
        if luminance(c) >= atLeast { return c }
        var lo = 0.0, hi = 1.0
        func mix(_ t: Double) -> RGB { (c.r + (1 - c.r) * t, c.g + (1 - c.g) * t, c.b + (1 - c.b) * t) }
        for _ in 0..<24 { let t = (lo + hi) / 2; if luminance(mix(t)) < atLeast { lo = t } else { hi = t } }
        return mix(hi)
    }
    // The icon drawn at 24 × 24: saturated, not too dark pixels vote for one of 18 hues by saturation × brightness; the winning hue's average colour, when it carries enough of the icon
    static func dominant(_ image: CGImage) -> (r: Double, g: Double, b: Double)? {
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return nil }
        var weight = [Double](repeating: 0, count: 18), sum = [RGB](repeating: (0, 0, 0), count: 18)
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255; guard a > 0.5 else { continue }
            let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
            let mx = max(r, g, b), mn = min(r, g, b), sat = mx > 0 ? (mx - mn) / mx : 0
            guard mx > 0.15, sat > 0.25 else { continue }
            var h: Double = mx == r ? (g - b) / (mx - mn) : mx == g ? 2 + (b - r) / (mx - mn) : 4 + (r - g) / (mx - mn)
            h = (h < 0 ? h + 6 : h) / 6
            let k = min(17, Int(h * 18)), w = sat * mx
            weight[k] += w; sum[k] = (sum[k].r + r * w, sum[k].g + g * w, sum[k].b + b * w)
        }
        guard let k = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[k] > Double(n * n) * 0.03 else { return nil }
        return (min(1, sum[k].r / weight[k]), min(1, sum[k].g / weight[k]), min(1, sum[k].b / weight[k]))
    }
    static func darkened(_ c: (r: Double, g: Double, b: Double), atMost: Double) -> (r: Double, g: Double, b: Double) { toLuminance(c, atMost: atMost) }
    static func lightened(_ c: (r: Double, g: Double, b: Double), atLeast: Double) -> (r: Double, g: Double, b: Double) { toLuminance(c, atLeast: atLeast) }
}

// MARK: - Focus by game controller

/// What a game controller can focus, in screen order: Play, the summary strip's cells (one stop going up or down), the rows, then the screen's own controls.
enum LauncherFocus: Hashable {
    case controller(ObjectIdentifier)
    case play, summary(String), row(String), advanced, cloud, cloudOff, cloudAuto, reset, showAtLaunch, quit, support(String)
    var isSummary: Bool { if case .summary = self { return true } else { return false } }
    /// The id the screen's vertical scroll brings into view
    var scrollID: String {
        switch self {
        case .row(let e): return "row." + e
        case .controller(let id): return "controller." + String(describing: id)
        case .summary: return "summary"
        case .play: return "header"
        case .cloud, .cloudOff, .cloudAuto: return "cloud"
        case .reset: return "reset"
        case .advanced: return "advanced"
        case .showAtLaunch, .quit: return "footer"
        case .support(let e): return "support." + e
        }
    }
}

/// Navigation by game controller, read by polling: the game installs its own controller handlers when it starts (DmGamepad.m, front_mac.m), and a launcher that set them
/// would leave them pointing here. Up and down move the focus, taking the summary strip as one stop (it is entered at the cell last used there); left and right move along
/// the strip or step the focused value; A activates; B goes back to Play; Menu (+) plays from anywhere. A held direction repeats after 0.4 s. The focus is drawn only once
/// a controller has been used, and the controller's own button symbols are kept for the screen's hint.
@MainActor final class LauncherNav: ObservableObject {
    @Published var focus: LauncherFocus?
    @Published private(set) var active = false
    @Published private(set) var glyphs: (a: String, b: String, menu: String) = ("a.circle", "b.circle", "line.3.horizontal.circle")
    var order: () -> [LauncherFocus] = { [] }
    var adjust: (LauncherFocus, Int) -> Void = { _, _ in }
    var activate: (LauncherFocus) -> Void = { _ in }
    var play: () -> Void = {}

    private var held: [String: Date] = [:], lastFire: [String: Date] = [:]
    private var lastCell: LauncherFocus?

#if DEBUG
    /// Debug builds only, for screenshots of the focus without a controller: DM_LAUNCHER_FOCUS=play, summary:<id>, row:<VAR>, advanced, cloud, cloudOff, reset,
    /// showAtLaunch or quit starts with that item focused and the focus drawn. Release builds (the IPA, the Mac app) have no such switch
    init() {
        guard let f = ProcessInfo.processInfo.environment["DM_LAUNCHER_FOCUS"] else { return }
        let parts = f.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts[0], parts.count > 1 ? parts[1] : "") {
        case ("play", _): focus = .play
        case ("summary", let e): focus = .summary(e)
        case ("row", let e): focus = .row(e)
        case ("advanced", _): focus = .advanced
        case ("cloud", _): focus = .cloud
        case ("cloudOff", _): focus = .cloudOff
        case ("reset", _): focus = .reset
        case ("showAtLaunch", _): focus = .showAtLaunch
        case ("quit", _): focus = .quit
        default: return
        }
        active = true
    }
#endif

    func isFocused(_ f: LauncherFocus) -> Bool { active && focus == f }

    // The order as stops: consecutive strip cells are one
    private func stops(_ o: [LauncherFocus]) -> [[LauncherFocus]] {
        o.reduce(into: [[LauncherFocus]]()) { r, f in if f.isSummary, let last = r.last?.last, last.isSummary { r[r.count - 1].append(f) } else { r.append([f]) } }
    }
    func move(_ d: Int) {
        let o = order(); guard !o.isEmpty else { return }
        active = true
        let st = stops(o)
        guard let f = focus, let i = st.firstIndex(where: { $0.contains(f) }) else { focus = o.first; return }
        let to = st[max(0, min(st.count - 1, i + d))]
        if to.count > 1 || to.first?.isSummary == true { focus = lastCell.flatMap { to.contains($0) ? $0 : nil } ?? to.first } else { focus = to.first }
        if let f = focus, f.isSummary { lastCell = f }
    }
    func side(_ d: Int) {
        active = true
        guard let f = focus else { focus = order().first; return }
        if f.isSummary {   // along the strip: the next or previous cell
            let cells = order().filter(\.isSummary)
            if let i = cells.firstIndex(of: f), cells.indices.contains(i + d) { focus = cells[i + d]; lastCell = focus }
            return
        }
        adjust(f, d)
    }
    func press() {
        active = true
        guard let f = focus else { focus = order().first; return }
        if f == .play { play() } else { activate(f) }
    }

    /// Runs while the view is on screen (`.task { await nav.run() }`)
    func run() async {
        while !Task.isCancelled {
            poll()
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func poll() {
        var up = false, down = false, left = false, right = false, a = false, b = false, menu = false
        for c in GCController.controllers() {
            if let g = c.extendedGamepad {
                up = up || g.dpad.up.isPressed || g.leftThumbstick.yAxis.value > 0.5
                down = down || g.dpad.down.isPressed || g.leftThumbstick.yAxis.value < -0.5
                left = left || g.dpad.left.isPressed || g.leftThumbstick.xAxis.value < -0.5
                right = right || g.dpad.right.isPressed || g.leftThumbstick.xAxis.value > 0.5
                a = a || g.buttonA.isPressed; b = b || g.buttonB.isPressed; menu = menu || g.buttonMenu.isPressed
                if a || b || menu || up || down || left || right {   // the symbols of the controller in use (a Switch pad's A is where an Xbox pad's B is)
                    let now = (a: g.buttonA.sfSymbolsName ?? "a.circle", b: g.buttonB.sfSymbolsName ?? "b.circle", menu: g.buttonMenu.sfSymbolsName ?? "line.3.horizontal.circle")
                    if now != glyphs { glyphs = now }
                }
            } else if let g = c.microGamepad {
                up = up || g.dpad.up.isPressed; down = down || g.dpad.down.isPressed
                left = left || g.dpad.left.isPressed; right = right || g.dpad.right.isPressed
                a = a || g.buttonA.isPressed; menu = menu || g.buttonMenu.isPressed
            }
        }
        if fires("up", up, repeats: true) { move(-1) }
        if fires("down", down, repeats: true) { move(1) }
        if fires("left", left, repeats: true) { side(-1) }
        if fires("right", right, repeats: true) { side(1) }
        if fires("a", a, repeats: false) { press() }
        if fires("b", b, repeats: false) { active = true; focus = .play }
        if fires("menu", menu, repeats: false) { play() }
    }
    private func fires(_ k: String, _ down: Bool, repeats: Bool) -> Bool {
        let now = Date()
        guard down else { held[k] = nil; return false }
        guard let t0 = held[k] else { held[k] = now; lastFire[k] = now; return true }
        guard repeats, now.timeIntervalSince(t0) > 0.4, now.timeIntervalSince(lastFire[k] ?? t0) > 0.09 else { return false }
        lastFire[k] = now; return true
    }
}

/// What the controller's buttons do, in its own symbols: shown once a controller has been used
struct PadHint: View {
    @ObservedObject var nav: LauncherNav
    var body: some View {
        if nav.active {
            HStack(spacing: 14) {
                Label("Choose", systemImage: nav.glyphs.a)
                Label("Back to Play", systemImage: nav.glyphs.b)
                Label("Play", systemImage: nav.glyphs.menu)
            }
            .font(.footnote).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The focus a controller moved here: a ring in the game's tint, drawn outside the content so nothing shifts, following a capsule's shape around a capsule
struct FocusRing: ViewModifier {
    let on: Bool
    let tint: GameTint
    var radius: CGFloat = 12
    var capsule = false
    func body(content: Content) -> some View {
        content.overlay {
            if on {
                Group {
                    if capsule { Capsule(style: .continuous).strokeBorder(tint.mark, lineWidth: 3) }
                    else { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(tint.mark, lineWidth: 3) }
                }
                .padding(-6).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
extension View {
    func focusRing(_ on: Bool, _ tint: GameTint, radius: CGFloat = 12) -> some View { modifier(FocusRing(on: on, tint: tint, radius: radius)) }
    func focusCapsule(_ on: Bool, _ tint: GameTint) -> some View { modifier(FocusRing(on: on, tint: tint, capsule: true)) }
}

// MARK: - Header

/// The game: its icon, name and version, and Play at the trailing edge; Play goes under the name only when the header is narrower than `stackBelow` or the text is at an
/// accessibility size. A long name wraps beside Play rather than pushing it down (a phone in landscape keeps its first screen for the settings)
struct GameHeader<PlayButton: View>: View {
    let icon: Image?
    let name: String
    let version: String
    var iconSize: CGFloat = 96
    var stackBelow: CGFloat = 520
    @ViewBuilder let play: () -> PlayButton
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous) }
    private var iconView: some View {
        Group {
            if let icon {
                icon.resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
            } else {
                shape.fill(.quaternary)
                    .overlay { Image(systemName: "gamecontroller.fill").font(.system(size: iconSize * 0.4)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.title.weight(.bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if !version.isEmpty { Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize || (width > 0 && width < stackBelow) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) { iconView; titles }
                    play()
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    iconView
                    titles
                    play().fixedSize()
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

// MARK: - Summary strip

/// One fact the strip states: a setting's value, or the cloud saves. Each cell takes the player to where it is set
struct SummaryItem: Identifiable {
    let id: String
    let value: String
    let caption: String
    var changed = false
    var locked = false
    var focus: LauncherFocus { .summary(id) }
}

extension LauncherModel {
    /// The strip's cells for the summary settings: a range by its percentage (its row has the size in pixels)
    func summaryItems() -> [SummaryItem] {
        summary.map { s in
            var v = valueLabel(s)
            if s.kind == "range", !isInvalid(s), let x = Double(value(s)), x.isFinite, abs(x) < 1e6 { v = "\(Int((x * 100).rounded())) %" }
            return SummaryItem(id: s.env, value: v, caption: s.label, changed: isChanged(s), locked: fixed.contains(s.env))
        }
    }
}

/// What Play starts with, one fact per cell, divided by hairlines on the page's own ground as a product page's information row. A cell takes the player to its setting.
/// One line when every cell fits at its own width (the spare width goes between them); otherwise the cells wrap onto further lines of equal columns, a value taking two
/// lines where it must. Nothing scrolls sideways, so every fact is in view and a focused cell's ring is never clipped
struct SummaryStrip: View {
    let items: [SummaryItem]
    let tint: GameTint
    @ObservedObject var nav: LauncherNav
    let select: (SummaryItem) -> Void
    @State private var width: CGFloat = 0

    private func cell(_ it: SummaryItem, wraps: Bool) -> some View {
        Button { select(it) } label: {
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if it.locked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                    else if it.changed { Circle().fill(tint.mark).frame(width: 7, height: 7) }
                    Text(it.value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(wraps ? 2 : 1).multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                }
                Text(it.caption).font(.caption).foregroundStyle(.secondary).lineLimit(wraps ? 2 : 1).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minWidth: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
#if os(iOS)
        .hoverEffect(.highlight)
#endif
        .focusRing(nav.isFocused(it.focus), tint, radius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(it.caption)
        .accessibilityValue(it.value + (it.locked ? ", fixed" : it.changed ? ", changed from the tested default" : ""))
        .accessibilityHint("Shows this setting")
        .accessibilityAddTraits(.isButton)
    }
    private var line: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                if i > 0 {   // as tall as the cells, at any text size; spare width goes between the cells, so none is cut to share it equally
                    Spacer(minLength: 0)
                    Divider().padding(.vertical, 12)
                    Spacer(minLength: 0)
                }
                cell(it, wraps: false).fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    // As few lines as cells of at least 120 pt allow, the cells spread evenly over them (7 cells in 520 pt: 4 and 3)
    private var columns: Int {
        let most = max(2, min(items.count, Int(width / 120))), lines = (items.count + most - 1) / most
        return max(1, (items.count + lines - 1) / lines)
    }
    private var wrapped: some View {
        let n = columns
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: n), spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                cell(it, wraps: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)   // a value on two lines rises: every caption of a line stays level
                    .overlay(alignment: .leading) { if i % n != 0 { HStack { Divider() }.padding(.vertical, 12) } }   // in an HStack: a vertical hairline
            }
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) { line; wrapped }
            .padding(.vertical, 8).padding(.horizontal, 8)   // room for a focus ring outside the cells
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 16 } action: { width = $0 }
    }
}

// MARK: - A setting

extension LauncherModel {
    func binding(_ s: Setting) -> Binding<String> { Binding(get: { self.values[s.env] ?? s.def }, set: { self.values[s.env] = $0 }) }
}

struct SettingRow: View {
    let s: Setting
    @ObservedObject var m: LauncherModel
    var tint: GameTint = .system
    var focused = false

    private var locked: Bool { m.fixed.contains(s.env) }
    private var changed: Bool { !locked && m.isChanged(s) }
    private var note: String {
        guard locked else { return s.note }
        return (s.note.isEmpty ? "" : s.note + " · ") + (m.fromLaunch.contains(s.env) ? "Set at launch" : "Set by an env file")
    }
    private var bounds: ClosedRange<Double> {
        let lo = s.min ?? 0, hi = s.max ?? 1
        return lo < hi ? lo...hi : lo...(lo + 1)
    }
    private var rangeValue: Binding<Double> {
        Binding(get: {
                    let v = Double(m.value(s)) ?? .nan
                    return v.isFinite ? Swift.min(bounds.upperBound, Swift.max(bounds.lowerBound, v)) : bounds.upperBound
                },
                set: { m.values[s.env] = String(format: "%.2f", $0) })
    }
    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    private var settingLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
            else if changed { Circle().fill(tint.mark).frame(width: 7, height: 7).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.label)
                if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
    private var readout: some View { Text(m.valueLabel(s)).monospacedDigit().foregroundStyle(.secondary).contentTransition(.numericText()) }
    // The problem and the way out: which line to change, and the values it may take
    private var invalidHelp: String {
        let where_ = m.fromLaunch.contains(s.env) ? "the launch environment" : "env.txt"
        let takes: String
        switch s.kind {
        case "range": takes = "a number from \(s.min.map { String($0) } ?? "?") to \(s.max.map { String($0) } ?? "?")"
        case "choice": takes = (s.options ?? []).compactMap(\.first).joined(separator: ", ")
        default: takes = "\(s.onValue) or \(s.offValue)"
        }
        return "Not a value this setting offers; the game gets it as set. Remove \(s.env) from \(where_), or set it to \(takes)."
    }

    @ViewBuilder private var control: some View {
        if m.isInvalid(s) {
            // An env file's value this build does not offer (DM_RENDER_SCALE=nan): no control can show it, and the game gets it as set
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { settingLabel; Spacer(minLength: 12); readout }
                    VStack(alignment: .leading, spacing: 4) { settingLabel; readout }
                }
                Label(invalidHelp, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            switch s.kind {
            case "choice":
                Picker(selection: m.binding(s)) {
                    ForEach(s.options ?? [], id: \.self) { o in Text(o.count > 1 ? o[1] : o.first ?? "").tag(o.first ?? "") }
                } label: { settingLabel }
                .pickerStyle(.menu)
                .tint(.secondary)   // the value reads as the row's value, as on the Mac: the game's tint marks only what changed or has the focus
            case "range":
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { settingLabel; Spacer(minLength: 12); readout }
                        VStack(alignment: .leading, spacing: 4) { settingLabel; readout }
                    }
                    // The ends beside the slider, not as its value labels: the Mac draws those in the tint, which here means changed or focused only, and shows its label a second time
                    HStack(spacing: 8) {
                        Text(percent(bounds.lowerBound)).font(.caption).monospacedDigit().foregroundStyle(.secondary).accessibilityHidden(true)
                        Slider(value: rangeValue, in: bounds, step: s.step ?? 0.05) { Text(s.label) }
                            .labelsHidden()
                            .accessibilityLabel(s.label)
                            .accessibilityValue(m.valueLabel(s))
                        Text(percent(bounds.upperBound)).font(.caption).monospacedDigit().foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
            default:
                Toggle(isOn: Binding(get: { m.value(s) == s.onValue }, set: { m.values[s.env] = $0 ? s.onValue : s.offValue })) { settingLabel }
            }
        }
    }

    var body: some View {
        control
            .disabled(locked)
            .focusRing(focused, tint)
            .contextMenu {
                if changed {
                    Button { m.useDefault(s) } label: { Label("Use tested default (\(m.defaultLabel(s)))", systemImage: "arrow.uturn.backward") }
                }
            }
            .id("row." + s.env)
    }
}
