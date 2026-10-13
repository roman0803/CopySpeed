import Foundation

/// Wo die Geschwindigkeit angezeigt wird.
enum OverlayMode: String, CaseIterable, Identifiable {
    /// Durchsichtiges Overlay direkt auf dem Kopierfenster (Titelzeile + Statuszeilen)
    case inWindow
    /// Schublade, die unter dem Kopierfenster hervorschaut
    case drawer
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inWindow: "Im Kopierfenster"
        case .drawer: "Unter dem Kopierfenster"
        }
    }
}

/// UserDefaults-Schlüssel, gemeinsam genutzt von `@AppStorage` und dem restlichen Code.
enum Preferences {
    static let unitKey = "speedUnit"
    static let showInMenuBarKey = "showInMenuBar"
    static let overlayModeKey = "overlayMode"

    static var unit: SpeedUnit {
        SpeedUnit(rawValue: UserDefaults.standard.string(forKey: unitKey) ?? "") ?? .both
    }

    static var overlayMode: OverlayMode {
        OverlayMode(rawValue: UserDefaults.standard.string(forKey: overlayModeKey) ?? "") ?? .inWindow
    }
}
