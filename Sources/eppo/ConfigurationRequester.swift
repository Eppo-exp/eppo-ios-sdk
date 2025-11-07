import Foundation

let UFC_JSON_CONFIG_URL = "/flag-config/v1/config"
let UFC_PB_CONFIG_URL = "/flag-config/v1/config-pb"

class ConfigurationRequester {
    private let httpClient: EppoHttpClient
    private let requestProtobuf: Bool
    private var debugLogger: ((String) -> Void)?

    public init(httpClient: EppoHttpClient, requestProtobuf: Bool) {
        self.httpClient = httpClient
        self.requestProtobuf = requestProtobuf
        self.debugLogger = nil
    }
    
    public func setDebugLogger(_ logger: @escaping (String) -> Void) {
        self.debugLogger = logger
    }

    public func fetchConfigurations() async throws -> Configuration {
        let networkStartTime = Date()
        debugLogger?("Starting network request to fetch configuration")
        
        let configUrl = requestProtobuf ? UFC_PB_CONFIG_URL : UFC_JSON_CONFIG_URL
        let (data, response) = try await httpClient.get(configUrl)
        
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
        
        if requestProtobuf {
            debugLogger?("Starting protobuf parsing and configuration creation (parsing \(data.count) bytes)")
            // protobuf API does not support obfuscated data yet
            let configuration = try Configuration(flagsConfigurationProtobuf: data, obfuscated: false)
            debugLogger?("Protobuf parsing completed")
            return configuration
        } else {
            debugLogger?("Starting JSON parsing and configuration creation (parsing \(data.count) bytes)")
            let configuration = try Configuration(flagsConfigurationJson: data, obfuscated: true)
            debugLogger?("JSON parsing completed")
            return configuration
        }
    }
}
