import Foundation

/// Liest die Texte aus dem Finder-Kopierfenster aus.
///
/// Beispiele (macOS 27.2):
/// - Titel:  `Kopieren von „Urlaubsvideo.mov“ nach „video“`
/// - Status: `2,00 GB von 3,74 GB - weniger als eine Minute`
enum ProgressTextParser {
    /// Finder rechnet dezimal (1 KB = 1000 Byte).
    private static let unitFactor: [String: Double] = [
        "byte": 1, "bytes": 1, "b": 1,
        "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12,
    ]

    private static let bytesRegex = try! NSRegularExpression(
        pattern: #"([\d.,  ]+)\s*(Bytes?|[KMGT]B)\s+(?:von|of)\s+([\d.,  ]+)\s*(Bytes?|[KMGT]B)"#,
        options: [.caseInsensitive])

    private static let quotedRegex = try! NSRegularExpression(pattern: #"[„“"«‹]([^“”"»›]+)[“”"»›]"#)

    /// „2,00 GB von 3,74 GB …“ → (2.0e9, 3.74e9)
    static func bytes(in text: String) -> (done: Double, total: Double)? {
        let ns = text as NSString
        guard let m = bytesRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
        guard let a = number(group(1)), let ua = unitFactor[group(2).lowercased()],
              let b = number(group(3)), let ub = unitFactor[group(4).lowercased()] else { return nil }
        return (a * ua, b * ub)
    }

    private static let countRegex = try! NSRegularExpression(pattern: #"(\d[\d.,]*)\s+(\p{L}+)"#)

    /// Was kopiert wird:
    /// - `Kopieren von „Film.mkv“ nach „video“` → `Film.mkv`
    /// - `Kopieren von 42 Objekten nach „video“` → `42 Objekte` (nur das Ziel steht in Anführungszeichen)
    static func itemName(in title: String) -> String? {
        let ns = title as NSString
        let quoted = quotedRegex.matches(in: title, range: NSRange(location: 0, length: ns.length))
        if quoted.count >= 2 {
            return ns.substring(with: quoted[0].range(at: 1))
        }
        if let m = countRegex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) {
            let count = ns.substring(with: m.range(at: 1))
            var noun = ns.substring(with: m.range(at: 2))
            if noun == "Objekten" { noun = "Objekte" } // Dativ aus „von 42 Objekten“
            return "\(count) \(noun)"
        }
        return quoted.first.map { ns.substring(with: $0.range(at: 1)) }
    }

    /// Versteht „1,5“, „1.5“, „1.234,5“ und „1,234.5“.
    static func number(_ raw: String) -> Double? {
        var s = raw.filter { !$0.isWhitespace }
        let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            // Beide vorhanden → das hintere Zeichen ist der Dezimaltrenner.
            if c > d {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if lastComma != nil {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        return Double(s)
    }
}
