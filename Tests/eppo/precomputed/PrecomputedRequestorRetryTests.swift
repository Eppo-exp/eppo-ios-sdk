import XCTest
@testable import EppoFlagging

// Mock URLSession for testing retry logic
class MockURLSessionWithRetry: URLProtocol {
    static var mockResponses: [(error: Error?, data: Data?, response: URLResponse?)] = []
    static var currentAttempt = 0
    static var requestCount = 0
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        MockURLSessionWithRetry.requestCount += 1
        
        guard MockURLSessionWithRetry.currentAttempt < MockURLSessionWithRetry.mockResponses.count else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        
        let response = MockURLSessionWithRetry.mockResponses[MockURLSessionWithRetry.currentAttempt]
        MockURLSessionWithRetry.currentAttempt += 1
        
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else if let data = response.data, let urlResponse = response.response {
            client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
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
        mockResponses = []
        currentAttempt = 0
        requestCount = 0
    }
}

class PrecomputedRequestorRetryTests: XCTestCase {
    var requestor: PrecomputedRequestor!
    var testPrecompute: Precompute!
    var mockSession: URLSession!
    
    override func setUp() {
        super.setUp()
        
        // Reset mock
        MockURLSessionWithRetry.reset()
        
        // Configure URLSession to use mock
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLSessionWithRetry.self]
        mockSession = URLSession(configuration: config)
        
        testPrecompute = Precompute(
            subjectKey: "test-user",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )
        
        requestor = PrecomputedRequestor(
            precompute: testPrecompute,
            sdkKey: "test-key",
            sdkName: "test-sdk",
            sdkVersion: "1.0.0",
            maxRetryAttempts: 3,
            initialRetryDelay: 0.1, // Short delay for tests
            urlSession: mockSession
        )
    }
    
    override func tearDown() {
        MockURLSessionWithRetry.reset()
        super.tearDown()
    }
    
    // MARK: - Retry Logic Tests
    
    func testCalculateRetryDelay() {
        // Test exponential backoff calculation with multiple samples to account for jitter
        var delay0Samples: [TimeInterval] = []
        var delay1Samples: [TimeInterval] = []
        var delay2Samples: [TimeInterval] = []
        
        // Take multiple samples to get reliable statistics despite jitter
        for _ in 0..<10 {
            delay0Samples.append(requestor.calculateRetryDelay(attempt: 0))
            delay1Samples.append(requestor.calculateRetryDelay(attempt: 1))
            delay2Samples.append(requestor.calculateRetryDelay(attempt: 2))
        }
        
        let avgDelay0 = delay0Samples.reduce(0, +) / Double(delay0Samples.count)
        let avgDelay1 = delay1Samples.reduce(0, +) / Double(delay1Samples.count)
        let avgDelay2 = delay2Samples.reduce(0, +) / Double(delay2Samples.count)
        
        // Verify exponential growth on average (accounting for ±25% jitter)
        XCTAssertGreaterThan(avgDelay1, avgDelay0 * 1.5, "Average delay1 should be > 1.5x delay0")
        XCTAssertGreaterThan(avgDelay2, avgDelay1 * 1.5, "Average delay2 should be > 1.5x delay1")
        
        // Verify jitter is applied by checking variance
        let hasVariance = Set(delay1Samples).count > 1
        XCTAssertTrue(hasVariance, "Jitter should make delays different")
        
        // Verify cap at 60 seconds
        let delayLarge = requestor.calculateRetryDelay(attempt: 10)
        XCTAssertLessThanOrEqual(delayLarge, 60.0)
    }
    
    func testIsRetryableError() {
        // Test URLError cases
        XCTAssertTrue(requestor.isRetryableError(URLError(.timedOut)))
        XCTAssertTrue(requestor.isRetryableError(URLError(.networkConnectionLost)))
        XCTAssertTrue(requestor.isRetryableError(URLError(.notConnectedToInternet)))
        XCTAssertFalse(requestor.isRetryableError(URLError(.cancelled)))
        XCTAssertFalse(requestor.isRetryableError(URLError(.badURL)))
        
        // Test NetworkError cases
        XCTAssertTrue(requestor.isRetryableError(NetworkError.httpError(statusCode: 500)))
        XCTAssertTrue(requestor.isRetryableError(NetworkError.httpError(statusCode: 502)))
        XCTAssertTrue(requestor.isRetryableError(NetworkError.httpError(statusCode: 429)))
        XCTAssertFalse(requestor.isRetryableError(NetworkError.httpError(statusCode: 400)))
        XCTAssertFalse(requestor.isRetryableError(NetworkError.httpError(statusCode: 404)))
        XCTAssertFalse(requestor.isRetryableError(NetworkError.invalidURL))
        
        // Test other errors
        XCTAssertFalse(requestor.isRetryableError(NSError(domain: "test", code: 1)))
    }
    
    func testSuccessfulRequestNoRetry() async throws {
        // Setup successful response
        let testData = """
        {
            "flags": {},
            "salt": "test-salt",
            "format": "PRECOMPUTED",
            "subject": {
                "subjectKey": "test-user",
                "subjectAttributes": {"age": 25}
            }
        }
        """.data(using: .utf8)!
        
        let response = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        MockURLSessionWithRetry.mockResponses = [(nil, testData, response)]
        
        // Make request
        do {
            _ = try await requestor.fetchPrecomputedFlags()
            // Request count should be 1 (no retries)
            XCTAssertEqual(MockURLSessionWithRetry.requestCount, 1)
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }
    
    func testRetryOnServerError() async throws {
        // Setup responses: first two fail with 500, third succeeds
        let testData = """
        {
            "flags": {},
            "salt": "test-salt",
            "format": "PRECOMPUTED",
            "subject": {
                "subjectKey": "test-user",
                "subjectAttributes": {"age": 25}
            }
        }
        """.data(using: .utf8)!
        
        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        MockURLSessionWithRetry.mockResponses = [
            (nil, Data(), errorResponse),
            (nil, Data(), errorResponse),
            (nil, testData, successResponse)
        ]
        
        // Make request with short retry delay
        let startTime = Date()
        do {
            _ = try await requestor.fetchPrecomputedFlags()
            let duration = Date().timeIntervalSince(startTime)
            
            // Should have made 3 attempts
            XCTAssertEqual(MockURLSessionWithRetry.requestCount, 3)
            
            // Should have delayed between attempts (at least 0.2 seconds for 2 retries)
            XCTAssertGreaterThan(duration, 0.2)
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }
    
    func testNoRetryOnClientError() async throws {
        // Setup 404 response (client error)
        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        
        MockURLSessionWithRetry.mockResponses = [(nil, Data(), errorResponse)]
        
        // Make request
        do {
            _ = try await requestor.fetchPrecomputedFlags()
            XCTFail("Should throw error")
        } catch {
            // Should only make 1 attempt (no retry on 4xx)
            XCTAssertEqual(MockURLSessionWithRetry.requestCount, 1)
        }
    }
    
    func testRetryOnNetworkError() async throws {
        // Setup network errors followed by success
        let testData = """
        {
            "flags": {},
            "salt": "test-salt", 
            "format": "PRECOMPUTED",
            "subject": {
                "subjectKey": "test-user",
                "subjectAttributes": {"age": 25}
            }
        }
        """.data(using: .utf8)!
        
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        MockURLSessionWithRetry.mockResponses = [
            (URLError(.networkConnectionLost), nil, nil),
            (URLError(.timedOut), nil, nil),
            (nil, testData, successResponse)
        ]
        
        // Make request
        do {
            _ = try await requestor.fetchPrecomputedFlags()
            // Should have made 3 attempts
            XCTAssertEqual(MockURLSessionWithRetry.requestCount, 3)
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }
    
    func testMaxRetriesExhausted() async throws {
        // Setup all attempts to fail
        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 503,
            httpVersion: nil,
            headerFields: nil
        )!
        
        MockURLSessionWithRetry.mockResponses = [
            (nil, Data(), errorResponse),
            (nil, Data(), errorResponse),
            (nil, Data(), errorResponse)
        ]
        
        // Make request (should fail after 3 attempts)
        do {
            _ = try await requestor.fetchPrecomputedFlags()
            XCTFail("Should throw error")
        } catch {
            // Should have made exactly 3 attempts
            XCTAssertEqual(MockURLSessionWithRetry.requestCount, 3)
            
            // Should throw the last error
            if let networkError = error as? NetworkError {
                if case .httpError(let code) = networkError {
                    XCTAssertEqual(code, 503)
                } else {
                    XCTFail("Wrong error type")
                }
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testRetryOnRateLimitError() async throws {
        // Setup 429 (rate limit) followed by success
        let testData = """
        {
            "flags": {},
            "salt": "test-salt",
            "format": "PRECOMPUTED",
            "subject": {
                "subjectKey": "test-user",
                "subjectAttributes": {"age": 25}
            }
        }
        """.data(using: .utf8)!
        
        let rateLimitResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        MockURLSessionWithRetry.mockResponses = [
            (nil, Data(), rateLimitResponse),
            (nil, testData, successResponse)
        ]
        
        // Make request
        do {
            _ = try await requestor.fetchPrecomputedFlags()
            // Should have made 2 attempts
            XCTAssertEqual(MockURLSessionWithRetry.requestCount, 2)
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }
}
