import ServiceManagement
import SwiftUI

/// Symbol bzw. Live-Geschwindigkeit in der Menüleiste.
struct MenuBarLabel: View {
    let monitor: CopyMonitor
    @AppStorage(Preferences.showInMenuBarKey) private var showInMenuBar = true
    @AppStorage(Preferences.unitKey) private var unit: SpeedUnit = .both

    var body: some View {
        if !monitor.isTrusted {
            Image(systemName: "exclamationmark.triangle")
        } else if showInMenuBar, monitor.operationCount > 0 {
            // In der Menüleiste nur eine Einheit, damit der Text kurz bleibt.
            Text(SpeedFormat.speed(monitor.totalSpeed, unit: unit == .megabits ? .megabits : .megabytes))
                .monospacedDigit()
        } else {
            Image(systemName: "speedometer")
        }
    }
}

struct MenuContent: View {
    let monitor: CopyMonitor
    @AppStorage(Preferences.showInMenuBarKey) private var showInMenuBar = true
    @AppStorage(Preferences.unitKey) private var unit: SpeedUnit = .both
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if !monitor.isTrusted {
            Text("Bedienungshilfen-Zugriff fehlt")
            Button("Zugriff erlauben …") {
                AX.requestTrust()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            Divider()
        } else {
            statusSection
            Divider()
        }

        Picker("Einheit", selection: $unit) {
            ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Geschwindigkeit in der Menüleiste", isOn: $showInMenuBar)
        Toggle("Bei Anmeldung starten", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()
        Button("Über CopySpeed") {
            NSApp.activate(ignoringOtherApps: true)
            // AppLogo hat eine helle und eine dunkle Variante und folgt dem Erscheinungsbild des Systems.
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationIcon: NSImage(named: "AppLogo") ?? NSApp.applicationIconImage as Any,
            ])
        }
        Button("CopySpeed beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var statusSection: some View {
        let ops = monitor.windows.flatMap(\.operations)
        if ops.isEmpty {
            Text("Keine Kopie aktiv")
        } else {
            ForEach(ops) { op in
                Text("\(op.name): \(SpeedFormat.speed(op.speed, unit: unit))")
            }
            if ops.count > 1 {
                Text("Gesamt: \(SpeedFormat.speed(monitor.totalSpeed, unit: unit))")
            }
        }
    }
}
