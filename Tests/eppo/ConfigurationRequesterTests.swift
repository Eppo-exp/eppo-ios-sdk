import XCTest
@testable import eppo_flagging

class ConfigurationRequesterTests: XCTestCase {
    var httpClientMock: EppoHttpClientMock!
    var configurationRequester: ConfigurationRequester!

    override func setUp() {
        super.setUp()
        httpClientMock = EppoHttpClientMock()
        configurationRequester = ConfigurationRequester(httpClient: httpClientMock)
    }

    override func tearDown() {
        httpClientMock = nil
        configurationRequester = nil
        super.tearDown()
    }

    func testDecodeRACConfig_ValidRACConfigJSON() throws {
        let jsonString = """
        {
            "flags": {
                "feature1": {
                    "enabled": true,
                    "subjectShards": 1,
                    "typedOverrides": {},
                    "rules": [],
                    "allocations": {}
                }
            }
        }
        """
        let racConfig = try ConfigurationRequester.decodeRACConfig(from: jsonString)
        XCTAssertTrue(racConfig.flags.keys.contains("feature1"), "Decoded RACConfig should contain 'feature1'")
    }

    func testDecodeRACConfig_MissingRequiredKeyJSON() throws {
        let jsonString = """
        {
            "flags": {
                "feature1": {
                    "enabled": true
                }
            }
        }
        """
        XCTAssertThrowsError(try ConfigurationRequester.decodeRACConfig(from: jsonString)) { error in
            guard let error = error as NSError? else {
                XCTFail("Error should be of type NSError")
                return
            }
            XCTAssertEqual(error.domain, ConfigurationRequesterError.errorDomain)
            XCTAssertEqual(error.code, 101)
        }
    }

    func testDecodeRACConfig_InvalidJSON() {
        let jsonString = "Invalid JSON"
        XCTAssertThrowsError(try ConfigurationRequester.decodeRACConfig(from: jsonString)) { error in
            guard let error = error as NSError? else {
                XCTFail("Error should be of type NSError")
                return
            }
            XCTAssertEqual(error.domain, ConfigurationRequesterError.errorDomain)
            XCTAssertEqual(error.code, 100)
        }
    }
}

class EppoHttpClientMock: EppoHttpClient {
    var getCompletionResult: (Data?, Error?)?

    func get(_ url: String) async throws -> (Data, URLResponse) {
        if let error = getCompletionResult?.1 {
            throw error
        }
        return (getCompletionResult?.0 ?? Data(), URLResponse())
    }
}
