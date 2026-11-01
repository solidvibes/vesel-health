import Foundation
import Observation
import ServiceManagement

/// "Open at login" through `SMAppService.mainApp`. Release builds only: a Debug build never registers itself.
@MainActor @Observable
final class LoginItem {
    #if DEBUG
    static let isAvailable = false
    #else
    static let isAvailable = true
    #endif

    private(set) var status: SMAppService.Status = .notRegistered

    init() {
        refresh()
    }

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ on: Bool) {
        guard Self.isAvailable else { return }
        if on {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        refresh()
    }

    /// Opens at login once by default; after that it is the owner's switch.
    func registerOnFirstLaunch(config: AppConfig) {
        guard Self.isAvailable, !config.defaults.bool(forKey: "loginItemOffered") else { return }
        config.defaults.set(true, forKey: "loginItemOffered")
        set(true)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
