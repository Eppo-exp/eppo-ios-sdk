import Foundation

class ConfigurationStore {
    // CAUTION! 
    // 
    // Take care before changing the DispatchQueue methods to `asyncOrWait`
    // as we previously had a bug related to support across older iOS versions.
    // https://github.com/Eppo-exp/eppo-ios-sdk/issues/46

    private var configuration: Configuration?
    private let syncQueue = DispatchQueue(
        label: "\(EPPO_NAMESPACE).configurationStoreQueue", attributes: .concurrent)

    private let cacheFileURL: URL?
    // This is a serial (non-concurrent) queue, so writers don't fight
    // each other and last writer wins.
    //
    // The queue is static because if there are multiple stores, they
    // would be sharing the cache file.
    static let persistenceQueue = DispatchQueue(
      label: "\(EPPO_NAMESPACE).configurationStorePersistence", qos: .background)
    
    // Initialize with the disk-based path for storage
    public init(withPersistentCache: Bool = true) {
        self.cacheFileURL = if withPersistentCache {
            Self.findCacheFileURL()
        } else {
            nil
        }

        // Load any existing configuration from disk when initializing
        self.configuration = self.loadFromDisk()
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

        Self.persistenceQueue.async {
            do {
                let data = try JSONEncoder().encode(configuration)
                try data.write(to: cacheFileURL, options: .atomic)
            } catch {
                print("Error saving configuration to disk: \(error)")
            }
        }
    }
    
    // Load the configuration from disk
    private func loadFromDisk() -> Configuration? {
        guard let cacheFileURL = self.cacheFileURL else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            print("No configuration found on disk or error decoding: \(error)")
            return nil
        }
    }
}
