import AppKit
import ApplicationServices

/// Momentaufnahme eines Vorgangs (einer Zeile) im Finder-Kopierfenster.
struct CopyOperationSnapshot {
    let title: String
    let status: String?
    /// Fortschrittsbalken 0…1
    let fraction: Double?
    /// Rahmen des Fortschrittsbalkens (Quartz-Koordinaten)
    let barFrame: CGRect?
}

/// Momentaufnahme eines Finder-Kopierfensters.
struct CopyWindowSnapshot {
    /// Rahmen in Quartz-Koordinaten
    let frame: CGRect
    let operations: [CopyOperationSnapshot]
}

/// Liest die Kopierfenster des Finders per Accessibility aus.
///
/// Struktur (macOS 27.2, siehe TODO.md / Spike A):
/// ```
/// AXWindow title="Kopieren" id="Progress"
///   AXScrollArea
///     AXImage · AXStaticText (Titel) · AXProgressIndicator · AXButton · AXStaticText (Status)   ← je Vorgang
/// ```
enum FinderCopyReader {
    /// Sprachunabhängige Kennung des Kopierfensters.
    static let copyWindowIdentifier = "Progress"

    static var finderPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
    }

    static func read() -> [CopyWindowSnapshot] {
        guard let pid = finderPID else { return [] }
        let app = AXUIElementCreateApplication(pid)
        return AX.windows(of: app)
            .filter { AX.string($0, kAXIdentifierAttribute) == copyWindowIdentifier }
            .compactMap { window in
                guard let frame = AX.frame(window) else { return nil }
                // Reihenfolge wie im Fenster (von oben nach unten) – die AX-Reihenfolge weicht davon ab.
                let ops = operations(in: window).sorted { ($0.barFrame?.minY ?? 0) < ($1.barFrame?.minY ?? 0) }
                return CopyWindowSnapshot(frame: frame, operations: ops)
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
            return CopyOperationSnapshot(
                title: before.flatMap { AX.string($0, kAXValueAttribute) } ?? "",
                status: after.flatMap { AX.string($0, kAXValueAttribute) },
                fraction: fraction,
                barFrame: AX.frame(bar))
        }
    }
}
