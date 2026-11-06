import Foundation
import IOKit.pwr_mgt
import Combine

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()
    @Published private(set) var isActive = false
    private var assertion: IOPMAssertionID = 0
    private init() {}

    func toggle() { isActive ? release() : acquire() }

    func acquire() {
        guard !isActive else { return }
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "Isla keep awake" as CFString, &assertion)
        isActive = ok == kIOReturnSuccess
        if isActive {
            NotchViewModel.shared.show(message: IslandMessage(title: "Keep Awake On", subtitle: "Mac will not sleep", symbol: "cup.and.saucer.fill", tint: .yellow), duration: 2)
        }
    }

    func release() {
        guard isActive else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
        NotchViewModel.shared.show(message: IslandMessage(title: "Keep Awake Off", symbol: "cup.and.saucer", tint: .secondary), duration: 1.5)
    }
}
