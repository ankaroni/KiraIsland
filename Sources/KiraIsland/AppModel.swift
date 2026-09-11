import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let battery = BatteryManager()
    let clipboard = ClipboardManager()
    let timer = IslandTimerManager()
    let audio = AudioDeviceManager()
    let audioProcesses = AudioProcessMonitor()
    let perAppAudio = PerAppAudioManager()

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
        audioProcesses.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        perAppAudio.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        battery.start()
        clipboard.start()
        audio.startMonitoring()
        audioProcesses.start()
        perAppAudio.start(monitor: audioProcesses)
    }

    func stop() {
        battery.stop()
        clipboard.stop()
        timer.stop()
        perAppAudio.stop()
        audioProcesses.stop()
        audio.stopMonitoring()
    }
}
