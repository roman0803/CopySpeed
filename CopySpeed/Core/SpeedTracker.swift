import Foundation

/// Berechnet aus fortlaufenden Byte-Ständen die aktuelle, durchschnittliche und höchste Geschwindigkeit.
struct SpeedTracker {
    private struct Sample { let time: TimeInterval; let bytes: Double }

    /// Zeitfenster für die Glättung der aktuellen Geschwindigkeit.
    var window: TimeInterval = 3
    private var samples: [Sample] = []
    private var first: Sample?
    private(set) var peak: Double = 0

    mutating func add(bytes: Double, at time: TimeInterval) {
        if let last = samples.last, bytes < last.bytes {
            // Deutlich rückwärts (z. B. neuer Vorgang mit gleichem Titel) → neu beginnen.
            // Kleine Rücksprünge (Gesamtgröße wird nachkorrigiert, Rundung) → Messwert ignorieren.
            if last.bytes - bytes > last.bytes * 0.05 {
                reset()
            } else {
                return
            }
        }
        let sample = Sample(time: time, bytes: bytes)
        if first == nil { first = sample }
        samples.append(sample)
        samples.removeAll { time - $0.time > window }
        if let c = current { peak = max(peak, c) }
    }

    mutating func reset() {
        samples.removeAll()
        first = nil
        peak = 0
    }

    /// Bytes pro Sekunde über das Glättungsfenster.
    var current: Double? {
        guard let a = samples.first, let b = samples.last, b.time - a.time >= 0.4 else { return nil }
        return (b.bytes - a.bytes) / (b.time - a.time)
    }

    /// Bytes pro Sekunde seit Beginn der Beobachtung.
    var average: Double? {
        guard let a = first, let b = samples.last, b.time - a.time >= 1 else { return nil }
        return (b.bytes - a.bytes) / (b.time - a.time)
    }
}
