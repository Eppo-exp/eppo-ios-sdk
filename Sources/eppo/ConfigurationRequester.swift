import Foundation

let UFC_CONFIG_URL = "/flag-config/v1/config"

class ConfigurationRequester {
    private let httpClient: EppoHttpClient
    private var debugLogger: ((String) -> Void)?

    public init(httpClient: EppoHttpClient) {
        self.httpClient = httpClient
        self.debugLogger = nil
    }
    
    public func setDebugLogger(_ logger: @escaping (String) -> Void) {
        self.debugLogger = logger
    }

    /// Fetches configuration from the remote server with configurable retry logic.
    ///
    /// - Parameter maxRetries: Number of attempts to make (including the initial attempt).
    ///   Default is 1 (no retries). Use higher values for initial startup fetches where
    ///   fast recovery is important. Use 1 for polling contexts where external retry
    ///   logic (like Poller) handles failures with exponential backoff.
    ///
    /// - Note: Retries use exponential backoff with 100ms base delay (100ms, 200ms, 400ms, etc.)
    ///   optimized for startup performance.
    public func fetchConfigurations(maxRetries: Int = 1) async throws -> Configuration {
        let networkStartTime = Date()
        debugLogger?("Starting network request to fetch configuration")

        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await httpClient.get(UFC_CONFIG_URL)

                let networkCompleteTime = Date()
                let networkDuration = networkCompleteTime.timeIntervalSince(networkStartTime)

                // Log response details
                let networkDurationMs = networkDuration * 1000
                if let httpResponse = response as? HTTPURLResponse {
                    debugLogger?("Network request completed (\(String(format: "%.1f", networkDurationMs))ms, Status: \(httpResponse.statusCode), Data: \(data.count) bytes)")
                } else {
                    debugLogger?("Network request completed (\(String(format: "%.1f", networkDurationMs))ms, Data: \(data.count) bytes)")
                }

                debugLogger?("Starting JSON parsing and configuration creation (parsing \(data.count) bytes)")

                let configuration = try Configuration(flagsConfigurationJson: data, obfuscated: true)

                debugLogger?("JSON parsing completed")

                return configuration
            } catch {
                lastError = error
                debugLogger?("Configuration fetch attempt \(attempt) failed: \(error.localizedDescription)")

                // If this is not the last attempt, wait before retrying
                if attempt < maxRetries {
                    let delayMs = Int(pow(2.0, Double(attempt - 1))) * 100 // Exponential backoff: 100ms, 200ms, 400ms, etc.
                    debugLogger?("Retrying configuration fetch in \(delayMs)ms (attempt \(attempt + 1) of \(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
                }
            }
        }

        // If we get here, all retries failed
        debugLogger?("All configuration fetch attempts failed after \(maxRetries) attempts")
        throw lastError ?? NSError(domain: "ConfigurationRequester", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error during configuration fetch"])
    }
}
