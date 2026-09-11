import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class IslandWindowController {
    private let compactSize = NSSize(width: 250, height: 42)
    private let expandedSize = NSSize(width: 500, height: 360)

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
        // These areas are optional. They are only present when macOS exposes
        // the menu-bar regions around a physical camera notch.
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

        // Keep the whole UI below the camera housing, touching its bottom edge.
        let notchBottomY = screen.frame.maxY - screen.safeAreaInsets.top
        let y = notchBottomY - size.height

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
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }
}
