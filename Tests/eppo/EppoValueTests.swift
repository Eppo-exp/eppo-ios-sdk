import XCTest

import Foundation

@testable import EppoFlagging

class EppoValueTests: XCTestCase {

    let decoder = JSONDecoder()
    let jsonKey = "value"

    func testDecodingString() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": "testString"}"#)

        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(decodedValue[jsonKey]?.stringValue, "testString")
    }

    func testDecodingInteger() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": 123}"#)

        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(decodedValue[jsonKey]?.doubleValue, 123)
    }

    func testDecodingDouble() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": 123.456}"#)

        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(decodedValue[jsonKey]?.doubleValue, 123.456)
    }

    func testDecodingArrayOfStrings() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": ["one","two","three"]}"#)
        let decoder = JSONDecoder()

        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(decodedValue[jsonKey]?.stringArrayValue, ["one", "two", "three"])
    }

    func testEppoValueEquality() throws {
        // Test boolean equality
        let boolValueTrue1 = EppoValue(value: true)
        let boolValueTrue2 = EppoValue(value: true)
        let boolValueFalse = EppoValue(value: false)
        XCTAssertTrue(boolValueTrue1 == boolValueTrue2, "Both true values should be equal")
        XCTAssertFalse(boolValueTrue1 == boolValueFalse, "True should not be equal to false")

        // Test numeric equality
        let numericValue1 = EppoValue(value: 42)
        let numericValue2 = EppoValue(value: 42.0)
        let numericValueDifferent = EppoValue(value: 43)
        XCTAssertTrue(numericValue1 == numericValue2, "Numeric 42 should be equal to 42.0")
        XCTAssertFalse(numericValue1 == numericValueDifferent, "42 should not be equal to 43")

        // Test string equality
        let stringValue1 = EppoValue(value: "test")
        let stringValue2 = EppoValue(value: "test")
        let stringValueDifferent = EppoValue(value: "Test")
        XCTAssertTrue(stringValue1 == stringValue2, "String 'test' should be equal to 'test'")
        XCTAssertFalse(stringValue1 == stringValueDifferent, "String 'test' should not be equal to 'Test'")

        // Test array equality with out of order and duplicates
        let arrayValue1 = EppoValue(array: ["one", "two", "two", "three"])
        let arrayValue2 = EppoValue(array: ["three", "one", "two", "two"])
        let arrayValueDifferent = EppoValue(array: ["one", "two", "four"])
        XCTAssertTrue(arrayValue1 == arrayValue2, "Arrays with the same elements in different order and duplicates should be equal")
        XCTAssertFalse(arrayValue1 == arrayValueDifferent, "Arrays with different elements or counts should not be equal")
    }

    func testToString() {
        // boolean
        XCTAssertEqual(try EppoValue(value: true).toEppoString(), "true")
        XCTAssertEqual(try EppoValue(value: false).toEppoString(), "false")

        // float
        XCTAssertEqual(try EppoValue(value: 10.5).toEppoString(), "10.5")
        XCTAssertEqual(try EppoValue(value: 10.0).toEppoString(), "10")
        XCTAssertEqual(try EppoValue(value: 123456789.0).toEppoString(), "123456789")

        // int
        XCTAssertEqual(try EppoValue(value: 10).toEppoString(), "10")

        // string
        XCTAssertEqual(try EppoValue(value: "test").toEppoString(), "test")

        // array of strings
        XCTAssertEqual(try EppoValue(array: ["one", "two", "three"]).toEppoString(), "one, two, three")
    }

    private func jsonData(from jsonString: String) throws -> Data {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "JSONError", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
        }
        return jsonData
    }
}
