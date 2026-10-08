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

    func testMissingValue() {
        XCTAssertEqual(SpeedFormat.speed(nil, unit: .both), "…")
    }
}
