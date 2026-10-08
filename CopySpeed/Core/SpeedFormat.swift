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
    static func speed(_ bytesPerSecond: Double?, unit: SpeedUnit) -> String {
        guard let v = bytesPerSecond, v.isFinite else { return "…" }
        let v0 = max(v, 0)
        switch unit {
        case .megabytes: return bytesPart(v0)
        case .megabits: return bitsPart(v0)
        case .both: return "\(bytesPart(v0)) · \(bitsPart(v0))"
        }
    }

    private static func bytesPart(_ v: Double) -> String {
        if v < 1e6 { return "\(fmt(v / 1e3, digits: 0)) KB/s" }
        return "\(fmt(v / 1e6, digits: 1)) MB/s"
    }

    private static func bitsPart(_ v: Double) -> String {
        let mbit = v * 8 / 1e6
        if mbit >= 10_000 { return "\(fmt(mbit / 1000, digits: 1)) Gbit/s" }
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
