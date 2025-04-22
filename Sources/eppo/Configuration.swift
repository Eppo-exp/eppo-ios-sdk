import Foundation

public struct Configuration: Codable {
    internal let flagsConfiguration: UniversalFlagConfig
    internal let obfuscated: Bool

    internal init(flagsConfiguration: UniversalFlagConfig, obfuscated: Bool) {
        self.flagsConfiguration = flagsConfiguration
        self.obfuscated = obfuscated
    }

    public init(flagsConfigurationJson: Data, obfuscated: Bool) throws {
        let flagsConfiguration = try UniversalFlagConfig.decodeFromJSON(from: flagsConfigurationJson)
        self.init(flagsConfiguration: flagsConfiguration, obfuscated: obfuscated)
    }

    internal func getFlag(flagKey: String) -> UFC_Flag? {
        return self.flagsConfiguration.flags[flagKey]
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
