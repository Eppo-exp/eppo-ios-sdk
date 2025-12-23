import XCTest
@testable import EppoFlagging


// Mock configuration change callback
class MockConfigurationChangeCallback {
    private(set) var configurations: [PrecomputedConfiguration] = []
    
    var callback: EppoPrecomputedClient.ConfigurationChangeCallback {
        return { [weak self] configuration in
            self?.configurations.append(configuration)
        }
    }
}

class EppoPrecomputedClientInitializationTests: XCTestCase {
    var mockConfigChangeCallback: MockConfigurationChangeCallback!
    var testSubject: Subject!
    var mockLogger: MockAssignmentLogger!
    
    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        mockConfigChangeCallback = MockConfigurationChangeCallback()
        testSubject = Subject(
            subjectKey: "test-user-123",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )
        mockLogger = MockAssignmentLogger()
    }
    
    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }
    
    // MARK: - Offline Initialization Tests
    
    func testSuccessfulOfflineInitialization() {
        let testConfig = PrecomputedConfiguration(
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
        
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: mockLogger.logger,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )
        
        XCTAssertNotNil(client)
        
        // Verify configuration change callback
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)
        XCTAssertEqual(mockConfigChangeCallback.configurations[0].salt, base64Encode("test-salt"))
        
        // Verify assignment works after offline init
        let result = client.getStringAssignment(
            flagKey: "test-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "hello")
        
        // Verify assignment was logged
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(mockLogger.getLoggedAssignments().count, 1)
    }
    
    func testOfflineInitializationWhenAlreadyInitialized() {
        // First initialization
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
        
        let originalClient = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Second initialization should return existing instance without changing state
        let client2 = EppoPrecomputedClient.initializeOffline(
            sdkKey: "different-key",
            subject: Subject(subjectKey: "different-user"),
            initialPrecomputedConfiguration: testConfig
        )
        
        XCTAssertNotNil(client2)
        // Verify it's the same instance (already initialized behavior)
        XCTAssertTrue(originalClient === client2)
    }
    
    // MARK: - No-Op Logger Tests
    
    func testInitializationWithoutLogger() {
        // This test validates that initialization without logger works (no-op behavior)
        let testConfig = PrecomputedConfiguration(
            flags: [:], // Use empty flags 
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
        
        // Initialize without logger - should not crash, assignments will not be logged
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: nil // No logger - assignments will be silent no-op
        )
        
        XCTAssertNotNil(client)
        
        // Verify client works with default values when no flags present
        let result = client.getStringAssignment(
            flagKey: "nonexistent-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }
    
    // MARK: - Error Handling Tests
    
    func testInitializationCleanupOnError() async {
        // This test would verify that state is cleaned up when initialization fails
        // Currently limited without URLSession injection
        
        // Test that client state is clean after failed initialization
        EppoPrecomputedClient.resetForTesting()
        
        // Verify client returns defaults when not initialized
        let result = EppoPrecomputedClient.shared.getStringAssignment(
            flagKey: "any-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }
    
    // MARK: - Configuration Change Callback Tests
    
    func testConfigurationChangeCallbackIsCalledOnInit() {
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )
        
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)
        XCTAssertEqual(mockConfigChangeCallback.configurations[0].salt, base64Encode("test-salt"))
        XCTAssertEqual(mockConfigChangeCallback.configurations[0].format, "PRECOMPUTED")
    }
    
    // MARK: - Parameter Validation Tests
    
    func testInitializationWithMinimalParameters() {
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
        
        // Should work with just required parameters
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        XCTAssertNotNil(client)
    }
    
    func testDefaultAssignmentCacheIsCreated() {
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"), 
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
        
        // Initialize without providing cache (should create default)
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: mockLogger.logger,
            assignmentCache: nil // Let it create default
        )
        
        // This would be better tested with internal state access
        // For now, just verify initialization succeeds
    }
}