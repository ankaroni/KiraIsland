import Combine
import Foundation

@MainActor
final class PerAppAudioManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var gains: [String: Float] = [:]

    private let engine = PerAppAudioEngine()
    private var syncTask: Task<Void, Never>?
    private weak var monitor: AudioProcessMonitor?

    func start(monitor: AudioProcessMonitor) {
        stop()
        self.monitor = monitor

        do {
            try engine.start()
            isRunning = true
            errorMessage = nil
        } catch {
            isRunning = false
            errorMessage = error.localizedDescription
        }

        sync()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { break }
                self?.sync()
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
        engine.stop()
        isRunning = false
    }

    func gain(for app: AudibleAudioApp) -> Float {
        gains[app.id] ?? engine.gain(for: app.id)
    }

    func setGain(_ value: Float, for app: AudibleAudioApp) {
        let clamped = max(0, min(1, value))
        gains[app.id] = clamped
        engine.setGain(clamped, for: app.id)
        objectWillChange.send()
    }

    func toggleMute(for app: AudibleAudioApp) {
        let current = gain(for: app)
        setGain(current > 0.001 ? 0 : 1, for: app)
    }

    private func sync() {
        guard isRunning, let monitor else { return }

        for app in monitor.apps where gains[app.id] == nil {
            gains[app.id] = 1
        }

        engine.setTrackedApps(
            monitor.apps.map {
                PerAppAudioEngine.TrackedApp(key: $0.id, processIDs: $0.processIDs)
            }
        )
    }
}
