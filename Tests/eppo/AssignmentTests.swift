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

    func testAssignmentWithAllFields() {
        let subjectAttributes = SubjectAttributes()
        let entityId = 67890
        let assignment = Assignment(
            flagKey: "featureE",
            allocationKey: "allocation5",
            variation: "variationD",
            subject: "user202",
            timestamp: "2024-03-23T12:34:56Z",
            subjectAttributes: subjectAttributes,
            extraLogging: ["holdoutKey": "holdout-abc", "holdoutVariation": "all_shipped"], 
            entityId: entityId
        )

        XCTAssertEqual(assignment.entityId, entityId)
        XCTAssertEqual(assignment.extraLogging, ["holdoutKey": "holdout-abc", "holdoutVariation": "all_shipped"])
        XCTAssertEqual(assignment.featureFlag, "featureE")
        XCTAssertEqual(assignment.allocation, "allocation5")
        XCTAssertEqual(assignment.variation, "variationD")
        XCTAssertEqual(assignment.subject, "user202")
    }

    func testAssignmentWithNilHoldoutFields() {
        let subjectAttributes = SubjectAttributes()
        let assignment = Assignment(
            flagKey: "featureF",
            allocationKey: "allocation6",
            variation: "variationE",
            subject: "user303",
            timestamp: "2024-03-24T12:34:56Z",
            subjectAttributes: subjectAttributes
        )

        XCTAssertTrue(assignment.extraLogging.isEmpty)
        XCTAssertNil(assignment.entityId)
        XCTAssertEqual(assignment.featureFlag, "featureF")
        XCTAssertEqual(assignment.allocation, "allocation6")
        XCTAssertEqual(assignment.variation, "variationE")
        XCTAssertEqual(assignment.subject, "user303")
    }
}
