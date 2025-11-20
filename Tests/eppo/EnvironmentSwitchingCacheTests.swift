import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import EppoFlagging

final class EnvironmentSwitchingCacheTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var UFCTestJSON: String!

    override func setUpWithError() throws {
        try super.setUpWithError()

        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()

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
        EppoClient.resetSharedInstance()
        try super.tearDownWithError()
    }

    func testAssignmentCacheIsClearedWhenSwitchingSDKKeys() async throws {
        // Test that assignment cache is properly cleared when switching to a different SDK key (environment)
        // This test reproduces the bug reported in https://github.com/Eppo-exp/eppo-ios-sdk/issues/83

        // Initialize with first SDK key
        let client1 = try await EppoClient.initialize(
            sdkKey: "first-sdk-key",
            assignmentLogger: loggerSpy.logger
        )

        // Make an assignment that will be cached
        _ = client1.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // Verify the assignment was logged
        XCTAssertEqual(loggerSpy.logCount, 1, "First assignment should be logged")

        // DO NOT reset shared instance - this is the real-world scenario where the user
        // tries to initialize with a different SDK key without explicitly resetting

        // Initialize with a different SDK key (different environment)
        // This should create a new client instance and clear the cache, but currently doesn't
        let client2 = try await EppoClient.initialize(
            sdkKey: "second-sdk-key",
            assignmentLogger: loggerSpy.logger
        )

        // Make the same assignment - this should be logged again since we're in a different environment
        // and the assignment cache should have been cleared
        _ = client2.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // The assignment should be logged again because we switched environments
        // This assertion will currently fail, demonstrating the bug
        XCTAssertEqual(loggerSpy.logCount, 2, "Assignment should be logged again when switching SDK keys")
    }

    func testAssignmentCachePersistsWhenReInitializingWithSameSDKKey() async throws {
        // Test that when reinitializing with the SAME SDK key, the assignment cache persists (correct behavior)

        // Initialize with SDK key
        let client1 = try await EppoClient.initialize(
            sdkKey: "same-sdk-key",
            assignmentLogger: loggerSpy.logger
        )

        // Make an assignment that will be cached
        _ = client1.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // Verify the assignment was logged
        XCTAssertEqual(loggerSpy.logCount, 1, "First assignment should be logged")

        // Reinitialize with the SAME SDK key - cache should persist
        let client2 = try await EppoClient.initialize(
            sdkKey: "same-sdk-key",
            assignmentLogger: loggerSpy.logger
        )

        // Make the same assignment - this should NOT be logged again since it's the same environment
        _ = client2.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // This should pass - no additional logging since we're using the same environment
        XCTAssertEqual(loggerSpy.logCount, 1, "Same assignment with same SDK key should not be logged again due to cache")
    }

    func testAssignmentCacheIsClearedWhenSwitchingSDKKeysOffline() throws {
        // Test that assignment cache is properly cleared when switching to a different SDK key (environment)
        // using initializeOffline method

        // Create configuration from test data (same format as ConfigurationTests)
        let testJsonString = """
        {
          "format": "SERVER",
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": {
            "name": "Test"
          },
          "flags": {
            "numeric_flag": {
              "key": "numeric_flag",
              "enabled": true,
              "variationType": "NUMERIC",
              "variations": {
                "e": {
                  "key": "e",
                  "value": 2.7182818
                },
                "pi": {
                  "key": "pi",
                  "value": 3.1415926
                }
              },
              "allocations": [
                {
                  "key": "rollout",
                  "doLog": true,
                  "splits": [
                    {
                      "variationKey": "pi",
                      "shards": []
                    }
                  ]
                }
              ],
              "totalShards": 10000
            }
          }
        }
        """

        let configuration = try Configuration(
            flagsConfigurationJson: Data(testJsonString.utf8),
            obfuscated: false
        )

        // Initialize offline with first SDK key
        let client1 = EppoClient.initializeOffline(
            sdkKey: "first-sdk-key",
            assignmentLogger: loggerSpy.logger,
            initialConfiguration: configuration
        )

        // Make an assignment that will be cached
        _ = client1.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // Verify the assignment was logged
        XCTAssertEqual(loggerSpy.logCount, 1, "First assignment should be logged")

        // DO NOT reset shared instance - this is the real-world scenario where the user
        // tries to initialize offline with a different SDK key without explicitly resetting

        // Initialize offline with a different SDK key (different environment)
        // This should create a new client instance and clear the cache, but currently doesn't
        let client2 = EppoClient.initializeOffline(
            sdkKey: "second-sdk-key",
            assignmentLogger: loggerSpy.logger,
            initialConfiguration: configuration
        )

        // Make the same assignment - this should be logged again since we're in a different environment
        // and the assignment cache should have been cleared
        _ = client2.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // The assignment should be logged again because we switched environments
        // This assertion will currently fail, demonstrating the bug exists in offline mode too
        XCTAssertEqual(loggerSpy.logCount, 2, "Assignment should be logged again when switching SDK keys in offline mode")
    }

    func testAssignmentCachePersistsWhenReInitializingWithSameSDKKeyOffline() throws {
        // Test that when reinitializing offline with the SAME SDK key, the assignment cache persists (correct behavior)

        // Create configuration from test data (same format as ConfigurationTests)
        let testJsonString = """
        {
          "format": "SERVER",
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": {
            "name": "Test"
          },
          "flags": {
            "numeric_flag": {
              "key": "numeric_flag",
              "enabled": true,
              "variationType": "NUMERIC",
              "variations": {
                "e": {
                  "key": "e",
                  "value": 2.7182818
                },
                "pi": {
                  "key": "pi",
                  "value": 3.1415926
                }
              },
              "allocations": [
                {
                  "key": "rollout",
                  "doLog": true,
                  "splits": [
                    {
                      "variationKey": "pi",
                      "shards": []
                    }
                  ]
                }
              ],
              "totalShards": 10000
            }
          }
        }
        """

        let configuration = try Configuration(
            flagsConfigurationJson: Data(testJsonString.utf8),
            obfuscated: false
        )

        // Initialize offline with SDK key
        let client1 = EppoClient.initializeOffline(
            sdkKey: "same-sdk-key",
            assignmentLogger: loggerSpy.logger,
            initialConfiguration: configuration
        )

        // Make an assignment that will be cached
        _ = client1.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // Verify the assignment was logged
        XCTAssertEqual(loggerSpy.logCount, 1, "First assignment should be logged")

        // Reinitialize offline with the SAME SDK key - cache should persist
        let client2 = EppoClient.initializeOffline(
            sdkKey: "same-sdk-key",
            assignmentLogger: loggerSpy.logger,
            initialConfiguration: configuration
        )

        // Make the same assignment - this should NOT be logged again since it's the same environment
        _ = client2.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            defaultValue: 0
        )

        // This should pass - no additional logging since we're using the same environment
        XCTAssertEqual(loggerSpy.logCount, 1, "Same assignment with same SDK key should not be logged again due to cache in offline mode")
    }
}