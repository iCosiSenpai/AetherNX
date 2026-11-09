// Support links: the project on GitHub and the maintainer's donation pages, each with its brand's own mark. Shared by the iPhone launcher (Launcher.swift), the Mac app's settings
// window (dm/mac/Launcher.swift, built by pack_app.py) and the native storage regression test. The marks are the brands' published icons as Simple Icons distributes them (CC0),
// the same artwork iCosiSenpai's other apps ship: their SVG path data is kept here as it is and drawn by a small SVG path reader, so both platforms draw the original shapes
// without an asset catalog (the Mac app has none).
import SwiftUI

enum SupportLink: String, CaseIterable, Identifiable {
    case github, paypal, coffee
    var id: String { rawValue }

    var url: URL {
        switch self {
        case .github: return URL(string: "https://github.com/iCosiSenpai/AetherNX")!
        case .paypal: return URL(string: "https://paypal.me/AlessioCosi")!
        case .coffee: return URL(string: "https://buymeacoffee.com/icosisenpai")!
        }
    }
    var title: String {
        switch self {
        case .github: return "GitHub"
        case .paypal: return "PayPal"
        case .coffee: return "Buy Me a Coffee"
        }
    }
    var subtitle: String {
        switch self {
        case .github: return "Source, updates and bug reports"
        case .paypal: return "Donate any amount"
        case .coffee: return "Support development"
        }
    }
    /// The brand's chip and the colour of its mark on it
    var chip: Color {
        switch self {
        case .github: return Color(red: 0.09, green: 0.09, blue: 0.09)
        case .paypal: return Color(red: 0.0, green: 0.19, blue: 0.53)
        case .coffee: return Color(red: 1.0, green: 0.867, blue: 0.0)
        }
    }
    var onChip: Color { self == .coffee ? Color(red: 0.11, green: 0.09, blue: 0.0) : .white }
    /// The mark: SVG path data in a 24 × 24 view box (Simple Icons: github, paypal, buymeacoffee)
    var mark: String {
        switch self {
        case .github: return "M12 .297c-6.63 0-12 5.373-12 12c0 5.303 3.438 9.8 8.205 11.385c.6.113.82-.258.82-.577c0-.285-.01-1.04-.015-2.04c-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729c1.205.084 1.838 1.236 1.838 1.236c1.07 1.835 2.809 1.305 3.495.998c.108-.776.417-1.305.76-1.605c-2.665-.3-5.466-1.332-5.466-5.93c0-1.31.465-2.38 1.235-3.22c-.135-.303-.54-1.523.105-3.176c0 0 1.005-.322 3.3 1.23c.96-.267 1.98-.399 3-.405c1.02.006 2.04.138 3 .405c2.28-1.552 3.285-1.23 3.285-1.23c.645 1.653.24 2.873.12 3.176c.765.84 1.23 1.91 1.23 3.22c0 4.61-2.805 5.625-5.475 5.92c.42.36.81 1.096.81 2.22c0 1.606-.015 2.896-.015 3.286c0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"
        case .paypal: return "M15.607 4.653H8.941L6.645 19.251H1.82L4.862 0h7.995c3.754 0 6.375 2.294 6.473 5.513c-.648-.478-2.105-.86-3.722-.86m6.57 5.546c0 3.41-3.01 6.853-6.958 6.853h-2.493L11.595 24H6.74l1.845-11.538h3.592c4.208 0 7.346-3.634 7.153-6.949a5.24 5.24 0 0 1 2.848 4.686M9.653 5.546h6.408c.907 0 1.942.222 2.363.541c-.195 2.741-2.655 5.483-6.441 5.483H8.714Z"
        case .coffee: return "m20.216 6.415l-.132-.666c-.119-.598-.388-1.163-1.001-1.379c-.197-.069-.42-.098-.57-.241c-.152-.143-.196-.366-.231-.572c-.065-.378-.125-.756-.192-1.133c-.057-.325-.102-.69-.25-.987c-.195-.4-.597-.634-.996-.788a6 6 0 0 0-.626-.194c-1-.263-2.05-.36-3.077-.416a26 26 0 0 0-3.7.062c-.915.083-1.88.184-2.75.5c-.318.116-.646.256-.888.501c-.297.302-.393.77-.177 1.146c.154.267.415.456.692.58c.36.162.737.284 1.123.366c1.075.238 2.189.331 3.287.37q1.829.074 3.65-.118q.449-.05.896-.119c.352-.054.578-.513.474-.834c-.124-.383-.457-.531-.834-.473c-.466.074-.96.108-1.382.146q-1.767.12-3.536.006a22 22 0 0 1-1.157-.107c-.086-.01-.18-.025-.258-.036q-.364-.055-.724-.13c-.111-.027-.111-.185 0-.212h.005q.416-.09.838-.147h.002c.131-.009.263-.032.394-.048a25 25 0 0 1 3.426-.12q1.011.029 2.017.144l.228.031q.4.06.798.145c.392.085.895.113 1.07.542c.055.137.08.288.111.431l.319 1.484a.237.237 0 0 1-.199.284h-.003l-.112.015a37 37 0 0 1-4.743.295a37 37 0 0 1-4.699-.304c-.14-.017-.293-.042-.417-.06c-.326-.048-.649-.108-.973-.161c-.393-.065-.768-.032-1.123.161c-.29.16-.527.404-.675.701c-.154.316-.199.66-.267 1c-.069.34-.176.707-.135 1.056c.087.753.613 1.365 1.37 1.502a39.7 39.7 0 0 0 11.343.376a.483.483 0 0 1 .535.53l-.071.697l-1.018 9.907c-.041.41-.047.832-.125 1.237c-.122.637-.553 1.028-1.182 1.171q-.868.197-1.756.205c-.656.004-1.31-.025-1.966-.022c-.699.004-1.556-.06-2.095-.58c-.475-.458-.54-1.174-.605-1.793l-.731-7.013l-.322-3.094c-.037-.351-.286-.695-.678-.678c-.336.015-.718.3-.678.679l.228 2.185l.949 9.112c.147 1.344 1.174 2.068 2.446 2.272c.742.12 1.503.144 2.257.156c.966.016 1.942.053 2.892-.122c1.408-.258 2.465-1.198 2.616-2.657l1.024-9.995l.215-2.087a.48.48 0 0 1 .39-.426c.402-.078.787-.212 1.074-.518c.455-.488.546-1.124.385-1.766zm-1.478.772c-.145.137-.363.201-.578.233c-2.416.359-4.866.54-7.308.46c-1.748-.06-3.477-.254-5.207-.498c-.17-.024-.353-.055-.47-.18c-.22-.236-.111-.71-.054-.995c.052-.26.152-.609.463-.646c.484-.057 1.046.148 1.526.22q.865.132 1.737.212c2.48.226 5.002.19 7.472-.14q.675-.09 1.345-.21c.399-.072.84-.206 1.08.206c.166.281.188.657.162.974a.54.54 0 0 1-.169.364z"
        }
    }
}

/// SVG path data (the `d` attribute) as a SwiftUI path: every command (M L H V C S Q T A Z, absolute and relative, with implicit repeats), numbers as SVG writes them
/// (".6.113" is two numbers, arc flags may touch the next number). Arcs become cubic curves of at most a quarter turn. Malformed data ends the path where it stops making sense
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var r = Reader(Array(d.utf8)), p = Path()
        var cur = CGPoint.zero, start = CGPoint.zero, lastCubic: CGPoint?, lastQuad: CGPoint?
        var cmd: UInt8 = 0
        while true {
            r.skip()
            guard let c = r.peek() else { break }
            if Reader.isCommand(c) { cmd = c; r.i += 1 } else if cmd == 0 || cmd == UInt8(ascii: "z") || cmd == UInt8(ascii: "Z") { break }
            let rel = cmd >= UInt8(ascii: "a")
            func pt(_ x: Double, _ y: Double) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            var cubic: CGPoint?, quad: CGPoint?
            switch cmd | 0x20 {   // lower case
            case UInt8(ascii: "m"):
                guard let x = r.number(), let y = r.number() else { return p }
                cur = pt(x, y); start = cur; p.move(to: cur)
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")   // further pairs are lines
            case UInt8(ascii: "l"):
                guard let x = r.number(), let y = r.number() else { return p }
                cur = pt(x, y); p.addLine(to: cur)
            case UInt8(ascii: "h"):
                guard let x = r.number() else { return p }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); p.addLine(to: cur)
            case UInt8(ascii: "v"):
                guard let y = r.number() else { return p }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); p.addLine(to: cur)
            case UInt8(ascii: "c"):
                guard let x1 = r.number(), let y1 = r.number(), let x2 = r.number(), let y2 = r.number(), let x = r.number(), let y = r.number() else { return p }
                let c1 = pt(x1, y1), c2 = pt(x2, y2), e = pt(x, y)
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; cubic = c2
            case UInt8(ascii: "s"):
                guard let x2 = r.number(), let y2 = r.number(), let x = r.number(), let y = r.number() else { return p }
                let c1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur, c2 = pt(x2, y2), e = pt(x, y)
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; cubic = c2
            case UInt8(ascii: "q"):
                guard let x1 = r.number(), let y1 = r.number(), let x = r.number(), let y = r.number() else { return p }
                let c1 = pt(x1, y1), e = pt(x, y)
                p.addQuadCurve(to: e, control: c1); cur = e; quad = c1
            case UInt8(ascii: "t"):
                guard let x = r.number(), let y = r.number() else { return p }
                let c1 = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur, e = pt(x, y)
                p.addQuadCurve(to: e, control: c1); cur = e; quad = c1
            case UInt8(ascii: "a"):
                guard let rx = r.number(), let ry = r.number(), let rot = r.number(), let large = r.flag(), let sweep = r.flag(), let x = r.number(), let y = r.number() else { return p }
                let e = pt(x, y)
                arc(&p, from: cur, rx: rx, ry: ry, degrees: rot, large: large, sweep: sweep, to: e); cur = e
            case UInt8(ascii: "z"):
                p.closeSubpath(); cur = start
            default:
                return p
            }
            lastCubic = cubic; lastQuad = quad
        }
        return p
    }

    /// An elliptical arc (SVG's endpoint form) as cubic curves: the centre form of SVG 1.1 appendix F.6.5, then one curve per quarter turn or less
    static func arc(_ p: inout Path, from p0: CGPoint, rx rx0: Double, ry ry0: Double, degrees: Double, large: Bool, sweep: Bool, to p1: CGPoint) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { p.addLine(to: p1); return }
        let phi = degrees * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1, den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = den == 0 ? 0 : max(0, num / den).squareRoot()
        if large == sweep { k = -k }
        let cxp = k * rx * y1 / ry, cyp = -k * ry * x1 / rx
        let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2, cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let t1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dt = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi } else if sweep && dt < 0 { dt += 2 * .pi }
        let n = max(1, Int((abs(dt) / (.pi / 2)).rounded(.up))), step = dt / Double(n), h = 4.0 / 3.0 * tan(step / 4)
        func map(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + rx * x * cp - ry * y * sp, y: cy + rx * x * sp + ry * y * cp) }
        var t = t1
        for _ in 0..<n {
            let c1 = cos(t), s1 = sin(t), c2 = cos(t + step), s2 = sin(t + step)
            p.addCurve(to: map(c2, s2), control1: map(c1 - h * s1, s1 + h * c1), control2: map(c2 + h * s2, s2 - h * c2))
            t += step
        }
    }

    private struct Reader {
        let b: [UInt8]; var i = 0
        init(_ b: [UInt8]) { self.b = b }
        static func isCommand(_ c: UInt8) -> Bool { "MmLlHhVvCcSsQqTtAaZz".utf8.contains(c) }
        func peek() -> UInt8? { i < b.count ? b[i] : nil }
        mutating func skip() { while i < b.count, b[i] == 0x20 || b[i] == 0x2C || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 } }
        mutating func flag() -> Bool? {   // an arc flag: one character, which may touch the next number
            skip(); guard i < b.count, b[i] == UInt8(ascii: "0") || b[i] == UInt8(ascii: "1") else { return nil }
            defer { i += 1 }; return b[i] == UInt8(ascii: "1")
        }
        mutating func number() -> Double? {
            skip(); let s = i
            if i < b.count, b[i] == UInt8(ascii: "-") || b[i] == UInt8(ascii: "+") { i += 1 }
            var digits = false, dot = false
            while i < b.count {
                let c = b[i]
                if c >= 0x30 && c <= 0x39 { digits = true; i += 1 }
                else if c == UInt8(ascii: "."), !dot { dot = true; i += 1 }   // a second point starts the next number
                else { break }
            }
            guard digits else { i = s; return nil }
            if i < b.count, b[i] == UInt8(ascii: "e") || b[i] == UInt8(ascii: "E") {
                var j = i + 1
                if j < b.count, b[j] == UInt8(ascii: "-") || b[j] == UInt8(ascii: "+") { j += 1 }
                if j < b.count, b[j] >= 0x30 && b[j] <= 0x39 { i = j; while i < b.count, b[i] >= 0x30 && b[i] <= 0x39 { i += 1 } }
            }
            return Double(String(decoding: b[s..<i], as: UTF8.self))
        }
    }
}

/// A brand mark drawn from its SVG path data, its 24 × 24 view box fitted and centred in the frame
struct BrandMark: Shape {
    let link: SupportLink
    private static let paths: [SupportLink: Path] = Dictionary(uniqueKeysWithValues: SupportLink.allCases.map { ($0, SVGPath.parse($0.mark)) })
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        return (Self.paths[link] ?? Path()).applying(CGAffineTransform(translationX: rect.midX - 12 * s, y: rect.midY - 12 * s).scaledBy(x: s, y: s))
    }
}

/// The brand's chip: its mark on its colour, in a circle
struct SupportChip: View {
    let link: SupportLink
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            Circle().fill(link.chip)
            if link == .github { Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1) }   // the near-black chip on a dark row
            BrandMark(link: link).fill(link.onChip).padding(size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The links, last on the settings screen: each opens its page in the browser
struct SupportSection: View {
    let tint: GameTint
    let focused: (SupportLink) -> Bool
    var body: some View {
        Section {
            ForEach(SupportLink.allCases) { link in
                Link(destination: link.url) {
                    HStack(spacing: 12) {
                        SupportChip(link: link)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title).fontWeight(.semibold).foregroundStyle(.primary)
                            Text(link.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
#if os(macOS)
                .buttonStyle(.plain)   // a Form row on the Mac; on iOS the list row keeps its tap highlight
#endif
                .focusRing(focused(link), tint, radius: 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(link.title), \(link.subtitle)")
                .accessibilityHint("Opens in the browser")
                .id(LauncherFocus.support(link.rawValue).scrollID)
            }
        } header: {
            Text("Support HorizonNative")
        } footer: {
            Text("HorizonNative is free and made by iCosiSenpai. A donation keeps it going.")
        }
    }
}
