import XCTest
@testable import EppoFlagging

/// Tests the precomputed configuration wire format using shared test data from sdk-test-data.
class PrecomputedConfigurationWireTests: XCTestCase {

    func testSaltUsedDirectlyForFlagKeyHashing() throws {
        let config = try loadPrecomputedConfig()

        let salt = config.salt
        XCTAssertEqual(salt, "c29kaXVtY2hsb3JpZGU=")

        let expectedHashedKey = getMD5Hex("string-flag", salt: salt)
        XCTAssertEqual(expectedHashedKey, "41a27b85ebdd7b1a5ae367a1a240a214")
        XCTAssertNotNil(config.flags[expectedHashedKey])
    }

    func testFlagAssignmentsWithSharedTestData() throws {
        let config = try loadPrecomputedConfig()

        EppoPrecomputedClient.resetForTesting()
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: config
        )

        let client = try EppoPrecomputedClient.shared()

        XCTAssertEqual(client.getStringAssignment(flagKey: "string-flag", defaultValue: "default"), "red")
        XCTAssertTrue(client.getJSONStringAssignment(flagKey: "json-flag", defaultValue: "{}").contains("key"))
        XCTAssertEqual(client.getStringAssignment(flagKey: "unknown-flag", defaultValue: "fallback"), "fallback")
    }

    func testBooleanFlagAssignmentWithBase64EncodedValue() throws {
        let config = try loadPrecomputedConfig()

        EppoPrecomputedClient.resetForTesting()
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: config
        )

        let client = try EppoPrecomputedClient.shared()

        // The test data has "boolean-flag" with variationValue "dHJ1ZQ==" (base64 of "true")
        let result = client.getBooleanAssignment(flagKey: "boolean-flag", defaultValue: false)
        XCTAssertTrue(result, "Boolean flag should return true, not the default value false")
    }

    func testIntegerFlagAssignmentWithBase64EncodedValue() throws {
        let config = try loadPrecomputedConfig()

        EppoPrecomputedClient.resetForTesting()
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: config
        )

        let client = try EppoPrecomputedClient.shared()

        // The test data has "integer-flag" with variationValue "NDI=" (base64 of "42")
        let result = client.getIntegerAssignment(flagKey: "integer-flag", defaultValue: 0)
        XCTAssertEqual(result, 42, "Integer flag should return 42, not the default value 0")
    }

    func testNumericFlagAssignmentWithBase64EncodedValue() throws {
        let config = try loadPrecomputedConfig()

        EppoPrecomputedClient.resetForTesting()
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: config
        )

        let client = try EppoPrecomputedClient.shared()

        // The test data has "numeric-flag" with variationValue "My4xNA==" (base64 of "3.14")
        let result = client.getNumericAssignment(flagKey: "numeric-flag", defaultValue: 0.0)
        XCTAssertEqual(result, 3.14, accuracy: 0.001, "Numeric flag should return 3.14, not the default value 0.0")
    }

    func testAllFlagTypesWithBase64EncodedValues() throws {
        let config = try loadPrecomputedConfig()

        EppoPrecomputedClient.resetForTesting()
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: config
        )

        let client = try EppoPrecomputedClient.shared()

        // Test all flag types in one test to verify comprehensive base64 decoding
        XCTAssertEqual(client.getStringAssignment(flagKey: "string-flag", defaultValue: "default"), "red")
        XCTAssertTrue(client.getBooleanAssignment(flagKey: "boolean-flag", defaultValue: false))
        XCTAssertEqual(client.getIntegerAssignment(flagKey: "integer-flag", defaultValue: 0), 42)
        XCTAssertEqual(client.getNumericAssignment(flagKey: "numeric-flag", defaultValue: 0.0), 3.14, accuracy: 0.001)
        XCTAssertTrue(client.getJSONStringAssignment(flagKey: "json-flag", defaultValue: "{}").contains("key"))
    }

    // MARK: - Helper Methods

    private func loadPrecomputedConfig() throws -> PrecomputedConfiguration {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/configuration-wire/precomputed-v1.json",
            withExtension: ""
        )!
        let jsonString = try String(contentsOf: fileURL)
        return try PrecomputedConfiguration(precomputedConfiguration: jsonString)
    }
}
