import XCTest

import Foundation

@testable import EppoFlagging

final class UniversalFlagConfigTest: XCTestCase {
    func testDecodeUFCConfig() {
        var fileURL: URL!
        var UFCTestJSON: Data!
        
        fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.json",
            withExtension: ""
        )
        do {
            UFCTestJSON = try Data(contentsOf: fileURL)
        } catch {
            XCTFail("Error loading test JSON: \(error)")
        }
        
        let config = try! UniversalFlagConfig.decodeFromJSON(from: UFCTestJSON)
        
        // empty flag
        let emptyFlag = config.flags.first(where: { $0.key == "empty_flag" })?.value
        XCTAssertTrue(emptyFlag?.enabled == true, "The 'empty_flag' flag should be enabled.")
        
        // disabled flag
        let disabledFlag = config.flags.first(where: { $0.key == "disabled_flag" })?.value
        XCTAssertTrue(disabledFlag?.enabled == false, "The 'disabled_flag' flag should be disabled.")
        
        // variation type
        let variationFlag = config.flags.first(where: { $0.key == "numeric_flag" })?.value
        XCTAssertEqual(variationFlag?.enabled, true, "The 'numeric_flag' flag should be enabled.")
        XCTAssertEqual(variationFlag?.variationType, UFC_VariationType.numeric, "The 'numeric_flag' flag should have a variation type of 'NUMERIC'.")
        XCTAssertEqual(variationFlag?.variations.count, 2, "The 'numeric_flag' flag should have 2 variations.")
        XCTAssertEqual(variationFlag?.variations["e"]?.key, "e", "The 'numeric_flag' flag should have a variation key of 'e'.")
        XCTAssertEqual(try variationFlag?.variations["e"]?.value.getDoubleValue(), 2.7182818)

        // total shards
        XCTAssertEqual(variationFlag?.totalShards, 10000, "The total shards should be 10000.")
    }
    
    func testDecodeObfuscatedUFCConfig() {
        var fileURL: URL!
        var UFCTestJSON: Data!
        
        fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
            withExtension: ""
        )
        do {
            UFCTestJSON = try Data(contentsOf: fileURL)
        } catch {
            XCTFail("Error loading test JSON: \(error)")
        }
        
        let config = try! UniversalFlagConfig.decodeFromJSON(from: UFCTestJSON)
        
        // empty flag
        let emptyFlag = config.flags.first(where: { $0.key == getMD5Hex("empty_flag") })?.value
        XCTAssertTrue(emptyFlag?.enabled == true, "The 'empty_flag' flag should be enabled.")
        
        // disabled flag
        let disabledFlag = config.flags.first(where: { $0.key == getMD5Hex("disabled_flag") })?.value
        XCTAssertTrue(disabledFlag?.enabled == false, "The 'disabled_flag' flag should be disabled.")
        
        // variation type
        let variationFlag = config.flags.first(where: { $0.key == getMD5Hex("numeric_flag") })?.value
        XCTAssertEqual(variationFlag?.enabled, true, "The 'numeric_flag' flag should be enabled.")
        XCTAssertEqual(variationFlag?.variationType, UFC_VariationType.numeric, "The 'numeric_flag' flag should have a variation type of 'NUMERIC'.")
        XCTAssertEqual(variationFlag?.variations.count, 2, "The 'numeric_flag' flag should have 2 variations.")
        XCTAssertEqual(variationFlag?.variations[base64Encode("e")]?.key, base64Encode("e"), "The 'numeric_flag' flag should have a variation key of 'e'.")
        
        let variationValue = try! variationFlag?.variations[base64Encode("e")]?.value.getStringValue()
        let decodedVariationValue = base64Decode(variationValue ?? "")
        XCTAssertEqual(decodedVariationValue, "2.7182818")

        // total shards
        XCTAssertEqual(variationFlag?.totalShards, 10000, "The total shards should be 10000.")
    }

    // errors

    // todo: add a test for not utf8 encoded values. need to figure out how to implement this.

    func testUnableToDecodeJSON() {
        let invalidJSON = "invalid_json".data(using: .utf8)!
        XCTAssertThrowsError(try UniversalFlagConfig.decodeFromJSON(from: invalidJSON)) { error in
            guard let thrownError = error as? UniversalFlagConfigError else {
                XCTFail("Error should be of type UniversalFlagConfigError")
                return
            }
            XCTAssertEqual(thrownError.errorCode, 101, "Error code should be 101 indicating a JSON parsing issue")
            XCTAssertEqual(thrownError.localizedDescription, "Data corrupted: The given data was not valid JSON.")
        }
    }
}
