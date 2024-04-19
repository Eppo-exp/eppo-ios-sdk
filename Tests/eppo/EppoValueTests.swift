import XCTest

import Foundation

@testable import eppo_flagging

class EppoValueTests: XCTestCase {

    let decoder = JSONDecoder()
    let jsonKey = "value"

    func testDecodingString() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": "testString"}"#)
        
        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(try decodedValue[jsonKey]?.getStringValue(), "testString")
    }
    
    func testDecodingInteger() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": 123}"#)
        
        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(try decodedValue[jsonKey]?.getDoubleValue(), 123)
    }
    
    func testDecodingDouble() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": 123.456}"#)
        
        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(try decodedValue[jsonKey]?.getDoubleValue(), 123.456)
    }
    
    func testDecodingArrayOfStrings() throws {
        let jsonData = try jsonData(from: #"{"\#(jsonKey)": ["one","two","three"]}"#)
        let decoder = JSONDecoder()
        
        let decodedValue = try decoder.decode([String: EppoValue].self, from: jsonData)
        XCTAssertEqual(try decodedValue[jsonKey]?.getStringArrayValue(), ["one", "two", "three"])
    }

    private func jsonData(from jsonString: String) throws -> Data {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "JSONError", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
        }
        return jsonData
    }
}
