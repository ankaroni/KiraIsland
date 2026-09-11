import Foundation
import IOKit.ps

@MainActor
final class BatteryManager: ObservableObject {
    @Published private(set) var percentage = 0
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false

    private var timer: Timer?

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        case 1...25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [AnyHashable: Any]
        else { return }

        let current = raw[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = raw[kIOPSMaxCapacityKey] as? Int ?? 100
        percentage = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0

        let state = raw[kIOPSPowerSourceStateKey] as? String
        isPluggedIn = state == (kIOPSACPowerValue as String)
        isCharging = raw[kIOPSIsChargingKey] as? Bool ?? false
    }
}
