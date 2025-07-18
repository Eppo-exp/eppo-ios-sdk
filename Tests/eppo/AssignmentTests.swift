import XCTest

@testable import EppoFlagging

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

    func testAssignmentWithEntityId() {
        let subjectAttributes = SubjectAttributes()
        let entityId = 12345
        let assignment = Assignment(
            flagKey: "featureC",
            allocationKey: "allocation3",
            variation: "variationB",
            subject: "user789",
            timestamp: "2024-03-21T12:34:56Z",
            subjectAttributes: subjectAttributes,
            entityId: entityId
        )

        XCTAssertTrue(assignment.extraLogging.isEmpty)
        XCTAssertEqual(assignment.entityId, entityId)
        XCTAssertEqual(assignment.featureFlag, "featureC")
        XCTAssertEqual(assignment.allocation, "allocation3")
        XCTAssertEqual(assignment.variation, "variationB")
        XCTAssertEqual(assignment.subject, "user789")
    }

    func testAssignmentWithHoldoutFields() {
        let subjectAttributes = SubjectAttributes()
        let assignment = Assignment(
            flagKey: "featureD",
            allocationKey: "allocation4",
            variation: "variationC",
            subject: "user101",
            timestamp: "2024-03-22T12:34:56Z",
            subjectAttributes: subjectAttributes,
            extraLogging: ["holdoutKey": "holdout-xyz", "holdoutVariation": "status_quo"]
        )

        XCTAssertEqual(assignment.extraLogging, ["holdoutKey": "holdout-xyz", "holdoutVariation": "status_quo"])
        XCTAssertEqual(assignment.featureFlag, "featureD")
        XCTAssertEqual(assignment.allocation, "allocation4")
        XCTAssertEqual(assignment.variation, "variationC")
        XCTAssertEqual(assignment.subject, "user101")
    }
}
