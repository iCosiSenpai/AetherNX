import Foundation
import GameController
import Observation

/// Game controller input for Console Mode: the first connected controller's directions and buttons
/// as simple events, with key repeat while a direction is held.
@MainActor
@Observable
final class Gamepad {
    enum Event: Equatable {
        case left, right, up, down, primary, back, secondary, menu
    }

    struct Glyphs: Equatable {
        var primary = "a.circle.fill"
        var back = "b.circle.fill"
        var secondary = "y.circle.fill"
        var menu = "line.3.horizontal.circle.fill"
    }

    private(set) var name: String?
    private(set) var batteryLevel: Float?
    private(set) var glyphs = Glyphs()
    @ObservationIgnored var onEvent: (@MainActor (Event) -> Void)?
    @ObservationIgnored private var heldDirection: Event?
    @ObservationIgnored private var repeatTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    var isConnected: Bool { name != nil }

    private func refresh() {
        guard let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }), let pad = controller.extendedGamepad else {
            name = nil
            batteryLevel = nil
            return
        }
        name = controller.vendorName ?? String(localized: "Controller")
        if let battery = controller.battery, battery.batteryState != .unknown { batteryLevel = battery.batteryLevel } else { batteryLevel = nil }
        glyphs = Glyphs(primary: pad.buttonA.sfSymbolsName ?? "a.circle.fill",
                        back: pad.buttonB.sfSymbolsName ?? "b.circle.fill",
                        secondary: pad.buttonY.sfSymbolsName ?? "y.circle.fill",
                        menu: pad.buttonMenu.sfSymbolsName ?? "line.3.horizontal.circle.fill")
        bind(pad)
    }

    private func bind(_ pad: GCExtendedGamepad) {
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.fire(.primary) } }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.fire(.back) } }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.fire(.secondary) } }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.fire(.menu) } }
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in self?.direction(x: x, y: y) }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in self?.direction(x: x, y: y) }
    }

    private nonisolated func fire(_ event: Event) {
        Task { @MainActor in self.onEvent?(event) }
    }

    private nonisolated func direction(x: Float, y: Float) {
        let event: Event? = abs(x) < 0.5 && abs(y) < 0.5 ? nil : abs(x) >= abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
        Task { @MainActor in self.hold(event) }
    }

    /// A held direction repeats after 0.4 s, then about eight times a second.
    private func hold(_ event: Event?) {
        guard event != heldDirection else { return }
        heldDirection = event
        repeatTask?.cancel()
        guard let event else { return }
        onEvent?(event)
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                guard let self, self.heldDirection == event else { return }
                self.onEvent?(event)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
}
