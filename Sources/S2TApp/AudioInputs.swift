import AppKit
import CoreAudio
import S2TCore

struct AudioInput: Identifiable, Equatable {
    let id: String
    let deviceID: AudioDeviceID
    let name: String
    let transport: MicrophoneCandidate.Transport
    var isBluetooth: Bool { transport == .bluetooth }
}

@MainActor final class AudioInputs: ObservableObject {
    @Published private(set) var devices: [AudioInput] = []
    @Published private(set) var defaultName = "System default"
    private var listener: AudioObjectPropertyListenerBlock?

    init(observe: Bool = true) {
        refresh()
        if observe {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            listener = block
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            }
        }
    }

    func refresh() {
        devices = Self.enumerate()
        defaultName = Self.selected(devices: devices, uid: "")?.name ?? "No wired or built-in input"
    }

    nonisolated static func resolve(_ uid: String) -> AudioDeviceID? {
        selected(devices: enumerate(), uid: uid)?.deviceID
    }

    nonisolated private static func selected(devices: [AudioInput], uid: String) -> AudioInput? {
        let defaultID = devices.first { $0.deviceID == defaultDevice() }?.id
        let selectedID = MicrophoneSelection.resolve(selection: uid, defaultID: defaultID,
            devices: devices.map { MicrophoneCandidate(id: $0.id, transport: $0.transport) })
        return devices.first { $0.id == selectedID }
    }

    nonisolated private static func defaultDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        return device
    }

    nonisolated private static func enumerate() -> [AudioInput] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var input = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &input, 0, nil, &bytes) == noErr, bytes > 0,
                  let uid = string(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = string(id, selector: kAudioObjectPropertyName) else { return nil }
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportProperty = address(kAudioDevicePropertyTransportType)
            let status = AudioObjectGetPropertyData(id, &transportProperty, 0, nil, &transportSize, &transport)
            guard status == noErr else { return nil }
            let kind: MicrophoneCandidate.Transport
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: kind = .bluetooth
            case kAudioDeviceTransportTypeBuiltIn: kind = .builtIn
            default: kind = .other
            }
            return AudioInput(id: uid, deviceID: id, name: name, transport: kind)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func string(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    nonisolated private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
