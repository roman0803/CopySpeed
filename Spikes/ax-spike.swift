// Spike A/B: Finder-Kopierfenster per Accessibility untersuchen.
//
//   ax-spike dump    → AX-Baum aller Finder-Fenster mit Fortschrittsbalken ausgeben
//   ax-spike dumpall → AX-Baum aller Finder-Fenster (begrenzte Tiefe)
//   ax-spike watch   → alle 0,5 s Fortschritt auslesen und Geschwindigkeit berechnen

import AppKit
import ApplicationServices

// MARK: - AX-Helfer

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v
}

func string(_ e: AXUIElement, _ name: String) -> String? {
    guard let v = attr(e, name) else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

func number(_ e: AXUIElement, _ name: String) -> Double? {
    (attr(e, name) as? NSNumber)?.doubleValue
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) ?? "?" }

func describe(_ e: AXUIElement) -> String {
    var parts = [role(e)]
    for (label, key) in [("sub", kAXSubroleAttribute), ("title", kAXTitleAttribute),
                         ("value", kAXValueAttribute), ("desc", kAXDescriptionAttribute),
                         ("id", kAXIdentifierAttribute), ("help", kAXHelpAttribute),
                         ("min", kAXMinValueAttribute), ("max", kAXMaxValueAttribute)] {
        if let s = string(e, key) { parts.append("\(label)=\"\(s)\"") }
    }
    return parts.joined(separator: " ")
}

func dumpTree(_ e: AXUIElement, depth: Int = 0, maxDepth: Int) {
    print(String(repeating: "  ", count: depth) + describe(e))
    guard depth < maxDepth else { return }
    for c in children(e) { dumpTree(c, depth: depth + 1, maxDepth: maxDepth) }
}

func findAll(_ e: AXUIElement, role wanted: String, maxDepth: Int = 15, depth: Int = 0) -> [AXUIElement] {
    var out: [AXUIElement] = []
    if role(e) == wanted { out.append(e) }
    guard depth < maxDepth else { return out }
    for c in children(e) { out += findAll(c, role: wanted, maxDepth: maxDepth, depth: depth + 1) }
    return out
}

func texts(_ e: AXUIElement, maxDepth: Int = 6, depth: Int = 0) -> [String] {
    var out: [String] = []
    if role(e) == kAXStaticTextRole as String, let s = string(e, kAXValueAttribute) { out.append(s) }
    guard depth < maxDepth else { return out }
    for c in children(e) { out += texts(c, maxDepth: maxDepth, depth: depth + 1) }
    return out
}

func finderApp() -> AXUIElement {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        fatalError("Finder läuft nicht")
    }
    return AXUIElementCreateApplication(finder.processIdentifier)
}

func finderWindows() -> [AXUIElement] {
    (attr(finderApp(), kAXWindowsAttribute) as? [AXUIElement]) ?? []
}

// MARK: - Byte-Parser („1,2 GB von 8,4 GB“, „512 KB of 3.1 GB“)

let unitFactor: [String: Double] = [
    "byte": 1, "bytes": 1, "b": 1,
    "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12,
]

func parseNumber(_ raw: String) -> Double? {
    var s = raw.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
    let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
    if let c = lastComma, let d = lastDot {
        // beide vorhanden → das letzte Zeichen ist der Dezimaltrenner
        if c > d { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else { s = s.replacingOccurrences(of: ",", with: "") }
    } else if lastComma != nil {
        s = s.replacingOccurrences(of: ",", with: ".")
    }
    return Double(s)
}

let bytesRegex = try! NSRegularExpression(
    pattern: #"([\d., ]+)\s*(Bytes?|[KMGT]B)\s+(?:von|of)\s+([\d., ]+)\s*(Bytes?|[KMGT]B)"#,
    options: [.caseInsensitive])

func parseBytes(_ text: String) -> (done: Double, total: Double)? {
    let ns = text as NSString
    guard let m = bytesRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    func g(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
    guard let a = parseNumber(g(1)), let ua = unitFactor[g(2).lowercased()],
          let b = parseNumber(g(3)), let ub = unitFactor[g(4).lowercased()] else { return nil }
    return (a * ua, b * ub)
}

// MARK: - Geschwindigkeit

struct Sample { let t: TimeInterval; let bytes: Double }

final class Tracker {
    var samples: [Sample] = []
    func add(_ bytes: Double) -> Double? {
        let now = Date().timeIntervalSinceReferenceDate
        samples.append(Sample(t: now, bytes: bytes))
        samples.removeAll { now - $0.t > 3.0 }
        guard let first = samples.first, let last = samples.last, last.t - first.t > 0.4 else { return nil }
        return (last.bytes - first.bytes) / (last.t - first.t)
    }
}

func fmt(_ bytesPerSec: Double?) -> String {
    guard let v = bytesPerSec else { return "    …" }
    return String(format: "%8.1f MB/s  %8.0f Mbit/s", v / 1e6, v * 8 / 1e6)
}

func fmtBytes(_ b: Double) -> String { String(format: "%.2f GB", b / 1e9) }

// MARK: - Modi

/// Alle Fenster auf dem Bildschirm (CoreGraphics) – zeigt, welcher Prozess das Kopierfenster besitzt.
func listScreenWindows() {
    let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    print("Fenster auf dem Bildschirm: \(infos.count)")
    for w in infos {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        let name = w[kCGWindowName as String] as? String ?? ""
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print(String(format: "  %-28@ pid=%-6d layer=%-4d %4.0f×%-4.0f @ %5.0f,%-5.0f  %@",
                     owner, pid, layer, b["Width"] ?? 0, b["Height"] ?? 0, b["X"] ?? 0, b["Y"] ?? 0, name))
    }
}

func dump(all: Bool) {
    listScreenWindows()
    print("\nFinder-App-Kinder (inkl. Fenster außerhalb von AXWindows):")
    for c in children(finderApp()) { print("  " + describe(c)) }
    let wins = finderWindows()
    print("\nFinder-Fenster: \(wins.count)")
    for (i, w) in wins.enumerated() {
        let hasProgress = !findAll(w, role: kAXProgressIndicatorRole as String).isEmpty
        print("\n=== Fenster \(i): \(describe(w)) | Fortschrittsbalken: \(hasProgress)")
        if all || hasProgress { dumpTree(w, maxDepth: all ? 6 : 20) }
    }
}

/// Kopierfenster des Finders (AXIdentifier "Progress", sprachunabhängig).
func copyWindows() -> [AXUIElement] {
    finderWindows().filter { string($0, kAXIdentifierAttribute) == "Progress" }
}

/// Ordnet jedem Fortschrittsbalken Titel (Text davor) und Status (Text danach) zu –
/// funktioniert, egal ob mehrere Vorgänge flach in einem Container oder in eigenen Gruppen liegen.
func operations(in window: AXUIElement) -> [(bar: AXUIElement, title: String?, status: String?)] {
    var out: [(AXUIElement, String?, String?)] = []
    for bar in findAll(window, role: kAXProgressIndicatorRole as String) {
        guard let parent = attr(bar, kAXParentAttribute).map({ $0 as! AXUIElement }) else { continue }
        let sibs = children(parent)
        guard let i = sibs.firstIndex(where: { CFEqual($0, bar) }) else { continue }
        let isText = { (e: AXUIElement) in role(e) == kAXStaticTextRole as String }
        let isBar = { (e: AXUIElement) in role(e) == kAXProgressIndicatorRole as String }
        let before = sibs[..<i].reversed().prefix { !isBar($0) }.first(where: isText)
        let after = sibs[(i + 1)...].prefix { !isBar($0) }.first(where: isText)
        out.append((bar, before.flatMap { string($0, kAXValueAttribute) }, after.flatMap { string($0, kAXValueAttribute) }))
    }
    return out
}

func frame(_ e: AXUIElement) -> CGRect? {
    var p = CGPoint.zero, s = CGSize.zero
    guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute),
          AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}

func watch() {
    var trackers: [String: (text: Tracker, bar: Tracker)] = [:]
    print("Beobachte Finder-Kopierfenster … (Ctrl+C beendet)")
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        var lines: [String] = []
        var totalText = 0.0, totalBar = 0.0, opCount = 0
        for (wi, w) in copyWindows().enumerated() {
            if let f = frame(w) { lines.append("Kopierfenster \(wi): \(Int(f.width))×\(Int(f.height)) @ \(Int(f.minX)),\(Int(f.minY))") }
            for (pi, op) in operations(in: w).enumerated() {
                let bar = op.bar
                let t = [op.title, op.status].compactMap { $0 }
                let key = op.title ?? "\(wi)/\(pi)"
                let tr = trackers[key] ?? (Tracker(), Tracker())
                trackers[key] = tr

                let value = number(bar, kAXValueAttribute)
                let maxV = number(bar, kAXMaxValueAttribute) ?? 1
                let minV = number(bar, kAXMinValueAttribute) ?? 0
                let parsed = t.lazy.compactMap(parseBytes).first

                opCount += 1
                var line = "  [\(key)]\n    "
                if let p = parsed {
                    let sText = tr.text.add(p.done)
                    line += "Text: \(fmtBytes(p.done))/\(fmtBytes(p.total)) \(fmt(sText))"
                    totalText += sText ?? 0
                    if let v = value, maxV > minV {
                        let barBytes = (v - minV) / (maxV - minV) * p.total
                        let sBar = tr.bar.add(barBytes)
                        totalBar += sBar ?? 0
                        line += " | Balken: \(fmtBytes(barBytes)) \(fmt(sBar))"
                    }
                } else {
                    line += "kein Byte-Text erkannt; Balken=\(value.map { String($0) } ?? "-")"
                }
                line += "\n    Status: \(op.status ?? "-")"
                lines.append(line)
            }
        }
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        if lines.isEmpty {
            print("\(ts)  keine Kopie aktiv")
        } else {
            print("\(ts)")
            lines.forEach { print($0) }
            if opCount > 1 { print("  Σ Text: \(fmt(totalText))  Σ Balken: \(fmt(totalBar))") }
        }
    }
    RunLoop.main.run()
}

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - main

let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(opts) else {
    print("""
    ⚠️  Kein Bedienungshilfen-Zugriff.
    Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen →
    dein Terminal-Programm aktivieren, Terminal neu starten und nochmal ausführen.
    """)
    exit(1)
}

switch CommandLine.arguments.dropFirst().first ?? "dump" {
case "dump": dump(all: false)
case "dumpall": dump(all: true)
case "watch": watch()
default: print("Benutzung: ax-spike [dump|dumpall|watch]")
}
