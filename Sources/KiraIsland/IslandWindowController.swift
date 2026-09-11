import AppKit
import SwiftUI
import QuartzCore
import Combine

@MainActor
final class IslandWindowController {
    private let preferredExpandedWidth: CGFloat = 520
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
    private var cancellables = Set<AnyCancellable>()

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
        installContentSizeObservers()
        panel.orderFrontRegardless()
    }

    func close() {
        cancellables.removeAll()
        removeEventMonitors()
        removeScreenObserver()
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
        let height = max(24, screen.safeAreaInsets.top)
        let centerX = screen.frame.midX

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let measured = screen.frame.width - left.width - right.width
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

    private func desiredExpandedHeight(on screen: NSScreen) -> CGFloat {
        // Shared shell: outer padding + header + tab bar + their spacing.
        let shellHeight: CGFloat = 136
        let bodyHeight: CGFloat

        switch state.selectedTab {
        case .home:
            // Three status cards only; no reason to keep a large empty canvas.
            bodyHeight = 112

        case .audio:
            // Master slider + device pills + mixer title/spacing + visible app rows.
            let visibleRows = min(max(model.audioProcesses.apps.count, 1), 3)
            bodyHeight = 102 + CGFloat(visibleRows) * 53

        case .clipboard:
            if model.clipboard.entries.isEmpty {
                bodyHeight = 92
            } else {
                let visibleRows = min(model.clipboard.entries.count, 5)
                bodyHeight = 48 + CGFloat(visibleRows) * 38
            }

        case .timer:
            bodyHeight = model.timer.remainingSeconds > 0 ? 118 : 128
        }

        let naturalHeight = shellHeight + bodyHeight
        let metrics = notchMetrics(on: screen)
        let maximum = max(240, screen.frame.height - metrics.height - expandedTopGap - 24)
        return min(max(naturalHeight, 220), maximum)
    }

    private func expandedSize(on screen: NSScreen) -> NSSize {
        let availableWidth = max(360, screen.frame.width - 32)
        return NSSize(
            width: min(preferredExpandedWidth, availableWidth),
            height: desiredExpandedHeight(on: screen)
        )
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let metrics = notchMetrics(on: screen)
        let size = expandedSize(on: screen)
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

    private func installContentSizeObservers() {
        cancellables.removeAll()

        state.$selectedTab
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.resizeExpandedToFit(animated: true)
                }
            }
            .store(in: &cancellables)

        model.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange is emitted before the child model mutation;
                // defer one run-loop turn so sizing uses the new values.
                Task { @MainActor in
                    await Task.yield()
                    self?.resizeExpandedToFit(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func resizeExpandedToFit(animated: Bool) {
        guard state.isExpanded, !isAnimating, let panel else { return }
        guard let screen = panel.screen ?? preferredScreen() else { return }

        let target = expandedFrame(on: screen)
        guard abs(target.height - panel.frame.height) > 1.0 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.80, 0.20, 1.0)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
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
            if event.keyCode == 53 {
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
