import XCTest
@testable import eppo

final class SdkTokenDecoderTests: XCTestCase {
    
    func testExtractEventIngestionHostname() {
        let token = SdkTokenDecoder("zCsQuoHJxVPp895.ZWg9MTIzNDU2LmUudGVzdGluZy5lcHBvLmNsb3Vk")
        XCTAssertEqual(token.getEventIngestionHostname(), "123456.e.testing.eppo.cloud")
    }
    
    func testExtractSubdomain() {
        let token = SdkTokenDecoder("zCsQuoHJxVPp895.Y3M9ZXhwZXJpbWVudCZlaD1hYmMxMjMuZXBwby5jbG91ZA==")
        XCTAssertEqual(token.getSubdomain(), "experiment")
    }
    
    func testExtractMultipleParameters() {
        let params = "eh=12+3456/.e.testing.eppo.cloud&cs=test+subdomain/special"
        let encoded = Data(params.utf8).base64EncodedString()
        let token = SdkTokenDecoder("zCsQuoHJxVPp895.\(encoded)")
        
        XCTAssertEqual(token.getEventIngestionHostname(), "12 3456/.e.testing.eppo.cloud")
        XCTAssertEqual(token.getSubdomain(), "test subdomain/special")
    }
    
    func testTokenWithoutRequiredParameter() {
        let tokenWithoutEh = SdkTokenDecoder("zCsQuoHJxVPp895.Y3M9ZXhwZXJpbWVudA==") // only cs=experiment
        XCTAssertNil(tokenWithoutEh.getEventIngestionHostname())
        XCTAssertEqual(tokenWithoutEh.getSubdomain(), "experiment")
        XCTAssertTrue(tokenWithoutEh.isValid())
        
        let tokenWithoutCs = SdkTokenDecoder("zCsQuoHJxVPp895.ZWg9YWJjMTIzLmVwcG8uY2xvdWQ=") // only eh=abc123.eppo.cloud
        XCTAssertEqual(tokenWithoutCs.getEventIngestionHostname(), "abc123.eppo.cloud")
        XCTAssertNil(tokenWithoutCs.getSubdomain())
        XCTAssertTrue(tokenWithoutCs.isValid())
    }
    
    func testInvalidToken() {
        let invalidToken = SdkTokenDecoder("zCsQuoHJxVPp895")
        XCTAssertNil(invalidToken.getEventIngestionHostname())
        XCTAssertNil(invalidToken.getSubdomain())
        XCTAssertFalse(invalidToken.isValid())
        
        let invalidEncodingToken = SdkTokenDecoder("zCsQuoHJxVPp895.%%%")
        XCTAssertNil(invalidEncodingToken.getEventIngestionHostname())
        XCTAssertNil(invalidEncodingToken.getSubdomain())
        XCTAssertFalse(invalidEncodingToken.isValid())
    }
    
    func testOriginalTokenAccess() {
        let tokenString = "zCsQuoHJxVPp895.ZWg9MTIzNDU2LmUudGVzdGluZy5lcHBvLmNsb3Vk"
        let token = SdkTokenDecoder(tokenString)
        XCTAssertEqual(token.getToken(), tokenString)
    }
}
