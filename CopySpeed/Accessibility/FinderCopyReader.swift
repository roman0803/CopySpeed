import AppKit
import ApplicationServices

/// Momentaufnahme eines Vorgangs (einer Zeile) im Finder-Kopierfenster.
/// Alle Rahmen in globalen Quartz-Koordinaten.
struct CopyOperationSnapshot {
    let title: String
    let status: String?
    /// Fortschrittsbalken 0…1
    let fraction: Double?
    let barFrame: CGRect?
    /// Rahmen des Status-Textfelds („2,00 GB von 3,74 GB – …“)
    let statusFrame: CGRect?
    /// Rechter Rand des tatsächlich gezeichneten Statustexts
    let statusTextMaxX: CGFloat?
}

/// Momentaufnahme eines Finder-Kopierfensters.
struct CopyWindowSnapshot {
    let element: AXUIElement
    /// Rahmen in Quartz-Koordinaten
    let frame: CGRect
    /// Rahmen des Schließen-Knopfs – gibt die Höhe der Titelzeile vor
    let closeButtonFrame: CGRect?
    /// Rechter Rand der Ampel-Knöpfe (Schließen/Minimieren/Zoomen)
    let trafficLightsMaxX: CGFloat?
    /// Sichtbarer Bereich der Vorgangsliste (AXScrollArea) – Zeilen außerhalb sind weggescrollt
    let contentFrame: CGRect?
    let operations: [CopyOperationSnapshot]
}

/// Liest die Kopierfenster des Finders per Accessibility aus.
///
/// Struktur (macOS 27.2, siehe TODO.md / Spike A):
/// ```
/// AXWindow title="Kopieren" id="Progress"
///   AXScrollArea
///     AXImage · AXStaticText (Titel) · AXProgressIndicator · AXButton · AXStaticText (Status)   ← je Vorgang
///   AXButton sub="AXCloseButton" · AXZoomButton · AXMinimizeButton
/// ```
enum FinderCopyReader {
    /// Sprachunabhängige Kennung des Kopierfensters.
    static let copyWindowIdentifier = "Progress"

    /// Schrift des Finder-Statustexts – nur für die Schätzung, falls AX die Textgrenzen nicht liefert.
    private static let statusFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    static var finderPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
    }

    static func finderApp() -> AXUIElement? {
        finderPID.map(AXUIElementCreateApplication)
    }

    static func read() -> [CopyWindowSnapshot] {
        guard let app = finderApp() else { return [] }
        return AX.windows(of: app)
            .filter { AX.string($0, kAXIdentifierAttribute) == copyWindowIdentifier }
            .compactMap { window in
                guard let frame = AX.frame(window) else { return nil }
                let children = AX.children(window)
                let buttons = children.filter { AX.role($0) == kAXButtonRole as String }
                func button(_ subrole: String) -> AXUIElement? {
                    buttons.first { AX.string($0, kAXSubroleAttribute) == subrole }
                }
                let close = button(kAXCloseButtonSubrole as String).flatMap(AX.frame)
                let trafficLights = [kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole]
                    .compactMap { button($0 as String).flatMap(AX.frame)?.maxX }
                let content = children.first { AX.role($0) == kAXScrollAreaRole as String }.flatMap(AX.frame)
                // Reihenfolge wie im Fenster (von oben nach unten) – die AX-Reihenfolge weicht davon ab.
                let ops = operations(in: window).sorted { ($0.barFrame?.minY ?? 0) < ($1.barFrame?.minY ?? 0) }
                return CopyWindowSnapshot(element: window, frame: frame, closeButtonFrame: close,
                                          trafficLightsMaxX: trafficLights.max(), contentFrame: content, operations: ops)
            }
    }

    /// Ordnet jedem Fortschrittsbalken den Titel (Text davor) und Status (Text danach) zu.
    /// Funktioniert, egal ob die Vorgänge flach in einem Container oder in eigenen Gruppen liegen.
    private static func operations(in window: AXUIElement) -> [CopyOperationSnapshot] {
        let barRole = kAXProgressIndicatorRole as String
        let textRole = kAXStaticTextRole as String
        return AX.findAll(window, role: barRole).compactMap { bar in
            guard let parent = AX.parent(bar) else { return nil }
            let siblings = AX.children(parent)
            guard let i = siblings.firstIndex(where: { CFEqual($0, bar) }) else { return nil }
            let before = siblings[..<i].reversed().prefix { AX.role($0) != barRole }.first { AX.role($0) == textRole }
            let after = siblings[(i + 1)...].prefix { AX.role($0) != barRole }.first { AX.role($0) == textRole }

            let minV = AX.number(bar, kAXMinValueAttribute) ?? 0
            let maxV = AX.number(bar, kAXMaxValueAttribute) ?? 1
            let fraction = AX.number(bar, kAXValueAttribute).flatMap { v in
                maxV > minV ? min(max((v - minV) / (maxV - minV), 0), 1) : nil
            }
            let status = after.flatMap { AX.string($0, kAXValueAttribute) }
            let statusFrame = after.flatMap(AX.frame)
            return CopyOperationSnapshot(
                title: before.flatMap { AX.string($0, kAXValueAttribute) } ?? "",
                status: status,
                fraction: fraction,
                barFrame: AX.frame(bar),
                statusFrame: statusFrame,
                statusTextMaxX: after.flatMap { textMaxX(of: $0, text: status, fieldFrame: statusFrame) })
        }
    }

    /// Rechter Rand des Statustexts: bevorzugt exakt per AX, sonst über die Schriftbreite geschätzt.
    private static func textMaxX(of element: AXUIElement, text: String?, fieldFrame: CGRect?) -> CGFloat? {
        if let bounds = AX.textBounds(element) { return bounds.maxX }
        guard let text, let fieldFrame else { return nil }
        let width = (text as NSString).size(withAttributes: [.font: statusFont]).width
        return min(fieldFrame.minX + ceil(width) + 2, fieldFrame.maxX)
    }
}
