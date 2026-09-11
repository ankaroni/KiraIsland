import CoreAudio
import Foundation

/// Per-app playback gain engine built on macOS Core Audio process taps.
/// Architecture informed by the MIT-licensed MacMixer project; see THIRD_PARTY_NOTICES.md.
final class PerAppAudioEngine {
    struct TrackedApp: Equatable {
        let key: String
        let processIDs: [pid_t]
    }

    private static let maxTaps = 32
    private static let aggregateUID = "com.kiraisland.audio.aggregate"

    private let gains = UnsafeMutablePointer<Float>.allocate(capacity: maxTaps)
    private let tapCount = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private let inputOffset = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    private var gainByKey: [String: Float] = [:]
    private var slotKeys: [String] = []
    private var tapIDs: [AudioObjectID] = []
    private var tappedSignature: [String] = []
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var outputID = AudioObjectID(kAudioObjectUnknown)
    private var running = false

    init() {
        gains.initialize(repeating: 1, count: Self.maxTaps)
        tapCount.pointee = 0
        inputOffset.pointee = 0
    }

    deinit {
        stop()
        gains.deallocate()
        tapCount.deallocate()
        inputOffset.deallocate()
    }

    func start() throws {
        outputID = defaultOutputDevice()
        guard outputID != kAudioObjectUnknown else { throw EngineError.noOutputDevice }
        running = true
    }

    func stop() {
        running = false
        teardownAggregate()
        tappedSignature = []
    }

    func gain(for key: String) -> Float { gainByKey[key] ?? 1 }

    func setGain(_ value: Float, for key: String) {
        let clamped = max(0, min(2, value))
        gainByKey[key] = clamped
        for (index, slotKey) in slotKeys.enumerated() where slotKey == key && index < Self.maxTaps {
            gains[index] = clamped
        }
    }

    func setTrackedApps(_ apps: [TrackedApp]) {
        guard running else { return }

        let currentOutput = defaultOutputDevice()
        if currentOutput != kAudioObjectUnknown, currentOutput != outputID {
            outputID = currentOutput
            tappedSignature = []
        }

        let processObjects = audioProcessObjects()
        var pidToObject: [pid_t: AudioObjectID] = [:]
        for object in processObjects {
            let pid: pid_t = scalar(object, kAudioProcessPropertyPID, pid_t(-1))
            if pid > 0 { pidToObject[pid] = object }
        }

        let resolved: [(String, [AudioObjectID])] = apps.compactMap { app in
            let objects = app.processIDs.compactMap { pidToObject[$0] }
            return objects.isEmpty ? nil : (app.key, objects)
        }

        let signature = resolved.map { key, objects in
            key + ":" + objects.sorted().map(String.init).joined(separator: ",")
        }.sorted()

        guard signature != tappedSignature else { return }
        rebuild(resolved)
        tappedSignature = signature
    }

    private func rebuild(_ apps: [(String, [AudioObjectID])]) {
        teardownAggregate()
        guard running, outputID != kAudioObjectUnknown, let outputUID = cfString(outputID, kAudioDevicePropertyDeviceUID) else { return }

        var newTapIDs: [AudioObjectID] = []
        var tapUIDs: [String] = []
        var keys: [String] = []

        for (key, objects) in apps.prefix(Self.maxTaps) {
            let description = CATapDescription()
            description.name = "KiraIsland-\(key)"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            description.isMono = false
            description.isMixdown = true
            description.isExclusive = false
            description.setValue(objects.map { NSNumber(value: $0) }, forKey: "processes")

            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr, tapID != kAudioObjectUnknown,
                  let uid = cfString(tapID, kAudioTapPropertyUID) else { continue }

            let slot = newTapIDs.count
            newTapIDs.append(tapID)
            tapUIDs.append(uid)
            keys.append(key)
            gains[slot] = gainByKey[key] ?? 1
        }

        tapIDs = newTapIDs
        slotKeys = keys
        tapCount.pointee = Int32(newTapIDs.count)
        guard !newTapIDs.isEmpty else { return }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Kira Island Audio",
            kAudioAggregateDeviceUIDKey: Self.aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: tapUIDs.map {
                [kAudioSubTapUIDKey: $0, kAudioSubTapDriftCompensationKey: true]
            }
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate) == noErr,
              aggregate != kAudioObjectUnknown else {
            teardownTaps()
            return
        }
        aggregateID = aggregate

        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let totalInputBuffers = bufferCount(aggregate, &inputAddress)
        inputOffset.pointee = Int32(max(0, totalInputBuffers - newTapIDs.count))

        var procID: AudioDeviceIOProcID?
        let ioBlock = makeIOBlock()
        guard AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil, ioBlock) == noErr,
              let procID else {
            teardownAggregate()
            return
        }
        ioProcID = procID

        guard AudioDeviceStart(aggregate, procID) == noErr else {
            teardownAggregate()
            return
        }
    }

    private func makeIOBlock() -> AudioDeviceIOBlock {
        let gains = self.gains
        let tapCount = self.tapCount
        let inputOffset = self.inputOffset

        return { _, inputData, _, outputData, _ in
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            guard !outputs.isEmpty else { return }

            for output in outputs {
                if let data = output.mData { memset(data, 0, Int(output.mDataByteSize)) }
            }

            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let count = Int(tapCount.pointee)
            let offset = Int(inputOffset.pointee)
            guard count > 0 else { return }

            let output = outputs[0]
            guard let outputRaw = output.mData else { return }
            let outputSamples = outputRaw.assumingMemoryBound(to: Float.self)
            let outputCount = Int(output.mDataByteSize) / MemoryLayout<Float>.size

            for tapIndex in 0..<count {
                let inputIndex = offset + tapIndex
                guard inputIndex < inputs.count else { break }
                let input = inputs[inputIndex]
                guard let inputRaw = input.mData else { continue }
                let inputSamples = inputRaw.assumingMemoryBound(to: Float.self)
                let sampleCount = min(outputCount, Int(input.mDataByteSize) / MemoryLayout<Float>.size)
                let gain = gains[tapIndex]
                if gain == 0 { continue }
                for sample in 0..<sampleCount {
                    outputSamples[sample] += inputSamples[sample] * gain
                }
            }
        }
    }

    private func teardownAggregate() {
        if aggregateID != kAudioObjectUnknown {
            if let procID = ioProcID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = kAudioObjectUnknown
        teardownTaps()
        tapCount.pointee = 0
        slotKeys = []
    }

    private func teardownTaps() {
        for id in tapIDs { AudioHardwareDestroyProcessTap(id) }
        tapIDs = []
    }

    private func defaultOutputDevice() -> AudioObjectID {
        scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(kAudioObjectUnknown))
    }

    private func audioProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var values = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = values.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, base)
        }
        return status == noErr ? values : []
    }

    private func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : fallback
    }

    private func cfString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func bufferCount(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Int {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, raw) == noErr else { return 0 }
        return Int(raw.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers)
    }

    enum EngineError: LocalizedError {
        case noOutputDevice
        var errorDescription: String? { "No audio output device is available." }
    }
}
