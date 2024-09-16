import Foundation

public struct Configuration {
    internal let flagsConfiguration: UniversalFlagConfig;


    internal init(flagsConfiguration: UniversalFlagConfig) {
        self.flagsConfiguration = flagsConfiguration
    }

    public init(flagsConfigurationJson: Data) throws {
        let flagsConfiguration = try UniversalFlagConfig.decodeFromJSON(from: flagsConfigurationJson);
        self.init(flagsConfiguration: flagsConfiguration)
    }
}
