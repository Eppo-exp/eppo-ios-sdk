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
    
    // Retry configuration
    private let maxRetryAttempts: Int
    private let initialRetryDelay: TimeInterval
    
    // MARK: - Initialization
    
    init(
        precompute: Precompute,
        sdkKey: String,
        sdkName: String,
        sdkVersion: String,
        host: String = precomputedBaseUrl,
        maxRetryAttempts: Int = 3,
        initialRetryDelay: TimeInterval = 1.0,
        urlSession: URLSession = .shared
    ) {
        self._precompute = precompute
        self.sdkKey = sdkKey
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
        self.host = host
        self.maxRetryAttempts = max(1, maxRetryAttempts) // Ensure at least one attempt
        self.initialRetryDelay = max(0.1, initialRetryDelay) // Minimum 100ms delay
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
        
        // Perform request with retry logic
        return try await performRequestWithRetry(request: request)
    }
    
    /// Performs a request with exponential backoff retry logic
    func performRequestWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        
        for attempt in 0..<maxRetryAttempts {
            do {
                let (data, response) = try await urlSession.data(for: request)
                
                // Check if we should retry based on response
                if let httpResponse = response as? HTTPURLResponse {
                    // Success (2xx, 3xx) - return immediately
                    if httpResponse.statusCode < 400 {
                        return (data, response)
                    }
                    
                    // Don't retry on client errors (4xx) except for 429 (rate limit)
                    if httpResponse.statusCode >= 400 && httpResponse.statusCode < 500 && httpResponse.statusCode != 429 {
                        return (data, response)
                    }
                    
                    // Rate limit (429) or server error (5xx) - will retry
                    lastError = NetworkError.httpError(statusCode: httpResponse.statusCode)
                } else {
                    return (data, response)
                }
            } catch {
                lastError = error
                
                if !isRetryableError(error) {
                    throw error
                }
            }
            
            // If not the last attempt, wait before retrying
            if attempt < maxRetryAttempts - 1 {
                let delay = calculateRetryDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // All retries exhausted
        throw lastError ?? NetworkError.invalidResponse
    }
    
    /// Calculates the retry delay using exponential backoff with jitter
    internal func calculateRetryDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: delay = initialDelay * 2^attempt
        let exponentialDelay = initialRetryDelay * pow(2.0, Double(attempt))
        
        // Add jitter (±25%) to prevent thundering herd
        let jitterRange = exponentialDelay * 0.25
        let jitter = Double.random(in: -jitterRange...jitterRange)
        
        // Cap at 60 seconds
        return min(exponentialDelay + jitter, 60.0)
    }
    
    /// Determines if an error is retryable
    internal func isRetryableError(_ error: Error) -> Bool {
        // Retry on URLError cases that indicate temporary issues
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        
        // Retry on our own network errors
        if let networkError = error as? NetworkError {
            switch networkError {
            case .httpError(let statusCode):
                // Retry on server errors (5xx) and rate limiting (429)
                return statusCode >= 500 || statusCode == 429
            default:
                return false
            }
        }
        
        return false
    }
}

// MARK: - Supporting Types

/// Payload for requesting precomputed flags
struct PrecomputedFlagsPayload: Encodable {
    let subjectKey: String
    let subjectAttributes: [String: EppoValue]
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