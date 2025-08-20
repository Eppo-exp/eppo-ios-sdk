import XCTest
import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import EppoFlagging

final class ConfigurationChangeCallbackTests: XCTestCase {
    let DUMMY_SDK_KEY = "dummy_sdk_key"
    
    override func setUp() {
        super.setUp()
        EppoClient.resetSharedInstance()
        HTTPStubs.removeAllStubs()
    }
    
    override func tearDown() {
        super.tearDown()
        HTTPStubs.removeAllStubs()
        EppoClient.resetSharedInstance()
    }
    
    func testConfigurationChangeListenerBuilderInitialization() async throws {
        var receivedConfigurations: [Configuration] = []
        
        // Stub the HTTP requests to return empty config first, then a config with a flag
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            // First call returns empty config
            let emptyConfig = """
            {
              "format": "SERVER",
              "createdAt": "2024-04-17T19:40:53.716Z",
              "environment": {"name": "Test"},
              "flags": {}
            }
            """.data(using: .utf8)!
            
            return HTTPStubsResponse(data: emptyConfig, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Initialize client with configuration change callback in builder
        let eppoClient = try await EppoClient.initialize(
            sdkKey: DUMMY_SDK_KEY,
            configurationChangeCallback: { config in
                receivedConfigurations.append(config)
            }
        )
        
        // Verify initial callback was triggered
        XCTAssertEqual(receivedConfigurations.count, 1)
        
        // Now stub a different config response
        HTTPStubs.removeAllStubs()
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let boolFlagConfig = """
            {
              "format": "SERVER",
              "createdAt": "2024-04-17T19:40:53.716Z",
              "environment": {"name": "Test"},
              "flags": {
                "bool_flag": {
                  "key": "bool_flag",
                  "enabled": true,
                  "variationType": "BOOLEAN",
                  "variations": {
                    "true": {"key": "true", "value": {"boolValue": true}},
                    "false": {"key": "false", "value": {"boolValue": false}}
                  },
                  "allocations": [{
                    "key": "allocation1",
                    "rules": [],
                    "splits": [{"variationKey": "true", "shards": [{"salt": "salt", "ranges": [{"start": 0, "end": 10000}]}]}],
                    "doLog": true
                  }],
                  "totalShards": 10000
                }
              }
            }
            """.data(using: .utf8)!
            
            return HTTPStubsResponse(data: boolFlagConfig, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Trigger a manual reload
        try await eppoClient.load()
        
        // Verify callback was triggered again
        XCTAssertEqual(receivedConfigurations.count, 2)
        
        // Reload again - callback should be triggered even if config is the same
        try await eppoClient.load()
        
        // Verify callback was triggered a third time
        XCTAssertEqual(receivedConfigurations.count, 3)
    }
    
    func testConfigurationChangeListenerSetAfterInitialization() async throws {
        var configurationChangedCount = 0
        let expectation = self.expectation(description: "Configuration change callback")
        expectation.expectedFulfillmentCount = 2 // Initial load + one poll
        
        // Stub HTTP requests
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let emptyConfig = """
            {
              "format": "SERVER",
              "createdAt": "2024-04-17T19:40:53.716Z",
              "environment": {"name": "Test"},
              "flags": {}
            }
            """.data(using: .utf8)!
            
            return HTTPStubsResponse(data: emptyConfig, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Initialize client with polling enabled (short interval for test)
        let eppoClient = try await EppoClient.initialize(
            sdkKey: DUMMY_SDK_KEY,
            pollingEnabled: true,
            pollingIntervalMs: 100, // 100ms for quick test
            pollingJitterMs: 0
        )
        
        // Set callback after initialization
        eppoClient.onConfigurationChange { _ in
            configurationChangedCount += 1
            expectation.fulfill()
        }
        
        // Wait for initial config and at least one polling cycle
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Should have been called at least twice (initial + polling)
        XCTAssertGreaterThanOrEqual(configurationChangedCount, 2)
        
        // Stop polling to clean up
        await eppoClient.stopPolling()
    }
    
    func testConfigurationChangeListenerOverwrite() async throws {
        var firstCallbackCount = 0
        var secondCallbackCount = 0
        
        // Stub HTTP requests
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let emptyConfig = """
            {
              "format": "SERVER",
              "createdAt": "2024-04-17T19:40:53.716Z",
              "environment": {"name": "Test"},
              "flags": {}
            }
            """.data(using: .utf8)!
            
            return HTTPStubsResponse(data: emptyConfig, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Initialize client with first callback
        let eppoClient = try await EppoClient.initialize(
            sdkKey: DUMMY_SDK_KEY,
            configurationChangeCallback: { _ in
                firstCallbackCount += 1
            }
        )
        
        // First callback should have been called during initialization
        XCTAssertEqual(firstCallbackCount, 1)
        XCTAssertEqual(secondCallbackCount, 0)
        
        // Replace with second callback
        eppoClient.onConfigurationChange { _ in
            secondCallbackCount += 1
        }
        
        // Trigger another load
        try await eppoClient.load()
        
        // Only second callback should be called, first should be overwritten
        XCTAssertEqual(firstCallbackCount, 1) // No change
        XCTAssertEqual(secondCallbackCount, 1) // Called once
    }
    
    func testConfigurationChangeListenerOfflineInitialization() {
        var receivedConfigurations: [Configuration] = []
        
        // Create a mock initial configuration
        let initialConfigData = """
        {
          "format": "SERVER",
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": {"name": "Test"},
          "flags": {}
        }
        """.data(using: .utf8)!
        
        let initialConfig = try! Configuration(flagsConfigurationJson: initialConfigData, obfuscated: false)
        
        // Initialize offline client with callback and initial configuration
        let eppoClient = EppoClient.initializeOffline(
            sdkKey: DUMMY_SDK_KEY,
            initialConfiguration: initialConfig,
            configurationChangeCallback: { config in
                receivedConfigurations.append(config)
            }
        )
        
        // Configuration change callback should not be triggered for offline initialization
        // until load is called (similar to Android behavior)
        XCTAssertEqual(receivedConfigurations.count, 0)
        
        // Verify the client has the initial configuration
        let storedConfig = eppoClient.getFlagsConfiguration()
        XCTAssertNotNil(storedConfig)
    }
}
