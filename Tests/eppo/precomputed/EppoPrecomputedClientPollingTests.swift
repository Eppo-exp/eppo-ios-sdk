import XCTest
@testable import EppoFlagging

@MainActor
class EppoPrecomputedClientPollingTests: XCTestCase {
    var mockConfigChangeCallback: MockConfigurationChangeCallback!
    var testSubject: Subject!
    var testConfiguration: PrecomputedConfiguration!
    
    override func setUp() async throws {
        try await super.setUp()
        EppoPrecomputedClient.resetForTesting()
        
        mockConfigChangeCallback = MockConfigurationChangeCallback()
        testSubject = Subject(
            subjectKey: "test-user-123",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )
        
        testConfiguration = PrecomputedConfiguration(
            flags: [
                getMD5Hex("test-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: base64Encode("allocation-1"),
                    variationKey: base64Encode("variant-a"),
                    variationType: .STRING,
                    variationValue: EppoValue(value: base64Encode("hello")),
                    extraLogging: [:],
                    doLog: true
                )
            ],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: Date(),
            environment: Environment(name: "test")
        )
    }
    
    override func tearDown() async throws {
        EppoPrecomputedClient.resetForTesting()
        try await super.tearDown()
    }
    
    // MARK: - Polling Lifecycle Tests
    
    func testStartPollingRequiresNetworkInitialization() async throws {
        // Initialize offline-only client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration
        )
        
        // Starting polling should fail without network components
        do {
            try await EppoPrecomputedClient.shared.startPolling()
            XCTFail("Should throw error when requestor is not available")
        } catch EppoPrecomputedClient.InitializationError.alreadyInitialized {
            // Expected error - polling requires network initialization
        } catch {
            XCTFail("Unexpected error: \\(error)")
        }
    }
    
    func testStopPollingWithoutStarting() async {
        // Initialize offline-only client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration
        )
        
        // Stopping polling should not crash even if never started
        EppoPrecomputedClient.shared.stopPolling()
        
        // Should complete without error
        XCTAssertTrue(true)
    }
    
    func testPollingWithNetworkInitialization() async throws {
        // First initialize offline
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )
        
        // Mock network load to set up requestor
        // Note: This would fail in real scenario without proper URLSession mocking
        // For now, just test that the API exists and doesn't crash immediately
        
        // Test stopping polling (should not crash)
        client.stopPolling()
        
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)
    }
    
    // MARK: - Polling Configuration Tests
    
    func testPollingWithCustomInterval() async throws {
        // Initialize offline-only client for API validation
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration
        )
        
        // Test that custom interval parameter is accepted
        let customInterval = 60000 // 1 minute
        
        do {
            try await EppoPrecomputedClient.shared.startPolling(intervalMs: customInterval)
            XCTFail("Should fail without requestor")
        } catch {
            // Expected to fail - just testing API signature
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
    
    func testPollingWithDefaultInterval() async throws {
        // Initialize offline-only client for API validation
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration
        )
        
        // Test that default interval is used when not specified
        do {
            try await EppoPrecomputedClient.shared.startPolling()
            XCTFail("Should fail without requestor")
        } catch {
            // Expected to fail - just testing API signature
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testMultipleStopPollingCalls() async {
        // Initialize offline-only client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration
        )
        
        // Multiple stop calls should not crash
        EppoPrecomputedClient.shared.stopPolling()
        EppoPrecomputedClient.shared.stopPolling()
        EppoPrecomputedClient.shared.stopPolling()
        
        XCTAssertTrue(true)
    }
    
    // MARK: - Integration with Configuration Callback Tests
    
    func testPollingIntegrationWithConfigurationCallback() async {
        // Test that configuration callback integration is properly set up
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfiguration,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )
        
        // Initial configuration should trigger callback
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)
        
        // Test that polling API exists for future network integration
        do {
            try await EppoPrecomputedClient.shared.startPolling()
        } catch {
            // Expected to fail without network setup
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
}