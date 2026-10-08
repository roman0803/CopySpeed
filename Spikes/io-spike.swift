// Spike D: Systemzähler – Bytes pro Datenträger (IOKit) und pro Netzwerk-Interface (sysctl).
//
//   io-spike   → gibt jede Sekunde alle Datenträger/Interfaces mit Aktivität aus

import Foundation
import IOKit

// MARK: - Datenträger

func diskCounters() -> [String: (read: UInt64, write: UInt64)] {
    var out: [String: (UInt64, UInt64)] = [:]
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else { return out }
    defer { IOObjectRelease(iter) }
    var entry = IOIteratorNext(iter)
    while entry != 0 {
        defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
        guard let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { continue }
        let name = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "BSD Name" as CFString,
                                                   kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? String ?? "disk?"
        let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
        let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        out[name] = (r, w)
    }
    return out
}

// MARK: - Netzwerk (64-Bit-Zähler via NET_RT_IFLIST2)

func netCounters() -> [String: (read: UInt64, write: UInt64)] {
    var out: [String: (UInt64, UInt64)] = [:]
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var len = 0
    guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return out }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return out }
    buf.withUnsafeBytes { raw in
        var off = 0
        while off + MemoryLayout<if_msghdr>.size <= len {
            let hdr = raw.load(fromByteOffset: off, as: if_msghdr.self)
            if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                let h2 = raw.load(fromByteOffset: off, as: if_msghdr2.self)
                var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(h2.ifm_index), &nameBuf) != nil {
                    out[String(cString: nameBuf)] = (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes)
                }
            }
            off += Int(hdr.ifm_msglen)
        }
    }
    return out
}

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Loop

func rate(_ a: UInt64, _ b: UInt64, _ dt: Double) -> Double { b >= a ? Double(b - a) / dt : 0 }
func fmt(_ v: Double) -> String { String(format: "%7.1f MB/s %6.0f Mbit/s", v / 1e6, v * 8 / 1e6) }

var lastDisk = diskCounters(), lastNet = netCounters(), lastT = Date()
let once = CommandLine.arguments.contains("--once")
print("Datenträger: \(lastDisk.keys.sorted()), Interfaces: \(lastNet.keys.sorted().count)")

Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    let d = diskCounters(), n = netCounters(), now = Date()
    let dt = now.timeIntervalSince(lastT)
    var lines: [String] = []
    for (k, v) in d.sorted(by: { $0.key < $1.key }) {
        guard let o = lastDisk[k] else { continue }
        let r = rate(o.read, v.read, dt), w = rate(o.write, v.write, dt)
        if r + w > 100_000 { lines.append("  💾 \(k.padding(toLength: 8, withPad: " ", startingAt: 0)) lesen \(fmt(r))  schreiben \(fmt(w))") }
    }
    for (k, v) in n.sorted(by: { $0.key < $1.key }) {
        guard let o = lastNet[k] else { continue }
        let r = rate(o.read, v.read, dt), w = rate(o.write, v.write, dt)
        if r + w > 100_000 { lines.append("  🌐 \(k.padding(toLength: 8, withPad: " ", startingAt: 0)) empf. \(fmt(r))  senden    \(fmt(w))") }
    }
    let ts = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .medium)
    print(lines.isEmpty ? "\(ts)  (keine nennenswerte Aktivität)" : "\(ts)\n" + lines.joined(separator: "\n"))
    lastDisk = d; lastNet = n; lastT = now
    if once { exit(0) }
}
RunLoop.main.run()
