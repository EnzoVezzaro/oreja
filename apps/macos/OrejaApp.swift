import AppKit
import SwiftUI
import OrejaCore

@main
struct OrejaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.state.menuBarSymbol)
                .accessibilityLabel("Oreja de Van Gogh: \(model.state.title)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility: no Dock icon and no main window.
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.bootstrap()
        // A menu-bar-only app otherwise appears to do nothing when opened from Finder. Show the
        // main settings surface for returning users; first-run users already get onboarding.
        if AppModel.shared.settings.onboardingCompleted {
            AppModel.shared.showSettings()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.handleTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
