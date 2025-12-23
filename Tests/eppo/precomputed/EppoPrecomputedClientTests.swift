import XCTest
@testable import EppoFlagging

class EppoPrecomputedClientTests: XCTestCase {
    
    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonPattern() {
        let instance1 = EppoPrecomputedClient.shared
        let instance2 = EppoPrecomputedClient.shared
        
        XCTAssertTrue(instance1 === instance2, "Should return the same instance")
    }
    
    func testSingletonIsNotNil() {
        XCTAssertNotNil(EppoPrecomputedClient.shared)
    }
    
    // MARK: - Lifecycle Tests
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentSingletonAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        expectation.expectedFulfillmentCount = 100
        var instances: [EppoPrecomputedClient] = []
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let instance = EppoPrecomputedClient.shared
            queue.async(flags: .barrier) {
                instances.append(instance)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Verify all instances are the same (singleton pattern)
        XCTAssertEqual(instances.count, 100)
        let firstInstance = instances[0]
        for instance in instances {
            XCTAssertTrue(firstInstance === instance, "All instances should be the same singleton")
        }
    }
    
    // MARK: - Reset Tests
    
    func testResetForTesting() {
        // This method is internal and used for testing
        // Ensure it doesn't crash and properly resets state
        EppoPrecomputedClient.resetForTesting()
        
        // Verify we can still access the singleton after reset
        XCTAssertNotNil(EppoPrecomputedClient.shared)
    }
    
    func testMultipleResets() {
        // Ensure multiple resets don't cause issues
        for _ in 0..<5 {
            EppoPrecomputedClient.resetForTesting()
        }
        
        XCTAssertNotNil(EppoPrecomputedClient.shared)
    }
    
    // MARK: - Assignment Method Tests
    
    func testAssignmentMethodsReturnDefaultsWhenNotInitialized() {
        // Test that assignment methods return default values when client is not initialized
        XCTAssertEqual(
            EppoPrecomputedClient.shared.getStringAssignment(flagKey: "test-flag", defaultValue: "default"),
            "default"
        )
        XCTAssertEqual(
            EppoPrecomputedClient.shared.getBooleanAssignment(flagKey: "test-flag", defaultValue: true),
            true
        )
    }
    
    func testConcurrentAssignmentCallsReturnDefaults() {
        let expectation = XCTestExpectation(description: "Concurrent assignment calls complete")
        expectation.expectedFulfillmentCount = 50
        var results: [(String, String)] = []
        let queue = DispatchQueue(label: "test.results", attributes: .concurrent)
        
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            let result = EppoPrecomputedClient.shared.getStringAssignment(
                flagKey: "flag-\(i)",
                defaultValue: "default-\(i)"
            )
            
            queue.async(flags: .barrier) {
                results.append(("flag-\(i)", result))
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Verify all calls returned defaults (since client is not initialized)
        XCTAssertEqual(results.count, 50)
        for (flagKey, result) in results {
            let expectedDefault = flagKey.replacingOccurrences(of: "flag-", with: "default-")
            XCTAssertEqual(result, expectedDefault, "Should return default value when not initialized")
        }
    }
    
    func testAssignmentWithEmptyFlagKey() {
        let result = EppoPrecomputedClient.shared.getStringAssignment(
            flagKey: "",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }
    
    func testAssignmentWithSpecialCharactersInFlagKey() {
        let result = EppoPrecomputedClient.shared.getStringAssignment(
            flagKey: "test-flag-@#$%^&*()",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }
}
