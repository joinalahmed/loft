import CoreAudio
import AppKit

/// Watches the default output device so volume/mute changes light up the pill.
final class VolumeMonitor {
    static let shared = VolumeMonitor()
    private var device: AudioObjectID = kAudioObjectUnknown
    private var lastVolume: Float = -1
    private var lastMuted = false
    private var primed = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?

    private init() {}

    func start() {
        defaultDeviceBlock = { [weak self] _, _ in self?.attach() }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, defaultDeviceBlock!)
        attach()
    }

    private func attach() {
        detach()
        device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        primed = false
        listenerBlock = { [weak self] _, _ in self?.changed() }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in [kAudioObjectPropertyElementMain, 1, 2] {
                var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                if AudioObjectHasProperty(device, &addr) {
                    AudioObjectAddPropertyListenerBlock(device, &addr, .main, listenerBlock!)
                }
            }
        }
        changed()
        primed = true
    }

    private func detach() {
        guard device != kAudioObjectUnknown, let block = listenerBlock else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in [kAudioObjectPropertyElementMain, 1, 2] {
                var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                AudioObjectRemovePropertyListenerBlock(device, &addr, .main, block)
            }
        }
    }

    private func changed() {
        let v = volume, m = muted
        defer { lastVolume = v; lastMuted = m }
        guard primed, Preferences.shared.hudEnabled, v != lastVolume || m != lastMuted else { return }
        Task { @MainActor in NotchViewModel.shared.show(.volume(Double(v), muted: m)) }
    }

    // MARK: Read / write

    var volume: Float {
        guard device != kAudioObjectUnknown else { return 0 }
        var values: [Float] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &addr) else { continue }
            var v: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &v) == noErr { values.append(v) }
        }
        return values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    var muted: Bool {
        guard device != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var m: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &m) == noErr && m != 0
    }

    func setVolume(_ value: Float) {
        guard device != kAudioObjectUnknown else { return }
        var v = max(0, min(1, value))
        var wrote = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &addr),
                  AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { continue }
            if AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr { wrote = true }
            if element == kAudioObjectPropertyElementMain && wrote { break }
        }
        if v > 0 && muted { setMuted(false) }
    }

    func setMuted(_ on: Bool) {
        guard device != kAudioObjectUnknown else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return }
        var m: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }

    func step(_ direction: Float, fine: Bool) {
        let delta: Float = (fine ? 1.0 / 64 : 1.0 / 16) * direction
        let target = max(0, min(1, volume + delta))
        setVolume(target)
        if target == 0 { setMuted(true) }
        Task { @MainActor in NotchViewModel.shared.show(.volume(Double(target), muted: target == 0)) }
    }

    func toggleMute() {
        let next = !muted
        setMuted(next)
        Task { @MainActor in NotchViewModel.shared.show(.volume(Double(self.volume), muted: next)) }
    }

    static func defaultOutputDevice() -> AudioObjectID {
        var id = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }
}
