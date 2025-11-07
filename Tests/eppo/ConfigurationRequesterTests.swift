import XCTest
@testable import EppoFlagging

class ConfigurationRequesterTests: XCTestCase {
    var httpClientMock: EppoHttpClientMock!
    var configurationRequester: ConfigurationRequester!

    override func setUp() {
        super.setUp()
        httpClientMock = EppoHttpClientMock()
        configurationRequester = ConfigurationRequester(httpClient: httpClientMock, requestProtobuf: false)
    }

    override func tearDown() {
        httpClientMock = nil
        configurationRequester = nil
        super.tearDown()
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
