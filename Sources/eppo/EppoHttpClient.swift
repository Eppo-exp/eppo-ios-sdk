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
        var urlString = self.baseURL + path
        urlString += "?sdkName=ios";
        urlString += "&sdkVersion=" + sdkVersion;
        urlString += "&apiKey=" + self.apiKey;

        guard let url = URL(string: urlString) else {
            throw Errors.invalidURL;
        }

        return try await URLSession.shared.data(from: url);
    }
}
