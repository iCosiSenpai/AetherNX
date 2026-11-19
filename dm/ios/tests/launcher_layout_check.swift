// The Mac launcher is driven by the same settings file as the storage tests.
import AppKit
import SwiftUI

@MainActor
func checkLauncherLayout(_ model: LauncherModel, defaults: UserDefaults) -> Int {
    NSApplication.shared.setActivationPolicy(.prohibited)
    var failed = 0
    func expect(_ condition: Bool, _ detail: String) {
        print((condition ? "PASS " : "FAIL ") + detail)
        if !condition { failed += 1 }
    }

    let pages = LauncherView.pages(for: model)
    expect(pages.map(\.id) == model.sections.map { "settings." + $0 } + ["cloud", "support"],
           "categories preserve the settings file's order and include launch services")
    for section in model.sections {
        let page = LauncherView.Page.settings(section)
        let rows = model.rows(in: section)
        let basic = rows.filter(\.basic)
        expect(page.rows(model, advanced: true).map(\.id) == rows.map(\.id),
               "Advanced exposes all visible settings in \(section)")
        expect(page.rows(model, advanced: false).map(\.id) == (basic.isEmpty ? rows : basic).map(\.id),
               "Basic settings come first without hiding categories that have only advanced settings")
        expect(page.offersAdvanced(model) == (!basic.isEmpty && basic.count < rows.count),
               "Advanced control appears only when it changes the contents")
    }

    let view = NSHostingView(rootView: LauncherView(m: model,
        name: "Xenoblade Chronicles X: Definitive Edition – Nintendo Switch 2 Edition",
        version: "2.0.0", done: { _ in }).defaultAppStorage(defaults))
    view.sizingOptions = []
    let minimum = NSSize(width: 580, height: 430)
    view.frame.size = minimum
    view.layoutSubtreeIfNeeded()
    expect(view.fittingSize.width <= minimum.width && view.fittingSize.height <= minimum.height,
           "the long title and launcher chrome fit at the minimum window size")

    let visible = NSRect(x: -1440, y: 40, width: 1440, height: 790)
    let preferred = NSSize(width: 740, height: 625)
    let centered = LauncherWindowLayout.initial(preferred, visible: visible)
    expect(centered.size == preferred && centered.midX == visible.midX && centered.midY == visible.midY,
           "the launcher opens centered on the active display")
    let smallScreen = NSRect(x: 0, y: 30, width: 680, height: 540)
    expect(LauncherWindowLayout.initial(preferred, visible: smallScreen) == smallScreen,
           "the initial size is constrained by the visible screen")
    return failed
}
