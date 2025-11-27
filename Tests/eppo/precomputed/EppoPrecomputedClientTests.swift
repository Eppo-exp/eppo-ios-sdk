import XCTest
@testable import EppoFlagging

class EppoPrecomputedClientTests: XCTestCase {
    
    override func tearDown() {
        // Reset singleton state after each test
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
    
    func testStopPolling() async {
        // This test just ensures the method exists and doesn't crash
        // More detailed testing will be added when polling is implemented
        await EppoPrecomputedClient.shared.stopPolling()
    }
    
    // MARK: - Thread Safety Tests
    
    func testThreadSafetyDuringConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        expectation.expectedFulfillmentCount = 100
        
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = EppoPrecomputedClient.shared
            // Can't call stopPolling here as it's @MainActor
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
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
}