import XCTest

@testable import eppo_flagging

final class AssignmentTests: XCTestCase {
    func testAssignmentInitialization() {
        let subjectAttributes = SubjectAttributes()
        let assignment = Assignment(
            flagKey: "featureA",
            allocationKey: "allocation1",
            variation: "variationB",
            subject: "user123",
            timestamp: "2024-03-19T12:34:56Z",
            subjectAttributes: subjectAttributes
        )
        
        XCTAssertEqual(assignment.allocation, "allocation1")
        XCTAssertEqual(assignment.experiment, "featureA-allocation1")
        XCTAssertEqual(assignment.featureFlag, "featureA")
        XCTAssertEqual(assignment.variation, "variationB")
        XCTAssertEqual(assignment.subject, "user123")
        XCTAssertEqual(assignment.timestamp, "2024-03-19T12:34:56Z")
        XCTAssertEqual(assignment.subjectAttributes, subjectAttributes)
    }
    
    func testAssignmentDescription() {
        let subjectAttributes = SubjectAttributes()
        let assignment = Assignment(
            flagKey: "featureB",
            allocationKey: "allocation2",
            variation: "variationA",
            subject: "user456",
            timestamp: "2024-03-20T12:34:56Z",
            subjectAttributes: subjectAttributes
        )
        
        let expectedDescription = "Subject user456 assigned to variation variationA in experiment featureB-allocation2"
        XCTAssertEqual(assignment.description, expectedDescription)
    }
}
