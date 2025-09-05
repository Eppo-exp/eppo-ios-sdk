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

    public func fetchConfigurations() async throws -> Configuration {
        let networkStartTime = Date()
        debugLogger?("Starting network request to fetch configuration")
        
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
        
        debugLogger?("Starting JSON parsing and configuration creation")
        
        let configuration = try Configuration(flagsConfigurationJson: data, obfuscated: true)
        
        debugLogger?("JSON parsing completed")
        
        return configuration
    }
}
