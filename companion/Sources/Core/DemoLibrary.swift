import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A library to look at without a Mac: invented games, written as Studio and the engine write a real one, read through the same LibraryReader.
enum DemoLibrary {
    struct Game {
        var name: String
        var titleId: String
        var version: String?
        var colors: (UInt32, UInt32)
        var initials: String
        var saved: TimeInterval?   // seconds before now
        var device: String
        var mods: [(name: String, sub: String)] = []
        var modsOff: [String] = []
        var cheats: String?
        var cheatsOn: [String] = []
        var describe = true
    }

    static let games: [Game] = [
        Game(name: "Starfall Tactics", titleId: "0100A1B2C3D40000", version: "1.2.0", colors: (0x3B2A8C, 0xE0637A), initials: "ST",
             saved: 2 * 3600, device: "Mac16,9",
             mods: [("HD Portraits", "romfs/ui"), ("Classic Soundtrack", "romfs/sound"), ("Speed Patch", "exefs")], modsOff: ["Classic Soundtrack"],
             cheats: """
             {Master Code}
             580F0000 01234560
             [-- Stats --]
             [Infinite HP]
             04000000 01234568 00000063
             [Max Gold]
             04000000 0123456C 0098967F
             [Max Gold]
             04000000 01234570 0098967F
             [Unlock All Classes]
             04000000 01234574 FFFFFFFF
             [Credits: an invented cheat site]
             """, cheatsOn: ["Infinite HP", "Max Gold #2"]),
        Game(name: "Moonlit Kart", titleId: "0100F00DCAFE0000", version: "2.0.1", colors: (0x0E5C68, 0x7FD4B0), initials: "MK",
             saved: 26 * 3600, device: "iPhone17,1",
             cheats: """
             [Always First Place]
             04000000 00ABCDE0 00000001
             [All Tracks]
             04000000 00ABCDE4 0000FFFF
             """),
        Game(name: "Lantern Keep", titleId: "0100C0FFEE120000", version: "1.0.0", colors: (0x8A4B12, 0xF2C14E), initials: "LK", saved: nil, device: "",
             mods: [("Brighter Lanterns", "atmosphere/contents/0100C0FFEE120000/romfs/fx")]),
        Game(name: "Echo Garden", titleId: "0100BEEF12340000", version: nil, colors: (0x2D6A4F, 0x95D5B2), initials: "EG",
             saved: 9 * 24 * 3600, device: "iPad14,3", describe: false),
    ]

    /// Writes the demo games under `root` (made again each time), with the time of their saves counted from `now`.
    static func write(to root: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for game in games {
            let folder = root.appending(path: game.name)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if game.describe {
                try icon(initials: game.initials, colors: game.colors).write(to: folder.appending(path: "icon.png"))
                let manifest = GameManifest(format: 1, name: game.name, titleId: game.titleId, version: game.version, icon: "icon.png",
                                            bundleId: "io.github.icosisenpai.horizonnative.\(game.titleId.lowercased())")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(manifest).write(to: folder.appending(path: GameManifest.fileName))
            }
            if let ago = game.saved {
                let saves = folder.appending(path: game.titleId)
                try fm.createDirectory(at: saves, withIntermediateDirectories: true)
                let hash = String(repeating: String(game.titleId.prefix(8)), count: 4)
                var data = SaveHeader.encode(entries: 12, hash: hash, saved: now.addingTimeInterval(-ago), titleId: game.titleId, device: game.device)
                data.append(Data(count: 180_000))   // stands for the entries
                data.append(Data("DMSYNCE\n".utf8))
                try data.write(to: saves.appending(path: "save.dmsync"))
            }
            let mods = folder.appending(path: "Mods"), cheats = folder.appending(path: "Cheats")
            try fm.createDirectory(at: mods, withIntermediateDirectories: true)
            try fm.createDirectory(at: cheats, withIntermediateDirectories: true)
            for mod in game.mods {
                let dir = mods.appending(path: mod.name).appending(path: mod.sub)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data("demo".utf8).write(to: dir.appending(path: "file.bin"))
            }
            if !game.mods.isEmpty {
                try ModState(order: game.mods.map(\.name), off: game.modsOff).encoded().write(to: mods.appending(path: ModState.fileName))
            }
            if let text = game.cheats {
                let build = String(game.titleId.reversed()).prefix(8) + game.titleId.prefix(8)
                try Data(text.utf8).write(to: cheats.appending(path: "\(build).txt"))
                if !game.cheatsOn.isEmpty { try Data(game.cheatsOn.map { $0 + "\n" }.joined().utf8).write(to: cheats.appending(path: "\(build).enabled")) }
            }
        }
    }

    /// A square picture: two colors and the game's initials.
    static func icon(initials: String, colors: (UInt32, UInt32), size: Int = 256) -> Data {
        func color(_ rgb: UInt32) -> CGColor {
            CGColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        let s = CGFloat(size)
        if let gradient = CGGradient(colorsSpace: space, colors: [color(colors.0), color(colors.1)] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
        }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
        ctx.fillEllipse(in: CGRect(x: s * 0.42, y: s * 0.38, width: s * 0.8, height: s * 0.8))
        ctx.fillEllipse(in: CGRect(x: -s * 0.25, y: -s * 0.3, width: s * 0.7, height: s * 0.7))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, s * 0.36, nil)
        let text = NSAttributedString(string: initials, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95),
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (s - bounds.width) / 2 - bounds.minX, y: (s - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        guard let image = ctx.makeImage() else { return Data() }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
