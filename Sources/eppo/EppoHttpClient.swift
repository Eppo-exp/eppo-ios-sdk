import Foundation

public enum EppoHttpClientErrors : Error {
    case invalidURL
}

public protocol EppoHttpClient {
    func get(_ url: URL) throws -> (Data, URLResponse);
}

public class NetworkEppoHttpClient : EppoHttpClient {
    public init() {}

    public func get(_ url: URL) throws -> (Data, URLResponse) {
        throw EppoHttpClientErrors.invalidURL
    }

    public func post() throws {}
}
