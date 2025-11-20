import XCTest
import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import EppoFlagging

final class ConfigurationCacheEnvironmentTests: XCTestCase {
    var UFCTestJSON: String!

    override func setUpWithError() throws {
        try super.setUpWithError()

        EppoClient.resetSharedInstance()
        ConfigurationStore.clearPersistentCache()

        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
            withExtension: ""
        )
        UFCTestJSON = try! String(contentsOfFile: fileURL!.path)

        // Set up HTTP stubs for API calls
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = self.UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
    }

    override func tearDownWithError() throws {
        HTTPStubs.removeAllStubs()
        ConfigurationStore.clearPersistentCache()
        EppoClient.resetSharedInstance()
        try super.tearDownWithError()
    }

    func testConfigurationCacheRespectsDifferentSDKKeys() async throws {
        // This test verifies the fix for: https://github.com/Eppo-exp/eppo-ios-sdk/issues/83
        // Configuration cache should be environment-specific based on SDK keys

        // Step 1: Initialize with first SDK key (Production)
        let prodClient = try await EppoClient.initialize(
            sdkKey: "prod-sdk-key-12345",
            withPersistentCache: true
        )

        let prodConfig = prodClient.getFlagsConfiguration()
        XCTAssertNotNil(prodConfig, "Production configuration should be loaded")

        // Verify production cache file exists
        let prodCacheFile = getCacheFileURL(sdkKey: "prod-sdk-key-12345")
        Thread.sleep(forTimeInterval: 0.2) // Wait for async file write
        XCTAssertTrue(FileManager.default.fileExists(atPath: prodCacheFile.path),
                     "Production should have its own cache file")

        // Step 2: Switch to staging environment (different SDK key)
        // Customer should NOT need to call resetSharedInstance()
        let stagingClient = try await EppoClient.initialize(
            sdkKey: "staging-sdk-key-67890",
            withPersistentCache: true
        )

        let stagingConfig = stagingClient.getFlagsConfiguration()
        XCTAssertNotNil(stagingConfig, "Staging configuration should be loaded")

        // Verify staging has its own separate cache file
        let stagingCacheFile = getCacheFileURL(sdkKey: "staging-sdk-key-67890")
        Thread.sleep(forTimeInterval: 0.2) // Wait for async file write
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingCacheFile.path),
                     "Staging should have its own cache file")

        // Critical: Verify cache files are different (environment isolation)
        XCTAssertNotEqual(prodCacheFile.path, stagingCacheFile.path,
                         "Different SDK keys should have different cache files")

        // Step 3: Switch back to production - should load production cache
        let prodClient2 = try await EppoClient.initialize(
            sdkKey: "prod-sdk-key-12345",
            withPersistentCache: true
        )

        let prodConfig2 = prodClient2.getFlagsConfiguration()
        XCTAssertNotNil(prodConfig2, "Production configuration should load from cache")

        // Verify both cache files still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: prodCacheFile.path),
                     "Production cache should persist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingCacheFile.path),
                     "Staging cache should persist")
    }

    func testConfigurationCacheRespectsDifferentSDKKeysOffline() throws {
        // Test offline initialization with different SDK keys

        // Environment A configuration
        let envAConfig = """
        {
          "format": "SERVER",
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": { "name": "EnvironmentA" },
          "flags": {
            "test_flag": {
              "key": "test_flag",
              "enabled": true,
              "variationType": "STRING",
              "variations": { "control": { "key": "control", "value": "envA_value" } },
              "allocations": [{ "key": "allocation1", "doLog": true, "splits": [{ "variationKey": "control", "shards": [] }] }],
              "totalShards": 10000
            }
          }
        }
        """

        let configA = try Configuration(flagsConfigurationJson: Data(envAConfig.utf8), obfuscated: false)

        // Initialize with SDK key A
        let clientA = EppoClient.initializeOffline(
            sdkKey: "offline-sdk-key-A",
            initialConfiguration: configA,
            withPersistentCache: true
        )

        let loadedConfigA = clientA.getFlagsConfiguration()
        XCTAssertEqual(loadedConfigA?.getFlagConfigDetails().configEnvironment.name, "EnvironmentA")

        // Verify cache file A exists
        let cacheFileA = getCacheFileURL(sdkKey: "offline-sdk-key-A")
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFileA.path))

        // Environment B configuration
        let envBConfig = """
        {
          "format": "SERVER",
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": { "name": "EnvironmentB" },
          "flags": {
            "test_flag": {
              "key": "test_flag",
              "enabled": true,
              "variationType": "STRING",
              "variations": { "control": { "key": "control", "value": "envB_value" } },
              "allocations": [{ "key": "allocation1", "doLog": true, "splits": [{ "variationKey": "control", "shards": [] }] }],
              "totalShards": 10000
            }
          }
        }
        """

        let configB = try Configuration(flagsConfigurationJson: Data(envBConfig.utf8), obfuscated: false)

        // Switch to SDK key B
        let clientB = EppoClient.initializeOffline(
            sdkKey: "offline-sdk-key-B",
            initialConfiguration: configB,
            withPersistentCache: true
        )

        let loadedConfigB = clientB.getFlagsConfiguration()
        XCTAssertEqual(loadedConfigB?.getFlagConfigDetails().configEnvironment.name, "EnvironmentB")

        // Verify cache file B exists and is different from A
        let cacheFileB = getCacheFileURL(sdkKey: "offline-sdk-key-B")
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFileB.path))
        XCTAssertNotEqual(cacheFileA.path, cacheFileB.path)

        // Both cache files should still exist (environment isolation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFileA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFileB.path))
    }

    func testSameSDKKeyReusesCacheCorrectly() async throws {
        // Verify that the same SDK key correctly reuses its cache file

        let client1 = try await EppoClient.initialize(
            sdkKey: "same-sdk-key",
            withPersistentCache: true
        )

        let config1 = client1.getFlagsConfiguration()
        XCTAssertNotNil(config1)

        let cacheFile = getCacheFileURL(sdkKey: "same-sdk-key")
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        // Reinitialize with same SDK key - should reuse existing instance and cache
        let client2 = try await EppoClient.initialize(
            sdkKey: "same-sdk-key",
            withPersistentCache: true
        )

        let config2 = client2.getFlagsConfiguration()
        XCTAssertNotNil(config2)

        // Should still have the same cache file
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    private func getCacheFileURL(sdkKey: String) -> URL {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let eppoDirectory = cacheDirectory.appendingPathComponent("eppo", isDirectory: true)
        let sdkKeyHash = sdkKey.hash
        let fileName = "eppo-configuration-\(abs(sdkKeyHash)).json"
        return eppoDirectory.appendingPathComponent(fileName, isDirectory: false)
    }
}