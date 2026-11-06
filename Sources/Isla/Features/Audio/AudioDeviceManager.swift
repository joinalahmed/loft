import CoreAudio
import Foundation
import Combine

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let transport: UInt32
    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "airpodspro"
        case kAudioDeviceTransportTypeUSB: "cable.connector"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
        default: "speaker.wave.2"
        }
    }
}

/// Lists output devices and switches the system default; also toggles the default input's mute.
@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var defaultOutputID: AudioObjectID = kAudioObjectUnknown
    @Published private(set) var micMuted = false
    private var savedInputVolume: Float = 0.8
    private init() { refresh(); installListeners() }

    private func installListeners() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func refresh() {
        defaultOutputID = VolumeMonitor.defaultOutputDevice()
        outputDevices = Self.allDevices().filter { Self.streamCount($0, scope: kAudioDevicePropertyScopeOutput) > 0 }
            .map { AudioDevice(id: $0, name: Self.name($0), transport: Self.transport($0)) }
            .filter { !$0.name.isEmpty }
        micMuted = Self.inputMuted()
    }

    func setDefaultOutput(_ device: AudioDevice) {
        var id = device.id
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
        NotchViewModel.shared.show(message: IslandMessage(title: device.name, subtitle: "Audio output", symbol: device.symbol, tint: .white), duration: 1.8)
    }

    // MARK: Mic mute

    func toggleMicMute() { setMicMuted(!micMuted) }

    func setMicMuted(_ muted: Bool) {
        let dev = Self.defaultInputDevice()
        guard dev != kAudioObjectUnknown else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &addr), AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue {
            var m: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        } else {
            // Devices without a hardware mute: drive input gain to zero and remember the old level.
            var vaddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<Float32>.size)
            if muted {
                var cur: Float32 = 0
                if AudioObjectGetPropertyData(dev, &vaddr, 0, nil, &size, &cur) == noErr, cur > 0 { savedInputVolume = cur }
                var zero: Float32 = 0
                AudioObjectSetPropertyData(dev, &vaddr, 0, nil, size, &zero)
            } else {
                var v = savedInputVolume
                AudioObjectSetPropertyData(dev, &vaddr, 0, nil, size, &v)
            }
        }
        micMuted = muted
        NotchViewModel.shared.show(message: IslandMessage(title: muted ? "Mic Muted" : "Mic On", symbol: muted ? "mic.slash.fill" : "mic.fill", tint: muted ? .red : .green), duration: 1.5)
    }

    // MARK: CoreAudio helpers

    static func allDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    static func streamCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioObjectID>.size
    }

    static func name(_ id: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return "" }
        return v.takeRetainedValue() as String
    }

    static func transport(_ id: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size); var t: UInt32 = 0
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }

    static func defaultInputDevice() -> AudioObjectID {
        var id = kAudioObjectUnknown; var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func inputMuted() -> Bool {
        let dev = defaultInputDevice()
        guard dev != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &addr) {
            var m: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &m) == noErr { return m != 0 }
        }
        var vaddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var v: Float32 = 1; var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(dev, &vaddr, 0, nil, &size, &v) == noErr { return v == 0 }
        return false
    }

    /// True while any process has the default input device running (a call, dictation, recording…).
    static func inputInUse() -> Bool {
        let dev = defaultInputDevice()
        guard dev != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var r: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &r) == noErr && r != 0
    }
}
