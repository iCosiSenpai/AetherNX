import SwiftUI

/// What the main window's detail column shows. Everything the app has lives in this one window: the library's home, a game, and the app's
/// own pages (activity, devices, updates, settings) are rows of the sidebar, not windows of their own.
enum Page: Hashable {
    case home, game, activity, devices, updates, settings
}

/// The groups of Settings, each a pane of the Settings page.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, library, keys, building, cloud

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .library: "Library"
        case .keys: "Keys"
        case .building: "Building"
        case .cloud: "Saves, Mods & Cheats"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .library: "books.vertical"
        case .keys: "key"
        case .building: "hammer"
        case .cloud: "icloud"
        }
    }
}

/// A row of the sidebar: its selection is the page the detail shows.
enum SidebarItem: Hashable {
    case home
    case game(Game.ID)
    case page(Page)
}

/// How much room the detail column has: rows show their buttons with titles when there is room, as icons when there is not.
enum LayoutWidth: Comparable {
    case compact, regular, wide

    init(width: CGFloat) {
        self = width < 720 ? .compact : width < 1180 ? .regular : .wide
    }
}

private struct LayoutWidthKey: EnvironmentKey {
    static let defaultValue = LayoutWidth.regular
}

extension EnvironmentValues {
    var layoutWidth: LayoutWidth {
        get { self[LayoutWidthKey.self] }
        set { self[LayoutWidthKey.self] = newValue }
    }
}

extension View {
    /// Measures the width this view gets and hands it down as `layoutWidth`.
    func measuringLayoutWidth() -> some View { modifier(MeasuredWidth()) }
}

private struct MeasuredWidth: ViewModifier {
    @State private var width = LayoutWidth.regular

    func body(content: Content) -> some View {
        content
            .environment(\.layoutWidth, width)
            .onGeometryChange(for: LayoutWidth.self) { LayoutWidth(width: $0.size.width) } action: { width = $0 }
    }
}

/// A row's button: its title beside its icon when the column has room, the icon alone (with the title as its tooltip) when it is narrow.
struct RowButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var prominent = false
    let action: () -> Void
    @Environment(\.layoutWidth) private var layoutWidth

    init(_ title: LocalizedStringKey, systemImage: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            if layoutWidth == .compact {
                Label(title, systemImage: systemImage).labelStyle(.iconOnly)
            } else {
                Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
            }
        }
        .help(Text(title))
        if prominent { button.buttonStyle(.borderedProminent) } else { button }
    }
}
