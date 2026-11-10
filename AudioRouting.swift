import AppKit
import CoreAudio
import CoreFoundation

// Audio routing changes macOS defaults only. Ladiocast remains the mixer.
// Preserves the user's original devices whenever PrivateGPT mode is enabled here.
final class AudioRouting {
    static let shared = AudioRouting()

    private struct Snapshot {
        let input: AudioDeviceID
        let output: AudioDeviceID
        let systemOutput: AudioDeviceID
    }
    private var normal: Snapshot?
    private(set) var lastError: String?

    private func getDefault(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
            ? device : nil
    }

    private func setDefault(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var target = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &target) == noErr
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

    private func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            id, &address, 0, nil, &size, &value)
        guard status == noErr, let name = value?.takeRetainedValue() else { return "" }
        return name as String
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

    private var mixerOutput: AudioDeviceID? {
        lookup(["Périphérique à sortie multiple", "Multi-Output Device"])
    }
    private var virtualInput: AudioDeviceID? {
        lookup(["BlackHole 16ch"])
    }
    var privateEnabled: Bool {
        guard let input = getDefault(kAudioHardwarePropertyDefaultInputDevice),
              let output = getDefault(kAudioHardwarePropertyDefaultOutputDevice),
              let mixer = mixerOutput, let virtual = virtualInput else { return false }
        return input == virtual && output == mixer
    }
    var statusDescription: String {
        let input = getDefault(kAudioHardwarePropertyDefaultInputDevice).map(deviceName) ?? "Unknown"
        let output = getDefault(kAudioHardwarePropertyDefaultOutputDevice).map(deviceName) ?? "Unknown"
        return "Input: \(input)\nOutput: \(output)"
    }
    func enablePrivate() -> Bool {
        lastError = nil
        guard let mixer = mixerOutput, let virtual = virtualInput else {
            lastError = "Missing Multi-Output Device or BlackHole 16ch. Check Audio MIDI Setup."
            return false
        }
        if privateEnabled { return true }
        if let input = getDefault(kAudioHardwarePropertyDefaultInputDevice),
           let output = getDefault(kAudioHardwarePropertyDefaultOutputDevice),
           let systemOutput = getDefault(kAudioHardwarePropertyDefaultSystemOutputDevice) {
            // Avoid overwriting the user's original devices during a repeated toggle.
            if normal == nil {
                normal = Snapshot(input: input, output: output, systemOutput: systemOutput)
            }
        }
        let okOutput = setDefault(kAudioHardwarePropertyDefaultOutputDevice, device: mixer)
        let okSystem = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, device: mixer)
        let okInput = setDefault(kAudioHardwarePropertyDefaultInputDevice, device: virtual)
        if !(okOutput && okSystem && okInput && privateEnabled) {
            lastError = "Could not fully switch devices. Check Audio MIDI Setup."
            return false
        }
        return true
    }
    func enableNormal() -> Bool {
        lastError = nil
        let targetInput = normal?.input ?? lookup(["Micro MacBook Pro", "MacBook Pro Microphone", "MacBook Pro Microphone (Built-in)"])
        let targetOutput = normal?.output ?? lookup(["Haut-parleurs MacBook Pro", "MacBook Pro Speakers"])
        let targetSystem = normal?.systemOutput ?? targetOutput
        guard let input = targetInput, let output = targetOutput, let sys = targetSystem else {
            lastError = "Normal audio devices not found. Select your speaker and microphone in Sound settings."
            return false
        }
        let ok1 = setDefault(kAudioHardwarePropertyDefaultOutputDevice, device: output)
        let ok2 = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, device: sys)
        let ok3 = setDefault(kAudioHardwarePropertyDefaultInputDevice, device: input)
        guard ok1 && ok2 && ok3 else {
            lastError = "Unable to restore one or more normal audio devices."
            return false
        }
        normal = nil
        return true
    }
    func ensureMixerRunning() {
        guard !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.kawauso.LadioCast"
        }) else { return }
        let url = URL(fileURLWithPath: "/Applications/Ladiocast.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error { NSLog("PrivateGPT mixer launch: %@", error.localizedDescription) }
        }
    }
}
