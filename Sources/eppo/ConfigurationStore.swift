import Foundation

class ConfigurationStore {
    // CAUTION! 
    // 
    // Take care before changing the DispatchQueue methods to `asyncOrWait`
    // as we previously had a bug related to support across older iOS versions.
    // https://github.com/Eppo-exp/eppo-ios-sdk/issues/46

    private var configuration: Configuration?
    private let syncQueue = DispatchQueue(
        label: "cloud.eppo.configurationStoreQueue", attributes: .concurrent)
    private var debugLogger: ((String) -> Void)?

    private let cacheFileURL: URL?
    // This is a serial (non-concurrent) queue, so writers don't fight
    // each other and last writer wins.
    //
    // The queue is static because if there are multiple stores, they
    // would be sharing the cache file.
    static let persistenceQueue = DispatchQueue(
      label: "cloud.eppo.configurationStorePersistence", qos: .background)

    // Initialize with the disk-based path for storage
    public init(withPersistentCache: Bool = true) {
        self.cacheFileURL = if withPersistentCache {
            Self.findCacheFileURL()
        } else {
            nil
        }

        // Configuration will be loaded after debug logger is set up
        self.configuration = nil
    }
    
    // Load initial configuration from disk (called after debug logger is set up)
    public func loadInitialConfiguration() {
        if self.configuration == nil {
            self.configuration = self.loadFromDisk()
        }
    }
    
    public func setDebugLogger(_ logger: @escaping (String) -> Void) {
        self.debugLogger = logger
    }

    private static func findCacheFileURL() -> URL? {
        guard let cacheDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
          .first?
          .appendingPathComponent("eppo", isDirectory: true) else {
            return nil
        }

        // Ensure the directory exists
        do {
            try FileManager.default.createDirectory(
              at: cacheDirectoryURL,
              withIntermediateDirectories: true,
              attributes: nil
            )
        } catch {
            print("Error creating cache directory: \(error)")
            // As we failed to create the directory, it's unlikely
            // that writing cache file will be successful.
            return nil
        }

        return cacheDirectoryURL
          .appendingPathComponent("eppo-configuration.json", isDirectory: false)
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
            self.saveToDisk(configuration: configuration)
        }
    }

    public static func clearPersistentCache() {
        guard let cacheFileURL = Self.findCacheFileURL() else {
            return
        }

        Self.persistenceQueue.sync {
            do {
                try FileManager.default.removeItem(at: cacheFileURL)
            } catch {
                print("Error removing cache file: \(error)")
            }
        }
    }

    // Save the configuration to disk (in background)
    private func saveToDisk(configuration: Configuration) {
        guard let cacheFileURL = self.cacheFileURL else {
            return
        }

        Self.persistenceQueue.async { [weak self] in
            self?.debugLogger?("Starting persistent storage write")
            do {
                let data = try JSONParsingFactory.currentProvider.encodeConfiguration(configuration)
                self?.debugLogger?("Encoded configuration data: \(data.count) bytes")
                try data.write(to: cacheFileURL, options: .atomic)
                self?.debugLogger?("Persistent storage write completed")
            } catch {
                print("Error saving configuration to disk: \(error)")
                self?.debugLogger?("Persistent storage write failed")
            }
        }
    }

    // Load the configuration from disk
    private func loadFromDisk() -> Configuration? {
        guard let cacheFileURL = self.cacheFileURL else {
            return nil
        }

        debugLogger?("Starting persistent storage read")
        do {
            let data = try Data(contentsOf: cacheFileURL)
            debugLogger?("Loaded configuration data from disk: \(data.count) bytes")
            let config = try JSONParsingFactory.currentProvider.decodeEncodedConfiguration(from: data)
            debugLogger?("Persistent storage read completed")
            return config
        } catch {
            print("No configuration found on disk or error decoding: \(error)")
            debugLogger?("Persistent storage read failed - no cached config")
            return nil
        }
    }
}
