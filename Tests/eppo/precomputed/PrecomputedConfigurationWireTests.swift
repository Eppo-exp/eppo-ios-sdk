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
