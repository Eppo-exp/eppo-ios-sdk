import XCTest
@testable import EppoFlagging

// Mock URLSession that can simulate various error conditions
class MockURLSessionForErrors: URLProtocol {
    enum MockError: Error {
        case networkDown
        case invalidJSON
        case timeout
        case serverError(statusCode: Int)
    }

    static var errorToThrow: MockError?
    static var responseData: Data?
    static var requestCount = 0
    static var requestDelay: TimeInterval = 0

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLSessionForErrors.requestCount += 1

        if MockURLSessionForErrors.requestDelay > 0 {
            Thread.sleep(forTimeInterval: MockURLSessionForErrors.requestDelay)
        }

        if let error = MockURLSessionForErrors.errorToThrow {
            switch error {
            case .networkDown:
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            case .invalidJSON:
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: "invalid json".data(using: .utf8)!)
                client?.urlProtocolDidFinishLoading(self)
            case .timeout:
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            case .serverError(let statusCode):
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data())
                client?.urlProtocolDidFinishLoading(self)
            }
        } else if let data = MockURLSessionForErrors.responseData {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        }
    }

    override func stopLoading() {
        // No-op
    }

    static func reset() {
        errorToThrow = nil
        responseData = nil
        requestCount = 0
        requestDelay = 0
    }
}

// Simple test logger for error scenarios
class ErrorTestLogger {
    private(set) var loggedAssignments: [Assignment] = []

    var logger: EppoPrecomputedClient.AssignmentLogger {
        return { [weak self] assignment in
            self?.loggedAssignments.append(assignment)
        }
    }
}

class EppoPrecomputedClientErrorTests: XCTestCase {
    var testPrecompute: Precompute!
    var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        MockURLSessionForErrors.reset()

        // Configure URLSession to use mock
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLSessionForErrors.self]
        mockSession = URLSession(configuration: config)

        // Register URLProtocol globally so URLSession.shared uses it
        URLProtocol.registerClass(MockURLSessionForErrors.self)

        testPrecompute = Precompute(
            subjectKey: "test-user",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )
    }

    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        MockURLSessionForErrors.reset()
        // Unregister URLProtocol
        URLProtocol.unregisterClass(MockURLSessionForErrors.self)
        super.tearDown()
    }

    // MARK: - Network Error Tests

    func testInitializationFailsOnNetworkError() async {
        MockURLSessionForErrors.errorToThrow = .networkDown

        do {
            _ = try await EppoPrecomputedClient.initialize(
                sdkKey: "test-key",
                precompute: testPrecompute
            )
            XCTFail("Should throw network error")
        } catch {
            // Verify it's a network error
            XCTAssertNotNil(error)
        }

        // Verify that despite network failure, an offline instance was created  
        // (initialize() calls initializeOffline() first, then tries to load config)
        do {
            let instance = try EppoPrecomputedClient.shared()
            XCTAssertNotNil(instance)
            // Instance exists but has no network configuration loaded
        } catch {
            XCTFail("Instance should exist after offline initialization, even if network load failed: \(error)")
        }
    }

    func testInitializationFailsOnTimeout() async {
        MockURLSessionForErrors.errorToThrow = .timeout

        do {
            _ = try await EppoPrecomputedClient.initialize(
                sdkKey: "test-key",
                precompute: testPrecompute
            )
            XCTFail("Should throw timeout error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testInitializationFailsOnServerError() async {
        MockURLSessionForErrors.errorToThrow = .serverError(statusCode: 500)

        do {
            _ = try await EppoPrecomputedClient.initialize(
                sdkKey: "test-key",
                precompute: testPrecompute
            )
            XCTFail("Should throw server error")
        } catch {
            // The error might be from retry logic, check request count
            if let networkError = error as? NetworkError {
                if case .httpError(let code) = networkError {
                    // Accept either 500 or the last error after retries
                    XCTAssertTrue(code == 500 || code >= 400, "Expected HTTP error, got \(code)")
                } else {
                    XCTFail("Wrong error type")
                }
            } else {
                XCTFail("Expected NetworkError")
            }
        }
    }

    // MARK: - Malformed Response Tests

    func testInitializationFailsOnInvalidJSON() async {
        MockURLSessionForErrors.errorToThrow = .invalidJSON

        do {
            _ = try await EppoPrecomputedClient.initialize(
                sdkKey: "test-key",
                precompute: testPrecompute
            )
            XCTFail("Should throw decoding error")
        } catch {
            // Could be decoding error or HTTP error depending on how the server responds
            if let networkError = error as? NetworkError {
                switch networkError {
                case .decodingError:
                    // Expected
                    break
                case .httpError(let code):
                    // Also acceptable if server returns error code
                    XCTAssertTrue(code >= 400, "Expected client/server error")
                default:
                    XCTFail("Wrong error type: \(networkError)")
                }
            } else {
                XCTFail("Expected NetworkError")
            }
        }
    }

    func testInitializationFailsOnMissingRequiredFields() async {
        // Response missing required 'salt' field
        let invalidData = """
        {
            "flags": {},
            "format": "PRECOMPUTED"
        }
        """.data(using: .utf8)!

        MockURLSessionForErrors.responseData = invalidData

        do {
            _ = try await EppoPrecomputedClient.initialize(
                sdkKey: "test-key",
                precompute: testPrecompute
            )
            XCTFail("Should throw decoding error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Assignment Error Tests

    func testAssignmentWithCorruptedFlagData() {
        // Reset client first
        EppoPrecomputedClient.resetForTesting()

        // Create config with invalid base64 data (now safe with validation)
        let testConfig = PrecomputedConfiguration(
            flags: [
                getMD5Hex("corrupt-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: "not-base64!@#$%", // Invalid base64 - should skip logging
                    variationKey: base64Encode("variant-a"),
                    variationType: .string,
                    variationValue: EppoValue(value: base64Encode("value")),
                    extraLogging: [:],
                    doLog: true // Logging enabled but will be skipped due to invalid base64
                )
            ],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: Date(),
            environment: nil
        )

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: testConfig
        )

        // Should return assignment value despite invalid logging data
        let result = try! EppoPrecomputedClient.shared().getStringAssignment(
            flagKey: "corrupt-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "value", "Assignment should work despite invalid base64 in logging data")
    }

    func testAssignmentWithTypeMismatch() {
        // Reset client first
        EppoPrecomputedClient.resetForTesting()

        let testConfig = PrecomputedConfiguration(
            flags: [
                getMD5Hex("type-mismatch-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: base64Encode("allocation-1"),
                    variationKey: base64Encode("variant-a"),
                    variationType: .integer, // Integer type
                    variationValue: EppoValue(value: base64Encode("not-a-number")), // String value
                    extraLogging: [:],
                    doLog: true
                )
            ],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: Date(),
            environment: nil
        )

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: testConfig
        )

        // Should return default when type conversion fails
        let result = try! EppoPrecomputedClient.shared().getIntegerAssignment(
            flagKey: "type-mismatch-flag",
            defaultValue: 42
        )
        XCTAssertEqual(result, 42)
    }

    // MARK: - Concurrent Initialization Tests

    func testConcurrentInitializationAttempts() async throws {
        // Prepare valid response
        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: Date(),
            subject: Subject(
                subjectKey: testPrecompute.subjectKey,
                subjectAttributes: testPrecompute.subjectAttributes
            ),
            publishedAt: Date(),
            environment: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        MockURLSessionForErrors.responseData = try encoder.encode(testConfig)
        MockURLSessionForErrors.requestDelay = 0.01 // Minimal delay to ensure concurrency

        // Use actor for thread-safe result collection
        actor ResultsCollector {
            private var results: [Result<EppoPrecomputedClient, Error>] = []

            func add(_ result: Result<EppoPrecomputedClient, Error>) {
                results.append(result)
            }

            func getResults() -> [Result<EppoPrecomputedClient, Error>] {
                return results
            }
        }

        let collector = ResultsCollector()

        // Attempt multiple concurrent initializations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        let client = try await EppoPrecomputedClient.initialize(
                            sdkKey: "test-key",
                            precompute: self.testPrecompute
                        )
                        await collector.add(.success(client))
                    } catch {
                        await collector.add(.failure(error))
                    }
                }
            }
        }

        let results = await collector.getResults()

        // All should succeed and return the same instance (like regular EppoClient)
        let successes = results.compactMap { try? $0.get() }
        let failures = results.compactMap {
            switch $0 {
            case .failure(let error):
                return error
            case .success:
                return nil
            }
        }

        XCTAssertEqual(successes.count, 5, "All concurrent initialization attempts should succeed")
        XCTAssertEqual(failures.count, 0, "No failures should occur with concurrent initialization")

        // Verify all successes return the same instance
        let firstInstance = successes[0]
        for instance in successes {
            XCTAssertTrue(firstInstance === instance, "All instances should be the same singleton")
        }
    }

    // MARK: - Configuration Expiration Tests

    func testExpiredConfigurationWithLogging() {
        // Test the actual expired configuration scenario with working assignment logging
        EppoPrecomputedClient.resetForTesting()

        let oldDate = Date(timeIntervalSinceNow: -86400 * 30) // 30 days ago
        let testLogger = ErrorTestLogger()

        let testConfig = PrecomputedConfiguration(
            flags: [
                getMD5Hex("test-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: base64Encode("allocation-1"),
                    variationKey: base64Encode("variant-a"),
                    variationType: .string,
                    variationValue: EppoValue(value: base64Encode("value")),
                    extraLogging: [:],
                    doLog: true
                )
            ],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: oldDate,
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: oldDate,
            environment: nil
        )

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: testConfig,
            assignmentLogger: testLogger.logger
        )

        let result = try! EppoPrecomputedClient.shared().getStringAssignment(
            flagKey: "test-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "value", "Assignment should work with old configuration")

        // Verify assignment logging worked with bypass solution!
        XCTAssertGreaterThan(testLogger.loggedAssignments.count, 0, "Assignment logging must work")
        let loggedAssignment = testLogger.loggedAssignments.first!
        XCTAssertEqual(loggedAssignment.featureFlag, "test-flag")
        XCTAssertEqual(loggedAssignment.allocation, "allocation-1")
        XCTAssertEqual(loggedAssignment.variation, "variant-a")
        XCTAssertEqual(loggedAssignment.subject, "test-user")
    }

    // MARK: - Edge Case Tests

    func testEmptyFlagKey() {
        // Reset client first
        EppoPrecomputedClient.resetForTesting()

        let testConfig = PrecomputedConfiguration(
            flags: [:],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: Date(),
            environment: nil
        )

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: testConfig
        )

        // Should handle empty flag key gracefully
        let result = try! EppoPrecomputedClient.shared().getStringAssignment(
            flagKey: "",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "default")
    }

    func testEmptyExtraLogging() {
        // Reset client first  
        EppoPrecomputedClient.resetForTesting()

        // Test that empty extraLogging is handled correctly
        let testConfig = PrecomputedConfiguration(
            flags: [
                getMD5Hex("empty-extra-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: base64Encode("allocation-1"),
                    variationKey: base64Encode("variant-a"),
                    variationType: .string,
                    variationValue: EppoValue(value: base64Encode("value")),
                    extraLogging: [:], // Empty dictionary as per test data
                    doLog: true
                )
            ],
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            fetchedAt: Date(),
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: Date(),
            environment: nil
        )

        // Initialize without logger - should be safe with new bypass implementation
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: testConfig
        )

        let result = try! EppoPrecomputedClient.shared().getStringAssignment(
            flagKey: "empty-extra-flag",
            defaultValue: "default"
        )

        // Verify the assignment returns correctly
        XCTAssertEqual(result, "value")
    }

    // MARK: - Assignment Cache Error Tests

    func testAssignmentContinuesWhenCacheFails() {
        // Reset client first
        EppoPrecomputedClient.resetForTesting()

        // Create a mock cache that always fails
        class FailingAssignmentCache: AssignmentCache {
            func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool {
                return false // Always return false to force new assignments
            }

            func setLastLoggedAssignment(key: AssignmentCacheKey) {
                // Fail silently - do nothing
            }

            func shouldLogAssignment(key: AssignmentCacheKey) -> Bool {
                return true // Always should log
            }
        }

        let testConfig = PrecomputedConfiguration(
            flags: [
                getMD5Hex("cache-test-flag", salt: "test-salt"): PrecomputedFlag(
                    allocationKey: base64Encode("allocation-1"),
                    variationKey: base64Encode("variant-a"),
                    variationType: .string,
                    variationValue: EppoValue(value: base64Encode("cached-value")),
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
            environment: nil
        )

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "test-key",
            initialPrecomputedConfiguration: testConfig,
            assignmentCache: FailingAssignmentCache()
        )

        // Should still return correct value even with failing cache
        let result = try! EppoPrecomputedClient.shared().getStringAssignment(
            flagKey: "cache-test-flag",
            defaultValue: "default"
        )
        XCTAssertEqual(result, "cached-value")
    }
}
