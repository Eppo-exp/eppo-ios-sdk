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

    // MARK: - Atomic shouldLogAssignment Tests

    func testShouldLogAssignmentInitialCall() {
        let key = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag",
            allocationKey: "allocation1",
            variationKey: "variation1"
        )

        // First call should return true (should log) and mark as logged
        let shouldLog = cache.shouldLogAssignment(key: key)
        XCTAssertTrue(shouldLog, "First call to shouldLogAssignment should return true")
    }

    func testShouldLogAssignmentSecondCall() {
        let key = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag",
            allocationKey: "allocation1", 
            variationKey: "variation1"
        )

        // First call marks as logged
        _ = cache.shouldLogAssignment(key: key)
        
        // Second call should return false (already logged)
        let shouldLogAgain = cache.shouldLogAssignment(key: key)
        XCTAssertFalse(shouldLogAgain, "Second call to shouldLogAssignment should return false")
    }

    func testShouldLogAssignmentDifferentAllocations() {
        let key1 = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag",
            allocationKey: "allocation1", // Different allocation
            variationKey: "variation1"
        )
        let key2 = AssignmentCacheKey(
            subjectKey: "user123", 
            flagKey: "feature-flag",
            allocationKey: "allocation2", // Different allocation
            variationKey: "variation1"
        )

        // First assignment should log and cache allocation1
        XCTAssertTrue(cache.shouldLogAssignment(key: key1))
        
        // Different allocation should also log (overwrites cache with allocation2)  
        XCTAssertTrue(cache.shouldLogAssignment(key: key2))
        
        // Now key1 (allocation1) should log again since cache has allocation2
        XCTAssertTrue(cache.shouldLogAssignment(key: key1))
        
        // key1 (allocation1) should not log again since cache now has allocation1
        XCTAssertFalse(cache.shouldLogAssignment(key: key1))
    }

    func testShouldLogAssignmentDifferentVariations() {
        let key1 = AssignmentCacheKey(
            subjectKey: "user123", 
            flagKey: "feature-flag",
            allocationKey: "allocation1",
            variationKey: "variation1" // Different variation
        )
        let key2 = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag", 
            allocationKey: "allocation1",
            variationKey: "variation2" // Different variation
        )

        // First assignment should log and cache variation1
        XCTAssertTrue(cache.shouldLogAssignment(key: key1))
        
        // Different variation should also log (overwrites cache with variation2)
        XCTAssertTrue(cache.shouldLogAssignment(key: key2))
        
        // Now key1 (variation1) should log again since cache has variation2
        XCTAssertTrue(cache.shouldLogAssignment(key: key1))
        
        // key1 (variation1) should not log again since cache now has variation1
        XCTAssertFalse(cache.shouldLogAssignment(key: key1))
    }

    // MARK: - Race Condition Tests

    func testDeprecatedHasLoggedAssignmentRaceCondition() async throws {
        // This test demonstrates why hasLoggedAssignment + setLastLoggedAssignment is unsafe
        // and why we need the atomic shouldLogAssignment method
        
        let key = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag",
            allocationKey: "allocation1", 
            variationKey: "variation1"
        )
        
        let concurrentTasks = 100
        var loggedCount = 0
        let resultsQueue = DispatchQueue(label: "results.queue")
        
        await withTaskGroup(of: Void.self) { group in
            // Launch many concurrent check-then-act operations using deprecated API
            for _ in 0..<concurrentTasks {
                group.addTask {
                    // This is the UNSAFE pattern that can cause race conditions
                    if !self.cache.hasLoggedAssignment(key: key) {  // Read
                        // Race condition window here! Another thread could slip in
                        try? await Task.sleep(nanoseconds: 1_000_000) // Amplify the race condition window (1ms)
                        self.cache.setLastLoggedAssignment(key: key)  // Write
                        
                        resultsQueue.sync {
                            loggedCount += 1  // Count how many "logged"
                        }
                    }
                }
            }
        }
        
        // EXPECTATION: W/o a race condition, loggedCount should be 1. W/ a race condition, loggedCount will be > 1
        XCTAssertGreaterThan(loggedCount, 1, "Multiple threads should have logged due to race condition, proving the deprecated API is unsafe")
    }


    // MARK: - Legacy setLastLoggedAssignment Test

    func testSetLastLoggedAssignmentCompatibility() {
        let key = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag", 
            allocationKey: "allocation1",
            variationKey: "variation1"
        )

        // Use legacy method to mark as logged
        cache.setLastLoggedAssignment(key: key)
        
        // shouldLogAssignment should now return false
        let shouldLog = cache.shouldLogAssignment(key: key)
        XCTAssertFalse(shouldLog, "shouldLogAssignment should respect setLastLoggedAssignment state")
    }

    func testConcurrentCacheAccess() async throws {
        let iterations = 1000
        let concurrentTasks = 10

        let key = AssignmentCacheKey(
            subjectKey: "user123",
            flagKey: "feature-flag",
            allocationKey: "allocation1", 
            variationKey: "variation1"
        )

        await withTaskGroup(of: Void.self) { group in
            // Add shouldLogAssignment tasks
            for _ in 0..<concurrentTasks {
                group.addTask {
                    for _ in 0..<iterations {
                        _ = self.cache.shouldLogAssignment(key: key)
                    }
                }
            }
        }

        // If we got here without crashing, the test passed
        // The actual values don't matter as much as the fact that we didn't crash
        // due to concurrent access
    }
}
