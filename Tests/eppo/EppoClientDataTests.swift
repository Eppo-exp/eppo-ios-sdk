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

/// Common test case runner that can be used by different evaluator implementations
class CommonCorrectnessTestRunner {
    /// Run assignment correctness tests using the provided client getter
    static func runAssignmentTests(
        obfuscated: Bool,
        clientProvider: (Bool, Data) throws -> Any,
        assignmentTester: (Any, AssignmentTestCase, TestSubject, Bool) -> Void
    ) throws {
        let resourceSuffix = obfuscated ? "-obfuscated" : ""

        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1\(resourceSuffix).json",
            withExtension: ""
        )!
        let testJSON = try Data(contentsOf: fileURL)

        let client = try clientProvider(obfuscated, testJSON)

        let testFiles = Bundle.module.urls(
            forResourcesWithExtension: ".json",
            subdirectory: "Resources/test-data/ufc/tests"
        )!

        for testFile in testFiles {
            let caseData = try Data(contentsOf: testFile)
            let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData)

            testCase.subjects.forEach { subject in
                assignmentTester(client, testCase, subject, obfuscated)
            }
        }

        XCTAssertGreaterThan(testFiles.count, 0)
    }

    /// Test assignment for EppoClient (Legacy/Standard evaluator)
    static func testEppoClientAssignment(client: Any, testCase: AssignmentTestCase, subject: TestSubject, obfuscated: Bool) {
        guard let eppoClient = client as? EppoClient else {
            XCTFail("Expected EppoClient")
            return
        }

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

    /// Test assignment for OptimizedJSON evaluator (via EppoClient)
    static func testOptimizedJSONClientAssignment(client: Any, testCase: AssignmentTestCase, subject: TestSubject, obfuscated: Bool) {
        guard let eppoClient = client as? EppoClient else {
            XCTFail("Expected EppoClient")
            return
        }

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

    /// Generate assertion message for test failures
    static func assertMessage(testCase: AssignmentTestCase, subjectKey: String, obfuscated: Bool) -> String {
        return "FlagKey: \(testCase.flag), SubjectKey: \(subjectKey), Obfuscated: \(obfuscated)"
    }
}

/// Legacy correctness tests using the standard JSON evaluator (formerly EppoClientDataTests)
final class LegacyCorrectnessTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!

    func testAllObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: true,
            clientProvider: createLegacyClient,
            assignmentTester: CommonCorrectnessTestRunner.testEppoClientAssignment
        )
    }

    func testAllNotObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: false,
            clientProvider: createLegacyClient,
            assignmentTester: CommonCorrectnessTestRunner.testEppoClientAssignment
        )
    }

    /// Create EppoClient using standard/legacy JSON evaluator
    private func createLegacyClient(obfuscated: Bool, testJSON: Data) throws -> Any {
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()

        return EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy.logger,
            initialConfiguration: try Configuration(flagsConfigurationJson: testJSON, obfuscated: obfuscated)
        )
    }
}

/// OptimizedJSON correctness tests using the OptimizedJSON evaluator
final class OptimizedJSONCorrectnessTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!
    var eppoClient: EppoClient!

    func testAllObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: true,
            clientProvider: createOptimizedJSONClient,
            assignmentTester: CommonCorrectnessTestRunner.testOptimizedJSONClientAssignment
        )
    }

    func testAllNotObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: false,
            clientProvider: createOptimizedJSONClient,
            assignmentTester: CommonCorrectnessTestRunner.testOptimizedJSONClientAssignment
        )
    }

    /// Create EppoClient using OptimizedJSON evaluator
    private func createOptimizedJSONClient(obfuscated: Bool, testJSON: Data) throws -> Any {
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()

        let configuration = try Configuration(flagsConfigurationJson: testJSON, obfuscated: obfuscated)
        return EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy.logger,
            initialConfiguration: configuration,
            evaluatorType: .optimizedJSON
        )
    }
}

/// Comprehensive data tests - tests correctness for both Legacy and OptimizedJSON evaluators
final class EppoClientDataTests: XCTestCase {
    var loggerSpy: AssignmentLoggerSpy!

    // MARK: - Legacy/Standard Evaluator Tests

    func testLegacyObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: true,
            clientProvider: createLegacyClient,
            assignmentTester: CommonCorrectnessTestRunner.testEppoClientAssignment
        )
    }

    func testLegacyNotObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: false,
            clientProvider: createLegacyClient,
            assignmentTester: CommonCorrectnessTestRunner.testEppoClientAssignment
        )
    }

    // MARK: - OptimizedJSON Evaluator Tests

    func testOptimizedJSONObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: true,
            clientProvider: createOptimizedJSONClient,
            assignmentTester: CommonCorrectnessTestRunner.testOptimizedJSONClientAssignment
        )
    }

    func testOptimizedJSONNotObfuscatedAssignments() async throws {
        try CommonCorrectnessTestRunner.runAssignmentTests(
            obfuscated: false,
            clientProvider: createOptimizedJSONClient,
            assignmentTester: CommonCorrectnessTestRunner.testOptimizedJSONClientAssignment
        )
    }

    // MARK: - Client Providers

    /// Create EppoClient using standard/legacy JSON evaluator
    private func createLegacyClient(obfuscated: Bool, testJSON: Data) throws -> Any {
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()

        return EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: try Configuration(flagsConfigurationJson: testJSON, obfuscated: obfuscated)
        )
    }

    /// Create EppoClient using OptimizedJSON evaluator
    private func createOptimizedJSONClient(obfuscated: Bool, testJSON: Data) throws -> Any {
        loggerSpy = AssignmentLoggerSpy()
        EppoClient.resetSharedInstance()

        let configuration = try Configuration(flagsConfigurationJson: testJSON, obfuscated: obfuscated)
        return EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy?.logger,
            initialConfiguration: configuration,
            evaluatorType: .optimizedJSON
        )
    }
}
