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

class AssignmentLoggerSpy {
    var wasCalled = false
    var lastAssignment: Assignment?

    func logger(assignment: Assignment) {
        wasCalled = true
        lastAssignment = assignment
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
        loggerSpy = AssignmentLoggerSpy()
        eppoClient = EppoClient("mock-api-key",
                                host: "http://localhost:4001",
                                assignmentLogger: loggerSpy.logger)
    }
 
    func testUnloadedClient() async throws {
        XCTAssertThrowsError(try eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
        {
            error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.configurationNotLoaded)
        };
    }

    func testBadFlagKey() async throws {
        try await eppoClient.load(httpClient: EppoMockHttpClient());

        XCTAssertThrowsError(try eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
        {
            error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.flagConfigNotFound)
        };
    }

    func testLogger() async throws {
        try await eppoClient.load(httpClient: EppoMockHttpClient());

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

        for testFile in testFiles {
            let caseString = try String(contentsOfFile: testFile);
            let caseData = caseString.data(using: .utf8)!;
            let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);

            try await eppoClient.load(httpClient: EppoMockHttpClient());

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
