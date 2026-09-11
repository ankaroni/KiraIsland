import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let battery = BatteryManager()
    let clipboard = ClipboardManager()
    let timer = IslandTimerManager()
    let audio = AudioDeviceManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        battery.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        clipboard.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        timer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        audio.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        battery.start()
        clipboard.start()
        audio.refresh()
    }

    func stop() {
        battery.stop()
        clipboard.stop()
        timer.stop()
    }
}
