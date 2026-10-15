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

    private func fits(_ r: InWindowLayout.Result, _ id: String) -> Bool? {
        r.rows.first { $0.id == id }?.fits
    }

    func testRowLabelDoesNotFitWhenStatusTextIsTooLong() {
        let r = compute(window([op("a", speed: 60e6, textMaxX: 360), op("b", speed: 50e6)]), unit: .megabytes)
        XCTAssertEqual(fits(r, "a"), false)
        XCTAssertEqual(fits(r, "b"), true)
    }

    func testFitDoesNotDependOnCurrentValue() {
        // Gleiche Entscheidung für alle Werte – auch ab 1 GB/s bzw. 1 Gbit/s (kompakt „1,20 GB/s“, „9,6 Gbit/s“).
        let speedsByUnit: [(SpeedUnit, [Double?])] = [
            (.megabytes, [nil, 5e6, 88.8e6, 117.4e6, 999e6, 1.2e9, 8.8e9]),
            (.megabits, [nil, 5e6, 88.8e6, 117.4e6, 999e6, 1.2e9]),
        ]
        for (unit, speeds) in speedsByUnit {
            for textMaxX: CGFloat in [290, 310, 320, 325, 330, 340] {
                var decisions = Set<Bool?>()
                for speed in speeds {
                    let r = compute(window([op("a", speed: speed, textMaxX: textMaxX), op("b", speed: 1e6)]), unit: unit)
                    decisions.insert(fits(r, "a"))
                }
                XCTAssertEqual(decisions.count, 1, "\(unit) textMaxX=\(textMaxX): Label springt je nach Wert")
            }
        }
    }

    func testRealFinderTextsFromUserScreenshot() {
        // Textenden gemessen bzw. mit der Finder-Schrift (11 pt) berechnet + gemessener AX-Versatz (+11,6 pt).
        let realMeasure: (String) -> CGFloat = { ceil(($0 as NSString).size(withAttributes: [.font: InWindowFonts.row]).width) }
        let cases: [(String, CGFloat, Bool)] = [
            ("2,21 GB von 3,92 GB - weniger als eine Minute", 315.6, true),
            ("318,8 MB von 26,85 GB - Ungefähr 13 Minuten", 317.6, true),
            ("220,5 MB von 3,92 GB - weniger als eine Minute", 325.6, true),
            ("12,3 MB von 26,85 GB - Verbleibende Zeit berechnen …", 364.6, false),
        ]
        for unit in [SpeedUnit.megabytes, .megabits, .both] {
            for (text, textMaxX, expected) in cases {
                let r = InWindowLayout.compute(window: window([op("a", speed: 33.6e6, textMaxX: textMaxX), op("b", speed: 2e6)]),
                                               width: 404, unit: unit, measureRow: realMeasure, measureTitle: measureTitle)
                XCTAssertEqual(fits(r, "a"), expected, "\(unit): \(text)")
            }
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
        // Mit echter Schrift ist die Vorlage („88,8 MB/s“) 56 pt breit.
        let realMeasure: (String) -> CGFloat = { ceil(($0 as NSString).size(withAttributes: [.font: InWindowFonts.row]).width) }
        let r = InWindowLayout.compute(window: window([op("a", speed: 1e6, textMaxX: 315.6), op("b", speed: 2e6)]),
                                       width: 404, unit: .megabytes, measureRow: realMeasure, measureTitle: measureTitle)
        XCTAssertEqual(r.rows.filter(\.fits).map(\.id), ["a", "b"])
    }

    func testOperationWithoutLayoutHasNoRowLabel() {
        let noLayout = CopyOperation(id: "x", name: "x", doneBytes: nil, totalBytes: nil, speed: 1e6, average: nil, layout: nil)
        let r = compute(window([noLayout, op("b", speed: 2e6)]), unit: .megabytes)
        XCTAssertEqual(r.rows.map(\.id), ["b"])
    }
}
