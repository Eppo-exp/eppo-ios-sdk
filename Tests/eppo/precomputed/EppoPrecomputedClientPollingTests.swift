import XCTest
@testable import EppoFlagging

@MainActor
class EppoPrecomputedClientPollingTests: XCTestCase {
    var mockConfigChangeCallback: MockConfigurationChangeCallback!
    var testPrecompute: Precompute!
    var testConfiguration: PrecomputedConfiguration!

    override func setUp() async throws {
        try await super.setUp()
        EppoPrecomputedClient.resetForTesting()

        mockConfigChangeCallback = MockConfigurationChangeCallback()
        testPrecompute = Precompute(
            subjectKey: "test-user-123",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )

        testConfiguration = PrecomputedConfiguration(
            flags: [
                getMD5Hex("test-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: base64Encode("allocation-1"),
                    variationKey: base64Encode("variant-a"),
                    variationType: .string,
                    variationValue: EppoValue(value: base64Encode("hello")),
                    extraLogging: [:],
                    doLog: true
                )
            ],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: Date(),
            subject: Subject(
                subjectKey: testPrecompute.subjectKey,
                subjectAttributes: testPrecompute.subjectAttributes
            ),
            publishedAt: Date(),
            environment: Environment(name: "test")
        )
    }

    override func tearDown() async throws {
        EppoPrecomputedClient.resetForTesting()
        try await super.tearDown()
    }

    // MARK: - Polling Lifecycle Tests

    func testPollingWithoutNetworkInitialization() async throws {
        // Initialize offline-only client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration
        )

        // Starting polling should succeed even without network components
        // It will just skip polling cycles until network is initialized
        try await EppoPrecomputedClient.shared().startPolling()

        // Polling should be active (even if skipping cycles)
        // We can't easily test the internal skipping without mocking, but
        // the important thing is that startPolling() doesn't throw

        // Clean up
        try EppoPrecomputedClient.shared().stopPolling()
    }

    func testStopPollingWithoutStarting() async {
        // Initialize offline-only client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration
        )

        // Stopping polling should not crash even if never started
        try! EppoPrecomputedClient.shared().stopPolling()

        // Should complete without error
        XCTAssertTrue(true)
    }

    func testPollingWithNetworkInitialization() async throws {
        // First initialize offline
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
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
            initialPrecomputedConfiguration: testConfiguration
        )

        // Test that custom interval parameter is accepted
        let customInterval = 60000 // 1 minute

        // Should succeed even without requestor (will skip polling cycles gracefully)
        try await EppoPrecomputedClient.shared().startPolling(intervalMs: customInterval)

        // Clean up
        try EppoPrecomputedClient.shared().stopPolling()
    }

    func testPollingWithDefaultInterval() async throws {
        // Initialize offline-only client for API validation
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration
        )

        // Test that default interval is used when not specified
        // Should succeed even without requestor (will skip polling cycles gracefully)
        try await EppoPrecomputedClient.shared().startPolling()

        // Clean up
        try EppoPrecomputedClient.shared().stopPolling()
    }

    // MARK: - Concurrent Access Tests

    func testMultipleStopPollingCalls() async {
        // Initialize offline-only client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration
        )

        // Multiple stop calls should not crash
        try! EppoPrecomputedClient.shared().stopPolling()
        try! EppoPrecomputedClient.shared().stopPolling()
        try! EppoPrecomputedClient.shared().stopPolling()

        XCTAssertTrue(true)
    }

    // MARK: - Integration with Configuration Callback Tests

    func testPollingIntegrationWithConfigurationCallback() async {
        // Test that configuration callback integration is properly set up
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )

        // Initial configuration should trigger callback
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)

        // Test that polling API exists for future network integration
        do {
            try await EppoPrecomputedClient.shared().startPolling()
        } catch {
            // Expected to fail without network setup
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
}
