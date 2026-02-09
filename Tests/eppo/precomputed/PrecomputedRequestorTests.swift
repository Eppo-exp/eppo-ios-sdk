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
        let invalidURLError = NetworkError.invalidURL
        XCTAssertEqual(invalidURLError.errorDescription, "Invalid URL")

        let invalidResponseError = NetworkError.invalidResponse
        XCTAssertEqual(invalidResponseError.errorDescription, "Invalid response from server")

        let httpError = NetworkError.httpError(statusCode: 404)
        XCTAssertEqual(httpError.errorDescription, "HTTP error: 404")

        let decodingError = NetworkError.decodingError(NSError(domain: "test", code: 1))
        XCTAssertTrue(decodingError.errorDescription?.contains("Failed to decode response") ?? false)
    }

    // MARK: - ContextAttributes Tests

    func testContextAttributesSeparatesNumericAndCategorical() {
        let flatAttributes: [String: EppoValue] = [
            "age": EppoValue(value: 25),
            "score": EppoValue(value: 99.5),
            "country": EppoValue(value: "US"),
            "isPremium": EppoValue(value: true)
        ]

        let contextAttributes = ContextAttributes(from: flatAttributes)

        XCTAssertEqual(contextAttributes.numericAttributes.count, 2)
        XCTAssertNotNil(contextAttributes.numericAttributes["age"])
        XCTAssertNotNil(contextAttributes.numericAttributes["score"])

        XCTAssertEqual(contextAttributes.categoricalAttributes.count, 2)
        XCTAssertNotNil(contextAttributes.categoricalAttributes["country"])
        XCTAssertNotNil(contextAttributes.categoricalAttributes["isPremium"])
    }

    func testContextAttributesEncodesToExpectedFormat() throws {
        let attributes: [String: EppoValue] = [
            "age": EppoValue(value: 30),
            "country": EppoValue(value: "UK")
        ]

        let contextAttributes = ContextAttributes(from: attributes)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(contextAttributes)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"numericAttributes\""))
        XCTAssertTrue(json.contains("\"categoricalAttributes\""))
    }

    func testPayloadUsesSnakeCaseTopLevelAndCamelCaseNestedKeys() throws {
        let payload = PrecomputedFlagsPayload(
            subjectKey: "test-user",
            subjectAttributes: [
                "age": EppoValue(value: 30),
                "country": EppoValue(value: "UK")
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(jsonObject["subject_key"])
        XCTAssertNotNil(jsonObject["subject_attributes"])

        let subjectAttributes = try XCTUnwrap(jsonObject["subject_attributes"] as? [String: Any])
        XCTAssertNotNil(subjectAttributes["numericAttributes"])
        XCTAssertNotNil(subjectAttributes["categoricalAttributes"])
    }

    func testContextAttributesIncludesNullsInCategorical() {
        let attributes: [String: EppoValue] = [
            "validString": EppoValue(value: "test"),
            "validNumber": EppoValue(value: 42),
            "nullValue": EppoValue()
        ]

        let contextAttributes = ContextAttributes(from: attributes)

        XCTAssertEqual(contextAttributes.numericAttributes.count, 1)
        XCTAssertEqual(contextAttributes.categoricalAttributes.count, 2)
        XCTAssertNotNil(contextAttributes.categoricalAttributes["nullValue"])
    }
}
