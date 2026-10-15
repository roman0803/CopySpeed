import CoreGraphics

/// Berechnet, welche Texte das Overlay im Kopierfenster wo zeigt.
/// Alle Koordinaten relativ zur linken oberen Fensterecke (Punkte, y nach unten).
///
/// - Titelzeile, rechtsbündig: bei einem Vorgang dessen Geschwindigkeit (+ Ø),
///   bei mehreren die Gesamtsumme. Ist rechts neben den Ampel-Knöpfen zu wenig Platz,
///   wird der Text schrittweise gekürzt.
/// - Bei mehreren Vorgängen zusätzlich die Geschwindigkeit am Ende jeder Statuszeile,
///   rechtsbündig mit der Titelzeile (unter dem Stopp-Knopf ist die Statuszeile frei) –
///   nur wenn sie neben den Finder-Text passt und die Zeile nicht weggescrollt ist.
enum InWindowLayout {
    struct Title: Equatable {
        /// Kleiner, grauer Text links vom Hauptwert („Ø 63,2 MB/s“ oder „Gesamt“)
        let secondary: String?
        let primary: String
        let trailingX: CGFloat
        let centerY: CGFloat
    }

    struct RowLabel: Equatable {
        let id: String
        let text: String
        let trailingX: CGFloat
        let centerY: CGFloat
        /// Bis hierhin darf Finders Statustext reichen, damit das Label daneben passt (fensterrelativ).
        /// Wird auch beim schnellen Nachprüfen zwischen zwei Abfragen verwendet.
        let maxStatusTextX: CGFloat
        /// Passt gerade neben den Finder-Statustext. Ob das Label gezeigt wird, entscheidet `RowVisibility`
        /// (sofort ausblenden, erst nach stabiler Lage wieder einblenden).
        let fits: Bool
    }

    struct Result: Equatable {
        let title: Title
        let rows: [RowLabel]
    }

    /// Abstand vom rechten Fensterrand – gilt für Titel- und Statuszeilen.
    /// Knapp bemessen: Finders übliche Statustexte enden bei ca. 316–326 pt
    /// („220,5 MB von 3,92 GB – weniger als eine Minute“); mit 12 + 6 pt passt „88,8 MB/s“ bis 330 pt.
    static let rightInset: CGFloat = 12
    /// Mindestabstand zwischen Finder-Statustext und unserer Geschwindigkeit
    static let rowGap: CGFloat = 6
    /// So weit muss die Mitte einer Statuszeile innerhalb des sichtbaren Listenbereichs liegen
    static let rowVisibilityMargin: CGFloat = 6

    /// - Parameters:
    ///   - width: aktuelle Fensterbreite (kann neuer sein als `window.frame`)
    ///   - measureRow: Breite eines Zeilen-Labels in Punkten
    ///   - measureTitle: Breite des Titel-Labels (Nebentext + Hauptwert) in Punkten
    static func compute(window: CopyWindow, width: CGFloat, unit: SpeedUnit,
                        measureRow: (String) -> CGFloat,
                        measureTitle: (_ secondary: String?, _ primary: String) -> CGFloat) -> Result {
        let ops = window.operations
        let trailingX = width - rightInset
        let singleUnit: SpeedUnit = unit == .both ? .megabytes : unit

        // Titel: vom ausführlichsten zum knappsten Vorschlag; der erste, der passt, gewinnt.
        let candidates: [(String?, String)]
        if ops.count == 1, let op = ops.first {
            let avg = op.average.map { "Ø \(SpeedFormat.speed($0, unit: unit))" }
            candidates = [
                (avg, SpeedFormat.speed(op.speed, unit: unit)),
                (nil, SpeedFormat.speed(op.speed, unit: unit)),
                (nil, SpeedFormat.speed(op.speed, unit: singleUnit, compact: true)),
            ]
        } else {
            candidates = [
                ("Gesamt", SpeedFormat.speed(window.totalSpeed, unit: unit)),
                ("Gesamt", SpeedFormat.speed(window.totalSpeed, unit: singleUnit, compact: true)),
                (nil, SpeedFormat.speed(window.totalSpeed, unit: singleUnit, compact: true)),
            ]
        }
        let available = trailingX - window.titleMinX
        let chosen = candidates.first { measureTitle($0.0, $0.1) <= available } ?? candidates[candidates.count - 1]
        let title = Title(secondary: chosen.0, primary: chosen.1, trailingX: trailingX, centerY: window.titleBarMidY)

        guard ops.count > 1 else { return Result(title: title, rows: []) }

        // In der Statuszeile ist wenig Platz → eine Einheit, kompaktes Format.
        // Gegen die breiteste kompakte Form prüfen („88,8 MB/s“ bzw. „888 Mbit/s“), nicht gegen den aktuellen
        // Wert – sonst springt das Label ein und aus, sobald sich die Zahl ändert.
        let templateWidth = measureRow(SpeedFormat.speed(singleUnit == .megabits ? 111e6 : 88.8e6,
                                                         unit: singleUnit, compact: true))
        let rows: [RowLabel] = ops.compactMap { op in
            guard let layout = op.layout else { return nil }
            // Weggescrollte Zeilen: AX meldet sie an ihrer virtuellen Position, z. B. in der Titelzeile.
            if let content = window.contentRect,
               layout.statusMidY < content.minY + rowVisibilityMargin || layout.statusMidY > content.maxY - rowVisibilityMargin {
                return nil
            }
            let text = SpeedFormat.speed(op.speed, unit: singleUnit, compact: true)
            let maxStatusTextX = trailingX - rowGap - max(measureRow(text), templateWidth)
            return RowLabel(id: op.id, text: text, trailingX: trailingX, centerY: layout.statusMidY,
                            maxStatusTextX: maxStatusTextX, fits: layout.statusTextMaxX <= maxStatusTextX)
        }
        return Result(title: title, rows: rows)
    }
}
