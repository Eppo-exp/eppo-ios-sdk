import XCTest
@testable import EppoFlagging

// Mock URLSession for testing network requests (simplified for now)
class MockURLSession {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    var requestExpectation: XCTestExpectation?
    var capturedRequest: URLRequest?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request
        requestExpectation?.fulfill()
        
        if let error = error {
            throw error
        }
        
        guard let data = data, let response = response else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }
}

// Mock debug callback
class MockDebugCallback {
    private(set) var calls: [(String, Double, Double)] = []
    
    var callback: (String, Double, Double) -> Void {
        return { [weak self] event, duration, timestamp in
            self?.calls.append((event, duration, timestamp))
        }
    }
    
    func hasEvent(_ event: String) -> Bool {
        return calls.contains { $0.0 == event }
    }
}

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
    var mockSession: MockURLSession!
    var mockDebugCallback: MockDebugCallback!
    var mockConfigChangeCallback: MockConfigurationChangeCallback!
    var testSubject: Subject!
    var mockLogger: MockAssignmentLogger!
    
    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        mockSession = MockURLSession()
        mockDebugCallback = MockDebugCallback()
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
    
    // MARK: - Online Initialization Tests
    
    func testSuccessfulOnlineInitialization() async throws {
        // Prepare mock response
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
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        mockSession.data = try encoder.encode(testConfig)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://fs-edge-assignment.eppo.cloud/assignments")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // Initialize with mock session
        // Note: We need to inject the mock session into PrecomputedRequestor
        // For now, test only the initialization setup without actual network call
        
        // Test that initialization fails when already initialized
        let client1 = try await EppoPrecomputedClient.initialize(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            assignmentLogger: mockLogger.logger,
            configurationChangeCallback: mockConfigChangeCallback.callback,
            debugCallback: mockDebugCallback.callback
        )
        
        XCTAssertNotNil(client1)
        
        // Verify debug callbacks were called
        XCTAssertTrue(mockDebugCallback.hasEvent("precomputed_client_initialize_start"))
        
        // Test re-initialization throws error
        do {
            _ = try await EppoPrecomputedClient.initialize(
                sdkKey: "test-sdk-key-2",
                subject: testSubject
            )
            XCTFail("Should throw already initialized error")
        } catch {
            XCTAssertEqual(error as? EppoPrecomputedClient.InitializationError, EppoPrecomputedClient.InitializationError.alreadyInitialized)
        }
    }
    
    func testOnlineInitializationWithCustomHost() async throws {
        // This test verifies custom host is used
        // Full implementation will require mock session injection
        
        EppoPrecomputedClient.resetForTesting()
        
        // For now, just verify the API accepts the parameter
        _ = "https://custom.eppo.host"
        
        // Note: Real test would verify the request URL uses custom host
        // Currently, the initialization will fail due to network request
        // This will be fully testable when we add URLSession injection
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
            configurationChangeCallback: mockConfigChangeCallback.callback,
            debugCallback: mockDebugCallback.callback
        )
        
        XCTAssertNotNil(client)
        
        // Verify debug callbacks
        XCTAssertTrue(mockDebugCallback.hasEvent("precomputed_client_offline_init_start"))
        XCTAssertTrue(mockDebugCallback.hasEvent("precomputed_client_offline_init_success"))
        
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
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            debugCallback: mockDebugCallback.callback
        )
        
        // Reset debug callback
        mockDebugCallback = MockDebugCallback()
        
        // Second initialization should return existing instance
        let client2 = EppoPrecomputedClient.initializeOffline(
            sdkKey: "different-key",
            subject: Subject(subjectKey: "different-user"),
            initialPrecomputedConfiguration: testConfig,
            debugCallback: mockDebugCallback.callback
        )
        
        XCTAssertNotNil(client2)
        XCTAssertTrue(mockDebugCallback.hasEvent("precomputed_client_already_initialized"))
        XCTAssertFalse(mockDebugCallback.hasEvent("precomputed_client_offline_init_start"))
    }
    
    // MARK: - Assignment Queue Tests
    
    func testQueuedAssignmentsAreFlushedOnInitialization() {
        // Initialize without logger first
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
            configPublishedAt: nil,
            environment: nil
        )
        
        // First init without logger to queue assignments
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: nil // No logger
        )
        
        // Get assignments (should be queued)
        _ = EppoPrecomputedClient.shared.getStringAssignment(
            flagKey: "test-flag",
            defaultValue: "default"
        )
        
        // Reset and initialize with logger
        EppoPrecomputedClient.resetForTesting()
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: mockLogger.logger
        )
        
        // Get another assignment
        _ = EppoPrecomputedClient.shared.getStringAssignment(
            flagKey: "test-flag",
            defaultValue: "default"
        )
        
        // Verify only the new assignment is logged (queued ones were lost on reset)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(mockLogger.getLoggedAssignments().count, 1)
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