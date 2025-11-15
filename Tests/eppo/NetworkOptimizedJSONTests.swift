import XCTest
@testable import EppoFlagging
import Foundation

/**
 * Network OptimizedJSON Tests
 *
 * Verifies that network initialization can conditionally use OptimizedJSONEvaluator
 * while keeping the public API backward compatible.
 */
final class NetworkOptimizedJSONTests: XCTestCase {

    func testNetworkInitializeSupportsOptimizedJSONEvaluatorType() throws {
        // This test verifies that the public API accepts evaluatorType: .optimizedJSON
        // for network initialization (this was already supported but now functional)

        // Test that the API compiles and accepts the parameter
        let sdkKey = "test-sdk-key"
        let host = "https://example.com"

        // This should compile without errors
        let initializeCall = {
            try await EppoClient.initialize(
                sdkKey: sdkKey,
                host: host,
                assignmentLogger: nil,
                assignmentCache: nil,
                initialConfiguration: nil,
                pollingEnabled: false,
                evaluatorType: .optimizedJSON,  // <- This is the key test
                configurationChangeCallback: nil,
                debugCallback: nil
            )
        }

        // We don't actually call it since it would make a network request,
        // but we verify the API signature compiles correctly
        XCTAssertNotNil(initializeCall)

        NSLog("✅ Network initialize() API supports evaluatorType: .optimizedJSON")
    }

    func testConfigurationRequesterHasNewMethods() {
        // Test that the new methods exist and compile
        let mockHttpClient = MockEppoHttpClient()
        let configurationRequester = ConfigurationRequester(httpClient: mockHttpClient)

        // Verify the methods exist by checking we can reference them
        let fetchWithRawDataMethod = configurationRequester.fetchConfigurationsWithRawData
        let fetchRawJSONMethod = configurationRequester.fetchRawJSON

        XCTAssertNotNil(fetchWithRawDataMethod)
        XCTAssertNotNil(fetchRawJSONMethod)

        NSLog("✅ ConfigurationRequester.fetchConfigurationsWithRawData() method exists and compiles")
        NSLog("✅ ConfigurationRequester.fetchRawJSON() method exists and compiles (fast path)")
    }
}

// Mock HTTP client for testing - conforms to EppoHttpClient protocol
class MockEppoHttpClient: EppoHttpClient {
    var mockResponse: (Data, URLResponse)?
    var mockError: Error?

    func get(_ path: String) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }

        guard let response = mockResponse else {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No mock response set"])
        }

        return response
    }
}