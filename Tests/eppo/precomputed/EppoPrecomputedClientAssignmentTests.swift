import XCTest
@testable import EppoFlagging

// Mock logger to verify assignment logging behavior
class MockAssignmentLogger {
    private(set) var loggedAssignments: [Assignment] = []
    private let queue = DispatchQueue(label: "mock.logger.queue", attributes: .concurrent)
    
    var logger: EppoPrecomputedClient.AssignmentLogger {
        return { [weak self] assignment in
            self?.queue.async(flags: .barrier) {
                self?.loggedAssignments.append(assignment)
            }
        }
    }
    
    func getLoggedAssignments() -> [Assignment] {
        queue.sync { loggedAssignments }
    }
    
    func reset() {
        queue.async(flags: .barrier) {
            self.loggedAssignments.removeAll()
        }
    }
}

// Mock assignment cache for testing deduplication
class MockAssignmentCache: AssignmentCache {
    private var loggedKeys = Set<String>()
    private let queue = DispatchQueue(label: "mock.cache.queue", attributes: .concurrent)
    
    func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool {
        queue.sync {
            let cacheKey = "\(key.subjectKey)|\(key.flagKey)|\(key.allocationKey)|\(key.variationKey)"
            return loggedKeys.contains(cacheKey)
        }
    }
    
    func setLastLoggedAssignment(key: AssignmentCacheKey) {
        queue.async(flags: .barrier) {
            let cacheKey = "\(key.subjectKey)|\(key.flagKey)|\(key.allocationKey)|\(key.variationKey)"
            self.loggedKeys.insert(cacheKey)
        }
    }
    
    func reset() {
        queue.async(flags: .barrier) {
            self.loggedKeys.removeAll()
        }
    }
}

class EppoPrecomputedClientAssignmentTests: XCTestCase {
    var mockLogger: MockAssignmentLogger!
    var mockCache: MockAssignmentCache!
    var testSubject: Subject!
    var testConfiguration: PrecomputedConfiguration!
    var configStore: PrecomputedConfigurationStore!
    
    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        mockLogger = MockAssignmentLogger()
        mockCache = MockAssignmentCache()
        testSubject = Subject(
            subjectKey: "test-user-123",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )
        
        let testFlags: [String: PrecomputedFlag] = [
            getMD5Hex("string-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-1"),
                variationKey: base64Encode("variant-a"),
                variationType: .STRING,
                variationValue: EppoValue(value: base64Encode("hello world")),
                extraLogging: [
                    base64Encode("holdoutKey"): base64Encode("feature-rollout"),
                    base64Encode("holdoutVariation"): base64Encode("status_quo")
                ],
                doLog: true
            ),
            
            getMD5Hex("bool-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-2"),
                variationKey: base64Encode("variant-b"),
                variationType: .BOOLEAN,
                variationValue: EppoValue(value: true),
                extraLogging: [:],
                doLog: true
            ),
            
            getMD5Hex("int-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-3"),
                variationKey: base64Encode("variant-c"),
                variationType: .INTEGER,
                variationValue: EppoValue(value: 42.0),
                extraLogging: [:],
                doLog: true
            ),
            
            getMD5Hex("numeric-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-4"),
                variationKey: base64Encode("variant-d"),
                variationType: .NUMERIC,
                variationValue: EppoValue(value: 3.14159),
                extraLogging: [:],
                doLog: true
            ),
            
            getMD5Hex("json-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-5"),
                variationKey: base64Encode("variant-e"),
                variationType: .JSON,
                variationValue: EppoValue(value: base64Encode("{\"key\":\"value\",\"num\":123}")),
                extraLogging: [:],
                doLog: true
            ),
            
            getMD5Hex("no-log-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-6"),
                variationKey: base64Encode("variant-f"),
                variationType: .STRING,
                variationValue: EppoValue(value: base64Encode("no logging")),
                extraLogging: [:],
                doLog: false
            ),
            
            getMD5Hex("type-mismatch-flag", salt: "test-salt"): PrecomputedFlag(
                allocationKey: base64Encode("allocation-7"),
                variationKey: base64Encode("variant-g"),
                variationType: .BOOLEAN,
                variationValue: EppoValue(value: base64Encode("not a boolean")),
                extraLogging: [:],
                doLog: true
            )
        ]
        
        testConfiguration = PrecomputedConfiguration(
            flags: testFlags,
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: PrecomputedSubject(from: testSubject),
            configPublishedAt: Date(),
            environment: Environment(name: "test")
        )
        
        configStore = PrecomputedConfigurationStore()
        configStore.setConfiguration(testConfiguration)
    }
    
    override func tearDown() {
        mockLogger.reset()
        mockCache.reset()
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }
    
    // MARK: - Test helpers
    
    private func initializeClient() {
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration,
            assignmentLogger: mockLogger.logger,
            assignmentCache: mockCache
        )
    }
    
    // MARK: - Assignment Value Tests
    
    func testAllAssignmentTypes() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        
        let stringResult = client.getStringAssignment(
            flagKey: "string-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(stringResult, "hello world")
        
        let boolResult = client.getBooleanAssignment(
            flagKey: "bool-flag",
            defaultValue: false
        )
        XCTAssertTrue(boolResult)
        
        let intResult = client.getIntegerAssignment(
            flagKey: "int-flag",
            defaultValue: 0
        )
        XCTAssertEqual(intResult, 42)
        
        let numericResult = client.getNumericAssignment(
            flagKey: "numeric-flag",
            defaultValue: 0.0
        )
        XCTAssertEqual(numericResult, 3.14159, accuracy: 0.00001)
        
        let jsonResult = client.getJSONStringAssignment(
            flagKey: "json-flag",
            defaultValue: "{}"
        )
        XCTAssertEqual(jsonResult, "{\"key\":\"value\",\"num\":123}")
    }
    
    // MARK: - Type Mismatch Tests
    
    func testTypeMismatchReturnsDefault() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        
        // Try to get boolean value from a flag that has a string value
        let boolResult = client.getBooleanAssignment(
            flagKey: "type-mismatch-flag",
            defaultValue: true
        )
        XCTAssertTrue(boolResult)
        
        // Try to get string value from boolean flag
        let stringResult = client.getStringAssignment(
            flagKey: "bool-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(stringResult, "default")
    }
    
    // MARK: - Assignment Logging Tests
    
    func testAssignmentLoggingForValidFlag() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        _ = client.getStringAssignment(
            flagKey: "string-flag",
            defaultValue: "default"
        )
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let logged = mockLogger.getLoggedAssignments()
        XCTAssertEqual(logged.count, 1)
        
        let assignment = logged[0]
        XCTAssertEqual(assignment.featureFlag, "string-flag")
        XCTAssertEqual(assignment.allocation, "allocation-1")
        XCTAssertEqual(assignment.variation, "variant-a")
        XCTAssertEqual(assignment.subject, "test-user-123")
        XCTAssertEqual(assignment.extraLogging["holdoutKey"], "feature-rollout")
        XCTAssertEqual(assignment.extraLogging["holdoutVariation"], "status_quo")
    }
    
    func testNoLoggingWhenDoLogIsFalse() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        _ = client.getStringAssignment(
            flagKey: "no-log-flag",
            defaultValue: "default"
        )
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let logged = mockLogger.getLoggedAssignments()
        XCTAssertEqual(logged.count, 0)
    }
    
    func testAssignmentDeduplication() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        for _ in 0..<5 {
            _ = client.getStringAssignment(
                flagKey: "string-flag",
                defaultValue: "default"
            )
        }
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let logged = mockLogger.getLoggedAssignments()
        XCTAssertEqual(logged.count, 1, "Should only log once due to caching")
    }
    
    func testAssignmentLoggingWithoutCache() throws {
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration,
            assignmentLogger: mockLogger.logger,
            assignmentCache: nil
        )
        
        let client = try EppoPrecomputedClient.shared()
        // Get the same assignment multiple times
        for _ in 0..<3 {
            _ = client.getStringAssignment(
                flagKey: "string-flag",
                defaultValue: "default"
            )
        }
        
        // Wait a bit for async logging
        Thread.sleep(forTimeInterval: 0.1)
        
        let logged = mockLogger.getLoggedAssignments()
        XCTAssertEqual(logged.count, 3, "Should log every time without cache")
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testAssignmentWithoutInitialization() {
        XCTAssertThrowsError(try EppoPrecomputedClient.shared()) { error in
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }
    
    func testAssignmentWithMissingFlag() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        let result = client.getStringAssignment(
            flagKey: "non-existent-flag",
            defaultValue: "default"
        )
        
        XCTAssertEqual(result, "default")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAssignmentLogging() throws {
        initializeClient()
        
        let client = try EppoPrecomputedClient.shared()
        let expectation = XCTestExpectation(description: "Concurrent logging completes")
        expectation.expectedFulfillmentCount = 50
        
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            let flagKey = i % 2 == 0 ? "string-flag" : "bool-flag"
            
            if i % 2 == 0 {
                _ = client.getStringAssignment(
                    flagKey: flagKey,
                    defaultValue: "default"
                )
            } else {
                _ = client.getBooleanAssignment(
                    flagKey: flagKey,
                    defaultValue: false
                )
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        Thread.sleep(forTimeInterval: 0.2)
        
        let logged = mockLogger.getLoggedAssignments()
        XCTAssertEqual(logged.count, 2)
    }
}
