import Foundation

/// Thread-safe storage for precomputed flag configurations with disk persistence
class PrecomputedConfigurationStore {
    private var configuration: PrecomputedConfiguration?
    private let syncQueue = DispatchQueue(
        label: "cloud.eppo.precomputedConfigurationStoreQueue", attributes: .concurrent)
    private var debugLogger: ((String) -> Void)?
    
    /// Salt extracted from the configuration for obfuscation
    var salt: String? {
        return syncQueue.sync { self.configuration?.salt }
    }
    
    private let cacheFileURL: URL?
    // Serial queue for disk persistence operations
    private static let persistenceQueue = DispatchQueue(
        label: "cloud.eppo.precomputedConfigurationStorePersistence", qos: .background)
    
    // MARK: - Initialization
    
    init(withPersistentCache: Bool = true) {
        self.cacheFileURL = if withPersistentCache {
            Self.findCacheFileURL()
        } else {
            nil
        }
        
        // Configuration will be loaded after debug logger is set up
        self.configuration = nil
    }
    
    // MARK: - Public Methods
    
    /// Load initial configuration from disk (called after debug logger is set up)
    func loadInitialConfiguration() {
        if self.configuration == nil {
            self.configuration = self.loadFromDisk()
        }
    }
    
    func setDebugLogger(_ logger: @escaping (String) -> Void) {
        self.debugLogger = logger
    }
    
    /// Get the stored configuration in a thread-safe manner
    func getConfiguration() -> PrecomputedConfiguration? {
        return syncQueue.sync { self.configuration }
    }
    
    /// Set the configuration in a thread-safe manner with disk persistence
    func setConfiguration(_ configuration: PrecomputedConfiguration) {
        syncQueue.sync(flags: .barrier) {
            self.configuration = configuration
            self.saveToDisk(configuration: configuration)
        }
    }
    
    /// Check if the store has been initialized with a configuration
    func isInitialized() -> Bool {
        return syncQueue.sync { self.configuration != nil }
    }
    
    /// Get all flag keys in the configuration
    func getKeys() -> [String] {
        return syncQueue.sync { 
            self.configuration?.flags.keys.map { $0 } ?? []
        }
    }
    
    /// Get a specific precomputed flag by key
    func getFlag(forKey key: String) -> PrecomputedFlag? {
        return syncQueue.sync { self.configuration?.flags[key] }
    }
    
    /// Check if configuration has expired based on a TTL
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
    
    // MARK: - Private Methods
    
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
        
        Self.persistenceQueue.async { [weak self] in
            self?.debugLogger?("Starting precomputed configuration persistent storage write")
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(configuration)
                self?.debugLogger?("Encoded precomputed configuration data: \(data.count) bytes")
                try data.write(to: cacheFileURL, options: .atomic)
                self?.debugLogger?("Precomputed configuration persistent storage write completed")
            } catch {
                print("Error saving precomputed configuration to disk: \(error)")
                self?.debugLogger?("Precomputed configuration persistent storage write failed")
            }
        }
    }
    
    private func loadFromDisk() -> PrecomputedConfiguration? {
        guard let cacheFileURL = self.cacheFileURL else {
            return nil
        }
        
        debugLogger?("Starting precomputed configuration persistent storage read")
        do {
            let data = try Data(contentsOf: cacheFileURL)
            debugLogger?("Loaded precomputed configuration data from disk: \(data.count) bytes")
            let decoder = JSONDecoder()
            let config = try decoder.decode(PrecomputedConfiguration.self, from: data)
            debugLogger?("Precomputed configuration persistent storage read completed")
            return config
        } catch {
            print("No precomputed configuration found on disk or error decoding: \(error)")
            debugLogger?("Precomputed configuration persistent storage read failed - no cached config")
            return nil
        }
    }
}