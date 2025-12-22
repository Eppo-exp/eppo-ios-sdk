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
                    "allocationKey": "allocation-123",
                    "variationKey": "variation-123",
                    "variationType": "STRING",
                    "variationValue": "red",
                    "extraLogging": {},
                    "doLog": true
                },
                "boolean-flag": {
                    "allocationKey": "allocation-124",
                    "variationKey": "variation-124",
                    "variationType": "BOOLEAN",
                    "variationValue": true,
                    "extraLogging": {"holdoutKey": "feature-rollout", "holdoutVariation": "all_shipped"},
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
        XCTAssertEqual(stringFlag?.variationKey, "variation-123")
        XCTAssertEqual(stringFlag?.variationType, .STRING)
        XCTAssertEqual(stringFlag?.variationValue, .valueOf("red"))
        XCTAssertTrue(stringFlag?.doLog ?? false)
        
        let boolFlag = config.flags["boolean-flag"]
        XCTAssertNotNil(boolFlag)
        XCTAssertEqual(boolFlag?.variationType, .BOOLEAN)
        XCTAssertEqual(try boolFlag?.variationValue.getBoolValue(), true)
        XCTAssertFalse(boolFlag?.doLog ?? true)
    }
    
    func testDecodingWithObfuscatedData() throws {
        let json = """
        {
            "createdAt": "MjAyNC0xMS0xOFQxNDoyMzoyNS4xMjNa",
            "format": "PRECOMPUTED",
            "salt": "c29kaXVtY2hsb3JpZGU=",
            "obfuscated": true,
            "flags": {
                "41a27b85ebdd7b1a5ae367a1a240a214": {
                    "allocationKey": "YWxsb2NhdGlvbi0xMjM=",
                    "variationKey": "dmFyaWF0aW9uLTEyMw==",
                    "variationType": "STRING",
                    "variationValue": "cmVk",
                    "extraLogging": {},
                    "doLog": true
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertEqual(config.salt, "c29kaXVtY2hsb3JpZGU=")
        XCTAssertEqual(config.flags.count, 1)
        
        let flag = config.flags["41a27b85ebdd7b1a5ae367a1a240a214"]
        XCTAssertNotNil(flag)
        XCTAssertEqual(flag?.allocationKey, "YWxsb2NhdGlvbi0xMjM=")
        XCTAssertEqual(flag?.variationKey, "dmFyaWF0aW9uLTEyMw==")
        XCTAssertEqual(flag?.variationValue, .valueOf("cmVk"))
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
    
    // MARK: - Format Tests
    
    func testFormatValidation() throws {
        let json = """
        {
            "salt": "test-salt",
            "format": "PRECOMPUTED",
            "flags": {}
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertEqual(config.format, "PRECOMPUTED")
    }
    
    // MARK: - Edge Cases
    
    func testDecodingWithoutEnvironment() throws {
        let json = """
        {
            "salt": "no-env-salt",
            "format": "PRECOMPUTED",
            "flags": {}
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertNil(config.environment)
    }
    
    func testDecodingWithoutCreatedAt() throws {
        let json = """
        {
            "salt": "no-date-salt",
            "format": "PRECOMPUTED",
            "flags": {}
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        XCTAssertNil(config.configPublishedAt)
        XCTAssertNotNil(config.configFetchedAt) // This is set to current date
    }
    
    func testLargeFlagConfiguration() throws {
        var flags: [String: PrecomputedFlag] = [:]
        for i in 1...100 {
            flags["flag\(i)"] = PrecomputedFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variation-\(i)",
                variationType: .STRING,
                variationValue: .valueOf("value-\(i)"),
                extraLogging: i % 10 == 0 ? ["holdoutKey": "holdout-\(i)", "holdoutVariation": "status_quo"] : [:],
                doLog: i % 2 == 0
            )
        }
        
        let config = PrecomputedConfiguration(
            flags: flags,
            salt: "large-config-salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date()
        )
        
        XCTAssertEqual(config.flags.count, 100)
        XCTAssertEqual(config.flags["flag50"]?.variationKey, "variation-50")
        XCTAssertTrue(config.flags["flag50"]?.doLog ?? false)
        XCTAssertFalse(config.flags["flag51"]?.doLog ?? true)
    }
    
    func testComplexExtraLogging() throws {
        let json = """
        {
            "salt": "complex-logging-salt",
            "format": "PRECOMPUTED",
            "flags": {
                "test-flag": {
                    "allocationKey": "allocation-1",
                    "variationKey": "variation-1",
                    "variationType": "STRING",
                    "variationValue": "test",
                    "extraLogging": {
                        "holdoutKey": "experiment-123-holdout",
                        "holdoutVariation": "status_quo"
                    },
                    "doLog": true
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
        
        let flag = config.flags["test-flag"]
        XCTAssertNotNil(flag)
        XCTAssertEqual(flag?.extraLogging.count, 2)
        XCTAssertEqual(flag?.extraLogging["holdoutKey"], "experiment-123-holdout")
        XCTAssertEqual(flag?.extraLogging["holdoutVariation"], "status_quo")
    }
}
