import SwiftUI

@main
struct CopySpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: appDelegate.monitor)
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = CopyMonitor()
    private let overlay = OverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Als Test-Host nichts starten (kein Berechtigungsdialog, keine Panels).
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        if !AX.isTrusted { AX.requestTrust() }
        monitor.onUpdate = { [overlay] windows in overlay.update(windows) }
        monitor.start()
    }
}
