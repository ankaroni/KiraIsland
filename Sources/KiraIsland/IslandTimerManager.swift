import Foundation

@MainActor
final class IslandTimerManager: ObservableObject {
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isRunning = false

    private var timer: Timer?

    var formatted: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func start(minutes: Int) {
        stop()
        remainingSeconds = max(1, minutes * 60)
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                }
                if self.remainingSeconds <= 0 {
                    self.stop()
                }
            }
        }
    }

    func togglePause() {
        if isRunning {
            timer?.invalidate()
            timer = nil
            isRunning = false
        } else if remainingSeconds > 0 {
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { timer.invalidate(); return }
                    self.remainingSeconds -= 1
                    if self.remainingSeconds <= 0 { self.stop() }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        if remainingSeconds < 0 { remainingSeconds = 0 }
    }

    func reset() {
        stop()
        remainingSeconds = 0
    }
}
