import XCTest

@testable import EppoFlagging

final class ObfuscationTests: XCTestCase {

    func testParseUtcISODateElement_ValidISODate() {
        let validISODate = "2024-04-17T19:40:53.716Z"
        let expectedDate = UTC_ISO_DATE_FORMAT.date(from: validISODate)
        let parsedDate = parseUtcISODateElement(validISODate)
        XCTAssertEqual(parsedDate, expectedDate, "The parsed date should match the expected date for a valid ISO string.")
    }

    func testParseUtcISODateElement_InvalidISODate() {
        let invalidISODate = "not-a-date"
        let parsedDate = parseUtcISODateElement(invalidISODate)
        XCTAssertNil(parsedDate, "The parsed date should be nil for an invalid ISO string.")
    }

    func testParseUtcISODateElement_EmptyString() {
        let emptyString = ""
        let parsedDate = parseUtcISODateElement(emptyString)
        XCTAssertNil(parsedDate, "The parsed date should be nil for an empty string.")
    }

    func testParseUtcISODateElement_ValidBase64EncodedISODate() {
        let validISODate = "2023-01-01T12:00:00Z"
        let base64EncodedDate = Data(validISODate.utf8).base64EncodedString()
        let expectedDate = UTC_ISO_DATE_FORMAT.date(from: validISODate)
        let parsedDate = parseUtcISODateElement(base64EncodedDate)
        XCTAssertEqual(parsedDate, expectedDate, "The parsed date should match the expected date for a valid base64 encoded ISO string.")
    }

    func testParseUtcISODateElement_InvalidBase64EncodedISODate() {
        let invalidBase64EncodedDate = Data("not-a-date".utf8).base64EncodedString()
        let parsedDate = parseUtcISODateElement(invalidBase64EncodedDate)
        XCTAssertNil(parsedDate, "The parsed date should be nil for an invalid base64 encoded ISO string.")
    }
}
