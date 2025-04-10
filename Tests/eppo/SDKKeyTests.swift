import XCTest
@testable import EppoFlagging

final class SDKKeyTests: XCTestCase {
    
    func testExtractSubdomain() {
        let key = SDKKey("zCsQuoHJxVPp895.Zm9vPWJhciZjcz1leHBlcmltZW50") // cs=experiment
        XCTAssertEqual(key.subdomain, "experiment")
    }
    
    func testTokenWithoutRequiredParameter() {
        let keyWithoutCs = SDKKey("a562v63ff55r2.Zm9vPWJhcg==") // no cs param
        XCTAssertNil(keyWithoutCs.subdomain)
        XCTAssertTrue(keyWithoutCs.isValid)
    }
    
    func testInvalidToken() {
        let invalidKey = SDKKey("zCsQuoHJxVPp895")
        XCTAssertNil(invalidKey.subdomain)
        XCTAssertFalse(invalidKey.isValid)
    }
    
    func testOriginalTokenAccess() {
        let tokenString = "zCsQuoHJxVPp895.3M9ZXhwZXJpbWVudCZlaD1hYmMxMjMuZXBwby5jbG91ZA=="
        let key = SDKKey(tokenString)
        XCTAssertEqual(key.token, tokenString)
    }
    
    func testErrorEnum() {
        // This test demonstrates the error enum exists
        let error = SDKKey.SDKKeyError.invalidFormat
        XCTAssertNotNil(error)
    }
}
