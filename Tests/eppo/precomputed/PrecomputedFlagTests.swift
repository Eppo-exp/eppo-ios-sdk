import XCTest
@testable import EppoFlagging

class PrecomputedFlagTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let flag = PrecomputedFlag(
            allocationKey: "allocation-1",
            variationKey: "control",
            variationType: .STRING,
            variationValue: .valueOf("test value"),
            extraLogging: ["key": "value"],
            doLog: true
        )
        
        XCTAssertEqual(flag.allocationKey, "allocation-1")
        XCTAssertEqual(flag.variationKey, "control")
        XCTAssertEqual(flag.variationType, .STRING)
        XCTAssertEqual(flag.variationValue, .valueOf("test value"))
        XCTAssertEqual(flag.extraLogging, ["key": "value"])
        XCTAssertTrue(flag.doLog)
    }
    
    func testInitializationWithNilValues() {
        let flag = PrecomputedFlag(
            allocationKey: nil,
            variationKey: nil,
            variationType: .BOOLEAN,
            variationValue: .valueOf(false),
            extraLogging: [:],
            doLog: false
        )
        
        XCTAssertNil(flag.allocationKey)
        XCTAssertNil(flag.variationKey)
        XCTAssertEqual(flag.variationType, .BOOLEAN)
        XCTAssertEqual(flag.variationValue, .valueOf(false))
        XCTAssertTrue(flag.extraLogging.isEmpty)
        XCTAssertFalse(flag.doLog)
    }
    
    // MARK: - Codable Tests
    
    func testJSONEncodingDecoding() throws {
        let originalFlag = PrecomputedFlag(
            allocationKey: "test-allocation",
            variationKey: "variant-a",
            variationType: .STRING,
            variationValue: .valueOf("test string"),
            extraLogging: ["experiment": "exp-123"],
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
                "source": "api",
                "version": "v2"
            },
            "doLog": true
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let flag = try decoder.decode(PrecomputedFlag.self, from: data)
        
        XCTAssertEqual(flag.allocationKey, "allocation-123")
        XCTAssertEqual(flag.variationKey, "treatment")
        XCTAssertEqual(flag.variationType, .NUMERIC)
        XCTAssertEqual(try flag.variationValue.getDoubleValue(), 42.5)
        XCTAssertEqual(flag.extraLogging["source"], "api")
        XCTAssertEqual(flag.extraLogging["version"], "v2")
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
        XCTAssertEqual(flag.variationType, .INTEGER)
        XCTAssertEqual(Int(try flag.variationValue.getDoubleValue()), 100)
        XCTAssertTrue(flag.extraLogging.isEmpty)
        XCTAssertFalse(flag.doLog)
    }
    
    // MARK: - VariationType Tests
    
    func testAllVariationTypes() throws {
        let testCases: [(VariationType, EppoValue, String)] = [
            (.BOOLEAN, .valueOf(true), "true"),
            (.STRING, .valueOf("hello"), "\"hello\""),
            (.INTEGER, .valueOf(42), "42"),
            (.NUMERIC, .valueOf(3.14), "3.14"),
            (.JSON, .valueOf("{\"key\":\"value\"}"), "\"{\\\"key\\\":\\\"value\\\"}\"")
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
            variationType: .BOOLEAN,
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
                "experiment_id": "exp-123",
                "cohort": "new_users",
                "timestamp": "2024-01-01T00:00:00Z",
                "feature_version": "2.0"
            },
            "doLog": true
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let flag = try decoder.decode(PrecomputedFlag.self, from: data)
        
        XCTAssertEqual(flag.extraLogging.count, 4)
        XCTAssertEqual(flag.extraLogging["experiment_id"], "exp-123")
        XCTAssertEqual(flag.extraLogging["cohort"], "new_users")
        XCTAssertEqual(flag.extraLogging["timestamp"], "2024-01-01T00:00:00Z")
        XCTAssertEqual(flag.extraLogging["feature_version"], "2.0")
    }
}