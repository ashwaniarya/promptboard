import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        guard isAvailable else { return }
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            NSLog("PromptBoard: Launch at Login toggle failed: %@", String(describing: error))
        }
    }
}
