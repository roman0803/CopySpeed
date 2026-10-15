import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable {
    case megabytes, megabits, both
    var id: String { rawValue }

    var label: String {
        switch self {
        case .megabytes: "MB/s"
        case .megabits: "Mbit/s"
        case .both: "MB/s und Mbit/s"
        }
    }
}

enum SpeedFormat {
    /// - Parameter compact: Für knappen Platz – höchstens so breit wie „88,8 MB/s“ bzw. „888 Mbit/s“:
    ///   ab 100 MB/s ohne Nachkommastelle („313 MB/s“), ab 1000 MB/s in GB/s („1,25 GB/s“),
    ///   ab 1000 Mbit/s in Gbit/s („1,2 Gbit/s“).
    static func speed(_ bytesPerSecond: Double?, unit: SpeedUnit, compact: Bool = false) -> String {
        guard let v = bytesPerSecond, v.isFinite else { return "…" }
        let v0 = max(v, 0)
        switch unit {
        case .megabytes: return bytesPart(v0, compact: compact)
        case .megabits: return bitsPart(v0, compact: compact)
        case .both: return "\(bytesPart(v0, compact: compact)) · \(bitsPart(v0, compact: compact))"
        }
    }

    private static func bytesPart(_ v: Double, compact: Bool) -> String {
        if v < 1e6 { return "\(fmt(v / 1e3, digits: 0)) KB/s" }
        let mb = v / 1e6
        if compact && mb >= 1000 { return "\(fmt(mb / 1000, digits: 2)) GB/s" }
        return "\(fmt(mb, digits: compact && mb >= 100 ? 0 : 1)) MB/s"
    }

    private static func bitsPart(_ v: Double, compact: Bool = false) -> String {
        let mbit = v * 8 / 1e6
        if mbit >= (compact ? 1000 : 10_000) { return "\(fmt(mbit / 1000, digits: 1)) Gbit/s" }
        if mbit < 1 { return "\(fmt(mbit * 1000, digits: 0)) kbit/s" }
        return "\(fmt(mbit, digits: 0)) Mbit/s"
    }

    static func bytes(_ b: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(b, 0)), countStyle: .file)
    }

    private static func fmt(_ v: Double, digits: Int) -> String {
        v.formatted(.number.precision(.fractionLength(digits)))
    }
}
