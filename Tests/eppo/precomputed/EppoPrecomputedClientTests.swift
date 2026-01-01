import XCTest
@testable import EppoFlagging

class EppoPrecomputedClientTests: XCTestCase {
    
    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonPattern() throws {
        // Initialize first
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: "salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
        )
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfig
        )
        
        let instance1 = try EppoPrecomputedClient.shared()
        let instance2 = try EppoPrecomputedClient.shared()
        
        XCTAssertTrue(instance1 === instance2, "Should return the same instance")
    }
    
    func testSingletonThrowsWhenNotInitialized() {
        XCTAssertThrowsError(try EppoPrecomputedClient.shared()) { error in
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
    
    // MARK: - Reset Tests
    
    func testResetForTesting() throws {
        // Initialize first
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: "salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
        )
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfig
        )
        
        // Verify initialized
        XCTAssertNoThrow(try EppoPrecomputedClient.shared())
        
        // Reset and verify it throws
        EppoPrecomputedClient.resetForTesting()
        XCTAssertThrowsError(try EppoPrecomputedClient.shared())
    }
    
    func testMultipleResets() throws {
        // Initialize first
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: "salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
        )
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfig
        )
        
        for _ in 0..<5 {
            EppoPrecomputedClient.resetForTesting()
        }
        
        XCTAssertThrowsError(try EppoPrecomputedClient.shared())
    }
    
    // MARK: - Assignment Method Tests
    
    func testAssignmentMethodsThrowWhenNotInitialized() {
        XCTAssertThrowsError(try EppoPrecomputedClient.shared())
    }
    
    func testConcurrentAssignmentCallsReturnDefaults() throws {
        // Initialize first with empty configuration
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: "salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
        )
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfig
        )
        
        let expectation = XCTestExpectation(description: "Concurrent assignment calls complete")
        expectation.expectedFulfillmentCount = 50
        var results: [(String, String)] = []
        let queue = DispatchQueue(label: "test.results", attributes: .concurrent)
        
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            do {
                let client = try EppoPrecomputedClient.shared()
                let result = client.getStringAssignment(
                    flagKey: "flag-\(i)",
                    defaultValue: "default-\(i)"
                )
                
                queue.async(flags: .barrier) {
                    results.append(("flag-\(i)", result))
                }
            } catch {
                XCTFail("Should not throw: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Ensure all barrier operations complete before asserting
        queue.sync(flags: .barrier) {}
        
        XCTAssertEqual(results.count, 50)
        for (flagKey, result) in results {
            let expectedDefault = flagKey.replacingOccurrences(of: "flag-", with: "default-")
            XCTAssertEqual(result, expectedDefault, "Should return default value when flags not found")
        }
    }
    
    func testAssignmentWithSpecialCharactersInFlagKey() throws {
        // Initialize first
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: "salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes)
        )
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfig
        )
        
        let client = try EppoPrecomputedClient.shared()
        let result = client.getStringAssignment(
            flagKey: "test-flag-@#$%^&*()",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }
    
    // MARK: - Polling API Tests
    
    @MainActor
    func testPollingMethodsExist() async {
        // Test that polling methods exist and don't crash when called on uninitialized client
        do {
            try EppoPrecomputedClient.shared().stopPolling()
        } catch {
            // Expected - shared() throws when not initialized
        }
        
        // Starting polling should fail gracefully without network setup
        do {
            try await EppoPrecomputedClient.shared().startPolling()
            XCTFail("Should fail without proper network initialization")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
}
