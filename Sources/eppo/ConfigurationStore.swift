import Foundation

class ConfigurationStore {
    private var configuration: Configuration?
    private let syncQueue = DispatchQueue(
        label: "com.eppo.configurationStoreQueue", attributes: .concurrent)
    
    private let fileURL: URL
    
    // Initialize with the disk-based path for storage
    public init() {
        // Set the file path for storing the configuration
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        self.fileURL = urls[0].appendingPathComponent("configuration.json")
        
        // Load any existing configuration from disk when initializing
        self.configuration = loadFromDisk()
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
        syncQueue.asyncAndWait(flags: .barrier) {
            self.configuration = configuration
            // Persist the new configuration to disk
            self.saveToDisk(configuration: configuration)
        }
    }
    
    // Save the configuration to disk
    private func saveToDisk(configuration: Configuration) {
        do {
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Error saving configuration to disk: \(error)")
        }
    }
    
    // Load the configuration from disk
    private func loadFromDisk() -> Configuration? {
        do {
            let data = try Data(contentsOf: fileURL)
            let configuration = try JSONDecoder().decode(Configuration.self, from: data)
            return configuration
        } catch {
            print("No configuration found on disk or error decoding: \(error)")
            return nil
        }
    }
}
