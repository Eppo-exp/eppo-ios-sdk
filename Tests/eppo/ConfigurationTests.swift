import XCTest
@testable import EppoFlagging

final class ConfigurationTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!
    let testJsonString = """
    {
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

    override func setUp() {
        super.setUp()
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()
    }

    // Test initializing with JSON and getting configuration
    func testInitializeWithJsonAndGetConfiguration() throws {
        eppoClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(testJsonString.utf8),
                obfuscated: false
            )
        )

        let configurationObject = eppoClient.getFlagsConfiguration()
        XCTAssertNotNil(configurationObject, "Flags configuration should not be nil")
        XCTAssertNotNil(configurationObject?.getFlag(flagKey: "numeric_flag"), "Should contain numeric_flag")
    }

    // Test initializing a new client with a Configuration object
    func testInitializeWithConfigurationObject() throws {
        // First set up initial client
        eppoClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(testJsonString.utf8),
                obfuscated: false
            )
        )

        let configurationObject = eppoClient.getFlagsConfiguration()
        EppoClient.resetSharedInstance()
        
        let newClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: configurationObject
        )
        
        try XCTAssertNotEqual(newClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            subjectAttributes: [:],
            defaultValue: 0
        ), 0)
    }

    // Test initializing a new client with a JSON string
    func testInitializeWithJsonString() throws {
        // First set up initial client
        eppoClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(testJsonString.utf8),
                obfuscated: false
            )
        )

        guard let flagsConfig = eppoClient.getFlagsConfiguration() else {
            XCTFail("Flags configuration should not be nil")
            return
        }

        let configurationString = try flagsConfig.toJsonString()
        EppoClient.resetSharedInstance()
        
        let newClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(configurationString.utf8),
                obfuscated: false
            )
        )
        
        try XCTAssertNotEqual(newClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "test-subject",
            subjectAttributes: [:],
            defaultValue: 0
        ), 0)
    }

    // Test JSON string equivalence
    func testJsonStringEquivalence() throws {
        // First set up initial client
        eppoClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(testJsonString.utf8),
                obfuscated: false
            )
        )

        guard let flagsConfig = eppoClient.getFlagsConfiguration() else {
            XCTFail("Flags configuration should not be nil")
            return
        }

        let configurationString = try flagsConfig.toJsonString()
        
        let configDict = try JSONSerialization.jsonObject(with: Data(configurationString.utf8)) as! [String: Any]
        let testDict = try JSONSerialization.jsonObject(with: Data(testJsonString.utf8)) as! [String: Any]

        // Compare flags
        let configFlags = configDict["flags"] as! [String: Any]
        let testFlags = testDict["flags"] as! [String: Any]
        XCTAssertEqual(
            NSDictionary(dictionary: configFlags),
            NSDictionary(dictionary: testFlags),
            "Flag configurations should match"
        )

        // Compare createdAt
        let configCreatedAt = configDict["createdAt"] as! String
        let testCreatedAt = testDict["createdAt"] as! String
        XCTAssertEqual(
            configCreatedAt,
            testCreatedAt,
            "CreatedAt timestamps should match"
        )
    }
}
