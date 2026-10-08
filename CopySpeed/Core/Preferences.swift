import Foundation

/// UserDefaults-Schlüssel, gemeinsam genutzt von `@AppStorage` und dem restlichen Code.
enum Preferences {
    static let unitKey = "speedUnit"
    static let showInMenuBarKey = "showInMenuBar"

    static var unit: SpeedUnit {
        SpeedUnit(rawValue: UserDefaults.standard.string(forKey: unitKey) ?? "") ?? .both
    }
}
