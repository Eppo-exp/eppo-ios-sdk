import Foundation

public enum EppoHttpClientErrors : Error {
    case invalidURL
}

public protocol EppoHttpClient {
    func get(_ path: String) async throws -> (Data, URLResponse);
}

public class NetworkEppoHttpClient : EppoHttpClient {
    private let baseURL: String
    private let sdkToken: String
    private let sdkName: String
    private let sdkVersion: String
    private let tokenDecoder: SdkTokenDecoder

    public init(
        baseURL: String,
        sdkKey: String,
        sdkName: String,
        sdkVersion: String
    ) {
        self.baseURL = baseURL
        self.sdkToken = sdkKey
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
        self.tokenDecoder = SdkTokenDecoder(sdkKey)
    }

    public func get(_ path: String) async throws -> (Data, URLResponse) {
        let effectiveBaseURL = getEffectiveBaseURL()
        var components = URLComponents(string: effectiveBaseURL)

        // Assuming `path` does not start with a "/", append it conditionally
        components?.path += path

        // Set up the query items
        let queryItems = [
            URLQueryItem(name: "sdkName", value: "ios"),
            URLQueryItem(name: "sdkVersion", value: sdkVersion),
            // Server expects the existing response to continue to be `apiKey`.
            URLQueryItem(name: "apiKey", value: self.sdkToken)
        ]
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw Errors.invalidURL;
        }

        return try await URLSession.shared.data(from: url);
    }
    
    /**
     * Determines the effective base URL to use for API requests.
     * If a valid subdomain is found in the SDK token, it will be used to construct the URL.
     * Otherwise, falls back to the default base URL.
     */
    private func getEffectiveBaseURL() -> String {
        if tokenDecoder.isValid(), let subdomain = tokenDecoder.getSubdomain() {
            if baseURL == defaultHost {
                return "https://\(subdomain).fscdn.eppo.cloud/api"
            }
        }
        
        return baseURL
    }
}
