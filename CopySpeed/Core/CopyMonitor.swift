import AppKit
import Observation

/// Lage einer Zeile im Kopierfenster – relativ zur linken oberen Fensterecke (Punkte, y nach unten).
struct RowLayout: Equatable {
    /// Vertikale Mitte der Statuszeile
    let statusMidY: CGFloat
    /// Rechter Rand des Statustexts – der größte bisher gesehene Wert dieses Vorgangs, damit unsere Zahl
    /// nicht ein- und ausblendet, während Finder die Restzeit mal länger, mal kürzer formuliert.
    let statusTextMaxX: CGFloat
}

/// Ein Kopiervorgang mit berechneter Geschwindigkeit.
struct CopyOperation: Identifiable {
    let id: String
    let name: String
    let doneBytes: Double?
    let totalBytes: Double?
    let speed: Double?
    let average: Double?
    let layout: RowLayout?
}

/// Ein Kopierfenster mit seinen Vorgängen.
struct CopyWindow: Identifiable {
    let id: Int
    /// Accessibility-Element des Fensters – für das schnelle Nachführen der Position
    let element: AXUIElement?
    /// Rahmen in Quartz-Koordinaten
    let frame: CGRect
    /// Vertikale Mitte der Titelzeile (Ampel-Knöpfe), relativ zur Fensteroberkante
    let titleBarMidY: CGFloat
    /// Ab hier ist die Titelzeile frei (rechts neben den Ampel-Knöpfen), relativ zum linken Fensterrand
    let titleMinX: CGFloat
    /// Sichtbarer Bereich der Vorgangsliste, fensterrelativ (nil = unbekannt)
    let contentRect: CGRect?
    let operations: [CopyOperation]
    var totalSpeed: Double? {
        let speeds = operations.compactMap(\.speed)
        return speeds.isEmpty ? nil : speeds.reduce(0, +)
    }
}

/// Fragt die Finder-Kopierfenster regelmäßig ab und berechnet Geschwindigkeiten.
@MainActor
@Observable
final class CopyMonitor {
    private(set) var windows: [CopyWindow] = []
    private(set) var isTrusted = AX.isTrusted

    @ObservationIgnored var onUpdate: (([CopyWindow]) -> Void)?
    @ObservationIgnored private var trackers: [String: SpeedTracker] = [:]
    /// Größter bisher gesehener rechter Rand des Statustexts je Vorgang (fensterrelativ)
    @ObservationIgnored private var statusExtents: [String: CGFloat] = [:]
    @ObservationIgnored private var timer: Timer?

    static let interval: TimeInterval = 0.5

    var operationCount: Int { windows.reduce(0) { $0 + $1.operations.count } }

    var totalSpeed: Double? {
        let speeds = windows.compactMap(\.totalSpeed)
        return speeds.isEmpty ? nil : speeds.reduce(0, +)
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        // .common: läuft auch weiter, während das Menüleisten-Menü offen ist.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Sofort neu auslesen, z. B. wenn sich die Fenstergröße geändert hat (Vorgang dazu/fertig).
    func refreshNow() {
        guard timer != nil else { return }
        tick()
    }

    private func tick() {
        let trusted = AX.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        guard trusted else {
            publish([])
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        var seen = Set<String>()
        var result: [CopyWindow] = []

        for (wi, snapshot) in FinderCopyReader.read().enumerated() {
            let origin = snapshot.frame.origin
            var titleCount: [String: Int] = [:]
            let ops: [CopyOperation] = snapshot.operations.map { op in
                // Schlüssel aus Fenster + Titel ohne Zahlen: Der Finder zählt im Titel die
                // verbleibenden Objekte herunter („Kopieren von 941 Objekten …“ → „… 906 …“).
                // Gleiche Titel werden durchnummeriert.
                let stableTitle = op.title.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
                let n = titleCount[stableTitle, default: 0]
                titleCount[stableTitle] = n + 1
                let key = "\(wi)|\(stableTitle)|\(n)"
                seen.insert(key)

                let parsed = op.status.flatMap(ProgressTextParser.bytes(in:))
                let total = parsed?.total
                // Balken × Gesamtgröße ist feiner aufgelöst als der gerundete Text.
                let done: Double? = if let f = op.fraction, let t = total { f * t } else { parsed?.done }

                var tracker = trackers[key] ?? SpeedTracker()
                if let done { tracker.add(bytes: done, at: now) }
                trackers[key] = tracker
                DebugLog.write("""
                    [\(key)] fraction=\(op.fraction.map { String(format: "%.6f", $0) } ?? "-") \
                    status=\"\(op.status ?? "-")\" done=\(done.map { String(format: "%.0f", $0) } ?? "-") \
                    speed=\(tracker.current.map { String(format: "%.0f", $0) } ?? "-")
                    """)

                var layout: RowLayout?
                if let status = op.statusFrame, let textMaxX = op.statusTextMaxX {
                    let extent = max(statusExtents[key] ?? 0, textMaxX - origin.x)
                    statusExtents[key] = extent
                    layout = RowLayout(statusMidY: status.midY - origin.y, statusTextMaxX: extent)
                }
                DebugLog.write("""
                    [\(key)] layout bar=\(op.barFrame.map { "\($0)" } ?? "-") status=\(op.statusFrame.map { "\($0)" } ?? "-") \
                    textMaxX=\(op.statusTextMaxX.map { "\($0)" } ?? "-") window=\(snapshot.frame) close=\(snapshot.closeButtonFrame.map { "\($0)" } ?? "-") \
                    lightsMaxX=\(snapshot.trafficLightsMaxX.map { "\($0)" } ?? "-") content=\(snapshot.contentFrame.map { "\($0)" } ?? "-")
                    """)

                return CopyOperation(
                    id: key,
                    name: ProgressTextParser.itemName(in: op.title) ?? op.title,
                    doneBytes: done,
                    totalBytes: total,
                    speed: tracker.current,
                    average: tracker.average,
                    layout: layout)
            }
            // Ohne Knöpfe: Maße einer üblichen Titelzeile annehmen.
            let titleBarMidY = snapshot.closeButtonFrame.map { $0.midY - origin.y } ?? 18
            let titleMinX = (snapshot.trafficLightsMaxX.map { $0 - origin.x } ?? 70) + 12
            let contentRect = snapshot.contentFrame.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            result.append(CopyWindow(id: wi, element: snapshot.element, frame: snapshot.frame,
                                     titleBarMidY: titleBarMidY, titleMinX: titleMinX,
                                     contentRect: contentRect, operations: ops))
        }

        trackers = trackers.filter { seen.contains($0.key) }
        statusExtents = statusExtents.filter { seen.contains($0.key) }
        publish(result)
    }

    private func publish(_ new: [CopyWindow]) {
        // Leere Zustände nicht ständig neu setzen, damit SwiftUI im Leerlauf nichts zu tun hat.
        if !(new.isEmpty && windows.isEmpty) { windows = new }
        onUpdate?(new)
    }
}
