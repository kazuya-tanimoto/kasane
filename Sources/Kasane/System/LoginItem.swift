import Foundation
import ServiceManagement

/// ログイン時の自動起動（SMAppService）
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Kasane: login item update failed: \(error)")
        }
    }
}
