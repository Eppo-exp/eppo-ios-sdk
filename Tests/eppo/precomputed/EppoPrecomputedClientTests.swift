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
    
    // MARK: - Assignment Method Tests
    
    func testGetStringAssignment() {
        let result = EppoPrecomputedClient.shared.getStringAssignment(
            flagKey: "test-flag",
            defaultValue: "default"
        )
        
        // Without initialization, should return default
        XCTAssertEqual(result, "default")
    }
    
    func testGetBooleanAssignment() {
        let result = EppoPrecomputedClient.shared.getBooleanAssignment(
            flagKey: "test-flag",
            defaultValue: true
        )
        
        // Without initialization, should return default
        XCTAssertEqual(result, true)
    }
    
    func testGetIntegerAssignment() {
        let result = EppoPrecomputedClient.shared.getIntegerAssignment(
            flagKey: "test-flag",
            defaultValue: 42
        )
        
        // Without initialization, should return default
        XCTAssertEqual(result, 42)
    }
    
    func testGetNumericAssignment() {
        let result = EppoPrecomputedClient.shared.getNumericAssignment(
            flagKey: "test-flag",
            defaultValue: 3.14
        )
        
        // Without initialization, should return default
        XCTAssertEqual(result, 3.14, accuracy: 0.001)
    }
    
    func testGetJSONStringAssignment() {
        let result = EppoPrecomputedClient.shared.getJSONStringAssignment(
            flagKey: "test-flag",
            defaultValue: "{\"key\":\"value\"}"
        )
        
        // Without initialization, should return default
        XCTAssertEqual(result, "{\"key\":\"value\"}")
    }
    
    func testConcurrentAssignmentCalls() {
        let expectation = XCTestExpectation(description: "Concurrent assignment calls complete")
        expectation.expectedFulfillmentCount = 100
        
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            switch i % 5 {
            case 0:
                _ = EppoPrecomputedClient.shared.getStringAssignment(
                    flagKey: "flag-\(i)",
                    defaultValue: "default-\(i)"
                )
            case 1:
                _ = EppoPrecomputedClient.shared.getBooleanAssignment(
                    flagKey: "flag-\(i)",
                    defaultValue: i % 2 == 0
                )
            case 2:
                _ = EppoPrecomputedClient.shared.getIntegerAssignment(
                    flagKey: "flag-\(i)",
                    defaultValue: i
                )
            case 3:
                _ = EppoPrecomputedClient.shared.getNumericAssignment(
                    flagKey: "flag-\(i)",
                    defaultValue: Double(i) * 0.5
                )
            case 4:
                _ = EppoPrecomputedClient.shared.getJSONStringAssignment(
                    flagKey: "flag-\(i)",
                    defaultValue: "{\"index\":\(i)}"
                )
            default:
                break
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
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