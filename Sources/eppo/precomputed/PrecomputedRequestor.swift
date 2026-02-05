import Foundation

/// Handles HTTP requests to fetch precomputed flag configurations
class PrecomputedRequestor {
    private let _precompute: Precompute
    private let host: String
    private let sdkKey: String
    private let sdkName: String
    private let sdkVersion: String
    private let urlSession: URLSession

    /// The precompute configuration used for this requestor
    var precompute: Precompute {
        return _precompute
    }

    // MARK: - Initialization

    init(
        precompute: Precompute,
        sdkKey: String,
        sdkName: String,
        sdkVersion: String,
        host: String = precomputedBaseUrl,
        urlSession: URLSession = .shared
    ) {
        self._precompute = precompute
        self.sdkKey = sdkKey
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
        self.host = host
        self.urlSession = urlSession
    }

    // MARK: - Public Methods

    /// Fetches precomputed flags from the server
    func fetchPrecomputedFlags() async throws -> PrecomputedConfiguration {
        let payload = PrecomputedFlagsPayload(
            subjectKey: _precompute.subjectKey,
            subjectAttributes: _precompute.subjectAttributes
        )

        let url = try buildURL()

        // Make the POST request
        let (data, response) = try await performPOSTRequest(url: url, payload: payload)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode the response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let configuration = try decoder.decode(PrecomputedConfiguration.self, from: data)
            return configuration
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}

// MARK: - Private Methods

extension PrecomputedRequestor {

    /// Builds the URL for the precomputed flags endpoint
    func buildURL() throws -> URL {
        var components = URLComponents(string: host)

        // Append the assignments endpoint
        components?.path = "/assignments"

        // Add query parameters
        let queryItems = [
            URLQueryItem(name: "sdkName", value: sdkName),
            URLQueryItem(name: "sdkVersion", value: sdkVersion),
            URLQueryItem(name: "apiKey", value: sdkKey) // Server expects "apiKey" not "sdkKey"
        ]
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        return url
    }

    /// Performs the POST request with the given payload
    func performPOSTRequest(url: URL, payload: PrecomputedFlagsPayload) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(payload)

        // Simple single request like NetworkEppoHttpClient
        return try await urlSession.data(for: request)
    }
}

// MARK: - Supporting Types

/// Payload for requesting precomputed flags
struct PrecomputedFlagsPayload: Encodable {
    let subjectKey: String
    let subjectAttributes: ContextAttributes

    init(subjectKey: String, subjectAttributes: [String: EppoValue]) {
        self.subjectKey = subjectKey
        self.subjectAttributes = ContextAttributes(from: subjectAttributes)
    }
}

/// Attribute context with numeric and categorical separation, as expected by the API.
/// Used for subject attributes and bandit actions.
struct ContextAttributes: Encodable {
    let numericAttributes: [String: EppoValue]
    let categoricalAttributes: [String: EppoValue]

    init(from attributes: [String: EppoValue]) {
        var numeric: [String: EppoValue] = [:]
        var categorical: [String: EppoValue] = [:]

        for (key, value) in attributes {
            if value.isNumeric() {
                numeric[key] = value
            } else if !value.isNull() {
                categorical[key] = value
            }
        }

        self.numericAttributes = numeric
        self.categoricalAttributes = categorical
    }
}

// MARK: - Errors

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
