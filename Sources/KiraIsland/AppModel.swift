import Foundation

@MainActor
final class AppModel: ObservableObject {
    let battery = BatteryManager()
    let clipboard = ClipboardManager()
    let timer = IslandTimerManager()
    let audio = AudioDeviceManager()

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
