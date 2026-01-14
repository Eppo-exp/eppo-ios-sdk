import Foundation

/*
 DESIGN NOTE: Obfuscation Strategy & Performance Optimization

 This SDK implements a decode-on-demand strategy for obfuscated flag configurations to optimize
 for fast startup times, which is critical for mobile applications.

 CURRENT APPROACH: Decode-on-Demand (Every Evaluation)
 =====================================================

 Obfuscated flag values are stored as base64-encoded strings and decoded during each flag evaluation:

 Configuration Load:  JSON → EppoValue(stringValue: "dHJ1ZQ==") [FAST - no decoding]
 Flag Evaluation:     base64Decode("dHJ1ZQ==") → "true" → Bool(true) [SLOWER - decode every time]

 Pros:
 • ⚡ Extremely fast startup - no upfront decoding cost
 • 💾 Minimal memory usage - unused flags never decoded
 • 🔒 Secure - sensitive values only decoded when needed

 Cons:
 • 🐌 Slower flag evaluation - decode + parse on every access
 • 🔄 Redundant work - same values decoded repeatedly
 • ⚙️ CPU overhead - base64 + string parsing in hot path
*/

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
