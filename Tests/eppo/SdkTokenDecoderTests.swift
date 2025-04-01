import XCTest
@testable import EppoFlagging

final class SdkTokenDecoderTests: XCTestCase {
    
    func testExtractSubdomain() {
        let token = SdkTokenDecoder("Zm9vPWJhciZjcz1leHBlcmltZW50.zCsQuoHJxVPp895") // cs=experiment
        XCTAssertEqual(token.getSubdomain(), "experiment")
    }
    
    
    func testTokenWithoutRequiredParameter() {
        let tokenWithoutCs = SdkTokenDecoder("Zm9vPWJhcg==.a562v63ff55r2") // no cs param
        XCTAssertNil(tokenWithoutCs.getSubdomain())
        XCTAssertTrue(tokenWithoutCs.isValid())
    }
    
    func testInvalidToken() {
        let invalidToken = SdkTokenDecoder("zCsQuoHJxVPp895")
        XCTAssertNil(invalidToken.getSubdomain())
        XCTAssertFalse(invalidToken.isValid())
    }
    
    func testOriginalTokenAccess() {
        let tokenString = "3M9ZXhwZXJpbWVudCZlaD1hYmMxMjMuZXBwby5jbG91ZA==.zCsQuoHJxVPp895"
        let token = SdkTokenDecoder(tokenString)
        XCTAssertEqual(token.getToken(), tokenString)
    }
}
