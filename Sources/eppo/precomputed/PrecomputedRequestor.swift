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
            subjectAttributes: _precompute.subjectAttributes,
            banditActions: _precompute.banditActions
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

        // Decode the server response and construct configuration
        do {
            let serverResponse = try JSONDecoder().decode(PrecomputedServerResponse.self, from: data)
            return PrecomputedConfiguration(
                flags: serverResponse.flags,
                bandits: serverResponse.bandits,
                salt: serverResponse.salt,
                format: serverResponse.format,
                subject: Subject(
                    subjectKey: _precompute.subjectKey,
                    subjectAttributes: _precompute.subjectAttributes
                ),
                // The server's `createdAt` represents the time this precomputed configuration was published
                publishedAt: serverResponse.createdAt,
                environment: serverResponse.environment
            )
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
    let banditActions: [String: [String: ContextAttributes]]?

    enum CodingKeys: String, CodingKey {
        case subjectKey = "subject_key"
        case subjectAttributes = "subject_attributes"
        case banditActions = "bandit_actions"
    }

    init(
        subjectKey: String,
        subjectAttributes: [String: EppoValue],
        banditActions: [String: [String: [String: EppoValue]]]?
    ) {
        self.subjectKey = subjectKey
        self.subjectAttributes = ContextAttributes(from: subjectAttributes)

        // Transform banditActions to use ContextAttributes for each action
        if let actions = banditActions {
            var transformed: [String: [String: ContextAttributes]] = [:]
            for (flagKey, actionMap) in actions {
                var transformedActions: [String: ContextAttributes] = [:]
                for (actionKey, attributes) in actionMap {
                    transformedActions[actionKey] = ContextAttributes(from: attributes)
                }
                transformed[flagKey] = transformedActions
            }
            self.banditActions = transformed
        } else {
            self.banditActions = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subjectKey, forKey: .subjectKey)
        try container.encode(subjectAttributes, forKey: .subjectAttributes)
        if let banditActions = banditActions, !banditActions.isEmpty {
            try container.encode(banditActions, forKey: .banditActions)
        }
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
            } else {
                categorical[key] = value
            }
        }

        self.numericAttributes = numeric
        self.categoricalAttributes = categorical
    }
}

// MARK: - Server Response

/// Server response format for precomputed flags
struct PrecomputedServerResponse: Decodable {
    let flags: [String: PrecomputedFlag]
    let bandits: [String: PrecomputedBandit]
    let salt: String
    let format: String
    let createdAt: String
    let environment: Environment?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flags = try container.decode([String: PrecomputedFlag].self, forKey: .flags)
        bandits = try container.decodeIfPresent([String: PrecomputedBandit].self, forKey: .bandits) ?? [:]
        salt = try container.decode(String.self, forKey: .salt)
        format = try container.decode(String.self, forKey: .format)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        environment = try container.decodeIfPresent(Environment.self, forKey: .environment)
    }

    private enum CodingKeys: String, CodingKey {
        case flags
        case bandits
        case salt
        case format
        case createdAt
        case environment
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
