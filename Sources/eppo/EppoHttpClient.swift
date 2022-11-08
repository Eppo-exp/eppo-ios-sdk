import Foundation

public enum EppoHttpClientErrors : Error {
    case invalidURL
}

public protocol EppoHttpClient {
    func get(_ url: URL) async throws -> (Data, URLResponse);
}

public class NetworkEppoHttpClient : EppoHttpClient {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, URLResponse) {
        return try await URLSession.shared.data(from: url);
    }
}
