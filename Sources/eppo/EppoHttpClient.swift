import Foundation

enum EppoHttpClientErrors : Error {
    case invalidURL
}

protocol EppoHttpClient {
    func get(_ url: URL) throws -> (Data, URLResponse);
    func post() throws;
}

class NetworkEppoHttpClient : EppoHttpClient {
    public init() {}

    func get(_ url: URL) throws -> (Data, URLResponse) {
        throw EppoHttpClientErrors.invalidURL
    }

    func post() throws {}
}
