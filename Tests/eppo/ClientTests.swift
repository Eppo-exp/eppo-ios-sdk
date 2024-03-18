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
    
    override func setUp() {
        super.setUp()
        // Initialize loggerSpy here
        loggerSpy = AssignmentLoggerSpy()
        // Now that loggerSpy is initialized, we can use it to initialize eppoClient
        eppoClient = EppoClient("mock-api-key",
                                host: "http://localhost:4001",
                                assignmentLogger: loggerSpy.logger)
    }
    
    func testUnloadedClient() async throws {
        XCTAssertThrowsError(try self.eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
        {
            error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.configurationNotLoaded)
        };
    }

    func testBadFlagKey() async throws {
        try await self.eppoClient.load(httpClient: EppoMockHttpClient());

        XCTAssertThrowsError(try self.eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
        {
            error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.flagConfigNotFound)
        };
    }

    func testAssignments() async throws {
        try await self.eppoClient.load(httpClient: EppoMockHttpClient());

        let testFiles = Bundle.module.paths(
            forResourcesOfType: ".json",
            inDirectory: "Resources/test-data/assignment-v2"
        );

        for testFile in testFiles {
            let caseString = try String(contentsOfFile: testFile);
            let caseData = caseString.data(using: .utf8)!;
            let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);

            switch (testCase.valueType) {
                case "boolean":
                    let assignments = try testCase.boolAssignments(self.eppoClient);
                    let expectedAssignments = testCase.expectedAssignments.map { try? $0?.boolValue() }
                    XCTAssertEqual(assignments, expectedAssignments);
                case "json":
                    let assignments = try testCase.jsonAssignments(self.eppoClient);
                    let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() }
                    XCTAssertEqual(assignments, expectedAssignments);
                case "numeric":
                    let assignments = try testCase.numericAssignments(self.eppoClient);
                    let expectedAssignments = testCase.expectedAssignments.map { try? $0?.doubleValue() }
                    XCTAssertEqual(assignments, expectedAssignments);
                case "string":
                    let assignments = try testCase.stringAssignments(self.eppoClient);
                    let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() }
                    XCTAssertEqual(assignments, expectedAssignments);
                default:
                    XCTFail("Unknown value type: \(testCase.valueType)");
            }
            

            XCTAssertTrue(loggerSpy.wasCalled, "Assignment logger was not called.")
            if let lastAssignment = loggerSpy.lastAssignment {
                XCTAssertTrue(lastAssignment.experiment.contains(lastAssignment.allocation))
                XCTAssertTrue(lastAssignment.experiment.count > lastAssignment.allocation.count)

                XCTAssertTrue(lastAssignment.experiment.contains(lastAssignment.featureFlag))
                XCTAssertTrue(lastAssignment.experiment.count > lastAssignment.featureFlag.count)
            } else {
                XCTFail("No last assignment was logged.")
            }

        }

        XCTAssertGreaterThan(testFiles.count, 0);
    }
}
