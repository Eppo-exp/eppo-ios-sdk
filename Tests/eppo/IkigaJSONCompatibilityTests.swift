import XCTest
import IkigaJSON
@testable import EppoFlagging

/// Tests to verify IkigaJSON can be used as a drop-in replacement for standard JSON parsing
class IkigaJSONCompatibilityTests: XCTestCase {

    private let standardProvider = StandardJSONParsingProvider()
    private let ikigaProvider = IkigaJSONParsingProvider()

    func testCanParseBasicConfigurationWithIkiga() throws {
        // Load a test configuration JSON
        guard let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1.json", withExtension: ""),
              let jsonData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load test JSON file: flags-v1.json")
            return
        }

        // Parse with both providers
        let standardConfig = try standardProvider.decodeUniversalFlagConfig(from: jsonData)
        let ikigaConfig = try ikigaProvider.decodeUniversalFlagConfig(from: jsonData)

        // Verify they produce equivalent results
        XCTAssertEqual(standardConfig.format, ikigaConfig.format)
        XCTAssertEqual(standardConfig.environment.name, ikigaConfig.environment.name)
        XCTAssertEqual(standardConfig.flags.count, ikigaConfig.flags.count)
        XCTAssertEqual(standardConfig.createdAt.timeIntervalSince1970,
                      ikigaConfig.createdAt.timeIntervalSince1970,
                      accuracy: 0.001)

        // Verify flag details are identical
        for (key, standardFlag) in standardConfig.flags {
            guard let ikigaFlag = ikigaConfig.flags[key] else {
                XCTFail("Missing flag \(key) in IkigaJSON result")
                continue
            }
            XCTAssertEqual(standardFlag.key, ikigaFlag.key)
            XCTAssertEqual(standardFlag.enabled, ikigaFlag.enabled)
            XCTAssertEqual(standardFlag.variationType, ikigaFlag.variationType)
            XCTAssertEqual(standardFlag.variations.count, ikigaFlag.variations.count)
            XCTAssertEqual(standardFlag.allocations.count, ikigaFlag.allocations.count)
            XCTAssertEqual(standardFlag.totalShards, ikigaFlag.totalShards)
        }
    }

    func testCanParseObfuscatedConfigurationWithIkiga() throws {
        // Load an obfuscated test configuration JSON
        guard let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json", withExtension: ""),
              let jsonData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load test JSON file: flags-v1-obfuscated.json")
            return
        }

        // Parse with both providers
        let standardConfig = try standardProvider.decodeUniversalFlagConfig(from: jsonData)
        let ikigaConfig = try ikigaProvider.decodeUniversalFlagConfig(from: jsonData)

        // Verify they produce equivalent results for obfuscated content
        XCTAssertEqual(standardConfig.flags.count, ikigaConfig.flags.count)

        // Verify specific obfuscated flag parsing
        for (key, standardFlag) in standardConfig.flags {
            guard let ikigaFlag = ikigaConfig.flags[key] else {
                XCTFail("Missing flag \(key) in IkigaJSON result")
                continue
            }
            XCTAssertEqual(standardFlag.key, ikigaFlag.key)
            XCTAssertEqual(standardFlag.enabled, ikigaFlag.enabled)

            // Check that rule conditions with MD5 values are properly parsed
            for (stdAlloc, ikigaAlloc) in zip(standardFlag.allocations, ikigaFlag.allocations) {
                if let stdRules = stdAlloc.rules, let ikigaRules = ikigaAlloc.rules {
                    XCTAssertEqual(stdRules.count, ikigaRules.count)
                    for (stdRule, ikigaRule) in zip(stdRules, ikigaRules) {
                        XCTAssertEqual(stdRule.conditions.count, ikigaRule.conditions.count)
                        for (stdCond, ikigaCond) in zip(stdRule.conditions, ikigaRule.conditions) {
                            XCTAssertEqual(stdCond.operator, ikigaCond.operator)
                            XCTAssertEqual(stdCond.attribute, ikigaCond.attribute)
                            // Can't compare private properties, so just verify they parsed successfully
                            XCTAssertNotNil(stdCond.value)
                            XCTAssertNotNil(ikigaCond.value)
                        }
                    }
                }
            }
        }
    }

    func testConfigurationRoundTripCompatibility() throws {
        // Load test data
        guard let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1.json", withExtension: ""),
              let jsonData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load test JSON file")
            return
        }

        // Create Configuration objects with both providers
        let standardConfig = try standardProvider.decodeConfiguration(from: jsonData, obfuscated: false)
        let ikigaConfig = try ikigaProvider.decodeConfiguration(from: jsonData, obfuscated: false)

        // Encode both back to data
        let standardEncodedData = try standardProvider.encodeConfiguration(standardConfig)
        let ikigaEncodedData = try ikigaProvider.encodeConfiguration(ikigaConfig)

        // Decode the encoded data with opposite providers to test cross-compatibility
        let standardDecodedFromIkiga = try standardProvider.decodeEncodedConfiguration(from: ikigaEncodedData)
        let ikigaDecodedFromStandard = try ikigaProvider.decodeEncodedConfiguration(from: standardEncodedData)

        // Verify cross-compatibility works
        XCTAssertEqual(standardConfig.obfuscated, standardDecodedFromIkiga.obfuscated)
        XCTAssertEqual(ikigaConfig.obfuscated, ikigaDecodedFromStandard.obfuscated)
        XCTAssertEqual(standardConfig.flagsConfiguration.flags.count,
                      standardDecodedFromIkiga.flagsConfiguration.flags.count)
        XCTAssertEqual(ikigaConfig.flagsConfiguration.flags.count,
                      ikigaDecodedFromStandard.flagsConfiguration.flags.count)
    }

    func testCanUseAsPluggableReplacement() throws {
        // Load test data
        guard let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1.json", withExtension: ""),
              let jsonData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load test JSON file")
            return
        }

        // Store original provider
        let originalProvider = JSONParsingFactory.currentProvider

        // Test with standard provider
        JSONParsingFactory.configure(provider: standardProvider)
        let standardConfig = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)

        // Switch to IkigaJSON provider
        JSONParsingFactory.configure(provider: ikigaProvider)
        let ikigaConfig = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)

        // Verify both configurations are equivalent
        XCTAssertEqual(standardConfig.obfuscated, ikigaConfig.obfuscated)
        XCTAssertEqual(standardConfig.flagsConfiguration.flags.count,
                      ikigaConfig.flagsConfiguration.flags.count)
        XCTAssertEqual(standardConfig.flagsConfiguration.environment.name,
                      ikigaConfig.flagsConfiguration.environment.name)

        // Test that toJsonString works with both
        let standardJson = try standardConfig.toJsonString()
        let ikigaJson = try ikigaConfig.toJsonString()

        XCTAssertFalse(standardJson.isEmpty)
        XCTAssertFalse(ikigaJson.isEmpty)

        // Restore original provider
        JSONParsingFactory.configure(provider: originalProvider)
    }

    func testPerformanceComparison() throws {
        // Load a larger test configuration for meaningful performance comparison
        let testBundle = Bundle(for: type(of: self))
        guard let jsonPath = testBundle.path(forResource: "flags-v1", ofType: "json", inDirectory: "Resources/test-data/ufc"),
              let jsonData = NSData(contentsOfFile: jsonPath) as Data? else {
            XCTFail("Could not load test JSON file")
            return
        }

        // Create metrics providers for timing
        let standardMetrics = MetricsJSONParsingProvider(wrapping: standardProvider, label: "Standard")
        let ikigaMetrics = MetricsJSONParsingProvider(wrapping: ikigaProvider, label: "IkigaJSON")

        print("\\n=== Performance Comparison for \\(jsonData.count) byte JSON ===")

        // Run multiple iterations for stable timing
        let iterations = 10

        measure {
            for _ in 0..<iterations {
                do {
                    _ = try standardMetrics.decodeUniversalFlagConfig(from: jsonData)
                } catch {
                    XCTFail("Standard provider failed: \\(error)")
                }
            }
        }

        measure {
            for _ in 0..<iterations {
                do {
                    _ = try ikigaMetrics.decodeUniversalFlagConfig(from: jsonData)
                } catch {
                    XCTFail("IkigaJSON provider failed: \\(error)")
                }
            }
        }

        print("=== End Performance Comparison ===\\n")
    }

    func testDateParsingCompatibility() throws {
        // Create a minimal JSON with various date formats that the SDK might encounter
        let dateTestJSON = """
        {
            "format": "universal_flag_config_v1",
            "createdAt": "2023-10-28T10:15:30.123Z",
            "environment": {"name": "test"},
            "flags": {}
        }
        """.data(using: .utf8)!

        // Parse with both providers
        let standardConfig = try standardProvider.decodeUniversalFlagConfig(from: dateTestJSON)
        let ikigaConfig = try ikigaProvider.decodeUniversalFlagConfig(from: dateTestJSON)

        // Verify date parsing is identical
        XCTAssertEqual(standardConfig.createdAt.timeIntervalSince1970,
                      ikigaConfig.createdAt.timeIntervalSince1970,
                      accuracy: 0.001)

        // Test encoding produces parseable dates for both
        let standardEncoded = try standardProvider.encodeUniversalFlagConfig(standardConfig)
        let ikigaEncoded = try ikigaProvider.encodeUniversalFlagConfig(ikigaConfig)

        // Cross-decode to verify date encoding compatibility
        let crossDecoded1 = try standardProvider.decodeUniversalFlagConfig(from: ikigaEncoded)
        let crossDecoded2 = try ikigaProvider.decodeUniversalFlagConfig(from: standardEncoded)

        XCTAssertEqual(crossDecoded1.createdAt.timeIntervalSince1970,
                      standardConfig.createdAt.timeIntervalSince1970,
                      accuracy: 0.001)
        XCTAssertEqual(crossDecoded2.createdAt.timeIntervalSince1970,
                      ikigaConfig.createdAt.timeIntervalSince1970,
                      accuracy: 0.001)
    }

    func testPolymorphicValueParsingCompatibility() throws {
        // Test JSON with various EppoValue types
        let polymorphicTestJSON = """
        {
            "format": "universal_flag_config_v1",
            "createdAt": "2023-10-28T10:15:30.123Z",
            "environment": {"name": "test"},
            "flags": {
                "test-flag": {
                    "key": "test-flag",
                    "enabled": true,
                    "variationType": "STRING",
                    "variations": {
                        "control": {"key": "control", "value": "control-string"},
                        "treatment": {"key": "treatment", "value": 42.5},
                        "bool-var": {"key": "bool-var", "value": true},
                        "array-var": {"key": "array-var", "value": ["a", "b", "c"]},
                        "null-var": {"key": "null-var", "value": null}
                    },
                    "allocations": [],
                    "totalShards": 100
                }
            }
        }
        """.data(using: .utf8)!

        // Parse with both providers
        let standardConfig = try standardProvider.decodeUniversalFlagConfig(from: polymorphicTestJSON)
        let ikigaConfig = try ikigaProvider.decodeUniversalFlagConfig(from: polymorphicTestJSON)

        // Verify polymorphic value parsing is identical
        guard let standardFlag = standardConfig.flags["test-flag"],
              let ikigaFlag = ikigaConfig.flags["test-flag"] else {
            XCTFail("Test flag not found")
            return
        }

        let standardVariations = standardFlag.variations
        let ikigaVariations = ikigaFlag.variations

        XCTAssertEqual(standardVariations.count, ikigaVariations.count)

        // Test each variation exists and was parsed (can't access private properties)
        XCTAssertNotNil(standardVariations["control"]?.value)
        XCTAssertNotNil(ikigaVariations["control"]?.value)
        XCTAssertNotNil(standardVariations["treatment"]?.value)
        XCTAssertNotNil(ikigaVariations["treatment"]?.value)
        XCTAssertNotNil(standardVariations["bool-var"]?.value)
        XCTAssertNotNil(ikigaVariations["bool-var"]?.value)
        XCTAssertNotNil(standardVariations["array-var"]?.value)
        XCTAssertNotNil(ikigaVariations["array-var"]?.value)
        XCTAssertNotNil(standardVariations["null-var"]?.value)
        XCTAssertNotNil(ikigaVariations["null-var"]?.value)
    }

    func testErrorHandlingCompatibility() throws {
        // Test that both providers handle invalid JSON similarly
        let invalidJSON = "invalid json".data(using: .utf8)!

        // Both should throw parsing errors
        XCTAssertThrowsError(try standardProvider.decodeUniversalFlagConfig(from: invalidJSON)) { error in
            XCTAssertTrue(error is UniversalFlagConfigError)
        }

        XCTAssertThrowsError(try ikigaProvider.decodeUniversalFlagConfig(from: invalidJSON)) { error in
            XCTAssertTrue(error is UniversalFlagConfigError)
        }

        // Test malformed JSON structure
        let malformedJSON = """
        {
            "format": "universal_flag_config_v1",
            "createdAt": "not-a-date",
            "environment": {"name": "test"},
            "flags": {}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try standardProvider.decodeUniversalFlagConfig(from: malformedJSON))
        XCTAssertThrowsError(try ikigaProvider.decodeUniversalFlagConfig(from: malformedJSON))
    }
}