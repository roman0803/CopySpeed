import AppKit
import SwiftUI

/// Rahmenloses Panel, das keinen Fokus nimmt und Klicks durchlässt.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Normale Ebene: Das Panel wird direkt über dem Kopierfenster einsortiert,
        // statt über allen anderen Programmen zu schweben.
        level = .normal
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Dockt an jedes Finder-Kopierfenster ein Panel mit den Geschwindigkeiten an.
@MainActor
final class OverlayController {
    private var panels: [Int: (panel: OverlayPanel, host: NSHostingView<OverlayView>)] = [:]
    private let gap: CGFloat = 6

    func update(_ windows: [CopyWindow]) {
        let unit = Preferences.unit
        let onScreen = Self.finderWindowsOnScreen()

        for window in windows {
            // Nur anzeigen, wenn das Kopierfenster sichtbar ist (nicht minimiert, aktueller Space).
            guard let windowID = onScreen.first(where: { Self.matches($0.bounds, window.frame) })?.id else {
                panels[window.id]?.panel.orderOut(nil)
                continue
            }

            let entry = panels[window.id] ?? makePanel(id: window.id)
            entry.host.rootView = OverlayView(window: window, unit: unit)

            let width = window.frame.width
            let height = entry.host.fittingSize.height
            entry.panel.setFrame(position(for: window.frame, size: CGSize(width: width, height: height)), display: true)
            // Direkt über dem Kopierfenster einsortieren – bei jedem Tick, weil der Finder
            // sein Fenster nach vorne holen kann.
            entry.panel.order(.above, relativeTo: windowID)
        }

        let alive = Set(windows.map(\.id))
        for (id, entry) in panels where !alive.contains(id) {
            entry.panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel(id: Int) -> (panel: OverlayPanel, host: NSHostingView<OverlayView>) {
        let panel = OverlayPanel()
        let host = NSHostingView(rootView: OverlayView(window: CopyWindow(id: id, frame: .zero, operations: []), unit: .both))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        let entry = (panel, host)
        panels[id] = entry
        return entry
    }

    /// Unter dem Kopierfenster, oder darüber, wenn unten kein Platz ist. Ergebnis in AppKit-Koordinaten.
    private func position(for quartzFrame: CGRect, size: CGSize) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitFrame = CGRect(x: quartzFrame.minX, y: primaryHeight - quartzFrame.maxY,
                                 width: quartzFrame.width, height: quartzFrame.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .infinite

        var origin = CGPoint(x: appKitFrame.minX, y: appKitFrame.minY - gap - size.height)
        if origin.y < visible.minY {
            origin.y = appKitFrame.maxY + gap
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Fensterliste (CoreGraphics)

    private struct ScreenWindow { let id: Int; let bounds: CGRect }

    /// Sichtbare Finder-Fenster mit CGWindowID und Rahmen (Quartz-Koordinaten).
    private static func finderWindowsOnScreen() -> [ScreenWindow] {
        guard let pid = FinderCopyReader.finderPID,
              let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return infos.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return ScreenWindow(id: id, bounds: bounds)
        }
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}
