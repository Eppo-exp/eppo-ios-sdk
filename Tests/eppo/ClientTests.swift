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

struct SubjectWithAttributes : Decodable {
    var subjectKey: String;
    var subjectAttributes: SubjectAttributes;
}

struct AssignmentTestCase : Decodable {
    var experiment: String = "";
    var valueType: String? = "string";
    var subjectsWithAttributes: [SubjectWithAttributes]?
    var subjects: [String]?;
    var expectedAssignments: [EppoValue?];

    func assignments(_ client: EppoClient) throws -> [String?] {
        if self.subjectsWithAttributes != nil {
            return try self.subjectsWithAttributes!.map({
                // todo: make more tests
                try client.getStringAssignment(
                    $0.subjectKey, self.experiment, $0.subjectAttributes
                )
            });
        }

        if self.subjects != nil {
            // todo: make more tests
            return try self.subjects!.map({ try client.getStringAssignment($0, self.experiment); })
        }

        return [];
    }
}

final class eppoClientTests: XCTestCase {
    private var eppoClient: EppoClient = EppoClient("mock-api-key",
                                                    host: "http://localhost:4001");
    
    func testUnloadedClient() async throws {
        // todo: more tests
        XCTAssertThrowsError(try self.eppoClient.getStringAssignment("badFlagRising", "allocation-experiment-1"))
        {
            error in XCTAssertEqual(error as! EppoClient.Errors, EppoClient.Errors.configurationNotLoaded)
        };
    }

    func testBadFlagKey() async throws {
        try await self.eppoClient.load(httpClient: EppoMockHttpClient());

        // todo: more tests
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

            let assignments = try testCase.assignments(self.eppoClient);
            // todo: more tests
            // todo: generic
            let expectedAssignments = testCase.expectedAssignments.map { try? $0?.stringValue() }
            XCTAssertEqual(assignments, expectedAssignments);
        }

        XCTAssertGreaterThan(testFiles.count, 0);
    }
}
