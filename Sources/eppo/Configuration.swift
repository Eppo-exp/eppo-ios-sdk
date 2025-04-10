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
}
