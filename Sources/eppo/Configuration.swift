import Foundation
import FlatBuffers

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
        let flagsConfiguration = try UniversalFlagConfig.decodeFromJSON(from: flagsConfigurationJson)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        self.init(
            flagsConfiguration: flagsConfiguration,
            obfuscated: obfuscated,
            fetchedAt: now,
            publishedAt: formatter.string(from: flagsConfiguration.createdAt)
        )
    }

    public init(flagsConfigurationFlatBuffer: Data, obfuscated: Bool) throws {
        let flagsConfiguration = try UniversalFlagConfig.decodeFromFlatBuffer(from: flagsConfigurationFlatBuffer)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        self.init(
            flagsConfiguration: flagsConfiguration,
            obfuscated: obfuscated,
            fetchedAt: now,
            publishedAt: formatter.string(from: flagsConfiguration.createdAt)
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let string = formatter.string(from: date)
            var container = encoder.singleValueContainer()
            try container.encode(string)
        }
        let jsonData = try encoder.encode(self.flagsConfiguration)
        guard let string = String(data: jsonData, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert JSON data to string"
            ))
        }
        return string
    }
}
