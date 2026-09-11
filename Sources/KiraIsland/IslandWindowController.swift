import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class IslandWindowController {
    private let preferredExpandedWidth: CGFloat = 520
    private let preferredExpandedHeight: CGFloat = 390
    private let compactWingWidth: CGFloat = 140
    private let expandedTopGap: CGFloat = 8

    private let state = IslandState()
    private let model = AppModel()

    private var panel: NSPanel?
    private var isAnimating = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    func show() {
        guard let screen = preferredScreen() else {
            print("❌ No screen found")
            return
        }

        model.start()

        let metrics = notchMetrics(on: screen)
        let panel = IslandPanel(contentRect: compactFrame(on: screen))
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
        installEventMonitors()
        installScreenObserver()
        panel.orderFrontRegardless()
    }

    func close() {
        removeEventMonitors()
        removeScreenObserver()
        model.stop()
        panel?.orderOut(nil)
        panel = nil
    }

    private func preferredScreen() -> NSScreen? {
        // Prefer the built-in notched display even when another monitor is main.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func notchMetrics(on screen: NSScreen) -> (centerX: CGFloat, width: CGFloat, height: CGFloat) {
        let height = max(24, screen.safeAreaInsets.top)

        // The MacBook camera housing is physically centered on the display.
        // Always anchor X to the display midpoint; auxiliary rect coordinates can
        // vary between macOS releases and display arrangements.
        let centerX = screen.frame.midX

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let measured = screen.frame.width - left.width - right.width
            // Reject pathological values from unusual display configurations.
            let width = min(max(measured, 120), 260)
            return (centerX, width, height)
        }

        return (centerX, 180, height)
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

    private func expandedSize(on screen: NSScreen) -> NSSize {
        let metrics = notchMetrics(on: screen)
        let availableWidth = max(360, screen.frame.width - 32)
        let availableHeight = max(280, screen.frame.height - metrics.height - 40)

        return NSSize(
            width: min(preferredExpandedWidth, availableWidth),
            height: min(preferredExpandedHeight, availableHeight)
        )
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let metrics = notchMetrics(on: screen)
        let size = expandedSize(on: screen)

        // Expanded content lives entirely below the physical camera housing.
        let top = screen.frame.maxY - metrics.height - expandedTopGap

        return NSRect(
            x: metrics.centerX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func toggle() {
        setExpanded(!state.isExpanded)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard let panel else { return }
        guard let screen = panel.screen ?? preferredScreen() else { return }
        guard state.isExpanded != expanded else { return }
        guard !isAnimating || !animated else { return }

        state.isExpanded = expanded
        if !expanded { state.selectedTab = .home }

        let targetFrame = expanded ? expandedFrame(on: screen) : compactFrame(on: screen)

        guard animated else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.28 : 0.20
            context.timingFunction = expanded
                ? CAMediaTimingFunction(controlPoints: 0.18, 0.88, 0.20, 1.0)
                : CAMediaTimingFunction(controlPoints: 0.35, 0.00, 0.30, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
            }
        }
    }

    private func installEventMonitors() {
        removeEventMonitors()

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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    guard let self, self.state.isExpanded else { return }
                    self.setExpanded(false)
                }
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func collapseIfClickIsOutside() {
        guard state.isExpanded, !state.isPinned, !isAnimating, let panel else { return }
        guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
        setExpanded(false)
    }

    private func installScreenObserver() {
        removeScreenObserver()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionForCurrentScreen()
            }
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func repositionForCurrentScreen() {
        guard let panel, let screen = preferredScreen() else { return }
        let target = state.isExpanded ? expandedFrame(on: screen) : compactFrame(on: screen)
        panel.setFrame(target, display: true)
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
