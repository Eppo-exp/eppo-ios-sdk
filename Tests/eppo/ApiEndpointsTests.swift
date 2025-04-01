import XCTest
@testable import EppoFlagging

final class ApiEndpointsTests: XCTestCase {
    // Test token with subdomain "test"
    private let validTokenWithSubdomain = "Y3M9dGVzdA==.zCsQuoHJxVPp895" // cs=test
    
    // Test token without subdomain
    private let validTokenWithoutSubdomain = "Zm9vPWJhcg==.signature" //foo=bar
    
    // Invalid token
    private let invalidToken = "invalid.token"
    
    func testDefaultHostWithSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkToken: validTokenWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://test.fscdn.eppo.cloud/api")
    }
    
    func testDefaultHostWithoutSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkToken: validTokenWithoutSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://fscdn.eppo.cloud/api")
    }
    
    func testDefaultHostWithInvalidToken() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkToken: invalidToken)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://fscdn.eppo.cloud/api")
    }
    
    func testCustomBaseURL() throws {
        let customURL = "https://custom.eppo.cloud/api"
        let endpoints = ApiEndpoints(baseURL: customURL, sdkToken: validTokenWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, customURL)
    }
    
    func testCustomBaseURLWithInvalidToken() throws {
        let customURL = "https://custom.eppo.cloud/api"
        let endpoints = ApiEndpoints(baseURL: customURL, sdkToken: invalidToken)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, customURL)
    }
    
    func testDefaultHostAsCustomURL() throws {
        // This should trigger the warning and use the subdomain logic
        let endpoints = ApiEndpoints(baseURL: "https://fscdn.eppo.cloud/api", sdkToken: validTokenWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://test.fscdn.eppo.cloud/api")
    }
    
    func testNilBaseURLWithSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkToken: validTokenWithSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://test.fscdn.eppo.cloud/api")
    }
    
    func testNilBaseURLWithoutSubdomain() throws {
        let endpoints = ApiEndpoints(baseURL: nil, sdkToken: validTokenWithoutSubdomain)
        let baseURL = endpoints.baseURL
        
        XCTAssertEqual(baseURL, "https://fscdn.eppo.cloud/api")
    }
} 