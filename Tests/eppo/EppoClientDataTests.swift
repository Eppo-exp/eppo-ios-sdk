import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import eppo_flagging


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
    
    override func tearDown() {
        super.tearDown()
        HTTPStubs.removeAllStubs()
        EppoClient.resetSharedInstance()
    }

    func testAllObfuscatedAssignments() async throws {
        try await testAssignments(obfuscated: true, useJsonString: false)
    }
    
    func testAllNotObfuscatedAssignments() async throws {
        try await testAssignments(obfuscated: false, useJsonString: false)
    }
    
    func testAllObfuscatedAssignmentsWithJSONString() async throws {
        try await testAssignments(obfuscated: true, useJsonString: true)
    }
    
    func testAllNotObfuscatedAssignmentsWithJSONString() async throws {
        try await testAssignments(obfuscated: false, useJsonString: true)
    }
    
    func setUpTests(resourceName: String, useJsonString: Bool) async throws -> String {
        guard let fileURL = Bundle.module.url(forResource: resourceName, withExtension: "") else {
            XCTFail("Failed to locate \(resourceName) in bundle.")
            throw NSError(domain: "FileNotFound", code: 1, userInfo: nil)
        }
        
        let jsonString = try String(contentsOfFile: fileURL.path)
        
        if !useJsonString {
            stub(condition: isHost("fscdn.eppo.cloud")) { _ in
                let stubData = jsonString.data(using: .utf8)!
                return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
            }
        }
        
        return jsonString
    }
    
    func testAssignments(obfuscated: Bool, useJsonString: Bool) async throws {
        let resourceSuffix = obfuscated ? "-obfuscated" : ""
        let configurationJson = try await setUpTests(resourceName: "Resources/test-data/ufc/flags-v1\(resourceSuffix).json", useJsonString: useJsonString)
        
        let testFiles = Bundle.module.paths(
            forResourcesOfType: ".json",
            inDirectory: "Resources/test-data/ufc/tests"
        );
        
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()
        
        if useJsonString {
            eppoClient = try EppoClient.initialize(
                sdkKey: "mock-api-key",
                configurationJson: configurationJson,
                obfuscated: obfuscated,
                assignmentLogger: loggerSpy.logger
            )
        } else {
            eppoClient = try await EppoClient.initialize(
                sdkKey: "mock-api-key",
                assignmentLogger: loggerSpy.logger
            )
            eppoClient.setConfigObfuscation(obfuscated: obfuscated)
        }
        
        for testFile in testFiles {
            let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: Data(contentsOf: URL(fileURLWithPath: testFile)))
            
            for subject in testCase.subjects {
                try validateAssignment(testCase: testCase, subject: subject, obfuscated: obfuscated)
            }
        }
        
        XCTAssertGreaterThan(testFiles.count, 0);
    }
    
    func validateAssignment(testCase: AssignmentTestCase, subject: TestSubject, obfuscated: Bool) throws {
        let assignment: Any?
        let expectedAssignment: Any?
        
        switch testCase.variationType {
        case .boolean:
            assignment = try? eppoClient.getBooleanAssignment(
                flagKey: testCase.flag,
                subjectKey: subject.subjectKey,
                subjectAttributes: subject.subjectAttributes,
                defaultValue: testCase.defaultValue.getBoolValue()
            )
            expectedAssignment = try? subject.assignment.getBoolValue()
        case .json:
            assignment = try? eppoClient.getJSONStringAssignment(
                flagKey: testCase.flag,
                subjectKey: subject.subjectKey,
                subjectAttributes: subject.subjectAttributes,
                defaultValue: testCase.defaultValue.getStringValue()
            )
            expectedAssignment = try? subject.assignment.getStringValue()
        case .integer:
            assignment = try? eppoClient.getIntegerAssignment(
                flagKey: testCase.flag,
                subjectKey: subject.subjectKey,
                subjectAttributes: subject.subjectAttributes,
                defaultValue: Int(testCase.defaultValue.getDoubleValue())
            )
            expectedAssignment = try? Int(subject.assignment.getDoubleValue())
        case .numeric:
            assignment = try? eppoClient.getNumericAssignment(
                flagKey: testCase.flag,
                subjectKey: subject.subjectKey,
                subjectAttributes: subject.subjectAttributes,
                defaultValue: testCase.defaultValue.getDoubleValue()
            )
            expectedAssignment = try? subject.assignment.getDoubleValue()
        case .string:
            assignment = try? eppoClient.getStringAssignment(
                flagKey: testCase.flag,
                subjectKey: subject.subjectKey,
                subjectAttributes: subject.subjectAttributes,
                defaultValue: testCase.defaultValue.getStringValue()
            )
            expectedAssignment = try? subject.assignment.getStringValue()
        }
        
        XCTAssertEqual(
            assignment as? AnyHashable,
            expectedAssignment as? AnyHashable,
            assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
        )
    }
    
    func assertMessage(testCase: AssignmentTestCase, subjectKey: String, obfuscated: Bool) -> String {
        return "FlagKey: \(testCase.flag), SubjectKey: \(subjectKey), Obfuscated: \(obfuscated)"
    }
}
