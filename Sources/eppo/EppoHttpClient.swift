import Foundation

public enum EppoHttpClientErrors : Error {
    case invalidURL
}

public protocol EppoHttpClient {
    func get(_ path: String) async throws -> (Data, URLResponse);
}

public class NetworkEppoHttpClient : EppoHttpClient {
    private let baseURL: String
    private let apiKey: String
    private let sdkName: String
    private let sdkVersion: String

    public init(
        baseURL: String,
        apiKey: String,
        sdkName: String,
        sdkVersion: String
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
    }

    public func get(_ path: String) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: self.baseURL)

        // Assuming `path` does not start with a "/", append it conditionally
        components?.path += path

        // Set up the query items
        let queryItems = [
            URLQueryItem(name: "sdkName", value: "ios"),
            URLQueryItem(name: "sdkVersion", value: sdkVersion),
            URLQueryItem(name: "apiKey", value: self.apiKey)
        ]
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw Errors.invalidURL;
        }

        return try await URLSession.shared.data(from: url);
    }
}
