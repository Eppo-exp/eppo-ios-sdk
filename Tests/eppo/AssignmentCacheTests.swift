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
    
    func testSetAndGet() {
        let key = "testKey"
        let value = "testValue"
        XCTAssertNil(cache.get(key: key), "Cache should return nil for a key that has not been set.")
        cache.set(key: key, value: value)
        XCTAssertEqual(cache.get(key: key), value, "Cache should return the value that was set for a key.")
    }
    
    func testHas() {
        let key = "testKey"
        XCTAssertFalse(cache.has(key: key), "Cache should return false for a key that has not been set.")
        cache.set(key: key, value: "testValue")
        XCTAssertTrue(cache.has(key: key), "Cache should return true for a key that has been set.")
    }
    
    func testHasLoggedAssignment() {
        let assignmentKey = AssignmentCacheKey(
            subjectKey: "Math", 
            flagKey: "TestFlag",
            allocationKey: "A1",
            variationValue: EppoValue(value: "VariationA")
        )
        
        XCTAssertFalse(cache.hasLoggedAssignment(key: assignmentKey), "Cache should return false for an assignment that has not been logged.")
        
        cache.setLastLoggedAssignment(key: assignmentKey)
        XCTAssertTrue(cache.hasLoggedAssignment(key: assignmentKey), "Cache should return true for an assignment that has been logged.")
    }
}
