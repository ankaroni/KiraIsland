import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class IslandWindowController {
    // The panel starts at the physical top edge of the display and grows down.
    // This makes the black island visually merge with the MacBook camera notch
    // instead of floating below the menu bar.
    private let compactSize = NSSize(width: 260, height: 52)
    private let expandedSize = NSSize(width: 500, height: 380)

    private let state = IslandState()
    private let model = AppModel()

    private var panel: NSPanel?
    private var isAnimating = false

    func show() {
        guard let screen = preferredScreen() else {
            print("❌ No screen found")
            return
        }

        model.start()
        let frame = frame(for: compactSize, on: screen)
        let panel = IslandPanel(contentRect: frame)
        panel.contentView = NSHostingView(
            rootView: IslandView(
                state: state,
                model: model,
                onToggle: { [weak self] in self?.toggle() }
            )
        )
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        model.stop()
        panel?.orderOut(nil)
        panel = nil
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func notchCenterX(on screen: NSScreen) -> CGFloat {
        // On a notched display macOS exposes the two usable menu-bar regions.
        // Their gap is the physical camera housing. Use its midpoint when
        // available; otherwise the display midpoint is the correct fallback.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           left.width > 0,
           right.width > 0,
           right.minX > left.maxX {
            return (left.maxX + right.minX) / 2
        }

        return screen.frame.midX
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let centerX = notchCenterX(on: screen)
        let x = centerX - size.width / 2

        // Critical geometry rule: the panel's TOP edge is always the physical
        // top edge of the display. Resizing therefore happens only downward.
        // safeAreaInsets.top is intentionally NOT subtracted here.
        let y = screen.frame.maxY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func toggle() {
        guard !isAnimating, let panel else { return }
        guard let screen = panel.screen ?? preferredScreen() else { return }

        isAnimating = true
        state.isExpanded.toggle()
        if !state.isExpanded { state.selectedTab = .home }

        let targetSize = state.isExpanded ? expandedSize : compactSize
        let targetFrame = frame(for: targetSize, on: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.82, 0.22, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.isAnimating = false }
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }
}
