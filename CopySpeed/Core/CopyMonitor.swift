import AppKit
import Observation

/// Ein Kopiervorgang mit berechneter Geschwindigkeit.
struct CopyOperation: Identifiable {
    let id: String
    let name: String
    let doneBytes: Double?
    let totalBytes: Double?
    let speed: Double?
    let average: Double?
}

/// Ein Kopierfenster mit seinen Vorgängen.
struct CopyWindow: Identifiable {
    let id: Int
    /// Rahmen in Quartz-Koordinaten
    let frame: CGRect
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
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.05
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

                return CopyOperation(
                    id: key,
                    name: ProgressTextParser.itemName(in: op.title) ?? op.title,
                    doneBytes: done,
                    totalBytes: total,
                    speed: tracker.current,
                    average: tracker.average)
            }
            result.append(CopyWindow(id: wi, frame: snapshot.frame, operations: ops))
        }

        trackers = trackers.filter { seen.contains($0.key) }
        publish(result)
    }

    private func publish(_ new: [CopyWindow]) {
        // Leere Zustände nicht ständig neu setzen, damit SwiftUI im Leerlauf nichts zu tun hat.
        if !(new.isEmpty && windows.isEmpty) { windows = new }
        onUpdate?(new)
    }
}
