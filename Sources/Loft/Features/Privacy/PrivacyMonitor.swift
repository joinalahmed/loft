import Foundation
import CoreAudio
import CoreMediaIO
import Combine
import AppKit

/// iPhone-style privacy dots: orange when the microphone is live, green when a camera is on.
/// When the mic has been live for a few seconds we treat it as a call and show the call island.
@MainActor
final class PrivacyMonitor: ObservableObject {
    static let shared = PrivacyMonitor()
    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var callStarted: Date?
    private var timer: Timer?
    private var micSince: Date?
    private init() {}

    var inCall: Bool { callStarted != nil }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        timer?.tolerance = 0.5
        poll()
    }

    private func poll() {
        guard Preferences.shared.privacyIndicator || Preferences.shared.callIsland else { return }
        let mic = AudioDeviceManager.inputInUse()
        let cam = Self.anyCameraRunning()
        if mic != micInUse { micInUse = mic }
        if cam != cameraInUse { cameraInUse = cam }
        if mic || cam {
            if micSince == nil { micSince = Date() }
            // A call is mic or camera live for 4+ seconds (filters out Siri / quick dictation).
            if callStarted == nil, let s = micSince, Date().timeIntervalSince(s) >= 4, Preferences.shared.callIsland {
                callStarted = s
            }
        } else {
            micSince = nil
            if callStarted != nil {
                let dur = Date().timeIntervalSince(callStarted!)
                callStarted = nil
                if dur > 30 {
                    NotchViewModel.shared.show(message: IslandMessage(title: "Call ended", subtitle: dur.clockString, symbol: "phone.down.fill", tint: .secondary), duration: 2.5)
                }
            }
        }
    }

    /// Scans CoreMediaIO devices for `DeviceIsRunningSomewhere`. Works for the built-in camera
    /// and Continuity Camera; virtual cameras may report differently.
    nonisolated static func anyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0; var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == 0, running != 0 { return true }
        }
        return false
    }
}
