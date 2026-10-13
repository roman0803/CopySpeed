import XCTest
@testable import CopySpeed

/// Werte aus einer echten Messung (macOS 27.2): Fenster 404 pt breit, Titelzeile bei y = 16,
/// Ampel-Knöpfe enden bei x = 70, Statustext endet ca. 300 pt vom linken Fensterrand, Zeilen 61 pt auseinander.
final class InWindowLayoutTests: XCTestCase {
    private func op(_ id: String, speed: Double?, average: Double? = nil, textMaxX: CGFloat = 300, midY: CGFloat = 72) -> CopyOperation {
        CopyOperation(id: id, name: id, doneBytes: nil, totalBytes: nil, speed: speed, average: average,
                      layout: RowLayout(statusMidY: midY, statusTextMaxX: textMaxX))
    }

    private func window(_ ops: [CopyOperation], titleMinX: CGFloat = 82, contentRect: CGRect? = nil) -> CopyWindow {
        CopyWindow(id: 0, element: nil, frame: CGRect(x: 795, y: 605, width: 404, height: 88),
                   titleBarMidY: 16, titleMinX: titleMinX, contentRect: contentRect, operations: ops)
    }

    /// Grobe Schätzung: 6 pt pro Zeichen
    private let measure: (String) -> CGFloat = { CGFloat($0.count) * 6 }
    private let measureTitle: (String?, String) -> CGFloat = { s, p in CGFloat(p.count) * 6 + (s.map { CGFloat($0.count) * 6 + 8 } ?? 0) }

    private func compute(_ w: CopyWindow, unit: SpeedUnit, width: CGFloat = 404) -> InWindowLayout.Result {
        InWindowLayout.compute(window: w, width: width, unit: unit, measureRow: measure, measureTitle: measureTitle)
    }

    func testSingleOperationShowsSpeedAndAverageInTitleOnly() {
        let r = compute(window([op("a", speed: 69.8e6, average: 63.2e6)]), unit: .megabytes)
        XCTAssertTrue(r.title.primary.hasSuffix("MB/s"))
        XCTAssertEqual(r.title.secondary?.hasPrefix("Ø"), true)
        XCTAssertEqual(r.title.trailingX, 404 - InWindowLayout.rightInset)
        XCTAssertEqual(r.title.centerY, 16)
        XCTAssertTrue(r.rows.isEmpty)
    }

    func testMultipleOperationsShowTotalAndRowLabels() {
        let r = compute(window([op("a", speed: 60e6, midY: 72), op("b", speed: 50e6, midY: 133)]), unit: .both)
        XCTAssertEqual(r.title.secondary, "Gesamt")
        XCTAssertTrue(r.title.primary.contains("·"), "Titel zeigt beide Einheiten")
        XCTAssertEqual(r.rows.map(\.id), ["a", "b"])
        XCTAssertEqual(r.rows.map(\.centerY), [72, 133])
        XCTAssertFalse(r.rows[0].text.contains("·"), "In der Statuszeile nur eine Einheit")
        XCTAssertTrue(r.rows.allSatisfy { $0.trailingX == r.title.trailingX }, "Bündig mit der Titelzeile")
    }

    func testRowLabelIsDroppedWhenStatusTextIsTooLong() {
        let r = compute(window([op("a", speed: 60e6, textMaxX: 360), op("b", speed: 50e6)]), unit: .megabytes)
        XCTAssertEqual(r.rows.map(\.id), ["b"])
    }

    func testFitDoesNotDependOnCurrentValue() {
        // Gleiche Entscheidung für alle Werte – auch über 1 GB/s, wo ein Tausenderpunkt dazukommt.
        for textMaxX: CGFloat in [290, 310, 320, 330] {
            var decisions = Set<Bool>()
            for speed in [nil, 5e6, 117.4e6, 1.2e9, 8.8e9] {
                let r = compute(window([op("a", speed: speed, textMaxX: textMaxX), op("b", speed: 1e6)]), unit: .megabytes)
                decisions.insert(r.rows.contains { $0.id == "a" })
            }
            XCTAssertEqual(decisions.count, 1, "textMaxX=\(textMaxX): Label springt je nach Wert")
        }
    }

    func testRowUsesCompactFormat() {
        let r = compute(window([op("a", speed: 313.1e6), op("b", speed: 8.1e6)]), unit: .megabytes)
        XCTAssertEqual(r.rows.first { $0.id == "a" }?.text.filter(\.isNumber), "313")
        XCTAssertEqual(r.rows.first { $0.id == "b" }?.text.filter(\.isNumber), "81")
    }

    func testTitleShortensWhenSpaceIsTight() {
        let wide = compute(window([op("a", speed: 69.8e6, average: 63.2e6)]), unit: .both)
        XCTAssertNotNil(wide.title.secondary, "Genug Platz: Ø wird gezeigt")

        let single = [op("a", speed: 1.0456e9, average: 1.0123e9)]

        // Nur wenig Platz rechts der Ampel-Knöpfe → erst Ø weg, dann nur eine Einheit.
        let narrow = compute(window(single, titleMinX: 250), unit: .both)
        XCTAssertNil(narrow.title.secondary)
        XCTAssertFalse(narrow.title.primary.contains("·"))
        XCTAssertLessThanOrEqual(measureTitle(narrow.title.secondary, narrow.title.primary), 404 - InWindowLayout.rightInset - 250)
    }

    func testTitleUsesCurrentWidth() {
        let r = compute(window([op("a", speed: 1e6)]), unit: .megabytes, width: 500)
        XCTAssertEqual(r.title.trailingX, 500 - InWindowLayout.rightInset)
    }

    func testRowsScrolledOutOfViewAreDropped() {
        // Liste von y = 40 bis 200 sichtbar; Zeile a wurde nach oben weggescrollt (Mitte bei y = 11).
        let content = CGRect(x: 0, y: 40, width: 404, height: 160)
        let r = compute(window([op("a", speed: 1e6, midY: 11), op("b", speed: 2e6, midY: 72), op("c", speed: 3e6, midY: 250)],
                               contentRect: content), unit: .megabytes)
        XCTAssertEqual(r.rows.map(\.id), ["b"])
    }

    func testLongestMeasuredFinderStatusStillFits() {
        // Gemessen: „1,22 GB von 6,44 GB - weniger als eine Minute“ endet bei 315,6 pt.
        // Mit echter Schrift ist die breiteste Vorlage („8.889 MB/s“) knapp 63 pt breit.
        let realMeasure: (String) -> CGFloat = { ceil(($0 as NSString).size(withAttributes: [.font: InWindowFonts.row]).width) }
        let r = InWindowLayout.compute(window: window([op("a", speed: 1e6, textMaxX: 315.6), op("b", speed: 2e6)]),
                                       width: 404, unit: .megabytes, measureRow: realMeasure, measureTitle: measureTitle)
        XCTAssertEqual(r.rows.map(\.id), ["a", "b"])
    }

    func testOperationWithoutLayoutHasNoRowLabel() {
        let noLayout = CopyOperation(id: "x", name: "x", doneBytes: nil, totalBytes: nil, speed: 1e6, average: nil, layout: nil)
        let r = compute(window([noLayout, op("b", speed: 2e6)]), unit: .megabytes)
        XCTAssertEqual(r.rows.map(\.id), ["b"])
    }
}
