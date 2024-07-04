import Foundation;

let UFC_CONFIG_URL = "api/flag-config/v1/config"

class ConfigurationRequester {
    private let httpClient: EppoHttpClient;

    public init(httpClient: EppoHttpClient) {
        self.httpClient = httpClient
    }

    public func fetchConfigurations() async throws -> UniversalFlagConfig {
        let (urlData, _) = try await httpClient.get(UFC_CONFIG_URL);
        return try UniversalFlagConfig.decodeFromJSON(from: String(data: urlData, encoding: .utf8)!);
    }
}
