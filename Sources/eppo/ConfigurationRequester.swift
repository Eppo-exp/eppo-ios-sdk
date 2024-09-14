import Foundation;

let UFC_CONFIG_URL = "/api/flag-config/v1/config"

protocol ConfigurationRequesterProtocol {
    func fetchConfigurations() async throws -> UniversalFlagConfig
}

class HttpConfigurationRequester: ConfigurationRequesterProtocol {
    private let httpClient: EppoHttpClient;

    public init(httpClient: EppoHttpClient) {
        self.httpClient = httpClient
    }

    public func fetchConfigurations() async throws -> UniversalFlagConfig {
        let (urlData, _) = try await httpClient.get(UFC_CONFIG_URL);
        return try UniversalFlagConfig.decodeFromJSON(from: String(data: urlData, encoding: .utf8)!);
    }
}

class JsonConfigurationRequester: ConfigurationRequesterProtocol {
    private let configurationJson: String;

    public init(configurationJson: String) {
        self.configurationJson = configurationJson
    }

    public func fetchConfigurations() throws -> UniversalFlagConfig {
        return try UniversalFlagConfig.decodeFromJSON(from: configurationJson);
    }
}
