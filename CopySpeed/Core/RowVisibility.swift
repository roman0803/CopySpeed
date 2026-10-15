/// Entscheidet, welche Zeilen-Labels im Kopierfenster gezeigt werden – mit Hysterese:
///
/// - Passt ein Label nicht (mehr) neben den Finder-Text → sofort ausblenden. Zwischen zwei Abfragen prüft der
///   OverlayController sichtbare Zeilen zusätzlich 10-mal pro Sekunde (`hide(_:)`), damit ein länger
///   werdender Finder-Text höchstens ~0,1 s überdeckt wird.
/// - Passt es wieder → erst einblenden, wenn das `showAfter` Abfragen in Folge so bleibt (verhindert Flackern,
///   wenn Finder seinen Restzeit-Text wechselt).
/// - Nichts wird dauerhaft gesperrt: Ein langer Text am Anfang einer Kopie („Verbleibende Zeit berechnen …“)
///   blendet das Label nur aus, solange er dasteht.
struct RowVisibility {
    /// Anzahl aufeinanderfolgender passender Abfragen, bis ein Label (wieder) erscheint
    let showAfter: Int
    private var fitStreak: [String: Int] = [:]
    private(set) var shown: Set<String> = []

    /// 3 Abfragen à 0,5 s → ein Label erscheint (wieder), wenn es 1–1,5 s lang passt.
    init(showAfter: Int = 3) {
        self.showAfter = showAfter
    }

    /// Sofort ausblenden (z. B. weil Finders Text zwischen zwei Abfragen länger geworden ist).
    mutating func hide(_ id: String) {
        shown.remove(id)
        fitStreak[id] = nil
    }

    /// Einmal pro Abfrage (alle 0,5 s) aufrufen. Zeilen, die nicht mehr vorkommen, werden vergessen.
    @discardableResult
    mutating func update(fits: [String: Bool]) -> Set<String> {
        var streak: [String: Int] = [:]
        var visible: Set<String> = []
        for (id, fitsNow) in fits {
            guard fitsNow else { continue } // sofort aus, Zähler zurück auf 0
            let n = (fitStreak[id] ?? 0) + 1
            streak[id] = n
            if shown.contains(id) || n >= showAfter { visible.insert(id) }
        }
        fitStreak = streak
        shown = visible
        return visible
    }
}
