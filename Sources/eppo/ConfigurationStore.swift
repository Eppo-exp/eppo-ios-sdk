class ConfigurationStore {
    private let requester: ConfigurationRequester;
    private var flagConfigs: RACConfig?

    public init(requester: ConfigurationRequester) {
        self.requester = requester;
        self.flagConfigs = RACConfig(flags: [:])
    }

    public func fetchAndStoreConfigurations() async throws {
        self.flagConfigs = try await self.requester.fetchConfigurations();
    }

    public func getConfiguration(flagKey: String) -> FlagConfig? {
        return flagConfigs?.flags[flagKey];
    }

    public func setConfiguration(flagKey: String, config: FlagConfig) {
        flagConfigs?.flags[flagKey] = config
    }

    public func isInitialized() -> Bool {
        return flagConfigs?.flags.isEmpty == false
    }
}
