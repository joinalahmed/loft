import Carbon
import AppKit

/// Global hotkeys via Carbon's RegisterEventHotKey: works without Accessibility.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    struct Binding { let id: UInt32; let keyCode: UInt32; let modifiers: UInt32; let title: String; let action: @MainActor () -> Void }
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private(set) var bindings: [Binding] = []
    private var handler: EventHandlerRef?
    private init() {}

    func registerDefaults() {
        let vm = NotchViewModel.shared
        let ctrlOpt = UInt32(controlKey | optionKey)
        bindings = [
            Binding(id: 1, keyCode: UInt32(kVK_ANSI_N), modifiers: ctrlOpt, title: "⌃⌥N  Toggle panel") { vm.toggle() },
            Binding(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), title: "⌥Space  Hide / show Isla") { vm.isHidden.toggle() },
            Binding(id: 3, keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOpt, title: "⌃⌥C  Clipboard") { vm.state == .open && vm.tab == .clipboard ? vm.close() : vm.open(tab: .clipboard) },
            Binding(id: 4, keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOpt, title: "⌃⌥K  Command palette") { vm.open(); vm.paletteVisible = true },
            Binding(id: 5, keyCode: UInt32(kVK_ANSI_T), modifiers: ctrlOpt, title: "⌃⌥T  Timer") { vm.open(tab: .timer) },
            Binding(id: 6, keyCode: UInt32(kVK_ANSI_S), modifiers: ctrlOpt, title: "⌃⌥S  Shelf") { vm.open(tab: .shelf) },
        ]
        installHandler()
        for b in bindings { register(b) }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            Task { @MainActor in HotKeyManager.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func register(_ b: Binding) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4953_4C41), id: b.id) // 'ISLA'
        let status = RegisterEventHotKey(b.keyCode, b.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[b.id] = ref } else { Log.app.warning("hotkey \(b.title) failed: \(status)") }
    }

    private func fire(_ id: UInt32) { bindings.first { $0.id == id }?.action() }
}
