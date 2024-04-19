import Foundation;

let RAC_CONFIG_URL = "/api/randomized_assignment/v3/config"

class ConfigurationRequester {
    private let httpClient: EppoHttpClient;

    public init(httpClient: EppoHttpClient) {
        self.httpClient = httpClient
    }

    public func fetchConfigurations() async throws -> UniversalFlagConfig {
        let (urlData, _) = try await httpClient.get(RAC_CONFIG_URL);
        return try UniversalFlagConfig.decodeFromJSON(from: String(data: urlData, encoding: .utf8)!);
    }
}
