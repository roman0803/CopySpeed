import AppKit
import SwiftUI

/// Rahmenloses Panel, das keinen Fokus nimmt und Klicks durchlässt.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Normale Ebene: Das Panel wird direkt über bzw. unter dem Kopierfenster einsortiert,
        // statt über allen anderen Programmen zu schweben.
        level = .normal
        // .transient: in Mission Control ausgeblendet, statt allein stehen zu bleiben.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Zeigt die Geschwindigkeiten an jedem Finder-Kopierfenster an –
/// als durchsichtige Ebene im Fenster oder als Schublade darunter.
@MainActor
final class OverlayController {
    @MainActor
    private final class Entry {
        let panel = OverlayPanel()
        let host: NSHostingView<OverlayRoot>
        var window: CopyWindow
        var mode: OverlayMode
        var unit: SpeedUnit
        var drawerEdge: DrawerView.Edge = .below
        /// Zuletzt bekannter Fensterrahmen (Quartz)
        var frame: CGRect
        /// CGWindowID des Kopierfensters
        var windowNumber: Int
        /// Größe des Panel-Inhalts laut letztem Rendern
        var contentSize: CGSize = .zero
        /// Welche Zeilen-Labels im Kopierfenster gerade gezeigt werden (mit Hysterese)
        var rowVisibility = RowVisibility()
        /// Je gezeigter Zeile: bis wohin Finders Statustext reichen darf (fensterrelativ)
        var rowLimits: [String: CGFloat] = [:]

        init(window: CopyWindow, mode: OverlayMode, unit: SpeedUnit, windowNumber: Int) {
            self.window = window
            self.mode = mode
            self.unit = unit
            self.frame = window.frame
            self.windowNumber = windowNumber
            host = NSHostingView(rootView: OverlayRoot(content: .inWindow(
                InWindowLayout.Result(title: .init(secondary: nil, primary: "", trailingX: 0, centerY: 0), rows: []),
                size: .zero)))
            // Nötig, damit fittingSize die Höhe der Schublade liefert (bei [] kommt 0 × 0 heraus).
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
        }
    }

    /// Seitlicher Einzug der Schublade, damit sie nicht an den runden Fensterecken hervorlugt.
    private let drawerInset: CGFloat = 14

    private var entries: [Int: Entry] = [:]
    private var tracker: Timer?
    private var trackTick = 0
    /// Fordert sofort frische Daten an (Fenstergröße hat sich geändert → Zeilen haben sich verschoben).
    var onNeedsRefresh: (() -> Void)?
    private var lastFrontmostPID: pid_t?
    private var lastFocusedWindow: AXUIElement?

    // MARK: - Inhalt (alle 0,5 s vom CopyMonitor)

    func update(_ windows: [CopyWindow]) {
        let mode = Preferences.overlayMode
        let unit = Preferences.unit
        let onScreen = Self.finderWindowsOnScreen()

        for window in windows {
            // CGWindowID: bekannte ID weiterverwenden, solange sie sichtbar ist (robust beim Verschieben),
            // sonst über den Rahmen zuordnen. Nicht sichtbar (minimiert, anderer Space) → ausblenden.
            let known = entries[window.id].map(\.windowNumber).flatMap { id in onScreen.first { $0.id == id } }
            guard let screenWindow = known ?? onScreen.first(where: { Self.matches($0.bounds, window.frame) }) else {
                DebugLog.write("Overlay: Kopierfenster \(window.frame) nicht sichtbar; Finder-Fenster: \(onScreen.map { "\($0.id) \($0.bounds)" })")
                entries[window.id]?.panel.orderOut(nil)
                continue
            }

            let entry = entries[window.id] ?? Entry(window: window, mode: mode, unit: unit, windowNumber: screenWindow.id)
            entries[window.id] = entry
            entry.window = window
            entry.mode = mode
            entry.unit = unit
            entry.frame = window.frame
            entry.windowNumber = screenWindow.id
            entry.panel.hasShadow = mode == .drawer // Im Fenster: kein Schatten um die Schrift.

            render(entry, newSample: true)
            order(entry)
            DebugLog.snapshot(entry.host, name: "overlay-\(mode.rawValue)-\(Int(window.frame.height))")
        }

        let alive = Set(windows.map(\.id))
        for (id, entry) in entries where !alive.contains(id) {
            entry.panel.orderOut(nil)
            entries[id] = nil
        }
        updateTracker()
    }

    /// Baut den Inhalt neu auf, misst ihn und platziert das Panel (alle 0,5 s oder bei Größenänderung).
    /// - Parameter newSample: `true` bei frischen Daten vom CopyMonitor – nur dann zählt die Hysterese
    ///   der Zeilen-Labels weiter.
    private func render(_ entry: Entry, newSample: Bool = false) {
        switch entry.mode {
        case .inWindow:
            let layout = InWindowLayout.compute(
                window: entry.window, width: entry.frame.width, unit: entry.unit,
                measureRow: { Self.width(of: $0, font: InWindowFonts.row) },
                measureTitle: { secondary, primary in
                    Self.width(of: primary, font: InWindowFonts.titlePrimary)
                        + (secondary.map { Self.width(of: $0, font: InWindowFonts.titleSecondary) + InWindowFonts.titleSpacing } ?? 0)
                })
            if newSample {
                entry.rowVisibility.update(fits: Dictionary(layout.rows.map { ($0.id, $0.fits) }, uniquingKeysWith: { a, _ in a }))
            }
            // Gezeigt wird nur, was laut Hysterese sichtbar ist UND gerade passt.
            let rows = layout.rows.filter { $0.fits && entry.rowVisibility.shown.contains($0.id) }
            entry.rowLimits = Dictionary(rows.map { ($0.id, $0.maxStatusTextX) }, uniquingKeysWith: { a, _ in a })
            entry.host.rootView = OverlayRoot(content: .inWindow(InWindowLayout.Result(title: layout.title, rows: rows),
                                                                 size: entry.frame.size))
            entry.contentSize = entry.frame.size

        case .drawer:
            let width = max(entry.frame.width - 2 * drawerInset, 120)
            entry.host.rootView = OverlayRoot(content: .drawer(entry.window, unit: entry.unit, width: width, edge: entry.drawerEdge))
            entry.contentSize = CGSize(width: width, height: entry.host.fittingSize.height)
        }
        place(entry)
    }

    /// Setzt nur die Position passend zum Fensterrahmen – ohne neu zu messen (30 ×/s beim Verschieben).
    private func place(_ entry: Entry) {
        let appKit = Self.appKitRect(fromQuartz: entry.frame)
        switch entry.mode {
        case .inWindow:
            entry.panel.setFrame(appKit, display: true)

        case .drawer:
            let size = entry.contentSize
            let visible = (NSScreen.screens.first { $0.frame.intersects(appKit) } ?? NSScreen.main)?.visibleFrame ?? .infinite
            // Unten hervorschauen; nur wenn dort kein Platz ist, oben.
            let belowY = appKit.minY - size.height + DrawerView.hiddenOverlap
            let edge: DrawerView.Edge = belowY >= visible.minY ? .below : .above
            if edge != entry.drawerEdge {
                // Verdeckter Streifen wechselt die Seite → Inhalt mit anderem Innenabstand neu aufbauen.
                // Endet sicher: Die Höhe ist für beide Seiten gleich, also bleibt die Seite danach stabil.
                entry.drawerEdge = edge
                render(entry)
                return
            }
            let y = edge == .below ? belowY : appKit.maxY - DrawerView.hiddenOverlap
            entry.panel.setFrame(CGRect(x: appKit.minX + drawerInset, y: y, width: size.width, height: size.height), display: true)
        }
    }

    /// Im Fenster: direkt darüber. Schublade: direkt darunter.
    private func order(_ entry: Entry) {
        entry.panel.order(entry.mode == .inWindow ? .above : .below, relativeTo: entry.windowNumber)
    }

    // MARK: - Schnelles Nachführen (30 ×/s, nur solange ein Kopierfenster sichtbar ist)

    private func updateTracker() {
        let needed = entries.values.contains { $0.panel.isVisible }
        if needed, tracker == nil {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.track() }
            }
            RunLoop.main.add(t, forMode: .common)
            tracker = t
        } else if !needed, let t = tracker {
            t.invalidate()
            tracker = nil
            lastFocusedWindow = nil
        }
    }

    private func track() {
        // Fenster verschoben → Panel sofort mitziehen (Inhalt bleibt, er ist fensterrelativ).
        // Größe geändert → Zeilen haben sich verschoben: sofort frische Daten holen statt mit alten zu zeichnen.
        var resized = false
        for entry in entries.values where entry.panel.isVisible {
            guard let element = entry.window.element, let f = AX.frame(element), f != entry.frame else { continue }
            if f.size != entry.frame.size { resized = true }
            entry.frame = f
            place(entry)
        }
        if resized {
            if let onNeedsRefresh { onNeedsRefresh() } else { entries.values.forEach { render($0) } }
        }

        // 10 ×/s: Wird Finders Statustext neben einer sichtbaren Zahl länger, sofort ausblenden –
        // nicht erst bei der nächsten Abfrage (bis zu 0,5 s Überlappung).
        trackTick += 1
        if trackTick % 3 == 0 { recheckRowLabels() }

        // Finder holt das Kopierfenster nach vorne → Panel wieder direkt darüber/darunter einsortieren.
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focused = FinderCopyReader.finderApp()
            .flatMap { AX.attribute($0, kAXFocusedWindowAttribute) }
            .flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        let focusChanged: Bool = switch (focused, lastFocusedWindow) {
        case (nil, nil): false
        case let (a?, b?): !CFEqual(a, b)
        default: true
        }
        if frontmost != lastFrontmostPID || focusChanged {
            lastFrontmostPID = frontmost
            lastFocusedWindow = focused
            for entry in entries.values where entry.panel.isVisible { order(entry) }
        }
    }

    private func recheckRowLabels() {
        for entry in entries.values where entry.mode == .inWindow && entry.panel.isVisible && !entry.rowLimits.isEmpty {
            var hidden = false
            for (id, limit) in entry.rowLimits {
                guard let element = entry.window.operations.first(where: { $0.id == id })?.statusElement,
                      let bounds = AX.textBounds(element),
                      bounds.maxX - entry.frame.minX > limit else { continue }
                entry.rowVisibility.hide(id)
                hidden = true
            }
            if hidden { render(entry) }
        }
    }

    // MARK: - Koordinaten & Fensterliste

    private static func width(of text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Quartz (Ursprung oben links am Hauptbildschirm) → AppKit (Ursprung unten links).
    private static func appKitRect(fromQuartz r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

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

    /// Toleranz 3 pt: Beim Einblenden weicht der CG-Rahmen kurz um 1–2 pt vom AX-Rahmen ab.
    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 3 && abs(a.minY - b.minY) <= 3 && abs(a.width - b.width) <= 3 && abs(a.height - b.height) <= 3
    }
}
