import XCTest
@testable import EppoFlagging

class PrecomputedConfigurationTests: XCTestCase {
    
    // MARK: - Test Data
    
    private func createSampleFlags() -> [String: PrecomputedFlag] {
        return [
            "flag1": PrecomputedFlag(
                allocationKey: "allocation-1",
                variationKey: "variation-1",
                variationType: .STRING,
                variationValue: .valueOf("value1"),
                extraLogging: [:],
                doLog: true
            ),
            "flag2": PrecomputedFlag(
                allocationKey: "allocation-2",
                variationKey: "variation-2",
                variationType: .BOOLEAN,
                variationValue: .valueOf(true),
                extraLogging: ["holdoutKey": "experiment-holdout", "holdoutVariation": "status_quo"],
                doLog: false
            )
        ]
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let flags = createSampleFlags()
        let fetchedAt = Date()
        let publishedAt = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let environment = Environment(name: "production")
        
        let config = PrecomputedConfiguration(
            flags: flags,
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: fetchedAt,
            configPublishedAt: publishedAt,
            environment: environment
        )
        
        XCTAssertEqual(config.flags.count, 2)
        XCTAssertEqual(config.salt, base64Encode("test-salt"))
        XCTAssertEqual(config.format, "PRECOMPUTED")
        XCTAssertEqual(config.configFetchedAt, fetchedAt)
        XCTAssertEqual(config.configPublishedAt, publishedAt)
        XCTAssertEqual(config.environment?.name, "production")
    }
    
    func testInitializationWithMinimalData() {
        let config = PrecomputedConfiguration(
            flags: [:],
            salt: "minimal-salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date()
        )
        
        XCTAssertTrue(config.flags.isEmpty)
        XCTAssertEqual(config.salt, "minimal-salt")
        XCTAssertNil(config.configPublishedAt)
        XCTAssertNil(config.environment)
    }
    
    // MARK: - Codable Tests
    
    func testJSONEncodingDecoding() throws {
        let originalConfig = PrecomputedConfiguration(
            flags: createSampleFlags(),
            salt: "encode-test-salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: Date(timeIntervalSinceNow: -7200),
            environment: Environment(name: "staging")
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(originalConfig)
        
        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertEqual(decodedConfig.flags.count, originalConfig.flags.count)
        XCTAssertEqual(decodedConfig.salt, originalConfig.salt)
        XCTAssertEqual(decodedConfig.format, originalConfig.format)
        XCTAssertEqual(decodedConfig.environment?.name, originalConfig.environment?.name)
    }
    
    func testDecodingFromServerResponse() throws {
        let json = """
        {
            "createdAt": "2024-11-18T14:23:25.123Z",
            "format": "PRECOMPUTED",
            "salt": "c29kaXVtY2hsb3JpZGU=",
            "obfuscated": true,
            "environment": {
                "name": "Test"
            },
            "flags": {
                "string-flag": {
                    "allocationKey": "YWxsb2NhdGlvbi0xMjM=",
                    "variationKey": "dmFyaWF0aW9uLTEyMw==",
                    "variationType": "STRING",
                    "variationValue": "cmVk",
                    "extraLogging": {},
                    "doLog": true
                },
                "boolean-flag": {
                    "allocationKey": "YWxsb2NhdGlvbi0xMjQ=",
                    "variationKey": "dmFyaWF0aW9uLTEyNA==",
                    "variationType": "BOOLEAN",
                    "variationValue": true,
                    "extraLogging": {"aG9sZG91dEtleQ==": "ZmVhdHVyZS1yb2xsb3V0", "aG9sZG91dFZhcmlhdGlvbg==": "YWxsX3NoaXBwZWQ="},
                    "doLog": false
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertEqual(config.salt, "c29kaXVtY2hsb3JpZGU=")
        XCTAssertEqual(config.format, "PRECOMPUTED")
        XCTAssertEqual(config.environment?.name, "Test")
        XCTAssertEqual(config.flags.count, 2)
        
        let stringFlag = config.flags["string-flag"]
        XCTAssertNotNil(stringFlag)
        XCTAssertEqual(stringFlag?.variationKey, "dmFyaWF0aW9uLTEyMw==")
        XCTAssertEqual(stringFlag?.variationType, .STRING)
        XCTAssertEqual(stringFlag?.variationValue, .valueOf("cmVk"))
        XCTAssertTrue(stringFlag?.doLog ?? false)
        
        let boolFlag = config.flags["boolean-flag"]
        XCTAssertNotNil(boolFlag)
        XCTAssertEqual(boolFlag?.variationType, .BOOLEAN)
        XCTAssertEqual(try boolFlag?.variationValue.getBoolValue(), true)
        XCTAssertFalse(boolFlag?.doLog ?? true)
    }
    
    
    // MARK: - Salt Validation Tests
    
    func testSaltIsRequired() throws {
        let json = """
        {
            "format": "PRECOMPUTED",
            "flags": {}
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        XCTAssertThrowsError(try decoder.decode(PrecomputedConfiguration.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    func testEmptySaltIsValid() throws {
        // Empty salt should be allowed (though not recommended)
        let json = """
        {
            "salt": "",
            "format": "PRECOMPUTED",
            "flags": {}
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertEqual(config.salt, "")
    }
    
}
