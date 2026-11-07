import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func apply(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { Log.app.error("launch at login: \(error.localizedDescription)") }
    }
}
