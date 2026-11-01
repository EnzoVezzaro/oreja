import Foundation
import ServiceManagement

/// Launch at login via `SMAppService.mainApp`.
///
/// The registration only takes effect for a signed app bundle in a stable location. When macOS
/// rejects it (for example an ad-hoc signed build run from a build folder) the failure is surfaced
/// in Settings instead of being reported as success.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func apply(_ enabled: Bool, report: @escaping (String?) -> Void) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            report(nil)
        } catch {
            report(error.localizedDescription)
        }
    }
}
