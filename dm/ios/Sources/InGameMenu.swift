// In-game menu: opened over the paused game by the touch controls' menu button, a controller's Home button, or − and + held together (DmGamepad.m, front_ios.m dm_ingame_menu_request).
// A panel at the trailing edge with the game's last picture dimmed beside it. The picture settings and the touch controls change at once; a setting the host reads only when the
// game starts (anisotropic filtering, Metal 4 pipelines) is marked for the next start. Choices the launcher also offers are saved the way the launcher saves them ("launcher.<VAR>"
// in UserDefaults, only while they differ from the game's default; LauncherModel.apply), so the next start and the launcher show them; a value an env file or the launch environment
// fixed is shown, not changed. A controller moves through it by polling (the game's own controller handlers stay in place, as for the launcher): up and down move, left and right
// change the value, A chooses, B, + or Home resume.
import SwiftUI
import UIKit
import GameController

/// The launcher's list for this game (dm/launcher.json): which rows it has, their defaults, and which values are fixed
@MainActor final class LauncherChoices {
    private var byEnv: [String: Setting] = [:]
    private let fixed: Set<String>
    init() {
        let env = ProcessInfo.processInfo.environment
        fixed = Set(((env["DM_ENV_FILE_KEYS"] ?? "") + " " + (env["DM_ENV_LAUNCH_KEYS"] ?? "")).split(separator: " ").map(String.init))
        if let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(SettingsFile.self, from: data) {
            for s in file.settings { byEnv[s.env] = s }
        }
    }
    func offers(_ env: String) -> Bool { byEnv[env] != nil }
    func isFixed(_ env: String) -> Bool { fixed.contains(env) }
    func setting(_ env: String) -> Setting? { byEnv[env] }
    /// The value the game started with: what the launcher (or an env file) put in the environment, else the game's default
    func current(_ env: String) -> String? { getenv(env).map { String(cString: $0) } ?? byEnv[env]?.def }
    func isOn(_ env: String) -> Bool { guard let v = current(env) else { return false }; return v == (byEnv[env]?.onValue ?? "1") }
    /// Keeps a choice as the launcher's Play does, and puts it in the environment (what the host reads at its next start)
    func save(_ env: String, _ value: String) {
        guard !fixed.contains(env) else { return }
        setenv(env, value, 1)
        guard let s = byEnv[env], getenv("DM_SAVED_CHOICES").map({ String(cString: $0) }) != "0" else { return }
        if s.isDefault(value) { UserDefaults.standard.removeObject(forKey: "launcher." + env) } else { UserDefaults.standard.set(value, forKey: "launcher." + env) }
        fputs("in-game menu: \(env)=\(value)\n", stderr)
    }
    func save(_ env: String, on: Bool) { save(env, on ? (byEnv[env]?.onValue ?? "1") : (byEnv[env]?.offValue ?? "0")) }
}

enum MenuItem: Hashable { case resume, upscale, sharpen, pixels, fit, fps, hud, aniso, metal4, layout, opacity, size, edit, haptics, shown, reset }

/// The menu's values. Each change goes to the host or the touch controls at once (ingame.h) and is kept
@MainActor @Observable final class InGameMenuModel {
    let choices = LauncherChoices()
    let upscaleSupported = dm_present_upscale_supported() != 0
    let tapAllowed = dm_pad_tap_allowed() != 0
    let controllerInUse = dm_pad_controller_in_use() != 0

    var upscale = dm_present_upscale() != 0 { didSet { dm_present_set_upscale(upscale ? 1 : 0); choices.save("DM_PRESENT_UPSCALE", upscale ? "metalfx" : "off") } }
    var sharpen = Double(dm_present_sharpen()) { didSet { dm_present_set_sharpen(Float(sharpen)); choices.save("DM_PRESENT_SHARPEN", String(format: "%.2f", sharpen)) } }
    var sharpPixels = dm_present_nearest() != 0 { didSet { dm_present_set_nearest(sharpPixels ? 1 : 0); choices.save("DM_PRESENT_FILTER", sharpPixels ? "nearest" : "linear") } }
    var stretch = dm_present_stretch() != 0 { didSet { front_set_stretch(stretch ? 1 : 0); choices.save("DM_PRESENT_FIT", stretch ? "stretch" : "aspect") } }
    var fpsCounter = front_fps_counter() != 0 { didSet { front_set_fps_counter(fpsCounter ? 1 : 0); choices.save("DM_SHOW_FPS", on: fpsCounter) } }
    var metalHUD = front_metal_hud() != 0 { didSet { front_set_metal_hud(metalHUD ? 1 : 0); choices.save("DM_METAL_HUD", on: metalHUD) } }
    var aniso: String { didSet { choices.save("DM_ANISO", aniso) } }   // next start
    var metal4: Bool { didSet { choices.save("DM_PSO_MTL4", on: metal4) } }   // next start

    var layout = Int(dm_pad_layout()) { didSet { if layout != oldValue { dm_pad_set_layout(Int32(layout)) } } }
    var opacity = Double(dm_pad_opacity()) { didSet { dm_pad_set_opacity(Float(opacity)) } }
    var size = Double(dm_pad_scale()) { didSet { dm_pad_set_scale(Float(size)) } }
    var haptics = dm_pad_haptics() != 0 { didSet { guard !choices.isFixed("DM_TOUCH_HAPTICS") else { return }; dm_pad_set_haptics(haptics ? 1 : 0); choices.save("DM_TOUCH_HAPTICS", on: haptics) } }
    var controlsShown = dm_pad_visible() != 0 { didSet { dm_pad_set_visible(controlsShown ? 1 : 0) } }

    init() {
        let c = choices
        aniso = c.current("DM_ANISO") ?? "0"
        metal4 = c.isOn("DM_PSO_MTL4")
    }

    /// Differs from the game's tested default: the launcher's 7 pt tint dot, for the rows both screens have
    func changed(_ env: String, _ value: String) -> Bool { choices.setting(env).map { !$0.isDefault(value) } ?? false }
    func changed(_ env: String, on: Bool) -> Bool { choices.setting(env).map { !$0.isDefault(on ? $0.onValue : $0.offValue) } ?? false }

    var anisoOptions: [[String]] { choices.setting("DM_ANISO")?.options?.filter { $0.count == 2 } ?? [] }
    var layoutOptions: [(Int, String)] { [(0, "2D"), (1, "3D")] + (tapAllowed ? [(2, "Tap")] : []) }

    /// The rows a controller moves through, in screen order
    var order: [MenuItem] {
        var o: [MenuItem] = [.resume, .upscale, .sharpen, .pixels, .fit, .fps]
        if choices.offers("DM_METAL_HUD") { o.append(.hud) }
        if !anisoOptions.isEmpty { o.append(.aniso) }
        o += [.layout, .opacity, .size, .edit, .haptics, .shown, .reset]
        if choices.offers("DM_PSO_MTL4") { o.append(.metal4) }
        return o
    }

    func resetControls() {
        dm_pad_reset_layout()
        opacity = Double(dm_pad_opacity()); size = Double(dm_pad_scale()); controlsShown = dm_pad_visible() != 0
    }

    /// A controller's left or right on a row
    func step(_ item: MenuItem, _ d: Int) {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
        switch item {
        case .upscale: if upscaleSupported && !choices.isFixed("DM_PRESENT_UPSCALE") { upscale = d > 0 }
        case .sharpen: if !choices.isFixed("DM_PRESENT_SHARPEN") { sharpen = clamp(((sharpen + Double(d) * 0.05) * 20).rounded() / 20, 0, 1) }
        case .pixels: if !choices.isFixed("DM_PRESENT_FILTER") { sharpPixels = d > 0 }
        case .fit: if !choices.isFixed("DM_PRESENT_FIT") { stretch = d > 0 }
        case .fps: if !choices.isFixed("DM_SHOW_FPS") { fpsCounter = d > 0 }
        case .hud: if !choices.isFixed("DM_METAL_HUD") { metalHUD = d > 0 }
        case .metal4: if !choices.isFixed("DM_PSO_MTL4") { metal4 = d > 0 }
        case .haptics: if !choices.isFixed("DM_TOUCH_HAPTICS") { haptics = d > 0 }
        case .shown: controlsShown = d > 0
        case .aniso:
            guard !choices.isFixed("DM_ANISO"), let i = anisoOptions.firstIndex(where: { $0[0] == aniso }) ?? anisoOptions.indices.first else { return }
            aniso = anisoOptions[max(0, min(anisoOptions.count - 1, i + d))][0]
        case .layout:
            let o = layoutOptions.map(\.0); let i = o.firstIndex(of: layout) ?? 0
            layout = o[max(0, min(o.count - 1, i + d))]
        case .opacity: opacity = clamp(((opacity + Double(d) * 0.1) * 10).rounded() / 10, 0.2, 1)
        case .size: size = clamp(((size + Double(d) * 0.05) * 20).rounded() / 20, 0.7, 1.3)
        case .resume, .edit, .reset: break
        }
    }
}

/// Controller navigation by polling. The button that opened the menu (Home, or − and + together) is still down when it appears: buttons held at the first look count only once
/// released and pressed again
@MainActor @Observable final class InGameNav {
    var focus: MenuItem?
    private(set) var active = false
    private(set) var glyphs: (a: String, b: String) = ("a.circle", "b.circle")
    @ObservationIgnored var order: () -> [MenuItem] = { [] }
    @ObservationIgnored var adjust: (MenuItem, Int) -> Void = { _, _ in }
    @ObservationIgnored var activate: (MenuItem) -> Void = { _ in }
    @ObservationIgnored var resume: () -> Void = {}
    @ObservationIgnored private var held: [String: Date] = [:]
    @ObservationIgnored private var lastFire: [String: Date] = [:]
    @ObservationIgnored private var primed = false

    func isFocused(_ f: MenuItem) -> Bool { active && focus == f }

    func run() async {
        while !Task.isCancelled {
            poll()
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
    private func move(_ d: Int) {
        let o = order(); guard !o.isEmpty else { return }
        active = true
        guard let f = focus, let i = o.firstIndex(of: f) else { focus = o.first; return }
        focus = o[max(0, min(o.count - 1, i + d))]
    }
    private func poll() {
        var up = false, down = false, left = false, right = false, a = false, b = false, back = false
        for c in GCController.controllers() {
            guard let g = c.extendedGamepad else { continue }
            up = up || g.dpad.up.isPressed || g.leftThumbstick.yAxis.value > 0.5
            down = down || g.dpad.down.isPressed || g.leftThumbstick.yAxis.value < -0.5
            left = left || g.dpad.left.isPressed || g.leftThumbstick.xAxis.value < -0.5
            right = right || g.dpad.right.isPressed || g.leftThumbstick.xAxis.value > 0.5
            a = a || g.buttonA.isPressed; b = b || g.buttonB.isPressed
            back = back || g.buttonMenu.isPressed || (g.buttonHome?.isPressed ?? false)
            if a || b || up || down || left || right {
                let now = (a: g.buttonA.sfSymbolsName ?? "a.circle", b: g.buttonB.sfSymbolsName ?? "b.circle")
                if now != glyphs { glyphs = now }
            }
        }
        if !primed {   // what is held now opened the menu: it counts once released
            primed = true
            for (k, v) in [("up", up), ("down", down), ("left", left), ("right", right), ("a", a), ("b", b), ("back", back)] where v { held[k] = .distantFuture }
            return
        }
        if fires("up", up, repeats: true) { move(-1) }
        if fires("down", down, repeats: true) { move(1) }
        if fires("left", left, repeats: true) { if let f = focus { active = true; adjust(f, -1) } else { move(0) } }
        if fires("right", right, repeats: true) { if let f = focus { active = true; adjust(f, 1) } else { move(0) } }
        if fires("a", a, repeats: false) { if let f = focus { active = true; activate(f) } else { move(0) } }
        if fires("b", b, repeats: false) || fires("back", back, repeats: false) { resume() }
    }
    private func fires(_ k: String, _ down: Bool, repeats: Bool) -> Bool {
        let now = Date()
        guard down else { held[k] = nil; return false }
        guard let t0 = held[k] else { held[k] = now; lastFire[k] = now; return true }
        guard repeats, t0 != .distantFuture, now.timeIntervalSince(t0) > 0.4, now.timeIntervalSince(lastFire[k] ?? t0) > 0.09 else { return false }
        lastFire[k] = now; return true
    }
}

/// The launcher's changed-value mark: a 7 pt dot in the game's tint before the name
private struct ChangedDot: View {
    let on: Bool
    let tint: GameTint
    var body: some View { if on { Circle().fill(tint.mark).frame(width: 7, height: 7).accessibilityHidden(true) } }
}

/// One setting on the panel: its name (after the changed dot), an optional value, the control, and a note (the next start, a value fixed by an env file). A compact
/// control (a segmented choice) sits beside the name when both fit and under it when they do not, so a row reflows rather than clips (the launcher's Whole Row Rule);
/// a slider always goes under. VoiceOver reads the control, which carries the name: the visible name and readout are not read again
private struct MenuRow<Control: View>: View {
    let title: String
    var value: String? = nil
    var note: String? = nil
    var changed = false
    var inline = false
    let focused: Bool
    let tint: GameTint
    @ViewBuilder let control: Control
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ChangedDot(on: changed, tint: tint)
            Text(title)
            Spacer(minLength: 8)
            if let value { Text(value).monospacedDigit().contentTransition(.numericText()).foregroundStyle(.secondary) }
        }
        .accessibilityHidden(true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if inline {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { name; control.fixedSize() }
                    VStack(alignment: .leading, spacing: 8) { name; control }
                }
            } else {
                name
                control
            }
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusRing(focused, tint, radius: 12)
    }
}

/// A choice: segmented while its labels fit at the reader's text size, a menu at the accessibility sizes, where a segmented control would truncate them
private struct ChoicePicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize { Picker(title, selection: $selection) { content }.pickerStyle(.menu) }
        else { Picker(title, selection: $selection) { content }.pickerStyle(.segmented).labelsHidden() }
    }
}

/// A switch on the panel: the name (after the changed dot) beside the switch, the note under it
private struct MenuToggle: View {
    let title: String
    @Binding var isOn: Bool
    var note: String? = nil
    var disabled = false
    var changed = false
    let focused: Bool
    let tint: GameTint
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) { HStack(spacing: 6) { ChangedDot(on: changed, tint: tint); Text(title) } }
                .disabled(disabled)
                .accessibilityLabel(title)
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusRing(focused, tint, radius: 12)
    }
}

struct InGameMenuView: View {
    @Bindable var model: InGameMenuModel
    let name: String
    let icon: UIImage?
    let tint: GameTint
    let resume: () -> Void
    let edit: () -> Void
    @State private var nav = InGameNav()
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let nextStart = "Applies at the next start."
    private func fixedNote(_ env: String) -> String? { model.choices.isFixed(env) ? "Set by env.txt or at launch." : nil }
    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: resume).accessibilityHidden(true)   // beside the panel: resume
                panel.frame(width: panelWidth(geo.size.width))
            }
        }
        .background(Color.black.opacity(0.45).ignoresSafeArea())
        .task {
            nav.order = { model.order }
            nav.adjust = { model.step($0, $1) }
            nav.activate = { item in
                switch item {
                case .resume: resume()
                case .edit: edit()
                case .reset: model.resetControls()
                case .upscale: model.step(.upscale, model.upscale ? -1 : 1)
                case .pixels: model.step(.pixels, model.sharpPixels ? -1 : 1)
                case .fit: model.step(.fit, model.stretch ? -1 : 1)
                case .fps: model.step(.fps, model.fpsCounter ? -1 : 1)
                case .hud: model.step(.hud, model.metalHUD ? -1 : 1)
                case .metal4: model.step(.metal4, model.metal4 ? -1 : 1)
                case .haptics: model.step(.haptics, model.haptics ? -1 : 1)
                case .shown: model.controlsShown.toggle()
                case .layout: model.step(.layout, 1)
                case .aniso: model.step(.aniso, 1)
                case .sharpen, .opacity, .size: model.step(item, 1)
                }
            }
            nav.resume = resume
            await nav.run()
        }
    }

    private func panelWidth(_ w: CGFloat) -> CGFloat {
        typeSize.isAccessibilitySize ? min(w - 24, max(420, w * 0.8)) : min(460, max(340, w * 0.5))
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Picture")
                        pictureRows
                        sectionTitle("Touch controls", note: model.controllerInUse ? "Hidden while a controller is connected." : nil)
                        controlRows
                        if model.choices.offers("DM_PSO_MTL4") {
                            sectionTitle("Performance")
                            MenuToggle(title: "Metal 4 pipelines", isOn: $model.metal4, note: fixedNote("DM_PSO_MTL4") ?? "Draws with stand-ins while new pipelines build, so scenes do not freeze. " + Self.nextStart,
                                       disabled: model.choices.isFixed("DM_PSO_MTL4"), changed: model.changed("DM_PSO_MTL4", on: model.metal4), focused: nav.isFocused(.metal4), tint: tint).id(MenuItem.metal4)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
                .onChange(of: nav.focus) { _, f in if let f { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(f, anchor: .center) } } }
            }
            if nav.active {
                HStack(spacing: 14) {
                    Label("Choose", systemImage: nav.glyphs.a)
                    Label("Resume", systemImage: nav.glyphs.b)
                }
                .font(.footnote).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .tint(tint.fill)   // sliders, switches and segments in the game's colour, as on the launcher
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.vertical, 10).padding(.trailing, 10)
        .accessibilityAction(.escape, resume)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(uiImage: icon).resizable().frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(2)
                Text("Paused").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: resume) { Label("Resume", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent).tint(tint.fill)
                .focusCapsule(nav.isFocused(.resume), tint)
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .id(MenuItem.resume)
    }

    private func sectionTitle(_ t: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.headline)
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.top, 8).padding(.leading, 4)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var pictureRows: some View {
        MenuRow(title: "Upscaling", note: model.upscaleSupported ? (fixedNote("DM_PRESENT_UPSCALE") ?? "MetalFX uses more GPU time and can increase heat.") : "This GPU has no MetalFX spatial scaler.",
                changed: model.changed("DM_PRESENT_UPSCALE", model.upscale ? "metalfx" : "off"), inline: true, focused: nav.isFocused(.upscale), tint: tint) {
            ChoicePicker(title: "Upscaling", selection: $model.upscale) { Text("Standard").tag(false); Text("MetalFX").tag(true) }
                .disabled(!model.upscaleSupported || model.choices.isFixed("DM_PRESENT_UPSCALE"))
        }.id(MenuItem.upscale)
        MenuRow(title: "Sharpness", value: model.sharpen > 0 ? percent(model.sharpen) : "Off", note: fixedNote("DM_PRESENT_SHARPEN"),
                changed: model.changed("DM_PRESENT_SHARPEN", String(format: "%.2f", model.sharpen)), focused: nav.isFocused(.sharpen), tint: tint) {
            Slider(value: $model.sharpen, in: 0...1, step: 0.05) { Text("Sharpness") }
                .disabled(model.choices.isFixed("DM_PRESENT_SHARPEN"))
                .accessibilityValue(model.sharpen > 0 ? percent(model.sharpen) : "Off")
        }.id(MenuItem.sharpen)
        MenuRow(title: "Pixels", note: fixedNote("DM_PRESENT_FILTER") ?? (model.sharpPixels ? "Each pixel as the game draws it; MetalFX is not used." : nil),
                changed: model.changed("DM_PRESENT_FILTER", model.sharpPixels ? "nearest" : "linear"), inline: true, focused: nav.isFocused(.pixels), tint: tint) {
            ChoicePicker(title: "Pixels", selection: $model.sharpPixels) { Text("Smooth").tag(false); Text("Sharp").tag(true) }
                .disabled(model.choices.isFixed("DM_PRESENT_FILTER"))
        }.id(MenuItem.pixels)
        MenuRow(title: "Screen", note: fixedNote("DM_PRESENT_FIT"), changed: model.changed("DM_PRESENT_FIT", model.stretch ? "stretch" : "aspect"), inline: true,
                focused: nav.isFocused(.fit), tint: tint) {
            ChoicePicker(title: "Screen", selection: $model.stretch) { Text("Game's shape").tag(false); Text("Fill screen").tag(true) }
                .disabled(model.choices.isFixed("DM_PRESENT_FIT"))
        }.id(MenuItem.fit)
        MenuToggle(title: "Frame-rate counter", isOn: $model.fpsCounter, note: fixedNote("DM_SHOW_FPS"), disabled: model.choices.isFixed("DM_SHOW_FPS"),
                   changed: model.changed("DM_SHOW_FPS", on: model.fpsCounter), focused: nav.isFocused(.fps), tint: tint).id(MenuItem.fps)
        if model.choices.offers("DM_METAL_HUD") {
            MenuToggle(title: "Performance HUD", isOn: $model.metalHUD, note: fixedNote("DM_METAL_HUD"), disabled: model.choices.isFixed("DM_METAL_HUD"),
                       changed: model.changed("DM_METAL_HUD", on: model.metalHUD), focused: nav.isFocused(.hud), tint: tint).id(MenuItem.hud)
        }
        if !model.anisoOptions.isEmpty {
            MenuRow(title: "Texture filtering", note: fixedNote("DM_ANISO") ?? "Sharper textures seen at an angle. " + Self.nextStart,
                    changed: model.changed("DM_ANISO", model.aniso), focused: nav.isFocused(.aniso), tint: tint) {
                ChoicePicker(title: "Texture filtering", selection: $model.aniso) { ForEach(model.anisoOptions, id: \.[0]) { o in Text(o[1]).tag(o[0]) } }
                    .disabled(model.choices.isFixed("DM_ANISO"))
            }.id(MenuItem.aniso)
        }
    }

    @ViewBuilder private var controlRows: some View {
        MenuRow(title: "Layout", inline: true, focused: nav.isFocused(.layout), tint: tint) {
            ChoicePicker(title: "Layout", selection: $model.layout) { ForEach(model.layoutOptions, id: \.0) { o in Text(o.1).tag(o.0) } }
        }.id(MenuItem.layout)
        MenuRow(title: "Opacity", value: percent(model.opacity), focused: nav.isFocused(.opacity), tint: tint) {
            Slider(value: $model.opacity, in: 0.2...1, step: 0.1) { Text("Opacity") }.accessibilityValue(percent(model.opacity))
        }.id(MenuItem.opacity)
        MenuRow(title: "Size", value: percent(model.size), focused: nav.isFocused(.size), tint: tint) {
            Slider(value: $model.size, in: 0.7...1.3, step: 0.05) { Text("Size") }.accessibilityValue(percent(model.size))
        }.id(MenuItem.size)
        Button(action: edit) {
            Label("Move the controls…", systemImage: "hand.draw")
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).focusRing(nav.isFocused(.edit), tint, radius: 12).id(MenuItem.edit)
        .accessibilityHint("Closes the menu; drag the controls, then Done resumes the game")
        MenuToggle(title: "Touch feedback", isOn: $model.haptics, note: fixedNote("DM_TOUCH_HAPTICS"), disabled: model.choices.isFixed("DM_TOUCH_HAPTICS"),
                   changed: model.changed("DM_TOUCH_HAPTICS", on: model.haptics), focused: nav.isFocused(.haptics), tint: tint).id(MenuItem.haptics)
        MenuToggle(title: "Show touch controls", isOn: $model.controlsShown, note: model.controlsShown ? nil : "Only the menu button stays; every other touch goes to the game.",
                   focused: nav.isFocused(.shown), tint: tint).id(MenuItem.shown)
        Button(action: model.resetControls) {
            Label("Reset touch controls", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).focusRing(nav.isFocused(.reset), tint, radius: 12).id(MenuItem.reset)
        .accessibilityHint("Positions, size, opacity and visibility back to the defaults")
    }
}

/// Shows the menu over the paused game. closed: the game resumes (front_ios.m); Move the controls hands over to the layout editor instead, which resumes at its Done
@_cdecl("dm_show_ingame_menu")
public func dmShowIngameMenu(_ viewController: UnsafeMutableRawPointer, _ closed: @convention(c) () -> Void) -> Bool {
    MainActor.assumeIsolated { showIngameMenu(Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue(), closed) }   // front_ios.m calls it on the main queue
}
@MainActor private func showIngameMenu(_ parent: UIViewController, _ closed: @convention(c) () -> Void) -> Bool {
    let icon = appIcon()
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Game"
    weak var host: UIViewController?
    var finished = false
    let finish: (Bool) -> Void = { editing in
        guard !finished, let h = host, h.presentedViewController == nil else { return }   // something over the menu (an alert) is answered first
        finished = true
        h.dismiss(animated: true) { if editing { front_ingame_edit() } else { closed() } }
    }
    let view = InGameMenuView(model: InGameMenuModel(), name: name, icon: icon, tint: GameTint.from(icon?.cgImage), resume: { finish(false) }, edit: { finish(true) })
    let h = UIHostingController(rootView: view)
    h.modalPresentationStyle = .overFullScreen
    h.modalTransitionStyle = .crossDissolve
    h.view.backgroundColor = .clear
    h.overrideUserInterfaceStyle = .dark
    host = h
    parent.present(h, animated: true)
    return true
}
