import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class IslandWindowController {
    private let compactSize = NSSize(width: 220, height: 44)
    private let expandedSize = NSSize(width: 430, height: 180)

    private var panel: NSPanel?
    private var isExpanded = false
    private var isAnimating = false

    func show() {
        guard let screen = preferredScreen() else {
            print("❌ No screen found")
            return
        }

        let frame = frame(for: compactSize, on: screen)
        let panel = IslandPanel(contentRect: frame)

        panel.contentView = NSHostingView(
            rootView: IslandView(
                isExpanded: { [weak self] in self?.isExpanded ?? false },
                onToggle: { [weak self] in self?.toggle() }
            )
        )

        self.panel = panel
        panel.orderFrontRegardless()
        print("✅ Island panel created: \(frame)")
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let topInset = max(screen.safeAreaInsets.top, 28)
        let x = screen.frame.midX - size.width / 2
        let topY = screen.frame.maxY - topInset - 6
        let y = topY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func toggle() {
        guard !isAnimating else {
            print("⏳ Ignored toggle during animation")
            return
        }

        guard let panel else { return }
        guard let screen = panel.screen ?? preferredScreen() else { return }

        isAnimating = true
        isExpanded.toggle()

        let targetSize = isExpanded ? expandedSize : compactSize
        let targetFrame = frame(for: targetSize, on: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                0.82,
                0.22,
                1.0
            )
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
            }
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

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }
}
