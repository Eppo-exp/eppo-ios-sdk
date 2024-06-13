import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging


class AssignmentLoggerSpy {
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

final class EppoClientDataTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!
      
    func testAllAssignments() async throws {
        try await testAssignments(obfuscated: false)
        try await testAssignments(obfuscated: true)
    }
    
    func setUpTestsWithFile(resourceName: String) async throws {
        let fileURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: ""
        )
        let testJSON: String = try! String(contentsOfFile: fileURL!.path)
        
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let stubData = testJSON.data(using: .utf8)!
            return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        loggerSpy = AssignmentLoggerSpy()
        eppoClient = EppoClient(apiKey: "mock-api-key", assignmentLogger: loggerSpy.logger)
    }
    
    func testAssignments(obfuscated: Bool) async throws {
        let resourceSuffix = obfuscated ? "-obfuscated" : ""
           try await setUpTestsWithFile(resourceName: "Resources/test-data/ufc/flags-v1\(resourceSuffix).json")
           
        let testFiles = Bundle.module.paths(
            forResourcesOfType: ".json",
            inDirectory: "Resources/test-data/ufc/tests"
        );

        // set mode for testing
        eppoClient.setConfigObfuscation(obfuscated: obfuscated)
        
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
                        assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
                    )
                case UFC_VariationType.json:
                    let assignment = try? eppoClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subject.subjectAttributes,
                        defaultValue: testCase.defaultValue.getStringValue()
                    );
                    let expectedAssignment = try? subject.assignment.getStringValue()
                    XCTAssertEqual(
                        assignment,
                        expectedAssignment,
                        assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
                    )
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
                        assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
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
                        assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
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
                        assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
                    )
                }
            }
        }
        
        XCTAssertGreaterThan(testFiles.count, 0);
    }
    
    func assertMessage(testCase: AssignmentTestCase, subjectKey: String, obfuscated: Bool) -> String {
        return "FlagKey: \(testCase.flag), SubjectKey: \(subjectKey), Obfuscated: \(obfuscated)"
    }
}
