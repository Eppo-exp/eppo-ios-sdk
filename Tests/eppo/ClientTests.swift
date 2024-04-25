import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging

let fileURL = Bundle.module.url(
    forResource: "Resources/test-data/rac-experiments-v3.json",
    withExtension: ""
);
let RacTestJSON: String = try! String(contentsOfFile: fileURL!.path);

public class AssignmentLoggerSpy {
    var wasCalled = false
    var lastAssignment: Assignment?
    var logCount = 0

    func logger(assignment: Assignment) {
        wasCalled = true
        lastAssignment = assignment
        logCount += 1
    }
}

struct SubjectWithAttributes : Decodable {
    var subjectKey: String;
    var subjectAttributes: SubjectAttributes;
}

struct AssignmentTestCase : Decodable {
    var experiment: String = "";
    var valueType: String;

    var subjectsWithAttributes: [SubjectWithAttributes]?
    var subjects: [String]?;
    var expectedAssignments: [EppoValue?];

    func boolAssignments(_ client: EppoClient) throws -> [Bool?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getBoolAssignment(
                    $0.subjectKey, self.experiment, $0.subjectAttributes
                )
            });
        }

        if self.subjects != nil {
            return try self.subjects!.map({ try client.getBoolAssignment($0, self.experiment); })
        }

        return [];
    }

    func jsonAssignments(_ client: EppoClient) throws -> [String?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getJSONStringAssignment(
                    $0.subjectKey, self.experiment, $0.subjectAttributes
                )
            });
        }

        if self.subjects != nil {
            return try self.subjects!.map({ try client.getJSONStringAssignment($0, self.experiment); })
        }

        return [];
    }

    func numericAssignments(_ client: EppoClient) throws -> [Double?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getNumericAssignment(
                    $0.subjectKey, self.experiment, $0.subjectAttributes
                )
            });
        }

        if self.subjects != nil {
            return try self.subjects!.map({ try client.getNumericAssignment($0, self.experiment); })
        }

        return [];
    }

    func stringAssignments(_ client: EppoClient) throws -> [String?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getStringAssignment(
                    $0.subjectKey, self.experiment, $0.subjectAttributes
                )
            });
        }

        if self.subjects != nil {
            return try self.subjects!.map({ try client.getStringAssignment($0, self.experiment); })
        }

        return [];
    }
}

final class eppoClientTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
    
       stub(condition: isHost("fscdn.eppo.cloud")) { _ in
           let stubData = RacTestJSON.data(using: .utf8)!
           return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
       }
       
       loggerSpy = AssignmentLoggerSpy()
       eppoClient = EppoClient("mock-api-key", assignmentLogger: loggerSpy.logger)
    
   }
   
   func testUnloadedClient() async throws {
       XCTAssertThrowsError(try eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
       {
           error in XCTAssertEqual(error as! Errors, Errors.configurationNotLoaded)
       };
   }
   
   func testBadFlagKey() async throws {
       try await eppoClient.load()
       
       XCTAssertThrowsError(try eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
       {
           error in XCTAssertEqual(error as! Errors, Errors.flagConfigNotFound)
       };
   }
   
   func testLogger() async throws {
       try await eppoClient.load()
       
       let assignment = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "randomization_algo")
       XCTAssertEqual(assignment, "red")
       XCTAssertTrue(loggerSpy.wasCalled)
       if let lastAssignment = loggerSpy.lastAssignment {
           XCTAssertEqual(lastAssignment.allocation, "allocation-experiment-1")
           XCTAssertEqual(lastAssignment.experiment, "randomization_algo-allocation-experiment-1")
           XCTAssertEqual(lastAssignment.subject, "6255e1a72a84e984aed55668")
       } else {
           XCTFail("No last assignment was logged.")
       }
   }
   
   func testAssignments() async throws {
       let testFiles = Bundle.module.paths(
           forResourcesOfType: ".json",
           inDirectory: "Resources/test-data/assignment-v2"
       );
       
       try await eppoClient.load();
       
       for testFile in testFiles {
           let caseString = try String(contentsOfFile: testFile);
           let caseData = caseString.data(using: .utf8)!;
           let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);
           
           switch (testCase.valueType) {
           case "boolean":
               let assignments = try testCase.boolAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.boolValue() }
               XCTAssertEqual(assignments, expectedAssignments);
           case "json":
               let assignments = try testCase.jsonAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() }
               XCTAssertEqual(assignments, expectedAssignments);
           case "numeric":
               let assignments = try testCase.numericAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.doubleValue() }
               XCTAssertEqual(assignments, expectedAssignments);
           case "string":
               let assignments = try testCase.stringAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() }
               XCTAssertEqual(assignments, expectedAssignments);
           default:
               XCTFail("Unknown value type: \(testCase.valueType)");
           }
       }
       
       XCTAssertGreaterThan(testFiles.count, 0);
   }
}

final class EppoClientAssignmentCachingTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        loggerSpy = AssignmentLoggerSpy()
        eppoClient = EppoClient("mock-api-key",
                    assignmentLogger: loggerSpy.logger
                    // InMemoryAssignmentCache is default enabled.
        )
    }
    
    func testLogsDuplicateAssignmentsWithoutCache() async throws {
        // Disable the assignment cache.
        eppoClient = EppoClient("mock-api-key",
                    assignmentLogger: loggerSpy.logger,
                    assignmentCache: nil)

        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = RacTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "randomization_algo")
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "randomization_algo")

        XCTAssertEqual(loggerSpy.logCount, 2, "Should log twice since there is no cache.")
    }

    func testDoesNotLogDuplicateAssignmentsWithCache() async throws {
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = RacTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "randomization_algo")
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "randomization_algo")

        XCTAssertEqual(loggerSpy.logCount, 1, "Should log once due to cache hit.")
    }
    
    func testLogsForEachUniqueFlag() async throws {
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = RacTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "randomization_algo")
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "new_user_onboarding")

        XCTAssertEqual(loggerSpy.logCount, 2, "Should log 2 times due to changing flags.")
    }
    
    func testLoggingWhenRolloutIncreases() async throws {
        let mockJson = """
            {
                "flags": {
                    "feature1": {
                        "subjectShards": 10000,
                        "typedOverrides": {},
                        "enabled": true,
                        "rules": [
                            {
                                "allocationKey": "allocation-experiment-1",
                                "conditions": []
                            }
                        ],
                        "allocations": {
                            "allocation-experiment-1": {
                            "percentExposure": 1,
                            "statusQuoVariationKey": null,
                            "shippedVariationKey": null,
                            "variations": [
                                {
                                    "name": "control",
                                    "value": "control",
                                    "typedValue": "control",
                                    "shardRange": {
                                        "start": 0,
                                        "end": 3333
                                    },
                                    "algorithmType": "CONSTANT"
                                },
                                {
                                    "name": "red",
                                    "value": "red",
                                    "typedValue": "red",
                                    "shardRange": {
                                        "start": 3333,
                                        "end": 6666
                                    },
                                    "algorithmType": "CONSTANT"
                                },
                                {
                                    "name": "green",
                                    "value": "green",
                                    "typedValue": "green",
                                    "shardRange": {
                                        "start": 6666,
                                        "end": 10000
                                    },
                                    "algorithmType": "CONSTANT"
                                }
                            ]
                            }
                        }
                    }
                }
            }
        """
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            return HTTPStubsResponse(data: mockJson.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "feature1")
        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "feature1")
        XCTAssertEqual(loggerSpy.logCount, 1, "Should log once with the cache.")

        // update the allocation
        let updatedVariationsJson = """
            {
                "flags": {
                    "feature1": {
                        "subjectShards": 10000,
                        "typedOverrides": {},
                        "enabled": true,
                        "rules": [
                            {
                                "allocationKey": "allocation-experiment-1",
                                "conditions": []
                            }
                        ],
                        "allocations": {
                            "allocation-experiment-1": {
                            "percentExposure": 1,
                            "statusQuoVariationKey": null,
                            "shippedVariationKey": null,
                            "variations": [
                                {
                                    "name": "control",
                                    "value": "control",
                                    "typedValue": "control",
                                    "shardRange": {
                                        "start": 0,
                                        "end": 0
                                    },
                                    "algorithmType": "CONSTANT"
                                },
                                {
                                    "name": "green",
                                    "value": "green",
                                    "typedValue": "green",
                                    "shardRange": {
                                        "start": 0,
                                        "end": 10000
                                    },
                                    "algorithmType": "CONSTANT"
                                }
                            ]
                            }
                        }
                    }
                }
            }
        """
        // Reload the EppoClient with the updated configuration
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            return HTTPStubsResponse(data: updatedVariationsJson.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()

        // update the allocation
        let newTreatmentJson = """
            {
                "flags": {
                    "feature1": {
                        "subjectShards": 10000,
                        "typedOverrides": {},
                        "enabled": true,
                        "rules": [
                            {
                                "allocationKey": "allocation-experiment-1",
                                "conditions": []
                            }
                        ],
                        "allocations": {
                            "allocation-experiment-1": {
                            "percentExposure": 1,
                            "statusQuoVariationKey": null,
                            "shippedVariationKey": null,
                            "variations": [
                                {
                                    "name": "new-treatment",
                                    "value": "new-treatment",
                                    "typedValue": "new-treatment",
                                    "shardRange": {
                                        "start": 0,
                                        "end": 10000
                                    },
                                    "algorithmType": "CONSTANT"
                                }
                            ]
                            }
                        }
                    }
                }
            }
        """
        // Reload the EppoClient with the updated configuration
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            return HTTPStubsResponse(data: newTreatmentJson.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()

        _ = try eppoClient.getStringAssignment("6255e1a72a84e984aed55668", "feature1")
        XCTAssertEqual(loggerSpy.logCount, 2, "Should log again since the allocation changed.")
    }
}
