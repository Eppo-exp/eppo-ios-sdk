import XCTest
@testable import eppo_flagging

class HttpConfigurationRequesterTests: XCTestCase {
    var httpClientMock: EppoHttpClientMock!
    var configurationRequester: HttpConfigurationRequester!

    override func setUp() {
        super.setUp()
        httpClientMock = EppoHttpClientMock()
        configurationRequester = HttpConfigurationRequester(httpClient: httpClientMock)
    }

    override func tearDown() {
        httpClientMock = nil
        configurationRequester = nil
        super.tearDown()
    }
}

class JsonConfigurationRequesterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testJsonConfigurationRequester_ValidConfig() async throws {
        let validJson = """
        {
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": {
            "name": "Test"
          },
          "flags": {
            "empty_flag": {
              "key": "empty_flag",
              "enabled": true,
              "variationType": "STRING",
              "variations": {},
              "allocations": [],
              "totalShards": 10000
            }
          }
        }
        """
        let requester = JsonConfigurationRequester(configurationJson: validJson)
        
        let config = try requester.fetchConfigurations()
        
        XCTAssertEqual(config.flags.count, 1)
        XCTAssertEqual(config.flags.keys.first, "empty_flag")
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
