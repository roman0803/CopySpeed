import XCTest
@testable import CopySpeed

final class SpeedTrackerTests: XCTestCase {
    func testConstantSpeed() throws {
        var t = SpeedTracker()
        for i in 0...10 { t.add(bytes: Double(i) * 50e6, at: Double(i) * 0.5) } // 100 MB/s
        XCTAssertEqual(try XCTUnwrap(t.current), 100e6, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(t.average), 100e6, accuracy: 1)
    }

    func testNeedsEnoughTimeBeforeReporting() {
        var t = SpeedTracker()
        t.add(bytes: 0, at: 0)
        XCTAssertNil(t.current)
        t.add(bytes: 10e6, at: 0.2)
        XCTAssertNil(t.current)
        XCTAssertNil(t.average)
    }

    func testWindowFollowsSpeedChange() throws {
        var t = SpeedTracker()
        var bytes = 0.0
        for i in 0..<10 { t.add(bytes: bytes, at: Double(i) * 0.5); bytes += 50e6 }   // 100 MB/s
        for i in 10..<20 { t.add(bytes: bytes, at: Double(i) * 0.5); bytes += 25e6 }  // 50 MB/s
        // Nach 5 s mit 50 MB/s liegt das 3-s-Fenster nur noch im langsamen Teil.
        XCTAssertEqual(try XCTUnwrap(t.current), 50e6, accuracy: 1)
        XCTAssertEqual(t.peak, 100e6, accuracy: 1)
    }

    func testSmallBackwardJitterIsIgnored() throws {
        var t = SpeedTracker()
        t.add(bytes: 0, at: 0)
        t.add(bytes: 100e6, at: 1)
        t.add(bytes: 99e6, at: 1.5)   // 1 % zurück → ignorieren
        t.add(bytes: 200e6, at: 2)
        XCTAssertEqual(try XCTUnwrap(t.current), 100e6, accuracy: 1)
    }

    func testResetWhenCounterGoesBackwards() {
        var t = SpeedTracker()
        t.add(bytes: 0, at: 0)
        t.add(bytes: 100e6, at: 1)
        t.add(bytes: 5e6, at: 1.5)
        XCTAssertNil(t.current)
        XCTAssertEqual(t.peak, 0)
    }
}
