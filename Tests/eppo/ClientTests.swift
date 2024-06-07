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
        
        let assignment = try eppoClient.getNumericAssignment(
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
            
            testCase.subjects.forEach { subject in
                switch testCase.variationType {
                case UFC_VariationType.boolean:
                    let assignment = try? eppoClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subject.subjectAttributes,
                        defaultValue: testCase.defaultValue.getBoolValue()
                    );
                    let expectedAssignment = try? subject.assignment.getBoolValue()
                    XCTAssertEqual(
                        assignment,
                        expectedAssignment,
                        "FlagKey: \(testCase.flag), SubjectKey: \(subject.subjectKey)"
                    )
                case UFC_VariationType.json:
                    print("json not supported")
                    //               let assignments = try testCase.jsonAssignments(eppoClient);
                    // //               let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() ?? "" }
                    // //               XCTAssertEqual(assignments, expectedAssignments);
                case UFC_VariationType.integer:
                    let assignment = try? eppoClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subject.subjectAttributes,
                        defaultValue: Int(testCase.defaultValue.getDoubleValue())
                    );
                    let expectedAssignment = try? Int(subject.assignment.getDoubleValue())
                    XCTAssertEqual(
                        assignment,
                        expectedAssignment,
                        "FlagKey: \(testCase.flag), SubjectKey: \(subject.subjectKey)"
                    )
                case UFC_VariationType.numeric:
                    let assignment = try? eppoClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subject.subjectAttributes,
                        defaultValue: testCase.defaultValue.getDoubleValue()
                    );
                    let expectedAssignment = try? subject.assignment.getDoubleValue()
                    XCTAssertEqual(
                        assignment,
                        expectedAssignment,
                        "FlagKey: \(testCase.flag), SubjectKey: \(subject.subjectKey)"
                    )
                case UFC_VariationType.string:
                    let assignment = try? eppoClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subject.subjectAttributes,
                        defaultValue: testCase.defaultValue.getStringValue()
                    );
                    let expectedAssignment = try? subject.assignment.getStringValue()
                    XCTAssertEqual(
                        assignment,
                        expectedAssignment,
                        "FlagKey: \(testCase.flag), SubjectKey: \(subject.subjectKey)"
                    )
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
        
        _ = try eppoClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )
        
        _ = try eppoClient.getNumericAssignment(
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
        
        _ = try eppoClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )
        _ = try eppoClient.getNumericAssignment(
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
        _ = try eppoClient.getNumericAssignment(
            flagKey: "numeric_flag",
            subjectKey: "6255e1a72a84e984aed55668",
            defaultValue: 0
        )
        
        XCTAssertEqual(loggerSpy.logCount, 2, "Should log 2 times due to changing flags.")
    }
}
