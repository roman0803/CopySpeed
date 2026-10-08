import XCTest
@testable import CopySpeed

final class ProgressTextParserTests: XCTestCase {
    func testGermanStatusFromRealCopyWindow() throws {
        let r = try XCTUnwrap(ProgressTextParser.bytes(in: "2,00 GB von 3,74 GB - weniger als eine Minute"))
        XCTAssertEqual(r.done, 2.0e9, accuracy: 1)
        XCTAssertEqual(r.total, 3.74e9, accuracy: 1)
    }

    func testMixedUnits() throws {
        let r = try XCTUnwrap(ProgressTextParser.bytes(in: "285,2 MB von 3,74 GB - weniger als eine Minute"))
        XCTAssertEqual(r.done, 285.2e6, accuracy: 1)
        XCTAssertEqual(r.total, 3.74e9, accuracy: 1)
    }

    func testEnglishStatus() throws {
        let r = try XCTUnwrap(ProgressTextParser.bytes(in: "512 KB of 1.5 GB - About a minute"))
        XCTAssertEqual(r.done, 512e3, accuracy: 1)
        XCTAssertEqual(r.total, 1.5e9, accuracy: 1)
    }

    func testBytesAndNonBreakingSpace() throws {
        let r = try XCTUnwrap(ProgressTextParser.bytes(in: "0\u{00A0}Bytes von 1.234,5\u{00A0}MB"))
        XCTAssertEqual(r.done, 0)
        XCTAssertEqual(r.total, 1234.5e6, accuracy: 1)
    }

    func testUnparsableStatus() {
        XCTAssertNil(ProgressTextParser.bytes(in: "Vorbereiten …"))
    }

    func testItemName() {
        XCTAssertEqual(ProgressTextParser.itemName(in: "Kopieren von „Urlaubsvideo.mov“ nach „video“"),
                       "Urlaubsvideo.mov")
        XCTAssertEqual(ProgressTextParser.itemName(in: "Copying “Movie.mkv” to “video”"), "Movie.mkv")
        XCTAssertNil(ProgressTextParser.itemName(in: "Kopieren"))
    }

    func testItemNameForMultipleObjects() {
        XCTAssertEqual(ProgressTextParser.itemName(in: "Kopieren von 42 Objekten nach „video“"), "42 Objekte")
        XCTAssertEqual(ProgressTextParser.itemName(in: "Copying 42 items to “video”"), "42 items")
        // Zahl im Dateinamen darf nicht als Anzahl gelesen werden.
        XCTAssertEqual(ProgressTextParser.itemName(in: "Kopieren von „Folge 3 Teil 2.mkv“ nach „video“"), "Folge 3 Teil 2.mkv")
    }

    func testNumberFormats() {
        XCTAssertEqual(ProgressTextParser.number("1,5"), 1.5)
        XCTAssertEqual(ProgressTextParser.number("1.5"), 1.5)
        XCTAssertEqual(ProgressTextParser.number("1.234,5"), 1234.5)
        XCTAssertEqual(ProgressTextParser.number("1,234.5"), 1234.5)
    }
}
