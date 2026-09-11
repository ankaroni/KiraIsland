import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let name: String

    var symbolName: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("headphone") || lower.contains("headset") { return "headphones" }
        if lower.contains("display") || lower.contains("hdmi") { return "display" }
        return "hifispeaker.fill"
    }
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var outputs: [AudioOutputDevice] = []
    @Published private(set) var selectedID: AudioObjectID = kAudioObjectUnknown
    @Published private(set) var masterVolume: Float = 0
    @Published private(set) var canControlVolume = false

    func refresh() {
        selectedID = defaultOutputDevice()
        outputs = allOutputDevices().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        refreshVolume()
    }

    func select(_ device: AudioOutputDevice) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        )
        guard status == noErr else { return }
        selectedID = device.id
        refreshVolume()
    }

    func setVolume(_ value: Float) {
        guard selectedID != kAudioObjectUnknown else { return }
        let clamped = min(max(value, 0), 1)
        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            AudioObjectPropertyElement(1),
            AudioObjectPropertyElement(2)
        ]
        var changed = false

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(selectedID, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(selectedID, &address, &settable) == noErr,
                  settable.boolValue else { continue }

            var volume = clamped
            if AudioObjectSetPropertyData(
                selectedID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &volume
            ) == noErr {
                changed = true
            }
        }

        if changed { masterVolume = clamped }
    }

    private func refreshVolume() {
        canControlVolume = false
        masterVolume = 0
        guard selectedID != kAudioObjectUnknown else { return }

        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            AudioObjectPropertyElement(1),
            AudioObjectPropertyElement(2)
        ]

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(selectedID, &address) else { continue }

            var settable = DarwinBoolean(false)
            let settableStatus = AudioObjectIsPropertySettable(selectedID, &address, &settable)
            var volume: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)

            if AudioObjectGetPropertyData(selectedID, &address, 0, nil, &size, &volume) == noErr {
                masterVolume = volume
                canControlVolume = settableStatus == noErr && settable.boolValue
                return
            }
        }
    }

    private func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        ) == noErr else {
            return kAudioObjectUnknown
        }
        return id
    }

    private func allOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }

        var ids = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = ids.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        guard status == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = deviceName(id) else { return nil }
            return AudioOutputDevice(id: id, name: name)
        }
    }

    private func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanagedName) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let unmanagedName else { return nil }
        return unmanagedName.takeUnretainedValue() as String
    }
}
