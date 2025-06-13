import Foundation

public enum EppoHttpClientErrors: Error {
    case invalidURL
}

public protocol EppoHttpClient {
    func get(_ path: String) async throws -> (Data, URLResponse)
}

public class NetworkEppoHttpClient: EppoHttpClient {
    private let baseURL: String
    private let sdkKey: String
    private let sdkName: String
    private let sdkVersion: String

    public init(
        baseURL: String,
        sdkKey: String,
        sdkName: String,
        sdkVersion: String
    ) {
        self.baseURL = baseURL
        self.sdkKey = sdkKey
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
    }

    public func get(_ path: String) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: self.baseURL)

        // Assuming `path` does not start with a "/", append it conditionally
        components?.path += path

        // Set up the query items
        let queryItems = [
            URLQueryItem(name: "sdkName", value: self.sdkName),
            URLQueryItem(name: "sdkVersion", value: self.sdkVersion),
            // Server expects the existing response to continue to be `apiKey`.
            URLQueryItem(name: "apiKey", value: self.sdkKey)
        ]
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw Errors.invalidURL
        }

        return try await URLSession.shared.data(from: url)
    }
}
