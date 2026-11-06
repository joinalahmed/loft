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
            Binding(id: 1, keyCode: UInt32(kVK_ANSI_N), modifiers: ctrlOpt, title: "⌃⌥N  Toggle panel") { vm.toggle(focus: true) },
            Binding(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), title: "⌥Space  Hide / show Isla") { vm.isHidden.toggle() },
            Binding(id: 3, keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOpt, title: "⌃⌥C  Clipboard") { vm.state == .open && vm.tab == .clipboard ? vm.close() : vm.open(tab: .clipboard, focus: true) },
            Binding(id: 4, keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOpt, title: "⌃⌥K  Command palette") { vm.open(focus: true); vm.paletteVisible = true },
            Binding(id: 5, keyCode: UInt32(kVK_ANSI_T), modifiers: ctrlOpt, title: "⌃⌥T  Timer") { vm.open(tab: .timer, focus: true) },
            Binding(id: 6, keyCode: UInt32(kVK_ANSI_S), modifiers: ctrlOpt, title: "⌃⌥S  Shelf") { vm.open(tab: .shelf, focus: true) },
            Binding(id: 7, keyCode: UInt32(kVK_ANSI_A), modifiers: ctrlOpt, title: "⌃⌥A  Toggle keep awake") { KeepAwakeManager.shared.toggle() },
            Binding(id: 8, keyCode: UInt32(kVK_ANSI_3), modifiers: ctrlOpt | UInt32(shiftKey), title: "⌃⌥⇧3  Screenshot: full screen") { ScreenshotManager.shared.capture(.full) },
            Binding(id: 9, keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOpt | UInt32(shiftKey), title: "⌃⌥⇧4  Screenshot: region") { ScreenshotManager.shared.capture(.region) },
            Binding(id: 10, keyCode: UInt32(kVK_ANSI_5), modifiers: ctrlOpt | UInt32(shiftKey), title: "⌃⌥⇧5  Screenshot: window") { ScreenshotManager.shared.capture(.window) },
            Binding(id: 11, keyCode: UInt32(kVK_ANSI_M), modifiers: ctrlOpt, title: "⌃⌥M  Join next meeting") {
                if let ev = CalendarManager.shared.nextEvent, let url = CalendarManager.joinURL(for: ev) { NSWorkspace.shared.open(url) } else { vm.open(tab: .calendar) }
            },
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
