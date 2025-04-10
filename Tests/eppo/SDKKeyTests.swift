import XCTest
@testable import EppoFlagging

final class SDKKeyTests: XCTestCase {
    
    func testExtractSubdomain() {
        let token = SDKKey("zCsQuoHJxVPp895.Zm9vPWJhciZjcz1leHBlcmltZW50") // cs=experiment
        XCTAssertEqual(token.getSubdomain(), "experiment")
    }
    
    
    func testTokenWithoutRequiredParameter() {
        let tokenWithoutCs = SDKKey("a562v63ff55r2.Zm9vPWJhcg==") // no cs param
        XCTAssertNil(tokenWithoutCs.getSubdomain())
        XCTAssertTrue(tokenWithoutCs.isValid())
    }
    
    func testInvalidToken() {
        let invalidToken = SDKKey("zCsQuoHJxVPp895")
        XCTAssertNil(invalidToken.getSubdomain())
        XCTAssertFalse(invalidToken.isValid())
    }
    
    func testOriginalTokenAccess() {
        let tokenString = "zCsQuoHJxVPp895.3M9ZXhwZXJpbWVudCZlaD1hYmMxMjMuZXBwby5jbG91ZA=="
        let token = SDKKey(tokenString)
        XCTAssertEqual(token.getToken(), tokenString)
    }
}
