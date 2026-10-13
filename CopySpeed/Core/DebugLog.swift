import AppKit

/// Schreibt Rohdaten aus dem Kopierfenster nach `~/Library/Logs/CopySpeed/debug.log`.
///
/// Einschalten: `defaults write com.roman.copyspeed debugLog -bool YES` (wirkt sofort)
enum DebugLog {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "debugLog") }

    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CopySpeed")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "debug.log")
    }()

    private static let handle: FileHandle? = {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    /// Speichert den Inhalt einer View als PNG im Log-Ordner (zum Prüfen des Overlay-Layouts).
    @MainActor
    static func snapshot(_ view: NSView, name: String) {
        guard isEnabled, view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: url.deletingLastPathComponent().appending(path: "\(name).png"))
    }

    static func write(_ line: @autoclosure () -> String) {
        guard isEnabled else { return }
        let ts = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        handle?.write(Data("\(ts) \(line())\n".utf8))
    }
}
