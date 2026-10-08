// Spike C: Veröffentlicht der Finder NSProgress-Objekte für Kopien?
//
//   progress-spike <Ordner>   (z. B. das Netzlaufwerk, die externe Platte oder /Volumes)
//
// Abonniert Fortschritt für den Ordner und gibt alle 0,5 s Bytes und Geschwindigkeit aus.
// Ergebnis 2026-10-08: Finder veröffentlicht pro Kopiervorgang ein NSProgress; die Bytes
// stehen NICHT in completedUnitCount, sondern in userInfo (NSProgressByteCompletedCountKey).

import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

guard CommandLine.arguments.count > 1 else {
    print("Benutzung: progress-spike <Ordner>")
    exit(1)
}
let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }

@Sendable func info(_ p: Progress, _ key: String) -> Any? { p.userInfo[ProgressUserInfoKey(key)] }
@Sendable func int64(_ p: Progress, _ key: String) -> Int64 { (info(p, key) as? NSNumber)?.int64Value ?? -1 }

final class Entry {
    let progress: Progress
    let started = Date()
    var last: (t: TimeInterval, bytes: Int64)?
    init(_ p: Progress) { progress = p }
}
var active: [ObjectIdentifier: Entry] = [:]

let tokens = urls.map { url in Progress.addSubscriber(forFileURL: url) { p in
    let id = ObjectIdentifier(p)
    active[id] = Entry(p)
    print("➕ PUBLISHED \(info(p, "NSProgressFileDisplayNameKey") ?? "-")  op=\(info(p, "NSProgressFileOperationKindKey") ?? "-")  url=\((info(p, "NSProgressFileURLKey") as? URL)?.path ?? "-")")
    return {
        if let e = active[id] {
            let secs = Date().timeIntervalSince(e.started)
            let bytes = int64(p, "NSProgressByteCompletedCountKey")
            print(String(format: "➖ UNPUBLISHED %@  Ø %.1f MB/s über %.1f s", "\(info(p, "NSProgressFileDisplayNameKey") ?? "-")",
                         Double(max(bytes, 0)) / 1e6 / secs, secs))
        }
        active[id] = nil
    }
} }

Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let now = Date().timeIntervalSinceReferenceDate
    var sum = 0.0
    for e in active.values.sorted(by: { $0.started < $1.started }) {
        let p = e.progress
        let bytes = int64(p, "NSProgressByteCompletedCountKey")
        let total = int64(p, "NSProgressByteTotalCountKey")
        var speed = "        …"
        if let l = e.last, now > l.t, bytes >= 0, l.bytes >= 0 {
            let bps = Double(bytes - l.bytes) / (now - l.t)
            sum += bps
            speed = String(format: "%7.1f MB/s %6.0f Mbit/s", bps / 1e6, bps * 8 / 1e6)
        }
        e.last = (now, bytes)
        print(String(format: "  %-20@ %6.2f/%6.2f GB  %@  Dateien %lld/%lld",
                     "\(info(p, "NSProgressFileDisplayNameKey") ?? "-")",
                     Double(max(bytes, 0)) / 1e9, Double(max(total, 0)) / 1e9, speed,
                     int64(p, "NSProgressFileCompletedCountKey"), int64(p, "NSProgressFileTotalCountKey")))
    }
    if active.count > 1 { print(String(format: "  Σ %.1f MB/s  %.0f Mbit/s", sum / 1e6, sum * 8 / 1e6)) }
}

print("Abonniert: \(urls.map(\.path)) – jetzt im Finder etwas dorthin kopieren (Ctrl+C beendet)")
withExtendedLifetime(tokens) { RunLoop.main.run() }
