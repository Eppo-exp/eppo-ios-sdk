import XCTest
@testable import EppoFlagging

final class SdkTokenDecoderTests: XCTestCase {
    
    func testExtractSubdomain() {
        let token = SdkTokenDecoder("zCsQuoHJxVPp895.Y3M9ZXhwZXJpbWVudCZlaD1hYmMxMjMuZXBwby5jbG91ZA==")
        XCTAssertEqual(token.getSubdomain(), "experiment")
    }
    
    
    func testTokenWithoutRequiredParameter() {
        let tokenWithoutCs = SdkTokenDecoder("zCsQuoHJxVPp895.ZWg9YWJjMTIzLmVwcG8uY2xvdWQ=") // only eh=abc123.eppo.cloud
        XCTAssertNil(tokenWithoutCs.getSubdomain())
        XCTAssertTrue(tokenWithoutCs.isValid())
    }
    
    func testInvalidToken() {
        let invalidToken = SdkTokenDecoder("zCsQuoHJxVPp895")
        XCTAssertNil(invalidToken.getSubdomain())
        XCTAssertFalse(invalidToken.isValid())
    }
    
    func testOriginalTokenAccess() {
        let tokenString = "zCsQuoHJxVPp895.ZWg9MTIzNDU2LmUudGVzdGluZy5lcHBvLmNsb3Vk"
        let token = SdkTokenDecoder(tokenString)
        XCTAssertEqual(token.getToken(), tokenString)
    }
}
