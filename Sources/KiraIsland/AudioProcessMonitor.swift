import AppKit
import Combine
import CoreAudio
import Foundation

struct AudibleAudioApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String?
    let icon: NSImage?
    let processIDs: [pid_t]
}

@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published private(set) var apps: [AudibleAudioApp] = []

    private var monitorTask: Task<Void, Never>?
    private var lastSeen: [String: Date] = [:]
    private var cachedApps: [String: AudibleAudioApp] = [:]
    private let idleGrace: TimeInterval = 5.0

    func start() {
        stop()
        refresh()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        lastSeen.removeAll()
        cachedApps.removeAll()
    }

    func refresh() {
        let now = Date()
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfBundleID = Bundle.main.bundleIdentifier

        var groups: [String: (app: NSRunningApplication?, name: String, bundleID: String?, pids: Set<pid_t>)] = [:]

        for objectID in audioProcessObjects() {
            guard isRunningOutput(objectID) else { continue }
            let pid = processPID(objectID)
            guard pid > 0, pid != selfPID else { continue }

            let processApp = NSRunningApplication(processIdentifier: pid)
            if processApp?.bundleIdentifier == selfBundleID { continue }

            let owner = resolveOwner(for: processApp, pid: pid, among: regularApps)
            let bundleID = owner?.bundleIdentifier ?? processApp?.bundleIdentifier
            let name = owner?.localizedName
                ?? processApp?.localizedName
                ?? bundleID
                ?? "Audio Process \(pid)"
            let key = bundleID ?? "pid:\(owner?.processIdentifier ?? pid)"

            if var existing = groups[key] {
                existing.pids.insert(pid)
                groups[key] = existing
            } else {
                groups[key] = (owner ?? processApp, name, bundleID, [pid])
            }
        }

        for (key, value) in groups {
            let app = AudibleAudioApp(
                id: key,
                name: value.name,
                bundleID: value.bundleID,
                icon: value.app?.icon,
                processIDs: Array(value.pids).sorted()
            )
            cachedApps[key] = app
            lastSeen[key] = now
        }

        // Keep a recently-audible app around briefly so track gaps and transient
        // helper-process restarts do not make the mixer row flicker.
        let retainedKeys = cachedApps.keys.filter { key in
            guard let seen = lastSeen[key] else { return false }
            return now.timeIntervalSince(seen) <= idleGrace
        }

        cachedApps = cachedApps.filter { retainedKeys.contains($0.key) }
        lastSeen = lastSeen.filter { retainedKeys.contains($0.key) }

        let updated = retainedKeys
            .compactMap { cachedApps[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let oldIDs = apps.map(\.id)
        let newIDs = updated.map(\.id)
        let processChanged = apps.count != updated.count || zip(apps, updated).contains { old, new in
            old.id != new.id || old.processIDs != new.processIDs || old.name != new.name
        }

        if oldIDs != newIDs || processChanged {
            apps = updated
        }
    }

    private func resolveOwner(
        for processApp: NSRunningApplication?,
        pid: pid_t,
        among regularApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        if let direct = regularApps.first(where: { $0.processIdentifier == pid }) {
            return direct
        }

        let childBundleID = processApp?.bundleIdentifier
        let childName = processApp?.localizedName?.lowercased() ?? ""

        if let childBundleID {
            let bundleMatch = regularApps
                .compactMap { app -> (NSRunningApplication, Int)? in
                    guard let parentBundleID = app.bundleIdentifier,
                          childBundleID == parentBundleID || childBundleID.hasPrefix(parentBundleID + ".")
                    else { return nil }
                    return (app, parentBundleID.count)
                }
                .max(by: { $0.1 < $1.1 })?.0

            if let bundleMatch { return bundleMatch }
        }

        if !childName.isEmpty {
            let nameMatch = regularApps
                .compactMap { app -> (NSRunningApplication, Int)? in
                    guard let parentName = app.localizedName?.lowercased(),
                          !parentName.isEmpty,
                          childName == parentName || childName.hasPrefix(parentName + " ")
                    else { return nil }
                    return (app, parentName.count)
                }
                .max(by: { $0.1 < $1.1 })?.0

            if let nameMatch { return nameMatch }
        }

        return processApp
    }

    private func audioProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.size else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var values = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = values.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, baseAddress)
        }
        return status == noErr ? values : []
    }

    private func processPID(_ objectID: AudioObjectID) -> pid_t {
        readScalar(objectID, selector: kAudioProcessPropertyPID, fallback: pid_t(-1))
    }

    private func isRunningOutput(_ objectID: AudioObjectID) -> Bool {
        let value: UInt32 = readScalar(
            objectID,
            selector: kAudioProcessPropertyIsRunningOutput,
            fallback: 0
        )
        return value != 0
    }

    private func readScalar<T>(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        fallback: T
    ) -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value : fallback
    }
}
