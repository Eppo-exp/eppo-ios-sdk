import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging

let fileURL = Bundle.module.url(
    forResource: "Resources/test-data/ufc/flags-v1.json",
    withExtension: ""
);
let UFCTestJSON: String = try! String(contentsOfFile: fileURL!.path);

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

struct TestSubject : Decodable {
    let subjectKey: String;
    let subjectAttributes: SubjectAttributes;
    let assignment: EppoValue;
}

struct AssignmentTestCase : Decodable {
    var flag: String = "";
    var variationType: UFC_VariationType;
    var defaultValue: EppoValue;
    var subjects: [TestSubject];

    func boolAssignments(_ client: EppoClient) throws -> [Bool?] {
        return try self.subjects.map({ try client.getBoolAssignment(
            flagKey: self.flag,
            subjectKey: $0.subjectKey,
            subjectAttributes: $0.subjectAttributes,
            defaultValue: self.defaultValue.getBoolValue()); })
    }

//    func jsonAssignments(_ client: EppoClient) throws -> [String?] {
//        if let subjects = self.subjects {
//            return try subjects.map({
//                try client.getJSONAssignment(
//                    flagKey: self.experiment,
//                    subjectKey: $0,
//                    subjectAttributes: SubjectAttributes(),
//                    defaultValue: [:]
//                );
//            })
//        }
//
//        return [];
//    }

    func doubleAssignments(_ client: EppoClient) throws -> [Double?] {
        return try self.subjects.map({ try client.getDoubleAssignment(
            flagKey: self.flag,
            subjectKey: $0.subjectKey,
            subjectAttributes: $0.subjectAttributes,
            defaultValue: self.defaultValue.getDoubleValue()
        )})
    }
    
    func intAssignments(_ client: EppoClient) throws -> [Int?] {
        return try self.subjects.map({ try client.getIntegerAssignment(
            flagKey: self.flag,
            subjectKey: $0.subjectKey,
            subjectAttributes: $0.subjectAttributes,
            defaultValue: Int(self.defaultValue.getDoubleValue())
        )})
    }

    func stringAssignments(_ client: EppoClient) throws -> [String?] {
        return try self.subjects.map({ try client.getStringAssignment(
            flagKey: self.flag,
            subjectKey: $0.subjectKey,
            subjectAttributes: $0.subjectAttributes,
            defaultValue: self.defaultValue.getStringValue()); })
    }
}

final class eppoClientTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
    
       stub(condition: isHost("fscdn.eppo.cloud")) { _ in
           let stubData = UFCTestJSON.data(using: .utf8)!
           return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
       }
       
       loggerSpy = AssignmentLoggerSpy()
       eppoClient = EppoClient(apiKey: "mock-api-key", assignmentLogger: loggerSpy.logger)
    
   }
   
   func testLogger() async throws {
       try await eppoClient.load()
       
       let assignment = try eppoClient.getDoubleAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: 0)
       XCTAssertEqual(assignment, 3.1415926)
       XCTAssertTrue(loggerSpy.wasCalled)
       if let lastAssignment = loggerSpy.lastAssignment {
           XCTAssertEqual(lastAssignment.allocation, "rollout")
           XCTAssertEqual(lastAssignment.experiment, "numeric_flag-rollout")
           XCTAssertEqual(lastAssignment.subject, "6255e1a72a84e984aed55668")
       } else {
           XCTFail("No last assignment was logged.")
       }
   }
   
   func testAssignments() async throws {
       let testFiles = Bundle.module.paths(
           forResourcesOfType: ".json",
           inDirectory: "Resources/test-data/ufc/tests"
       );
       
       try await eppoClient.load();
       
       for testFile in testFiles {
           let caseString = try String(contentsOfFile: testFile);
           let caseData = caseString.data(using: .utf8)!;
           let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);
           
           switch (testCase.variationType) {
           case UFC_VariationType.boolean:
               let assignments = try testCase.boolAssignments(eppoClient);
               let expectedAssignments = testCase.subjects.map { try? $0.assignment.getBoolValue() }
               
               if assignments != expectedAssignments {
                    let difference = zip(assignments, expectedAssignments)
                        .filter { $0 != $1 }
                        .map { "(\($0), \($1))" }
                        .joined(separator: ", ")
                    XCTFail("Mismatch for flagKey: \(testCase.flag) - Differences: [\(difference)]")
                } else {
                    XCTAssert(true)
                }
           case UFC_VariationType.json:
                print("json not supported")
//               let assignments = try testCase.jsonAssignments(eppoClient);
//               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() ?? "" }
//               XCTAssertEqual(assignments, expectedAssignments);
           case UFC_VariationType.integer:
               let assignments = try testCase.intAssignments(eppoClient);
               let expectedAssignments = testCase.subjects.map { try? $0.assignment.getDoubleValue() }.compactMap { $0 }.map { Int($0) }
               
                if assignments != expectedAssignments {
                    let difference = zip(assignments, expectedAssignments)
                        .filter { $0 != $1 }
                        .map { "(\(String(describing: $0)), \($1))" }
                        .joined(separator: ", ")
                    XCTFail("Mismatch for flagKey: \(testCase.flag) - Differences: [\(difference)]")
                } else {
                    XCTAssert(true)
                }

           case UFC_VariationType.numeric:
               let assignments = try testCase.doubleAssignments(eppoClient);
               let expectedAssignments = testCase.subjects.map { try? $0.assignment.getDoubleValue() }
               
               if assignments != expectedAssignments {
                let difference = zip(assignments, expectedAssignments)
                    .filter { $0 != $1 }
                    .map { "(\($0), \($1))" }
                    .joined(separator: ", ")
                XCTFail("Mismatch for flagKey: \(testCase.flag) - Differences: [\(difference)]")
            } else {
                XCTAssert(true)
            }
           case UFC_VariationType.string:
               let assignments = try testCase.stringAssignments(eppoClient);
               let expectedAssignments = testCase.subjects.map { try? $0.assignment.getStringValue() }
               
                if assignments != expectedAssignments {
                    let difference = zip(assignments, expectedAssignments)
                        //.filter { $0 != $1 }
                        .map { "(\(String(describing: $0)), \(String(describing: $1)))" }
                        .joined(separator: ", ")
                    XCTFail("Mismatch for flagKey: \(testCase.flag) - Differences: [\(difference)]")
                } else {
                    XCTAssert(true)
                }
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
        eppoClient = EppoClient(apiKey: "mock-api-key",
                    assignmentLogger: loggerSpy.logger
                    // InMemoryAssignmentCache is default enabled.
        )
    }
    
    func testLogsDuplicateAssignmentsWithoutCache() async throws {
        // Disable the assignment cache.
        eppoClient = EppoClient(apiKey: "mock-api-key",
                    assignmentLogger: loggerSpy.logger,
                    assignmentCache: nil)

        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ = try eppoClient.getDoubleAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )
 
        _ = try eppoClient.getDoubleAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )

        XCTAssertEqual(loggerSpy.logCount, 2, "Should log twice since there is no cache.")
    }

    func testDoesNotLogDuplicateAssignmentsWithCache() async throws {
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ = try eppoClient.getDoubleAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )
        _ = try eppoClient.getDoubleAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )

        XCTAssertEqual(loggerSpy.logCount, 1, "Should log once due to cache hit.")
    }
    
    func testLogsForEachUniqueFlag() async throws {
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = UFCTestJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        try await eppoClient.load()
        
        _ =  try eppoClient.getStringAssignment(
            flagKey: "start-and-end-date-test",
            subjectKey: "6255e1a72a84e984aed55668",
            subjectAttributes: SubjectAttributes(),
            defaultValue: "")
        _ = try eppoClient.getDoubleAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )

        XCTAssertEqual(loggerSpy.logCount, 2, "Should log 2 times due to changing flags.")
    }
}
