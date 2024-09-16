import Foundation

class ConfigurationStore {
    private var configuration: Configuration?
    
    private let requester: ConfigurationRequester
    private let syncQueue = DispatchQueue(
        label: "com.eppo.configurationStoreQueue", attributes: .concurrent)
    
    public init(requester: ConfigurationRequester) {
        self.requester = requester
    }

    public func fetchAndStoreConfigurations() async throws {
        let config = try await self.requester.fetchConfigurations()
        self.setConfiguration(configuration: config)
    }

    // Get the configuration for a given flag key in a thread-safe manner.
    //
    // The use of a syncQueue ensures that this read operation is thread-safe and doesn't cause
    // race conditions where reads could see a partially updated state.
    public func getConfiguration(flagKey: String) -> UFC_Flag? {
        return syncQueue.sync {
            self.configuration?.flagsConfiguration.flags[flagKey]
        }
    }
    
    // Set the configurations in a thread-safe manner.
    //
    // The use of a barrier ensures that this write operation completes before any other read or write
    // operations on the `flagConfigs` can proceed. This guarantees that the configuration state is
    // consistent and prevents race conditions where reads could see a partially updated state.
    public func setConfiguration(configuration: Configuration) {
        syncQueue.async(flags: .barrier) {
            self.configuration = configuration
        }
    }
    
    public func isInitialized() -> Bool {
        return syncQueue.sync {
            self.configuration != nil
        }
    }
}
