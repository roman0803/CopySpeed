import XCTest
@testable import CopySpeed

final class SpeedFormatTests: XCTestCase {
    private func digitsOnly(_ s: String) -> String { s.filter { $0.isNumber } }

    func testUnits() {
        XCTAssertTrue(SpeedFormat.speed(117.4e6, unit: .megabytes).hasSuffix("MB/s"))
        XCTAssertEqual(digitsOnly(SpeedFormat.speed(117.4e6, unit: .megabytes)), "1174")
        XCTAssertEqual(digitsOnly(SpeedFormat.speed(117.4e6, unit: .megabits)), "939")
        XCTAssertTrue(SpeedFormat.speed(117.4e6, unit: .both).contains("·"))
    }

    func testSmallAndLargeValues() {
        XCTAssertTrue(SpeedFormat.speed(500e3, unit: .megabytes).hasSuffix("KB/s"))
        XCTAssertTrue(SpeedFormat.speed(100e3, unit: .megabits).hasSuffix("kbit/s"))
        XCTAssertTrue(SpeedFormat.speed(2.5e9, unit: .megabits).hasSuffix("Gbit/s"))
    }

    func testCompactDropsDecimalFrom100MBps() {
        XCTAssertEqual(digitsOnly(SpeedFormat.speed(313.14e6, unit: .megabytes, compact: true)), "313")
        XCTAssertEqual(digitsOnly(SpeedFormat.speed(99.94e6, unit: .megabytes, compact: true)), "999")
        XCTAssertEqual(digitsOnly(SpeedFormat.speed(313.14e6, unit: .megabytes)), "3131")
    }

    func testCompactSwitchesToGigaUnits() {
        XCTAssertTrue(SpeedFormat.speed(1.25e9, unit: .megabytes, compact: true).hasSuffix("GB/s"))
        XCTAssertEqual(digitsOnly(SpeedFormat.speed(1.25e9, unit: .megabytes, compact: true)), "125")
        XCTAssertTrue(SpeedFormat.speed(150e6, unit: .megabits, compact: true).hasSuffix("Gbit/s"))
        XCTAssertTrue(SpeedFormat.speed(110e6, unit: .megabits, compact: true).hasSuffix("Mbit/s"))
        XCTAssertTrue(SpeedFormat.speed(150e6, unit: .megabits).hasSuffix("Mbit/s"), "Nicht kompakt bleibt Mbit/s bis 10 Gbit/s")
    }

    func testCompactIsNeverWiderThanItsTemplate() {
        let font = InWindowFonts.row
        func w(_ s: String) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font]).width) }
        let mbTemplate = w(SpeedFormat.speed(88.8e6, unit: .megabytes, compact: true))
        for v in [1e6, 9.9e6, 88.8e6, 99.9e6, 313e6, 999e6, 1.25e9, 8.88e9] {
            XCTAssertLessThanOrEqual(w(SpeedFormat.speed(v, unit: .megabytes, compact: true)), mbTemplate, "\(v)")
        }
        let mbitTemplate = w(SpeedFormat.speed(111e6, unit: .megabits, compact: true))
        for v in [1e6, 12.5e6, 111e6, 124e6, 125e6, 1.2e9] {
            XCTAssertLessThanOrEqual(w(SpeedFormat.speed(v, unit: .megabits, compact: true)), mbitTemplate, "\(v)")
        }
    }

    func testMissingValue() {
        XCTAssertEqual(SpeedFormat.speed(nil, unit: .both), "…")
    }
}
