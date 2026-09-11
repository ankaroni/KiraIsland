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
    private var lastNonZeroGains: [String: Float] = [:]

    private let defaults = UserDefaults.standard
    private let gainsDefaultsKey = "KiraIsland.perAppGains"

    init() {
        loadSavedGains()
    }

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
                try? await Task.sleep(for: .milliseconds(600))
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
        gains[app.id] ?? 1
    }

    func setGain(_ value: Float, for app: AudibleAudioApp) {
        let clamped = max(0, min(1, value))

        if clamped > 0.001 {
            lastNonZeroGains[app.id] = clamped
        }

        gains[app.id] = clamped
        engine.setGain(clamped, for: app.id)
        saveGains()
    }

    func toggleMute(for app: AudibleAudioApp) {
        let current = gain(for: app)

        if current > 0.001 {
            lastNonZeroGains[app.id] = current
            setGain(0, for: app)
        } else {
            setGain(lastNonZeroGains[app.id] ?? 1, for: app)
        }
    }

    private func sync() {
        guard isRunning, let monitor else { return }

        for app in monitor.apps {
            let savedGain = gains[app.id] ?? 1
            if gains[app.id] == nil {
                gains[app.id] = savedGain
            }
            if savedGain > 0.001, lastNonZeroGains[app.id] == nil {
                lastNonZeroGains[app.id] = savedGain
            }
        }

        engine.setTrackedApps(
            monitor.apps.map {
                PerAppAudioEngine.TrackedApp(key: $0.id, processIDs: $0.processIDs)
            }
        )

        // Re-apply persisted gains after process/tap recreation.
        for app in monitor.apps {
            engine.setGain(gain(for: app), for: app.id)
        }
    }

    private func loadSavedGains() {
        guard let saved = defaults.dictionary(forKey: gainsDefaultsKey) else { return }

        var restored: [String: Float] = [:]
        for (key, value) in saved {
            if let number = value as? NSNumber {
                restored[key] = max(0, min(1, number.floatValue))
            }
        }
        gains = restored
        lastNonZeroGains = restored.filter { $0.value > 0.001 }
    }

    private func saveGains() {
        let encoded = gains.mapValues { NSNumber(value: $0) }
        defaults.set(encoded, forKey: gainsDefaultsKey)
    }
}
