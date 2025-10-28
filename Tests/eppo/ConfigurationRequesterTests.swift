import XCTest
@testable import EppoFlagging

class ConfigurationRequesterTests: XCTestCase {
    var httpClientMock: EppoHttpClientMock!
    var configurationRequester: ConfigurationRequester!

    override func setUp() {
        super.setUp()
        httpClientMock = EppoHttpClientMock()
        configurationRequester = ConfigurationRequester(httpClient: httpClientMock)
    }

    override func tearDown() {
        httpClientMock = nil
        configurationRequester = nil
        super.tearDown()
    }

    func testRetryFunctionality() async throws {
        // Create a requester
        let httpClientMock = EppoHttpClientMockWithCallTracking()
        let configurationRequester = ConfigurationRequester(httpClient: httpClientMock)

        // Configure mock to fail on first call, succeed on second call
        let validConfigData = """
        {
            "flags": {},
            "bandits": {},
            "obfuscated": true,
            "format": "SERVER",
            "createdAt": "2023-01-01T00:00:00.000Z",
            "environment": {
                "name": "test"
            }
        }
        """.data(using: .utf8)!

        httpClientMock.responses = [
            .failure(NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "First attempt fails"])),
            .success((validConfigData, URLResponse()))
        ]

        // Execute the fetch with 2 max retries - should succeed on second attempt
        let configuration = try await configurationRequester.fetchConfigurations(maxRetries: 2)

        // Verify that exactly 2 calls were made
        XCTAssertEqual(httpClientMock.callCount, 2, "Expected exactly 2 HTTP calls (1 failure + 1 success)")

        // Verify that a valid configuration was returned
        XCTAssertNotNil(configuration, "Configuration should not be nil after successful retry")
    }

    func testRetryExhaustion() async throws {
        // Create a requester
        let httpClientMock = EppoHttpClientMockWithCallTracking()
        let configurationRequester = ConfigurationRequester(httpClient: httpClientMock)

        // Configure mock to always fail
        let testError = NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Always fails"])
        httpClientMock.responses = [
            .failure(testError),
            .failure(testError)
        ]

        // Execute the fetch with 2 max retries - should fail after all retries
        do {
            _ = try await configurationRequester.fetchConfigurations(maxRetries: 2)
            XCTFail("Expected fetchConfigurations to throw an error after all retries exhausted")
        } catch {
            // Verify that exactly 2 calls were made
            XCTAssertEqual(httpClientMock.callCount, 2, "Expected exactly 2 HTTP calls (all failures)")

            // Verify the error is the one we expected
            XCTAssertEqual((error as NSError).localizedDescription, testError.localizedDescription)
        }
    }

    func testZeroRetriesMakesOneAttempt() async throws {
        // Create a requester
        let httpClientMock = EppoHttpClientMockWithCallTracking()
        let configurationRequester = ConfigurationRequester(httpClient: httpClientMock)

        let validConfigData = """
        {
            "flags": {},
            "bandits": {},
            "obfuscated": true,
            "format": "SERVER",
            "createdAt": "2023-01-01T00:00:00.000Z",
            "environment": {
                "name": "test"
            }
        }
        """.data(using: .utf8)!

        httpClientMock.responses = [
            .success((validConfigData, URLResponse()))
        ]

        // Execute the fetch with 0 retries - should still make 1 attempt
        let configuration = try await configurationRequester.fetchConfigurations(maxRetries: 0)

        // Verify that exactly 1 call was made
        XCTAssertEqual(httpClientMock.callCount, 1, "Expected exactly 1 HTTP call when maxRetries = 0")

        // Verify that a valid configuration was returned
        XCTAssertNotNil(configuration, "Configuration should not be nil")
    }
}

class EppoHttpClientMock: EppoHttpClient {
    var getCompletionResult: (Data?, Error?)?

    func get(_ url: String) async throws -> (Data, URLResponse) {
        if let error = getCompletionResult?.1 {
            throw error
        }
        return (getCompletionResult?.0 ?? Data(), URLResponse())
    }
}

class EppoHttpClientMockWithCallTracking: EppoHttpClient {
    var callCount = 0
    var responses: [Result<(Data, URLResponse), Error>] = []

    func get(_ url: String) async throws -> (Data, URLResponse) {
        defer { callCount += 1 }

        guard callCount < responses.count else {
            throw NSError(domain: "MockError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No more responses configured"])
        }

        let result = responses[callCount]

        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}
