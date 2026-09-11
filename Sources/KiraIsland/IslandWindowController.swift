import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class IslandWindowController {
    private let expandedSize = NSSize(width: 500, height: 380)
    private let compactWingWidth: CGFloat = 132
    private let expandedTopGap: CGFloat = 6

    private let state = IslandState()
    private let model = AppModel()

    private var panel: NSPanel?
    private var isAnimating = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func show() {
        guard let screen = preferredScreen() else {
            print("❌ No screen found")
            return
        }

        model.start()
        let metrics = notchMetrics(on: screen)
        let frame = compactFrame(on: screen)
        let panel = IslandPanel(contentRect: frame)
        panel.contentView = NSHostingView(
            rootView: IslandView(
                state: state,
                model: model,
                notchWidth: metrics.width,
                compactWingWidth: compactWingWidth,
                onToggle: { [weak self] in self?.toggle() }
            )
        )
        self.panel = panel
        installOutsideClickMonitors()
        panel.orderFrontRegardless()
    }

    func close() {
        removeOutsideClickMonitors()
        model.stop()
        panel?.orderOut(nil)
        panel = nil
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

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
        return NSSize(
            width: notch.width + compactWingWidth * 2,
            height: max(36, notch.height)
        )
    }

    private func compactFrame(on screen: NSScreen) -> NSRect {
        let metrics = notchMetrics(on: screen)
        let size = compactSize(on: screen)
        return NSRect(
            x: metrics.centerX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let metrics = notchMetrics(on: screen)
        // The expanded card starts BELOW the physical camera housing. This
        // keeps the header, tabs and controls completely clear of the notch.
        let top = screen.frame.maxY - metrics.height - expandedTopGap
        return NSRect(
            x: metrics.centerX - expandedSize.width / 2,
            y: top - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    private func toggle() {
        setExpanded(!state.isExpanded)
    }

    private func setExpanded(_ expanded: Bool) {
        guard !isAnimating, let panel else { return }
        guard let screen = panel.screen ?? preferredScreen() else { return }
        guard state.isExpanded != expanded else { return }

        isAnimating = true
        state.isExpanded = expanded
        if !expanded { state.selectedTab = .home }

        let targetFrame = expanded ? expandedFrame(on: screen) : compactFrame(on: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.30 : 0.22
            context.timingFunction = expanded
                ? CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.22, 1.0)
                : CAMediaTimingFunction(controlPoints: 0.30, 0.00, 0.30, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
            }
        }
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.collapseIfClickIsOutside()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfClickIsOutside()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func collapseIfClickIsOutside() {
        guard state.isExpanded, !isAnimating, let panel else { return }
        let point = NSEvent.mouseLocation
        guard !panel.frame.contains(point) else { return }
        setExpanded(false)
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
