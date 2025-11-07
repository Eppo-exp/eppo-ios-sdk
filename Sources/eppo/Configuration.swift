import Foundation

public struct ConfigDetails {
    public let configFetchedAt: String
    public let configPublishedAt: String
    public let configEnvironment: Environment
    public let configFormat: String
    public let salt: String?
}

public struct Configuration {
    internal let flagsConfiguration: UniversalFlagConfig?
    internal let flagsPb: Ufc_UniversalFlagConfig?
    internal let obfuscated: Bool
    internal let fetchedAt: String
    internal let publishedAt: String

    internal init(flagsConfiguration: UniversalFlagConfig?, flagsConfigurationProtobuf: Ufc_UniversalFlagConfig?, obfuscated: Bool, fetchedAt: String, publishedAt: String) {
        self.flagsConfiguration = flagsConfiguration
        self.flagsPb = flagsConfigurationProtobuf
        self.obfuscated = obfuscated
        self.fetchedAt = fetchedAt
        self.publishedAt = publishedAt
    }
    
    public init(flagsConfigurationProtobuf: Data, obfuscated: Bool) throws {
        let flagsConfiguration = try Ufc_UniversalFlagConfig(serializedBytes: flagsConfigurationProtobuf)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        let createdAtDate = Date(timeIntervalSince1970: TimeInterval(flagsConfiguration.createdAtMs) / 1000)
        self.init(
            flagsConfiguration: nil,
            flagsConfigurationProtobuf: flagsConfiguration,
            obfuscated: obfuscated,
            fetchedAt: now,
            publishedAt: formatter.string(from: createdAtDate)
        )
    }

    public init(flagsConfigurationJson: Data, obfuscated: Bool) throws {
        let flagsConfiguration = try UniversalFlagConfig.decodeFromJSON(from: flagsConfigurationJson)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        self.init(
            flagsConfiguration: flagsConfiguration,
            flagsConfigurationProtobuf: nil,
            obfuscated: obfuscated,
            fetchedAt: now,
            publishedAt: formatter.string(from: flagsConfiguration.createdAt)
        )
    }

    internal func getFlag(flagKey: String) -> UFC_Flag? {
        // Only return flags from JSON configuration
        // For protobuf, use getProtobufFlag instead
        return self.flagsConfiguration?.flags[flagKey]
    }

    internal func getProtobufFlag(flagKey: String) -> Ufc_FlagDto? {
        // Only return flags from protobuf configuration
        return self.flagsPb?.flags[flagKey]
    }

    public func getFlagConfigDetails() -> ConfigDetails {
        if let jsonConfig = self.flagsConfiguration {
            return ConfigDetails(
                configFetchedAt: self.fetchedAt,
                configPublishedAt: self.publishedAt,
                configEnvironment: jsonConfig.environment,
                configFormat: jsonConfig.format,
                salt: nil
            )
        } else if let protobufConfig = self.flagsPb {
            return ConfigDetails(
                configFetchedAt: self.fetchedAt,
                configPublishedAt: self.publishedAt,
                configEnvironment: Environment(name: protobufConfig.environment.name),
                configFormat: convertProtobufFormat(protobufConfig.format),
                salt: nil
            )
        } else {
            // Fallback if neither is available
            return ConfigDetails(
                configFetchedAt: self.fetchedAt,
                configPublishedAt: self.publishedAt,
                configEnvironment: Environment(name: "unknown"),
                configFormat: "unknown",
                salt: nil
            )
        }
    }
    
    public func toJsonString() throws -> String {
        guard let jsonConfig = self.flagsConfiguration else {
            if self.flagsPb != nil {
                throw EncodingError.invalidValue(self, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Cannot convert protobuf configuration to JSON - this operation is not supported to avoid wasteful conversion"
                ))
            } else {
                throw EncodingError.invalidValue(self, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "No configuration data available"
                ))
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let string = formatter.string(from: date)
            var container = encoder.singleValueContainer()
            try container.encode(string)
        }
        let jsonData = try encoder.encode(jsonConfig)
        guard let string = String(data: jsonData, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert JSON data to string"
            ))
        }
        return string
    }

    // MARK: - Format Detection

    public func isProtobufFormat() -> Bool {
        return flagsPb != nil && flagsConfiguration == nil
    }

    public func isJsonFormat() -> Bool {
        return flagsConfiguration != nil && flagsPb == nil
    }

    // MARK: - Protobuf Methods

    public func toProtobufData() throws -> Data {
        guard let protobufConfig = self.flagsPb else {
            if self.flagsConfiguration != nil {
                throw EncodingError.invalidValue(self, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Cannot convert JSON configuration to protobuf - this operation is not supported to avoid wasteful conversion"
                ))
            } else {
                throw EncodingError.invalidValue(self, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "No configuration data available"
                ))
            }
        }
        return try protobufConfig.serializedData()
    }

    // MARK: - Helper Methods

    private func convertProtobufFormat(_ format: Ufc_UFCFormat) -> String {
        switch format {
        case .server:
            return "server"
        case .client:
            return "client"
        case .unspecified:
            return "unspecified"
        case .UNRECOGNIZED(let value):
            return "unrecognized(\(value))"
        }
    }
}
