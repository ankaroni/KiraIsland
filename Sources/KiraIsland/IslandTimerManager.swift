import Foundation

@MainActor
final class IslandTimerManager: ObservableObject {
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isRunning = false

    private var countdownTask: Task<Void, Never>?

    var formatted: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func start(minutes: Int) {
        countdownTask?.cancel()
        remainingSeconds = max(1, minutes * 60)
        isRunning = true
        beginCountdown()
    }

    func togglePause() {
        if isRunning {
            countdownTask?.cancel()
            countdownTask = nil
            isRunning = false
        } else if remainingSeconds > 0 {
            isRunning = true
            beginCountdown()
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        isRunning = false
        if remainingSeconds < 0 { remainingSeconds = 0 }
    }

    func reset() {
        stop()
        remainingSeconds = 0
    }

    private func beginCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard let self, self.isRunning else { return }
                self.remainingSeconds = max(0, self.remainingSeconds - 1)

                if self.remainingSeconds == 0 {
                    self.isRunning = false
                    self.countdownTask = nil
                    return
                }
            }
        }
    }
}
