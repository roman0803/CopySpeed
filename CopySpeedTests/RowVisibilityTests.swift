import XCTest
@testable import CopySpeed

final class RowVisibilityTests: XCTestCase {
    func testDefaultShowsAfterThreeConsecutiveFits() {
        var v = RowVisibility()
        XCTAssertEqual(v.update(fits: ["a": true]), [])
        XCTAssertEqual(v.update(fits: ["a": true]), [])
        XCTAssertEqual(v.update(fits: ["a": true]), ["a"])
    }

    func testHideRemovesImmediatelyAndRestartsCounting() {
        var v = RowVisibility(showAfter: 2)
        v.update(fits: ["a": true]); v.update(fits: ["a": true])
        v.hide("a")
        XCTAssertEqual(v.shown, [])
        XCTAssertEqual(v.update(fits: ["a": true]), [], "Zähler beginnt nach hide neu")
        XCTAssertEqual(v.update(fits: ["a": true]), ["a"])
    }

    func testShowsAfterTwoConsecutiveFits() {
        var v = RowVisibility(showAfter: 2)
        XCTAssertEqual(v.update(fits: ["a": true]), [])
        XCTAssertEqual(v.update(fits: ["a": true]), ["a"])
        XCTAssertEqual(v.update(fits: ["a": true]), ["a"])
    }

    func testHidesImmediatelyWhenNotFitting() {
        var v = RowVisibility(showAfter: 2)
        v.update(fits: ["a": true]); v.update(fits: ["a": true])
        XCTAssertEqual(v.update(fits: ["a": false]), [], "Nie überlappen: sofort aus")
    }

    func testLongTextAtStartDoesNotBlockForever() {
        // Der Fehler aus 0.2.0: Ein langer Text am Anfang („Verbleibende Zeit berechnen …“) sperrte die Zeile dauerhaft.
        var v = RowVisibility(showAfter: 2)
        for _ in 0..<5 { XCTAssertEqual(v.update(fits: ["a": false]), []) }
        XCTAssertEqual(v.update(fits: ["a": true]), [])
        XCTAssertEqual(v.update(fits: ["a": true]), ["a"])
    }

    func testAlternatingFitDoesNotFlicker() {
        var v = RowVisibility(showAfter: 2)
        for i in 0..<10 { XCTAssertEqual(v.update(fits: ["a": i % 2 == 0]), [], "Tick \(i)") }
    }

    func testRowsAreIndependentAndForgotten() {
        var v = RowVisibility(showAfter: 2)
        v.update(fits: ["a": true, "b": false]); v.update(fits: ["a": true, "b": true])
        XCTAssertEqual(v.shown, ["a"])
        XCTAssertEqual(v.update(fits: ["b": true]), ["b"], "a ist weg, b hat zweimal gepasst")
        XCTAssertEqual(v.update(fits: ["a": true, "b": true]), ["b"], "a beginnt neu")
    }
}
