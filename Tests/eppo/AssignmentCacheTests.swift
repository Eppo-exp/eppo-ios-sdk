import XCTest

@testable import EppoFlagging

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

    func testConcurrentCacheAccess() async throws {
        let iterations = 1000
        let concurrentTasks = 10

        let key = AssignmentCacheKey(
            subjectKey: "Math",
            flagKey: "TestFlag",
            allocationKey: "A1",
            variationKey: "VariationA"
        )

        await withTaskGroup(of: Void.self) { group in
            // Add reader tasks
            for _ in 0..<concurrentTasks {
                group.addTask {
                    for _ in 0..<iterations {
                        _ = self.cache.hasLoggedAssignment(key: key)
                    }
                }
            }

            // Add writer tasks
            for _ in 0..<concurrentTasks {
                group.addTask {
                    for _ in 0..<iterations {
                        self.cache.setLastLoggedAssignment(key: key)
                    }
                }
            }
        }

        // If we got here without crashing, the test passed
        // The actual values don't matter as much as the fact that we didn't crash
        // due to concurrent access
    }
}
