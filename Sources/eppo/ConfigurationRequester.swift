import Foundation;

let UFC_CONFIG_URL = "/api/flag-config/v1/config"

class ConfigurationRequester {
    private let httpClient: EppoHttpClient;

    public init(httpClient: EppoHttpClient) {
        self.httpClient = httpClient
    }

    public func fetchConfigurations() async throws -> Configuration {
        let (data, _) = try await httpClient.get(UFC_CONFIG_URL);
        return try Configuration(flagsConfigurationJson: data);
    }
}
