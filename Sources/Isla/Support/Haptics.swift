import AppKit

enum Haptics {
    static func tap() {
        guard Preferences.shared.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    static func level() {
        guard Preferences.shared.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
