import Foundation

class ConfigurationStore {
    // CAUTION! 
    // 
    // Take care before changing the DispatchQueue methods to `asyncOrWait`
    // as we previously had a bug related to support across older iOS versions.
    // https://github.com/Eppo-exp/eppo-ios-sdk/issues/46

    private var configuration: Configuration?
    
    private let syncQueue = DispatchQueue(
        label: "com.eppo.configurationStoreQueue", attributes: .concurrent)
    
    public init() {
    }

    // Get the configuration for a given flag key in a thread-safe manner.
    //
    // The use of a syncQueue ensures that this read operation is thread-safe and doesn't cause
    // race conditions where reads could see a partially updated state.
    public func getConfiguration() -> Configuration? {
        return syncQueue.sync { self.configuration }
    }
    
    // Set the configurations in a thread-safe manner.
    //
    // The use of a barrier ensures that this write operation completes before any other read or write
    // operations on the `flagConfigs` can proceed. This guarantees that the configuration state is
    // consistent and prevents race conditions where reads could see a partially updated state.
    public func setConfiguration(configuration: Configuration) {
        syncQueue.sync(flags: .barrier) {
            self.configuration = configuration
        }
    }
}
