import XCTest

import Foundation

@testable import eppo_flagging

class EppoMockHttpClient: EppoHttpClient {
    public init() {}

    public func get(_ url: URL) throws -> (Data, URLResponse) {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/rac-experiments-v2.json",
            withExtension: ""
        );

        let stringData = try String(contentsOfFile: fileURL!.path);
        return (stringData.data(using: .utf8)!, URLResponse());
    }

    public func post() throws {}
}

struct subjectWithAttributes : Decodable {
    var subjectKey: String;
    var subjectAttributes: SubjectAttributes;
}

struct AssignmentTestCase : Decodable {
    public var experiment: String = "";
    var subjectsWithAttributes: [subjectWithAttributes]?
    public var subjects: [String]?;
    public var expectedAssignments: [String?];

    func assignments(_ client: EppoClient) throws -> [String] {
//        if self.subjectsWithAttributes != nil {
//        }

        if self.subjects != nil {

            return try self.subjects!.map({ try client.getAssignment($0, self.experiment); })
        }

        return [];
    }
}

final class eppoClientTests: XCTestCase {
    private var eppoClient: EppoClient = EppoClient("mock-api-key",
                                                    "http://localhost:4001",
                                                    nil,
                                                    nil,
                                                    httpClient: EppoMockHttpClient());
    
    override func setUp() {
        super.setUp();
    }

    func testAssignments() throws {
        let testFiles = Bundle.module.paths(
            forResourcesOfType: ".json",
            inDirectory: "Resources/test-data/assignment-v2"
        );

        for testFile in testFiles {
            let caseString = try String(contentsOfFile: testFile);
            let caseData = caseString.data(using: .utf8)!;
            let testCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);

            let assignments = try testCase.assignments(self.eppoClient);
            XCTAssertEqual(assignments, testCase.expectedAssignments);
        }

        XCTAssertGreaterThan(testFiles.count, 0);
    }
}
