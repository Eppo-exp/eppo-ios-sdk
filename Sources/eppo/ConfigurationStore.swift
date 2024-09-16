import Foundation

class ConfigurationStore {
    private var configuration: Configuration?
    
    private let syncQueue = DispatchQueue(
        label: "com.eppo.configurationStoreQueue", attributes: .concurrent)
    
    public init() {
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
        syncQueue.asyncAndWait(flags: .barrier) {
            self.configuration = configuration
        }
    }
    
    public func isInitialized() -> Bool {
        return syncQueue.sync {
            self.configuration != nil
        }
    }
}
