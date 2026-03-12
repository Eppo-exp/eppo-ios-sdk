import XCTest
@testable import EppoFlagging

// Mock bandit logger to verify bandit logging behavior
class MockBanditLogger {
    private(set) var loggedEvents: [BanditEvent] = []
    private let queue = DispatchQueue(label: "mock.bandit.logger.queue", attributes: .concurrent)

    var logger: BanditLogger {
        return { [weak self] event in
            self?.queue.async(flags: .barrier) {
                self?.loggedEvents.append(event)
            }
        }
    }

    func getLoggedEvents() -> [BanditEvent] {
        queue.sync { loggedEvents }
    }

    func reset() {
        queue.async(flags: .barrier) {
            self.loggedEvents.removeAll()
        }
    }
}

class EppoPrecomputedClientBanditTests: XCTestCase {
    var mockAssignmentLogger: MockAssignmentLogger!
    var mockBanditLogger: MockBanditLogger!
    var mockAssignmentCache: MockAssignmentCache!
    var mockBanditCache: MockAssignmentCache!
    var testSubjectKey: String!
    var testSubjectAttributes: [String: EppoValue]!
    var testConfiguration: PrecomputedConfiguration!

    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        mockAssignmentLogger = MockAssignmentLogger()
        mockBanditLogger = MockBanditLogger()
        mockAssignmentCache = MockAssignmentCache()
        mockBanditCache = MockAssignmentCache()
        testSubjectKey = "test-user-123"
        testSubjectAttributes = [
            "age": EppoValue(value: 25),
            "country": EppoValue(value: "US")
        ]

        // Create test flags
        let testFlags = createTestFlags([
            ("bandit-flag", createTestFlag(
                allocationKey: "allocation-1",
                variationKey: "variant-a",
                variationType: .string,
                variationValue: "recommendation-model"
            )),
            ("string-flag", createTestFlag(
                allocationKey: "allocation-2",
                variationKey: "variant-b",
                variationType: .string,
                variationValue: "hello world"
            ))
        ])

        // Create test bandits
        let testBandits = createTestBandits([
            ("bandit-flag", createTestBandit(
                banditKey: "recommendation-model",
                action: "show-promo",
                modelVersion: "v1.2.3",
                actionNumericAttributes: [
                    "expectedConversion": 0.25,
                    "expectedRevenue": 15.75
                ],
                actionCategoricalAttributes: [
                    "category": "promotion",
                    "placement": "home_screen"
                ],
                actionProbability: 0.85,
                optimalityGap: 0.12
            ))
        ])

        testConfiguration = PrecomputedConfiguration(
            flags: testFlags,
            bandits: testBandits,
            salt: "test-salt",
            format: "PRECOMPUTED",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            publishedAt: ISO8601DateFormatter().string(from: Date()),
            environment: Environment(name: "test")
        )
    }

    override func tearDown() {
        mockAssignmentLogger.reset()
        mockBanditLogger.reset()
        mockAssignmentCache.reset()
        mockBanditCache.reset()
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }

    // MARK: - Test helpers

    private func initializeClient() {
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration,
            assignmentLogger: mockAssignmentLogger.logger,
            assignmentCache: mockAssignmentCache,
            banditLogger: mockBanditLogger.logger,
            banditAssignmentCache: mockBanditCache
        )
    }

    // MARK: - Bandit Action Tests

    func testGetBanditActionWithBanditFlag() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        let result = client.getBanditAction(
            flagKey: "bandit-flag",
            defaultValue: "default"
        )

        XCTAssertEqual(result.variation, "recommendation-model")
        XCTAssertEqual(result.action, "show-promo")
    }

    func testGetBanditActionWithNonBanditFlag() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        let result = client.getBanditAction(
            flagKey: "string-flag",
            defaultValue: "default"
        )

        // Should fall back to regular string assignment
        XCTAssertEqual(result.variation, "hello world")
        XCTAssertNil(result.action)
    }

    func testGetBanditActionWithMissingFlag() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        let result = client.getBanditAction(
            flagKey: "non-existent-flag",
            defaultValue: "default"
        )

        XCTAssertEqual(result.variation, "default")
        XCTAssertNil(result.action)
    }

    func testGetBanditActionWithoutInitialization() {
        XCTAssertThrowsError(try EppoPrecomputedClient.shared()) { error in
            XCTAssertTrue(error is EppoPrecomputedClient.InitializationError)
        }
    }

    // MARK: - Bandit Logging Tests

    func testBanditLoggingForValidBandit() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        _ = client.getBanditAction(
            flagKey: "bandit-flag",
            defaultValue: "default"
        )

        Thread.sleep(forTimeInterval: 0.1)

        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 1)

        let event = loggedEvents[0]
        XCTAssertEqual(event.flagKey, "bandit-flag")
        XCTAssertEqual(event.banditKey, "recommendation-model")
        XCTAssertEqual(event.subjectKey, "test-user-123")
        XCTAssertEqual(event.action, "show-promo")
        XCTAssertEqual(event.actionProbability, 0.85, accuracy: 0.001)
        XCTAssertEqual(event.optimalityGap, 0.12, accuracy: 0.001)
        XCTAssertEqual(event.modelVersion, "v1.2.3")

        // Check action attributes
        XCTAssertEqual(event.actionNumericAttributes["expectedConversion"] ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(event.actionNumericAttributes["expectedRevenue"] ?? 0, 15.75, accuracy: 0.001)
        XCTAssertEqual(event.actionCategoricalAttributes["category"], "promotion")
        XCTAssertEqual(event.actionCategoricalAttributes["placement"], "home_screen")

        // Check metadata
        XCTAssertEqual(event.metaData["obfuscated"], "true")
        XCTAssertNotNil(event.metaData["sdkLanguage"])
        XCTAssertNotNil(event.metaData["sdkLibVersion"])
    }

    func testBanditLoggingIncludesSubjectAttributes() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        _ = client.getBanditAction(
            flagKey: "bandit-flag",
            defaultValue: "default"
        )

        Thread.sleep(forTimeInterval: 0.1)

        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 1)

        let event = loggedEvents[0]
        XCTAssertEqual(event.subjectNumericAttributes["age"] ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(event.subjectCategoricalAttributes["country"], "US")
    }

    func testNoLoggingForNonBanditFlag() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        _ = client.getBanditAction(
            flagKey: "string-flag",
            defaultValue: "default"
        )

        Thread.sleep(forTimeInterval: 0.1)

        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 0, "Should not log bandit event for non-bandit flag")
    }

    func testBanditLoggingDeduplication() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        for _ in 0..<5 {
            _ = client.getBanditAction(
                flagKey: "bandit-flag",
                defaultValue: "default"
            )
        }

        Thread.sleep(forTimeInterval: 0.1)

        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 1, "Should only log once due to caching")
    }

    func testBanditLoggingWithoutCache() throws {
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: testConfiguration,
            assignmentLogger: mockAssignmentLogger.logger,
            assignmentCache: nil,
            banditLogger: mockBanditLogger.logger,
            banditAssignmentCache: nil
        )

        let client = try EppoPrecomputedClient.shared()
        for _ in 0..<3 {
            _ = client.getBanditAction(
                flagKey: "bandit-flag",
                defaultValue: "default"
            )
        }

        Thread.sleep(forTimeInterval: 0.1)

        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 3, "Should log every time without cache")
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentBanditAccess() throws {
        initializeClient()

        let client = try EppoPrecomputedClient.shared()
        let expectation = XCTestExpectation(description: "Concurrent bandit access completes")
        expectation.expectedFulfillmentCount = 50

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            let result = client.getBanditAction(
                flagKey: "bandit-flag",
                defaultValue: "default"
            )
            XCTAssertEqual(result.variation, "recommendation-model")
            XCTAssertEqual(result.action, "show-promo")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        Thread.sleep(forTimeInterval: 0.2)

        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 1, "Should only log once due to caching")
    }

    // MARK: - Bandit Without Action Tests

    func testBanditWithoutAction() throws {
        // Create bandit without action
        let testBandits = createTestBandits([
            ("bandit-no-action", createTestBandit(
                banditKey: "model-without-action",
                action: nil,
                modelVersion: "v1.0.0",
                actionProbability: 0.5,
                optimalityGap: 0.1
            ))
        ])

        let testFlags = createTestFlags([
            ("bandit-no-action", createTestFlag(
                allocationKey: "allocation-1",
                variationKey: "variant-a",
                variationType: .string,
                variationValue: "model-without-action"
            ))
        ])

        let config = PrecomputedConfiguration(
            flags: testFlags,
            bandits: testBandits,
            salt: "test-salt",
            format: "PRECOMPUTED",
            subject: Subject(subjectKey: testSubjectKey, subjectAttributes: testSubjectAttributes),
            publishedAt: ISO8601DateFormatter().string(from: Date()),
            environment: Environment(name: "test")
        )

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "mock-api-key",
            initialPrecomputedConfiguration: config,
            banditLogger: mockBanditLogger.logger,
            banditAssignmentCache: mockBanditCache
        )

        let client = try EppoPrecomputedClient.shared()
        let result = client.getBanditAction(
            flagKey: "bandit-no-action",
            defaultValue: "default"
        )

        XCTAssertEqual(result.variation, "model-without-action")
        XCTAssertNil(result.action)

        Thread.sleep(forTimeInterval: 0.1)

        // Should not log because there's no action
        let loggedEvents = mockBanditLogger.getLoggedEvents()
        XCTAssertEqual(loggedEvents.count, 0, "Should not log bandit event without action")
    }
}
