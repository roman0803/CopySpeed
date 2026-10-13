import AppKit
import SwiftUI

/// Inhalt des Overlay-Panels – je nach Darstellung im oder unter dem Kopierfenster.
struct OverlayRoot: View {
    enum Content {
        case inWindow(InWindowLayout.Result, size: CGSize)
        case drawer(CopyWindow, unit: SpeedUnit, width: CGFloat, edge: DrawerView.Edge)
    }

    let content: Content

    var body: some View {
        switch content {
        case let .inWindow(layout, size):
            InWindowView(layout: layout, size: size)
        case let .drawer(window, unit, width, edge):
            DrawerView(window: window, unit: unit, width: width, edge: edge)
        }
    }
}

// MARK: - Im Kopierfenster

/// Schriften für die Anzeige im Kopierfenster – dieselben werden zum Ausmessen verwendet.
enum InWindowFonts {
    static let row = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let titlePrimary = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let titleSecondary = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let titleSpacing: CGFloat = 8
}

/// Durchsichtige Ebene in Fenstergröße; zeichnet nur die Texte an die berechneten Stellen.
private struct InWindowView: View {
    let layout: InWindowLayout.Result
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            HStack(alignment: .firstTextBaseline, spacing: InWindowFonts.titleSpacing) {
                if let secondary = layout.title.secondary {
                    Text(secondary)
                        .font(Font(InWindowFonts.titleSecondary))
                        .foregroundStyle(.secondary)
                }
                Text(layout.title.primary)
                    .font(Font(InWindowFonts.titlePrimary))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
            .fixedSize()
            .frame(width: max(layout.title.trailingX, 0), height: 20, alignment: .trailing)
            .position(x: layout.title.trailingX / 2, y: layout.title.centerY)

            ForEach(layout.rows, id: \.id) { row in
                Text(row.text)
                    .font(Font(InWindowFonts.row))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: max(row.trailingX, 0), height: 16, alignment: .trailing)
                    .position(x: row.trailingX / 2, y: row.centerY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Unter dem Kopierfenster (Schublade)

/// Schublade, deren oberer Teil hinter dem Kopierfenster verschwindet.
/// Zeigt immer Name und Geschwindigkeit jedes Vorgangs, bei mehreren zusätzlich die Summe.
struct DrawerView: View {
    enum Edge { case below, above }

    /// So weit liegt die Schublade unter dem Kopierfenster verborgen.
    static let hiddenOverlap: CGFloat = 16

    let window: CopyWindow
    let unit: SpeedUnit
    let width: CGFloat
    let edge: Edge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(window.operations) { op in
                DrawerRow(operation: op, unit: unit)
            }
            if window.operations.count > 1 {
                Divider()
                HStack {
                    Text("Gesamt").font(.callout.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(SpeedFormat.speed(window.totalSpeed, unit: unit))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        // Der verdeckte Streifen bekommt zusätzlichen Innenabstand, damit nichts darunter verschwindet.
        .padding(.top, edge == .below ? Self.hiddenOverlap + 8 : 10)
        .padding(.bottom, edge == .above ? Self.hiddenOverlap + 8 : 10)
        .frame(width: width, alignment: .leading)
        .background(background)
    }

    @ViewBuilder private var background: some View {
        let r: CGFloat = 12
        let shape = edge == .below
            ? UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

private struct DrawerRow: View {
    let operation: CopyOperation
    let unit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)
                Text(operation.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(SpeedFormat.speed(operation.speed, unit: unit))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            if let avg = operation.average {
                Text("Ø \(SpeedFormat.speed(avg, unit: unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
