import Foundation

class ConfigurationStore {
    private let requester: ConfigurationRequesterProtocol
    private var flagConfigs: UniversalFlagConfig?
    private let syncQueue = DispatchQueue(
        label: "com.eppo.configurationStoreQueue", attributes: .concurrent)
    
    public init(requester: ConfigurationRequesterProtocol) {
        self.requester = requester
        self.flagConfigs = UniversalFlagConfig(createdAt: nil, flags: [:])
    }

    public func fetchAndStoreConfigurations() async throws {
        let config = try await self.requester.fetchConfigurations()
        self.setConfigurations(config: config)
    }

    // Get the configuration for a given flag key in a thread-safe manner.
    //
    // The use of a syncQueue ensures that this read operation is thread-safe and doesn't cause
    // race conditions where reads could see a partially updated state.
    public func getConfiguration(flagKey: String) -> UFC_Flag? {
        return syncQueue.sync {
            flagConfigs?.flags[flagKey]
        }
    }
    
    // Set the configurations in a thread-safe manner.
    //
    // The use of a barrier ensures that this write operation completes before any other read or write
    // operations on the `flagConfigs` can proceed. This guarantees that the configuration state is
    // consistent and prevents race conditions where reads could see a partially updated state.
    public func setConfigurations(config: UniversalFlagConfig) {
        syncQueue.async(flags: .barrier) {
            self.flagConfigs = config
        }
    }
    
    public func isInitialized() -> Bool {
        return syncQueue.sync {
            flagConfigs?.flags.isEmpty == false
        }
    }
}
