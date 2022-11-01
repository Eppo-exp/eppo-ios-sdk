import XCTest

@testable import eppo_flagging

class EppoMockHttpClient: EppoHttpClient {
    public init() {}

    public func get() throws {}
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
    public var expectedAssignments: [String?]?;
}

final class eppoClientTests: XCTestCase {
    private var eppoHttpClient: EppoHttpClient = EppoMockHttpClient();
    private var eppoClient: EppoClient?;
    
    override func setUp() {
        super.setUp();

        try? eppoClient = EppoClient(
            "mock-api-key",
            "http://localhost:4001",
            nil,
            nil
        );
    }

    func testAssignments() throws {
        let testFiles = Bundle.module.paths(
            forResourcesOfType: ".json",
            inDirectory: "Resources/test-data/assignment-v2"
        );

        for testFile in testFiles {
            let caseString = try String(contentsOfFile: testFile);
            let caseData = caseString.data(using: .utf8)!;
            let AssignmentTestCase = try JSONDecoder().decode(AssignmentTestCase.self, from: caseData);
        }

        XCTAssertGreaterThan(testFiles.count, 0);
    }
}
