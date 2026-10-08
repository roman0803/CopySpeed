import Foundation

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

    static func write(_ line: @autoclosure () -> String) {
        guard isEnabled else { return }
        let ts = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        handle?.write(Data("\(ts) \(line())\n".utf8))
    }
}
