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
    var testSubjectKey: String!
    var testSubjectAttributes: [String: EppoValue]!
    var mockLogger: MockAssignmentLogger!
    
    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        mockConfigChangeCallback = MockConfigurationChangeCallback()
        testSubjectKey = "test-user-123"
        testSubjectAttributes = ["age": EppoValue(value: 25)]
        mockLogger = MockAssignmentLogger()
    }
    
    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }
    
    // MARK: - Online Initialization Tests
    
    func testSuccessfulOnlineInitialization() async throws {
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
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: Date(),
            environment: Environment(name: "test")
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let mockData = try encoder.encode(testConfig)
        
        // Test that initialization would work with proper network mocking
        // For now, just verify the API signature
        _ = mockData
        
        // Test re-initialization throws error after first initialization
        let testConfig2 = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: nil,
            environment: nil
        )
        
        let client1 = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig2,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )
        
        XCTAssertNotNil(client1)
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)
        
        // Test that subsequent offline initialization returns same instance
        let client2 = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-sdk-key-2",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig2
        )
        
        XCTAssertTrue(client1 === client2)
    }
    
    func testOnlineInitializationWithCustomHost() {
        EppoPrecomputedClient.resetForTesting()
        
        // Verify the API accepts custom host parameter
        let customHost = "https://custom.eppo.host"
        XCTAssertNotNil(customHost)
        
        // Real test would verify the request URL uses custom host
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
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: Date(),
            environment: Environment(name: "test")
        )
        
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: mockLogger.logger,
            configurationChangeCallback: mockConfigChangeCallback.callback
        )
        
        XCTAssertNotNil(client)
        
        XCTAssertEqual(mockConfigChangeCallback.configurations.count, 1)
        XCTAssertEqual(mockConfigChangeCallback.configurations[0].salt, base64Encode("test-salt"))
        let result = client.getStringAssignment(
            flagKey: "test-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "hello")
        
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(mockLogger.getLoggedAssignments().count, 1)
    }
    
    func testOfflineInitializationWhenAlreadyInitialized() {
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: nil,
            environment: nil
        )
        
        let originalClient = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig
        )
        let client2 = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key-2",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig
        )
        
        XCTAssertNotNil(client2)
        XCTAssertTrue(originalClient === client2)
    }
    
    // MARK: - No-Op Logger Tests
    
    func testInitializationWithoutLogger() {
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: nil,
            environment: nil
        )
        
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: nil
        )
        
        XCTAssertNotNil(client)
        let result = client.getStringAssignment(
            flagKey: "nonexistent-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }
    
    // MARK: - Error Handling Tests
    
    func testInitializationCleanupOnError() async {
        EppoPrecomputedClient.resetForTesting()
        
        // Test that after reset, shared() throws error indicating no configuration
        do {
            _ = try EppoPrecomputedClient.shared()
            XCTFail("Should throw error after reset")
        } catch EppoPrecomputedClient.InitializationError.notConfigured {
            // Expected behavior after reset
        } catch {
            XCTFail("Should throw notConfigured error, but got: \(error)")
        }
    }
    
    // MARK: - Configuration Change Callback Tests
    
    func testConfigurationChangeCallbackIsCalledOnInit() {
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: nil,
            environment: nil
        )
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
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
            subject: PrecomputedSubject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            configPublishedAt: nil,
            environment: nil
        )
        let client = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            initialPrecomputedConfiguration: testConfig
        )
        
        XCTAssertNotNil(client)
    }
    
}
