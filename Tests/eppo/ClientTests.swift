import XCTest

import Foundation

@testable import eppo_flagging

class EppoMockHttpClient: EppoHttpClient {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, URLResponse) {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/rac-experiments-v3.json",
            withExtension: ""
        );

        let stringData = try String(contentsOfFile: fileURL!.path);
        return (stringData.data(using: .utf8)!, URLResponse());
    }

    public func post() throws {}
}

class EppoJSONAcceptorClient: EppoHttpClient {
    var jsonResponse: Data?
    
    init(jsonResponse: String) {
        self.jsonResponse = jsonResponse.data(using: .utf8)
    }
    
    func get(_ url: URL) async throws -> (Data, URLResponse) {
        guard let jsonData = jsonResponse else {
            throw URLError(.badServerResponse)
        }
        return (jsonData, URLResponse(url: url, mimeType: "application/json", expectedContentLength: jsonData.count, textEncodingName: nil))
    }
}

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
                    flagKey: self.experiment, 
                    subjectKey: $0.subjectKey,
                    subjectAttributes: $0.subjectAttributes,
                    defaultValue: false
                )
            });
        }

        if let subjects = self.subjects {
            return try subjects.map({ try client.getBoolAssignment(
                flagKey: self.experiment,
                subjectKey: $0,
                defaultValue: false); })
        }

        return [];
    }

    func jsonAssignments(_ client: EppoClient) throws -> [String?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getJSONStringAssignment(
                    flagKey: self.experiment,
                    subjectKey: $0.subjectKey,
                    subjectAttributes: $0.subjectAttributes,
                    defaultValue: ""
                )
            });
        }

        if let subjects = self.subjects {
            return try subjects.map({
                try client.getJSONStringAssignment(
                    flagKey: self.experiment,
                    subjectKey: $0,
                    subjectAttributes: SubjectAttributes(),
                    defaultValue: ""
                );
            })
        }

        return [];
    }

    func numericAssignments(_ client: EppoClient) throws -> [Double?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getNumericAssignment(
                    flagKey: self.experiment,
                    subjectKey: $0.subjectKey,
                    subjectAttributes: $0.subjectAttributes,
                    defaultValue: 0
                )
            });
        }

        if let subjects = self.subjects {
            return try subjects.map({
                try client.getNumericAssignment(
                    flagKey: self.experiment,
                    subjectKey: $0,
                    subjectAttributes: SubjectAttributes(),
                    defaultValue: 0
                );
            })
        }

        return [];
    }

    func stringAssignments(_ client: EppoClient) throws -> [String?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                try client.getStringAssignment(
                    flagKey: self.experiment,
                    subjectKey: $0.subjectKey,
                    subjectAttributes: $0.subjectAttributes,
                    defaultValue: ""
                )
            });
        }

        if let subjects = self.subjects {
            return try subjects.map({
                try client.getStringAssignment(
                    flagKey: self.experiment,
                    subjectKey: $0,
                    subjectAttributes: SubjectAttributes(),
                    defaultValue: ""
                );
            })
        }

        return [];
    }
}

final class eppoClientTests: XCTestCase {
   var loggerSpy: AssignmentLoggerSpy!
   var eppoClient: EppoClient!
   
   override func setUpWithError() throws {
       try super.setUpWithError()
       loggerSpy = AssignmentLoggerSpy()
       eppoClient = EppoClient(apiKey: "mock-api-key",
                               host: "http://localhost:4001",
                               assignmentLogger: loggerSpy.logger)
   }
   
   func testUnloadedClient() async throws {
       XCTAssertThrowsError(try eppoClient.getStringAssignment(
            flagKey: "badFlagRising",
            subjectKey: "abc",
            subjectAttributes: SubjectAttributes(),
            defaultValue: ""))
       {
           error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.configurationNotLoaded)
       };
   }
   
   func testBadFlagKey() async throws {
       try await eppoClient.load(httpClient: EppoMockHttpClient());
       
       XCTAssertThrowsError(try eppoClient.getStringAssignment(
            flagKey: "badFlagRising",
            subjectKey: "def",
            subjectAttributes: SubjectAttributes(),
            defaultValue: ""))
       {
           error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.flagConfigNotFound)
       };
   }
   
   func testLogger() async throws {
       try await eppoClient.load(httpClient: EppoMockHttpClient());
       
       let assignment = try eppoClient.getStringAssignment(
            flagKey: "randomization_algo",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
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
       
       for testFile in testFiles {
           let caseString = try String(contentsOfFile: testFile);
           let caseData = caseString.data(using: .utf8)!;
           let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);
           
           try await eppoClient.load(httpClient: EppoMockHttpClient());
           
           switch (testCase.valueType) {
           case "boolean":
               let assignments = try testCase.boolAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.boolValue() ?? false }
               XCTAssertEqual(assignments, expectedAssignments);
           case "json":
               let assignments = try testCase.jsonAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() ?? "" }
               XCTAssertEqual(assignments, expectedAssignments);
           case "numeric":
               let assignments = try testCase.numericAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.doubleValue() ?? 0 }
               XCTAssertEqual(assignments, expectedAssignments);
           case "string":
               let assignments = try testCase.stringAssignments(eppoClient);
               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() ?? "" }
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
        eppoClient = EppoClient(
                    apiKey: "mock-api-key",
                    host: "http://localhost:4001",
                    assignmentLogger: loggerSpy.logger
                    // InMemoryAssignmentCache is default enabled.
        )
    }
    
    func testLogsDuplicateAssignmentsWithoutCache() async throws {
        // Disable the assignment cache.
        eppoClient = EppoClient(
                    apiKey: "mock-api-key",
                    host: "http://localhost:4001",
                    assignmentLogger: loggerSpy.logger,
                    assignmentCache: nil)
        try await eppoClient.load(httpClient: EppoMockHttpClient());

        _ = try eppoClient.getStringAssignment(
            flagKey: "randomization_algo",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
        _ = try eppoClient.getStringAssignment(
            flagKey: "randomization_algo",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")

        XCTAssertEqual(loggerSpy.logCount, 2, "Should log twice since there is no cache.")
    }

    func testDoesNotLogDuplicateAssignmentsWithCache() async throws {
        try await eppoClient.load(httpClient: EppoMockHttpClient());
        
        _ = try eppoClient.getStringAssignment(
            flagKey: "randomization_algo",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
        _ = try eppoClient.getStringAssignment(
            flagKey: "randomization_algo",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")

        XCTAssertEqual(loggerSpy.logCount, 1, "Should log once due to cache hit.")
    }
    
    func testLogsForEachUniqueFlag() async throws {
        try await eppoClient.load(httpClient: EppoMockHttpClient());
        
        _ =  try eppoClient.getStringAssignment(
            flagKey: "randomization_algo",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
        _ = try eppoClient.getStringAssignment(
            flagKey: "new_user_onboarding",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")

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
        let mockHttpClient = EppoJSONAcceptorClient(jsonResponse: mockJson)
        let eppoClient = EppoClient(apiKey: "your_api_key", host: "http://localhost:4001", assignmentLogger: loggerSpy.logger)
        // Inject the mock HTTP client
        try await eppoClient.load(httpClient: mockHttpClient)
        
        _ = try eppoClient.getStringAssignment(
            flagKey: "feature1",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
        _ = try eppoClient.getStringAssignment(
            flagKey: "feature1",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
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
        try await eppoClient.load(httpClient:  EppoJSONAcceptorClient(jsonResponse: updatedVariationsJson))

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
        try await eppoClient.load(httpClient: EppoJSONAcceptorClient(jsonResponse: newTreatmentJson))


        _ = try eppoClient.getStringAssignment(
            flagKey: "feature1",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
        XCTAssertEqual(loggerSpy.logCount, 2, "Should log again since the allocation changed.")

    }
}
