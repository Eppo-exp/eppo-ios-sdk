import XCTest
@testable import EppoFlagging

final class ApiEndpointsTests: XCTestCase {
    // Test token with subdomain "test"
    private let keyWithSubdomain = SDKKey("zCsQuoHJxVPp895.Y3M9dGVzdA==") // cs=test
    
    // Test token without subdomain
    private let enhancedKeyWithoutSubdomain = SDKKey("signature.Zm9vPWJhcg==") //foo=bar
    
    // Invalid token
    private let keyWithInvalidPayload = SDKKey("invalid.token")
    
    func testDefaultHostWithSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkKey: keyWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://test.fscdn.eppo.cloud/api")
    }
    
    func testDefaultHostWithoutSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkKey: enhancedKeyWithoutSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://fscdn.eppo.cloud/api")
    }
    
    func testDefaultHostWithInvalidToken() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkKey: keyWithInvalidPayload)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://fscdn.eppo.cloud/api")
    }
    
    func testCustomBaseURL() throws {
        let customURL = "https://custom.eppo.cloud/api"
        let endpoints = ApiEndpoints(baseURL: customURL, sdkKey: keyWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, customURL)
    }
    
    func testCustomBaseURLWithInvalidToken() throws {
        let customURL = "https://custom.eppo.cloud/api"
        let endpoints = ApiEndpoints(baseURL: customURL, sdkKey: keyWithInvalidPayload)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, customURL)
    }
    
    func testDefaultHostAsCustomURL() throws {
        // This should trigger the warning and use the subdomain logic
        let endpoints = ApiEndpoints(baseURL: "https://fscdn.eppo.cloud/api", sdkKey: keyWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://test.fscdn.eppo.cloud/api")
    }
    
    func testNilBaseURLWithSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkKey: keyWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://test.fscdn.eppo.cloud/api")
    }
    
    func testNilBaseURLWithoutSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkKey: enhancedKeyWithoutSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://fscdn.eppo.cloud/api")
    }
} 