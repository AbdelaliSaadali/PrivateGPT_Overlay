import AppKit
import CoreAudio
import CoreFoundation

// Changes system defaults using an app-owned temporary stacked (mirrored)
// Multi-Output Device: [the user's current output, BlackHole 2ch].
// The user's pre-existing Audio MIDI Setup devices are never edited.
final class AudioRouting {
    static let shared = AudioRouting()

    private struct Snapshot {
        let input: AudioDeviceID
        let output: AudioDeviceID
        let systemOutput: AudioDeviceID
    }

    private var normal: Snapshot?
    private var normalSpeakerVolume: Float32?
    private let speakerVolumeKey = "privategpt.privateSpeakerVolume"
    private let ownedMultiOutputUID = "local.prototype.privategptoverlay.audio.output"
    private let originalInputKey = "privategpt.originalInputUID"
    private let originalOutputKey = "privategpt.originalOutputUID"
    private let originalSystemOutputKey = "privategpt.originalSystemOutputUID"
    private(set) var lastError: String?

    var privateSpeakerVolume: Float32 {
        let saved = UserDefaults.standard.object(forKey: speakerVolumeKey) as? NSNumber
        return Float32(min(max(saved?.floatValue ?? 0.65, 0.05), 1.0))
    }

    private func readDeviceString(_ id: AudioDeviceID,
                                  selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let cf = value else { return nil }
        return cf.takeRetainedValue() as String
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        readDeviceString(id, selector: kAudioObjectPropertyName) ?? "Unknown"
    }

    private func deviceUID(_ id: AudioDeviceID) -> String? {
        readDeviceString(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0, size < 65536 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
            else { return [] }
        return devices
    }

    private func findDevice(uid: String) -> AudioDeviceID? {
        allDevices().first { deviceUID($0) == uid }
    }

    private func lookup(_ names: [String]) -> AudioDeviceID? {
        for id in allDevices() {
            let name = deviceName(id)
            if names.contains(where: { name.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
                return id
            }
        }
        return nil
    }

    private var macBookSpeaker: AudioDeviceID? {
        lookup(["Haut-parleurs MacBook Pro", "MacBook Pro Speakers"])
    }

    private var blackHole2ch: AudioDeviceID? {
        lookup(["BlackHole 2ch"])
    }

    private var blackHole16ch: AudioDeviceID? {
        lookup(["BlackHole 16ch"])
    }

    private func getDefault(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
            ? device : nil
    }

    private func setDefault(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var target = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &target) == noErr
    }

    private func readVolume(_ device: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr
        else { return nil }
        return volume
    }

    private func setVolume(_ device: AudioDeviceID, to newValue: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var volume = min(max(newValue, 0), 1)
        return AudioObjectSetPropertyData(device, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &volume) == noErr
    }

    @discardableResult
    func changePrivateSpeakerVolume(_ newValue: Float32) -> Bool {
        let value = min(max(newValue, 0.05), 1)
        UserDefaults.standard.set(value, forKey: speakerVolumeKey)
        guard privateEnabled, let speaker = macBookSpeaker,
              currentMonitoredDevice()?.id == speaker else { return true }
        return setVolume(speaker, to: value)
    }

    private func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0, size < 16384 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func isAggregate(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cls = AudioClassID(0)
        var size = UInt32(MemoryLayout<AudioClassID>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cls) == noErr
        else { return false }
        return cls == kAudioAggregateDeviceClassID
    }

    private func currentMonitoredDevice() -> (id: AudioDeviceID, name: String)? {
        if let output = normal?.output, allDevices().contains(output) {
            return (output, deviceName(output))
        }
        if let uid = UserDefaults.standard.string(forKey: originalOutputKey),
           let output = findDevice(uid: uid) {
            return (output, deviceName(output))
        }
        return nil
    }

    var privateEnabled: Bool {
        guard let input = getDefault(kAudioHardwarePropertyDefaultInputDevice),
              let output = getDefault(kAudioHardwarePropertyDefaultOutputDevice),
              let virtual = blackHole16ch else { return false }
        return input == virtual && deviceUID(output) == ownedMultiOutputUID
    }

    var statusDescription: String {
        let input = getDefault(kAudioHardwarePropertyDefaultInputDevice)
            .map(deviceName) ?? "Unknown"
        let output = getDefault(kAudioHardwarePropertyDefaultOutputDevice)
            .map(deviceName) ?? "Unknown"
        let monitor = privateEnabled ? " + Listening on: \(currentMonitoredDevice()?.name ?? "previous output")" : ""
        return "Input: \(input)\nOutput: \(output)\(monitor)"
    }

    private func captureOriginal(_ snapshot: Snapshot) {
        let defaults = UserDefaults.standard
        if let input = deviceUID(snapshot.input) { defaults.set(input, forKey: originalInputKey) }
        if let output = deviceUID(snapshot.output) { defaults.set(output, forKey: originalOutputKey) }
        if let system = deviceUID(snapshot.systemOutput) {
            defaults.set(system, forKey: originalSystemOutputKey)
        }
    }

    private func clearOriginal() {
        let defaults = UserDefaults.standard
        for key in [originalInputKey, originalOutputKey, originalSystemOutputKey] {
            defaults.removeObject(forKey: key)
        }
    }

    private func savedDevice(_ key: String) -> AudioDeviceID? {
        guard let uid = UserDefaults.standard.string(forKey: key) else { return nil }
        return findDevice(uid: uid)
    }

    private func destroyOldOwnedAggregate() {
        guard let old = findDevice(uid: ownedMultiOutputUID),
              old != getDefault(kAudioHardwarePropertyDefaultOutputDevice) else { return }
        let status = AudioHardwareDestroyAggregateDevice(old)
        if status != noErr { NSLog("PrivateGPT: could not remove old output device: %d", status) }
    }

    private func createMirroredOutput(for physical: AudioDeviceID, blackHole: AudioDeviceID)
        -> AudioDeviceID? {
        guard let physicalUID = deviceUID(physical),
              let blackHoleUID = deviceUID(blackHole) else {
            lastError = "Could not determine output device identifiers."
            return nil
        }
        // 'stacked' mirrors a stereo pair into both outputs, unlike a normal
        // non-stacked aggregate (which adds channel counts without duplicating).
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PrivateGPT Output",
            kAudioAggregateDeviceUIDKey: ownedMultiOutputUID,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: physicalUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: physicalUID, kAudioSubDeviceDriftCompensationKey: 0],
                [kAudioSubDeviceUIDKey: blackHoleUID, kAudioSubDeviceDriftCompensationKey: 1]
            ]
        ]
        var newID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newID)
        guard status == noErr else {
            lastError = "Could not create a Multi-Output Device for \(deviceName(physical)) (CoreAudio \(status))."
            return nil
        }
        if outputChannelCount(newID) < 2 {
            _ = AudioHardwareDestroyAggregateDevice(newID)
            lastError = "The selected output cannot be mirrored as stereo. Choose another output."
            return nil
        }
        return newID
    }

    func enablePrivate() -> Bool {
        lastError = nil
        if privateEnabled { return true }
        guard let output = getDefault(kAudioHardwarePropertyDefaultOutputDevice),
              let input = getDefault(kAudioHardwarePropertyDefaultInputDevice),
              let systemOutput = getDefault(kAudioHardwarePropertyDefaultSystemOutputDevice),
              let blackHole = blackHole2ch,
              let virtual = blackHole16ch else {
            lastError = "Audio devices unavailable. Connect your headphones and verify BlackHole 2ch/16ch."
            return false
        }
        guard output != blackHole, output != virtual,
              outputChannelCount(output) >= 2, !isAggregate(output) else {
            lastError = "Select a physical stereo output (headphones or Mac speakers) before enabling PrivateGPT Audio."
            return false
        }

        destroyOldOwnedAggregate()
        let original = Snapshot(input: input, output: output, systemOutput: systemOutput)
        guard let mirrored = createMirroredOutput(for: output, blackHole: blackHole) else { return false }

        let okOutput = setDefault(kAudioHardwarePropertyDefaultOutputDevice, device: mirrored)
        let okSystem = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, device: mirrored)
        let okInput = setDefault(kAudioHardwarePropertyDefaultInputDevice, device: virtual)

        guard okOutput && okSystem && okInput && privateEnabled else {
            // Roll back every default before destroying the temporary aggregate.
            _ = setDefault(kAudioHardwarePropertyDefaultInputDevice, device: original.input)
            _ = setDefault(kAudioHardwarePropertyDefaultOutputDevice, device: original.output)
            _ = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, device: original.systemOutput)
            _ = AudioHardwareDestroyAggregateDevice(mirrored)
            lastError = "Could not switch audio completely. Previous devices were restored."
            return false
        }

        normal = original
        captureOriginal(original)

        // Only apply the separate speaker slider when the original output was
        // the MacBook speakers. Never change the headphone's volume on toggle.
        if let speakers = macBookSpeaker, output == speakers {
            normalSpeakerVolume = readVolume(speakers)
            if !setVolume(speakers, to: privateSpeakerVolume) {
                NSLog("PrivateGPT: speaker volume control unavailable")
            }
        }
        NSLog("PrivateGPT: audio monitoring output %@ + BlackHole 2ch", deviceName(output))
        return true
    }

    func enableNormal() -> Bool {
        lastError = nil
        let targetOutput = normal?.output
            ?? savedDevice(originalOutputKey)
            ?? lookup(["Haut-parleurs MacBook Pro", "MacBook Pro Speakers"])
        let targetInput = normal?.input
            ?? savedDevice(originalInputKey)
            ?? lookup(["Micro MacBook Pro", "MacBook Pro Microphone", "Microphone externe"])
        let targetSystem = normal?.systemOutput
            ?? savedDevice(originalSystemOutputKey)
            ?? targetOutput
        guard let output = targetOutput, let input = targetInput, let system = targetSystem else {
            lastError = "Original audio devices disconnected. Reconnect them or select another output."
            return false
        }
        let okOutput = setDefault(kAudioHardwarePropertyDefaultOutputDevice, device: output)
        let okSystem = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, device: system)
        let okInput = setDefault(kAudioHardwarePropertyDefaultInputDevice, device: input)
        guard okOutput && okSystem && okInput else {
            lastError = "Unable to restore one or more original devices."
            return false
        }
        if let speakers = macBookSpeaker, let saved = normalSpeakerVolume {
            _ = setVolume(speakers, to: saved)
        }
        normalSpeakerVolume = nil
        normal = nil
        clearOriginal()
        destroyOldOwnedAggregate()
        return true
    }

    func ensureMixerRunning() {
        // Don't hide a mixer window the user deliberately opened themselves.
        guard !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.kawauso.LadioCast"
        }) else { return }
        let url = URL(fileURLWithPath: "/Applications/Ladiocast.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error = error {
                NSLog("PrivateGPT mixer launch: %@", error.localizedDescription)
            } else {
                // Keep the app and its mixing engine running without a visible
                // Mixer window or stealing focus from the current app.
                _ = app?.hide()
            }
        }
    }
}
