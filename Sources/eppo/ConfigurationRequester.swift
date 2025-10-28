import Foundation

let UFC_CONFIG_URL = "/flag-config/v1/config"

class ConfigurationRequester {
    private let httpClient: EppoHttpClient
    private let maxConfigurationFetchRetries: Int
    private var debugLogger: ((String) -> Void)?

    public init(httpClient: EppoHttpClient, maxConfigurationFetchRetries: Int = 1) {
        self.httpClient = httpClient
        self.maxConfigurationFetchRetries = maxConfigurationFetchRetries
        self.debugLogger = nil
    }
    
    public func setDebugLogger(_ logger: @escaping (String) -> Void) {
        self.debugLogger = logger
    }

    public func fetchConfigurations() async throws -> Configuration {
        let networkStartTime = Date()
        debugLogger?("Starting network request to fetch configuration")

        var lastError: Error?
        for attempt in 1...maxConfigurationFetchRetries {
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
                if attempt < maxConfigurationFetchRetries {
                    let delayMs = Int(pow(2.0, Double(attempt - 1))) * 1000 // Exponential backoff: 1s, 2s, 4s, etc.
                    debugLogger?("Retrying configuration fetch in \(delayMs)ms (attempt \(attempt + 1) of \(maxConfigurationFetchRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
                }
            }
        }

        // If we get here, all retries failed
        debugLogger?("All configuration fetch attempts failed after \(maxConfigurationFetchRetries) attempts")
        throw lastError ?? NSError(domain: "ConfigurationRequester", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error during configuration fetch"])
    }
}
