import XCTest
@testable import eppo

final class NetworkEppoHttpClientTests: XCTestCase {
    
    func testGetEffectiveBaseURL() {
        class TestableNetworkEppoHttpClient: NetworkEppoHttpClient {
            func testGetEffectiveBaseURL() -> String {
                return getEffectiveBaseURL()
            }
        }
        
        let clientWithSubdomain = TestableNetworkEppoHttpClient(
            baseURL: defaultHost,
            sdkKey: "abc.Y3M9dGVzdC1zdWJkb21haW4=", // cs=test-subdomain
            sdkName: "test",
            sdkVersion: "1.0.0"
        )
        XCTAssertEqual(clientWithSubdomain.testGetEffectiveBaseURL(), "https://test-subdomain.fscdn.eppo.cloud/api")
        
        let clientWithCustomHost = TestableNetworkEppoHttpClient(
            baseURL: "https://custom-domain.com",
            sdkKey: "abc.Y3M9dGVzdC1zdWJkb21haW4=", // cs=test-subdomain
            sdkName: "test",
            sdkVersion: "1.0.0"
        )
        XCTAssertEqual(clientWithCustomHost.testGetEffectiveBaseURL(), "https://custom-domain.com")
        
        let clientWithoutSubdomain = TestableNetworkEppoHttpClient(
            baseURL: defaultHost,
            sdkKey: "abc.ZWg9ZXZlbnQtaG9zdG5hbWU=", // eh=event-hostname
            sdkName: "test",
            sdkVersion: "1.0.0"
        )
        XCTAssertEqual(clientWithoutSubdomain.testGetEffectiveBaseURL(), defaultHost)
        
        let clientWithInvalidToken = TestableNetworkEppoHttpClient(
            baseURL: defaultHost,
            sdkKey: "invalid-token",
            sdkName: "test",
            sdkVersion: "1.0.0"
        )
        XCTAssertEqual(clientWithInvalidToken.testGetEffectiveBaseURL(), defaultHost)
    }
}
