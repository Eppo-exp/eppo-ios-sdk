import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import EppoFlagging

struct TestSubject: Decodable {
    let subjectKey: String
    let subjectAttributes: SubjectAttributes
    let assignment: EppoValue
}

struct AssignmentTestCase: Decodable {
    var flag: String = ""
    var variationType: UFC_VariationType
    var defaultValue: EppoValue
    var subjects: [TestSubject]
}

final class EppoClientDataTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!

    func testAllObfuscatedAssignments() async throws {
        try await testAssignments(obfuscated: true)
    }

    func testAllNotObfuscatedAssignments() async throws {
        try await testAssignments(obfuscated: false)
    }

    func setUpTestsWithFile(resourceName: String, obfuscated: Bool) throws {
        let fileURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: ""
        )!
        let testJSON = try! Data(contentsOf: fileURL)

        loggerSpy = AssignmentLoggerSpy()

        EppoClient.resetSharedInstance()

        eppoClient = EppoClient.initializeOffline(
          sdkKey: "mock-api-key",
          assignmentLogger: loggerSpy.logger,
          initialConfiguration:
            try Configuration.init(flagsConfigurationJson: testJSON, obfuscated: obfuscated)
        )
    }

    func testAssignments(obfuscated: Bool) async throws {
        let resourceSuffix = obfuscated ? "-obfuscated" : ""

        try setUpTestsWithFile(
          resourceName: "Resources/test-data/ufc/flags-v1\(resourceSuffix).json",
          obfuscated: obfuscated
        )

        let testFiles = Bundle.module.urls(
            forResourcesWithExtension: ".json",
            subdirectory: "Resources/test-data/ufc/tests"
        )!

        for testFile in testFiles {
            let caseData = try! Data(contentsOf: testFile)
            let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData)

            testCase.subjects.forEach { subject in
                switch testCase.variationType {
                case UFC_VariationType.boolean:
                    let assignment = try? eppoClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subject.subjectAttributes,
                        defaultValue: testCase.defaultValue.getBoolValue()
                    )
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
                    )
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
                    )
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
                    )
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
                    )
                    let expectedAssignment = try? subject.assignment.getStringValue()
                    XCTAssertEqual(
                        assignment,
                        expectedAssignment,
                        assertMessage(testCase: testCase, subjectKey: subject.subjectKey, obfuscated: obfuscated)
                    )
                }
            }
        }

        XCTAssertGreaterThan(testFiles.count, 0)
    }

    func assertMessage(testCase: AssignmentTestCase, subjectKey: String, obfuscated: Bool) -> String {
        return "FlagKey: \(testCase.flag), SubjectKey: \(subjectKey), Obfuscated: \(obfuscated)"
    }
}
