import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class IslandWindowController {
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
        let frame = frame(for: compactSize(on: screen), on: screen)
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

    // auxiliaryTopLeftArea / auxiliaryTopRightArea sizes describe the usable
    // menu-bar regions. Their widths are screen-local measurements; deriving
    // the notch from those widths avoids mixing local and global coordinates.
    private func notchMetrics(on screen: NSScreen) -> (centerX: CGFloat, width: CGFloat, height: CGFloat) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = max(0, screen.frame.width - left.width - right.width)
            if notchWidth > 0 {
                let centerX = screen.frame.minX + left.width + notchWidth / 2
                return (centerX, notchWidth, screen.safeAreaInsets.top)
            }
        }

        return (screen.frame.midX, 180, max(24, screen.safeAreaInsets.top))
    }

    private func compactSize(on screen: NSScreen) -> NSSize {
        let notch = notchMetrics(on: screen)
        // Leave useful wings on both sides of the physical camera housing.
        return NSSize(width: max(320, notch.width + 170), height: max(52, notch.height + 18))
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let centerX = notchMetrics(on: screen).centerX
        let x = centerX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func toggle() {
        guard !isAnimating, let panel else { return }
        guard let screen = panel.screen ?? preferredScreen() else { return }

        isAnimating = true
        state.isExpanded.toggle()
        if !state.isExpanded { state.selectedTab = .home }

        let targetSize = state.isExpanded ? expandedSize : compactSize(on: screen)
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
