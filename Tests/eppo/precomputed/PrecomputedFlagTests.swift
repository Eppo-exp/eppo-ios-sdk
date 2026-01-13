import XCTest
@testable import EppoFlagging

class PrecomputedFlagTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() {
        let flag = PrecomputedFlag(
            allocationKey: "allocation-1",
            variationKey: "control",
            variationType: .string,
            variationValue: .valueOf("test value"),
            extraLogging: ["holdoutKey": "test-holdout", "holdoutVariation": "status_quo"],
            doLog: true
        )

        XCTAssertEqual(flag.allocationKey, "allocation-1")
        XCTAssertEqual(flag.variationKey, "control")
        XCTAssertEqual(flag.variationType, .string)
        XCTAssertEqual(flag.variationValue, .valueOf("test value"))
        XCTAssertEqual(flag.extraLogging, ["holdoutKey": "test-holdout", "holdoutVariation": "status_quo"])
        XCTAssertTrue(flag.doLog)
    }

    func testInitializationWithNilValues() {
        let flag = PrecomputedFlag(
            allocationKey: nil,
            variationKey: nil,
            variationType: .boolean,
            variationValue: .valueOf(false),
            extraLogging: [:],
            doLog: false
        )

        XCTAssertNil(flag.allocationKey)
        XCTAssertNil(flag.variationKey)
        XCTAssertEqual(flag.variationType, .boolean)
        XCTAssertEqual(flag.variationValue, .valueOf(false))
        XCTAssertTrue(flag.extraLogging.isEmpty)
        XCTAssertFalse(flag.doLog)
    }

    // MARK: - Codable Tests

    func testJSONEncodingDecoding() throws {
        let originalFlag = PrecomputedFlag(
            allocationKey: "test-allocation",
            variationKey: "variant-a",
            variationType: .string,
            variationValue: .valueOf("test string"),
            extraLogging: ["holdoutKey": "experiment-123", "holdoutVariation": "all_shipped"],
            doLog: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalFlag)

        let decoder = JSONDecoder()
        let decodedFlag = try decoder.decode(PrecomputedFlag.self, from: data)

        XCTAssertEqual(decodedFlag.allocationKey, originalFlag.allocationKey)
        XCTAssertEqual(decodedFlag.variationKey, originalFlag.variationKey)
        XCTAssertEqual(decodedFlag.variationType, originalFlag.variationType)
        XCTAssertEqual(decodedFlag.variationValue, originalFlag.variationValue)
        XCTAssertEqual(decodedFlag.extraLogging, originalFlag.extraLogging)
        XCTAssertEqual(decodedFlag.doLog, originalFlag.doLog)
    }

    func testDecodingFromJSON() throws {
        let json = """
        {
            "allocationKey": "allocation-123",
            "variationKey": "treatment",
            "variationType": "NUMERIC",
            "variationValue": 42.5,
            "extraLogging": {
                "holdoutKey": "api-experiment",
                "holdoutVariation": "all_shipped"
            },
            "doLog": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let flag = try decoder.decode(PrecomputedFlag.self, from: data)

        XCTAssertEqual(flag.allocationKey, "allocation-123")
        XCTAssertEqual(flag.variationKey, "treatment")
        XCTAssertEqual(flag.variationType, .numeric)
        XCTAssertEqual(try flag.variationValue.getDoubleValue(), 42.5)
        XCTAssertEqual(flag.extraLogging["holdoutKey"], "api-experiment")
        XCTAssertEqual(flag.extraLogging["holdoutVariation"], "all_shipped")
        XCTAssertTrue(flag.doLog)
    }

    func testDecodingWithNullValues() throws {
        let json = """
        {
            "allocationKey": null,
            "variationKey": null,
            "variationType": "INTEGER",
            "variationValue": 100,
            "extraLogging": {},
            "doLog": false
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let flag = try decoder.decode(PrecomputedFlag.self, from: data)

        XCTAssertNil(flag.allocationKey)
        XCTAssertNil(flag.variationKey)
        XCTAssertEqual(flag.variationType, .integer)
        XCTAssertEqual(Int(try flag.variationValue.getDoubleValue()), 100)
        XCTAssertTrue(flag.extraLogging.isEmpty)
        XCTAssertFalse(flag.doLog)
    }

    // MARK: - VariationType Tests

    func testAllVariationTypes() throws {
        let testCases: [(VariationType, EppoValue, String)] = [
            (.boolean, .valueOf(true), "true"),
            (.string, .valueOf("hello"), "\"hello\""),
            (.integer, .valueOf(42), "42"),
            (.numeric, .valueOf(3.14), "3.14"),
            (.json, .valueOf("{\"key\":\"value\"}"), "\"{\\\"key\\\":\\\"value\\\"}\"")
        ]

        for (variationType, variationValue, jsonValue) in testCases {
            let json = """
            {
                "allocationKey": "test",
                "variationKey": "variant",
                "variationType": "\(variationType.rawValue)",
                "variationValue": \(jsonValue),
                "extraLogging": {},
                "doLog": false
            }
            """

            let data = json.data(using: .utf8)!
            let decoder = JSONDecoder()
            let flag = try decoder.decode(PrecomputedFlag.self, from: data)

            XCTAssertEqual(flag.variationType, variationType)
            XCTAssertEqual(flag.variationValue, variationValue)
        }
    }

    // MARK: - Edge Cases

    func testEmptyExtraLogging() {
        let flag = PrecomputedFlag(
            allocationKey: "test",
            variationKey: "variant",
            variationType: .boolean,
            variationValue: .valueOf(true),
            extraLogging: [:],
            doLog: false
        )

        XCTAssertTrue(flag.extraLogging.isEmpty)
    }

    func testComplexExtraLogging() throws {
        let json = """
        {
            "allocationKey": "test",
            "variationKey": "variant",
            "variationType": "STRING",
            "variationValue": "test",
            "extraLogging": {
                "holdoutKey": "activeHoldout",
                "holdoutVariation": "all_shipped"
            },
            "doLog": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let flag = try decoder.decode(PrecomputedFlag.self, from: data)

        XCTAssertEqual(flag.extraLogging.count, 2)
        XCTAssertEqual(flag.extraLogging["holdoutKey"], "activeHoldout")
        XCTAssertEqual(flag.extraLogging["holdoutVariation"], "all_shipped")
    }
}
