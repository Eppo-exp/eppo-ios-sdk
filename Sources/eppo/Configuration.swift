import Foundation

public struct ConfigDetails {
    public let configFetchedAt: String
    public let configPublishedAt: String
    public let configEnvironment: Environment
    public let configFormat: String
    public let salt: String?
}

public struct Configuration: Codable {
    internal let flagsConfiguration: UniversalFlagConfig
    internal let obfuscated: Bool
    internal let fetchedAt: String
    internal let publishedAt: String

    internal init(flagsConfiguration: UniversalFlagConfig, obfuscated: Bool, fetchedAt: String, publishedAt: String) {
        self.flagsConfiguration = flagsConfiguration
        self.obfuscated = obfuscated
        self.fetchedAt = fetchedAt
        self.publishedAt = publishedAt
    }

    public init(flagsConfigurationJson: Data, obfuscated: Bool) throws {
        let configuration = try JSONParsingFactory.currentProvider.decodeConfiguration(from: flagsConfigurationJson, obfuscated: obfuscated)
        self.init(
            flagsConfiguration: configuration.flagsConfiguration,
            obfuscated: configuration.obfuscated,
            fetchedAt: configuration.fetchedAt,
            publishedAt: configuration.publishedAt
        )
    }

    internal func getFlag(flagKey: String) -> UFC_Flag? {
        return self.flagsConfiguration.flags[flagKey]
    }

    public func getFlagConfigDetails() -> ConfigDetails {
        return ConfigDetails(
            configFetchedAt: self.fetchedAt,
            configPublishedAt: self.publishedAt,
            configEnvironment: self.flagsConfiguration.environment,
            configFormat: self.flagsConfiguration.format,
            salt: nil
        )
    }
    
    public func toJsonString() throws -> String {
        return try JSONParsingFactory.currentProvider.encodeUniversalFlagConfigToString(self.flagsConfiguration)
    }
}
