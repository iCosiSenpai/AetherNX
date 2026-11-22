import SwiftUI

@main
struct CompanionApp: App {
    @State private var store = LibraryStore()
    /// The live link with AetherNX Studio on the Mac (LinkSupport.swift).
    @State private var lifecycle = LinkLifecycle()

    var body: some Scene {
        WindowGroup {
            RootView(lifecycle: lifecycle)
                .environment(store)
                .environment(lifecycle.link)
        }
    }
}

struct RootView: View {
    let lifecycle: LinkLifecycle
    @Environment(LibraryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        Group {
            if store.source == .none {
                WelcomeView()
            } else {
                LibraryView()
            }
        }
        .task(id: store.source) { await store.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.reload() } }   // iCloud may have brought changes from the Mac meanwhile
        }
        .onChange(of: scenePhase, initial: true) { _, phase in lifecycle.phaseChanged(to: phase) }
        .alert(Text(verbatim: "AetherNX"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.message ?? "")
        }
    }
}
