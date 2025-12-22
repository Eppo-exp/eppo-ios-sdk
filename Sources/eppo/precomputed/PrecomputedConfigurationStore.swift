import Foundation

/// Thread-safe storage for precomputed flag configurations with disk persistence
class PrecomputedConfigurationStore {
    private var configuration: PrecomputedConfiguration?
    private let syncQueue = DispatchQueue(
        label: "cloud.eppo.precomputedConfigurationStoreQueue", attributes: .concurrent)
    
    /// Salt extracted from the configuration for obfuscation
    var salt: String? {
        return syncQueue.sync { self.configuration?.salt }
    }
    
    private let cacheFileURL: URL?
    // Serial queue for disk persistence operations
    private static let persistenceQueue = DispatchQueue(
        label: "cloud.eppo.precomputedConfigurationStorePersistence", qos: .background)
    
    init(withPersistentCache: Bool = true) {
        self.cacheFileURL = if withPersistentCache {
            Self.findCacheFileURL()
        } else {
            nil
        }
        
        self.configuration = nil
    }
    
    /// Load initial configuration from disk
    func loadInitialConfiguration() {
        if self.configuration == nil {
            self.configuration = self.loadFromDisk()
        }
    }
    
    func getConfiguration() -> PrecomputedConfiguration? {
        return syncQueue.sync { self.configuration }
    }
    
    /// Set configuration with disk persistence
    func setConfiguration(_ configuration: PrecomputedConfiguration) {
        syncQueue.sync(flags: .barrier) {
            self.configuration = configuration
            self.saveToDisk(configuration: configuration)
        }
    }
    
    func isInitialized() -> Bool {
        return syncQueue.sync { self.configuration != nil }
    }
    
    func getKeys() -> [String] {
        return syncQueue.sync { 
            self.configuration?.flags.keys.map { $0 } ?? []
        }
    }
    
    func getFlag(forKey key: String) -> PrecomputedFlag? {
        return syncQueue.sync { self.configuration?.flags[key] }
    }
    
    func isExpired(ttlSeconds: TimeInterval = 300) -> Bool {
        return syncQueue.sync {
            guard let config = self.configuration else {
                return true // No config means expired
            }
            
            let age = Date().timeIntervalSince(config.configFetchedAt)
            return age > ttlSeconds
        }
    }
    
    /// Clear the persistent cache
    static func clearPersistentCache() {
        guard let cacheFileURL = Self.findCacheFileURL() else {
            return
        }
        
        Self.persistenceQueue.sync {
            do {
                try FileManager.default.removeItem(at: cacheFileURL)
            } catch {
                print("Error removing precomputed cache file: \(error)")
            }
        }
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
            return nil
        }
        
        // Use precomputed-specific file name
        return cacheDirectoryURL
            .appendingPathComponent("eppo-precomputed-configuration.json", isDirectory: false)
    }
    
    private func saveToDisk(configuration: PrecomputedConfiguration) {
        guard let cacheFileURL = self.cacheFileURL else {
            return
        }
        
        Self.persistenceQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(configuration)
                try data.write(to: cacheFileURL, options: .atomic)
            } catch {
                print("Error saving precomputed configuration to disk: \(error)")
            }
        }
    }
    
    private func loadFromDisk() -> PrecomputedConfiguration? {
        guard let cacheFileURL = self.cacheFileURL else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
            return config
        } catch {
            print("No precomputed configuration found on disk or error decoding: \(error)")
            return nil
        }
    }
}
