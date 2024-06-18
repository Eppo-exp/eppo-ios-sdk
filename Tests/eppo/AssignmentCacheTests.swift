import XCTest

@testable import eppo_flagging

final class AssignmentCacheTests: XCTestCase {
    var cache: InMemoryAssignmentCache!
    
    override func setUp() {
        super.setUp()
        
        cache = InMemoryAssignmentCache()
    }
    
    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    func testOscillatingAllocation() {
        let key1 = AssignmentCacheKey(
            subjectKey: "Math", 
            flagKey: "TestFlag",
            allocationKey: "A1", // initial
            variationKey: "VariationA"
        )
        let key2 = AssignmentCacheKey(
            subjectKey: "Math", 
            flagKey: "TestFlag",
            allocationKey: "A2", // changes
            variationKey: "VariationA"
        )

        cache.setLastLoggedAssignment(key: key1)
        XCTAssertTrue(cache.hasLoggedAssignment(key: key1))
        XCTAssertFalse(cache.hasLoggedAssignment(key: key2))

        cache.setLastLoggedAssignment(key: key2)
        XCTAssertFalse(cache.hasLoggedAssignment(key: key1))
        XCTAssertTrue(cache.hasLoggedAssignment(key: key2))

        cache.setLastLoggedAssignment(key: key1)
        XCTAssertTrue(cache.hasLoggedAssignment(key: key1))
        XCTAssertFalse(cache.hasLoggedAssignment(key: key2))

        cache.setLastLoggedAssignment(key: key2)
        XCTAssertFalse(cache.hasLoggedAssignment(key: key1))
        XCTAssertTrue(cache.hasLoggedAssignment(key: key2))
    }
    
    func testOscillatingVariations() {
        let key1 = AssignmentCacheKey(
            subjectKey: "Math",
            flagKey: "TestFlag",
            allocationKey: "A1",
            variationKey: "VariationA"  // initial
        )
        let key2 = AssignmentCacheKey(
            subjectKey: "Math",
            flagKey: "TestFlag",
            allocationKey: "A1",
            variationKey: "VariationB"  // changes
        )

        cache.setLastLoggedAssignment(key: key1)
        XCTAssertTrue(cache.hasLoggedAssignment(key: key1))
        XCTAssertFalse(cache.hasLoggedAssignment(key: key2))

        cache.setLastLoggedAssignment(key: key2)
        XCTAssertFalse(cache.hasLoggedAssignment(key: key1))
        XCTAssertTrue(cache.hasLoggedAssignment(key: key2))

        cache.setLastLoggedAssignment(key: key1)
        XCTAssertTrue(cache.hasLoggedAssignment(key: key1))
        XCTAssertFalse(cache.hasLoggedAssignment(key: key2))

        cache.setLastLoggedAssignment(key: key2)
        XCTAssertFalse(cache.hasLoggedAssignment(key: key1))
        XCTAssertTrue(cache.hasLoggedAssignment(key: key2))
    }
}
