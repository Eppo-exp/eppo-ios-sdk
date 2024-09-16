import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import eppo_flagging

final class OfflineClientTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!
    
    override func setUp() {
        super.setUp()
        EppoClient.resetSharedInstance()
    }
    
    // Test initializing EppoClient with a local JSON string, performing an assignment,
    // then initializing with a stubbed remote JSON and performing a different assignment.
    func testInitializationWithLocalAndRemoteJSONAssignments() async throws {
        // Step 1: Initialize with local JSON string
        // No allocations.
        let localJsonString = """
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
              "allocations": [],
              "totalShards": 10000
            }
          }
        }
        """
        
        // Initialize EppoClient with local JSON
        eppoClient = try EppoClient.initialize(
            sdkKey: "mock-api-key",
            configurationJson: localJsonString,
            obfuscated: false,
            assignmentLogger: loggerSpy?.logger
        )
        
        // Perform an assignment with the initial client
        let initialAssignment = try eppoClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "alice",
            defaultValue: 100
        )
        
        // Verify the initial assignment
        XCTAssertEqual(initialAssignment, 100, "initial configuration has no allocations; return default value")
        
        // Step 2: Stub the remote JSON response
        let remoteJsonString = """
        {
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": {
            "name": "Test"
          },
          "flags": {
            "2c27190d8645fe3bc3c1d63b31f0e4ee": {
              "key": "2c27190d8645fe3bc3c1d63b31f0e4ee",
              "enabled": true,
              "variationType": "NUMERIC",
              "totalShards": 10000,
              "variations": {
                "ZQ==": {
                  "key": "ZQ==",
                  "value": "Mi43MTgyODE4"
                },
                "cGk=": {
                  "key": "cGk=",
                  "value": "My4xNDE1OTI2"
                }
              },
              "allocations": [
                {
                  "key": "cm9sbG91dA==",
                  "doLog": true,
                  "splits": [
                    {
                      "variationKey": "cGk=",
                      "shards": []
                    }
                  ]
                }
              ]
            }
          }
        }
        """
        
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = remoteJsonString.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Step 3: Re-initialize EppoClient to fetch remote configurations
        eppoClient.takeOnline(sdkKey: "mock-api-key")
        try await eppoClient.load()
        
        // Perform a different assignment with the updated client
        let updatedAssignment = try eppoClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "alice",
            defaultValue: 100
        )
        
        // Verify the updated assignment
        XCTAssertEqual(updatedAssignment, 3.1415926, "Updated assignment uses variation value.")
    }
}
