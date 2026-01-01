import XCTest
@testable import EppoFlagging

class PrecomputedRequestorTests: XCTestCase {
    
    // MARK: - Test Setup
    
    var subject: Precompute!
    
    override func setUp() {
        super.setUp()
        subject = Precompute(
            subjectKey: "test-user",
            subjectAttributes: ["age": .valueOf(25), "country": .valueOf("US")]
        )
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithDefaultHost() {
        let requestor = PrecomputedRequestor(
            precompute: subject,
            sdkKey: "test-sdk-key",
            sdkName: "ios",
            sdkVersion: "1.0.0"
        )
        XCTAssertNotNil(requestor)
    }
    
    func testInitializationWithCustomHost() {
        let requestor = PrecomputedRequestor(
            precompute: subject,
            sdkKey: "test-sdk-key",
            sdkName: "ios",
            sdkVersion: "1.0.0",
            host: "https://custom.eppo.cloud"
        )
        XCTAssertNotNil(requestor)
    }
    
    func testInitializationWithEmptySubjectAttributes() {
        let emptySubject = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let requestor = PrecomputedRequestor(
            precompute: emptySubject,
            sdkKey: "test-sdk-key",
            sdkName: "ios",
            sdkVersion: "1.0.0"
        )
        XCTAssertNotNil(requestor)
    }
    
    func testInitializationWithComplexSubjectAttributes() {
        let complexSubject = Precompute(
            subjectKey: "test-user",
            subjectAttributes: [
                "age": .valueOf(25),
                "country": .valueOf("US"),
                "isPremium": .valueOf(true),
                "score": .valueOf(95.5),
                "metadata": .valueOf("{\"key\":\"value\"}")
            ]
        )
        let requestor = PrecomputedRequestor(
            precompute: complexSubject,
            sdkKey: "test-sdk-key",
            sdkName: "ios",
            sdkVersion: "1.0.0"
        )
        XCTAssertNotNil(requestor)
    }
    
    func testInitializationWithSpecialCharactersInSubjectKey() {
        let specialSubject = Precompute(
            subjectKey: "user-123@example.com",
            subjectAttributes: ["type": .valueOf("special")]
        )
        let requestor = PrecomputedRequestor(
            precompute: specialSubject,
            sdkKey: "test-sdk-key",
            sdkName: "ios",
            sdkVersion: "1.0.0"
        )
        XCTAssertNotNil(requestor)
    }
    
    // MARK: - Error Type Tests
    
    func testNetworkErrorTypes() {
        // Test error descriptions
        let invalidURLError = NetworkError.invalidURL
        XCTAssertEqual(invalidURLError.errorDescription, "Invalid URL")
        
        let invalidResponseError = NetworkError.invalidResponse
        XCTAssertEqual(invalidResponseError.errorDescription, "Invalid response from server")
        
        let httpError = NetworkError.httpError(statusCode: 404)
        XCTAssertEqual(httpError.errorDescription, "HTTP error: 404")
        
        let decodingError = NetworkError.decodingError(NSError(domain: "test", code: 1))
        XCTAssertTrue(decodingError.errorDescription?.contains("Failed to decode response") ?? false)
    }
}
