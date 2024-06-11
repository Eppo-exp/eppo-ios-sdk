import XCTest
@testable import eppo_flagging

class UtilsTests: XCTestCase {
    
    func testGetISODate() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01T00:00:00Z
        let isoDate = Utils.getISODate(date)
        XCTAssertEqual(isoDate, "2021-01-01T00:00:00.000Z")
    }
    
    func testGetMD5Hex() {
        let string = "Hello, world!"
        let md5Hex = Utils.getMD5Hex(string)
        XCTAssertEqual(md5Hex, "6cd3556deb0da54bca060b4c39479839")
    }
    
    func testBase64Decode() {
        let encodedString = "SGVsbG8sIHdvcmxkIQ=="
        let decodedString = Utils.base64Decode(encodedString)
        XCTAssertEqual(decodedString, "Hello, world!")
    }
}
