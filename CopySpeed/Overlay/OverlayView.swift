import SwiftUI

/// Inhalt des Panels unter dem Kopierfenster: eine Zeile pro Vorgang, bei mehreren zusätzlich die Summe.
struct OverlayView: View {
    let window: CopyWindow
    let unit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(window.operations) { op in
                OperationRow(operation: op, unit: unit, showName: window.operations.count > 1)
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
        .padding(.vertical, 10)
        .frame(width: window.frame.width, alignment: .leading)
        .background(background)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

private struct OperationRow: View {
    let operation: CopyOperation
    let unit: SpeedUnit
    let showName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)
                if showName {
                    Text(operation.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(SpeedFormat.speed(operation.speed, unit: unit))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
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
