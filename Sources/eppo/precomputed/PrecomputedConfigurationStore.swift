import Foundation

/// Thread-safe storage for precomputed flag configurations with disk persistence
class PrecomputedConfigurationStore {
    private var decodedConfiguration: DecodedPrecomputedConfiguration?
    private let syncQueue = DispatchQueue(
        label: "cloud.eppo.precomputedConfigurationStoreQueue", attributes: .concurrent)

    func getDecodedConfiguration() -> DecodedPrecomputedConfiguration? {
        return syncQueue.sync { self.decodedConfiguration }
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
    }

    /// Load initial configuration from disk
    func loadInitialConfiguration() {
        if self.decodedConfiguration == nil {
            self.decodedConfiguration = self.loadFromDisk()
        }
    }

    /// Set configuration with disk persistence
    func setConfiguration(_ configuration: PrecomputedConfiguration) {
        syncQueue.sync(flags: .barrier) {
            if let decoded = configuration.decode() {
                self.decodedConfiguration = decoded
                self.saveToDisk(decodedConfiguration: decoded)
            }
        }
    }

    func isInitialized() -> Bool {
        return syncQueue.sync { self.decodedConfiguration != nil }
    }

    func getKeys() -> [String] {
        return syncQueue.sync {
            self.decodedConfiguration?.flags.keys.map { $0 } ?? []
        }
    }

    func getDecodedFlag(forKey key: String) -> DecodedPrecomputedFlag? {
        return syncQueue.sync { self.decodedConfiguration?.flags[key] }
    }

    func isExpired(ttlSeconds: TimeInterval = 300) -> Bool {
        return syncQueue.sync {
            guard let config = self.decodedConfiguration else {
                return true
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
            if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                do {
                    try FileManager.default.removeItem(at: cacheFileURL)
                } catch {
                    print("Error removing precomputed cache file: \(error)")
                }
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

    private func saveToDisk(decodedConfiguration: DecodedPrecomputedConfiguration) {
        guard let cacheFileURL = self.cacheFileURL else {
            return
        }

        Self.persistenceQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(decodedConfiguration)
                try data.write(to: cacheFileURL, options: .atomic)
            } catch {
                print("Error saving precomputed configuration to disk: \(error)")
            }
        }
    }

    private func loadFromDisk() -> DecodedPrecomputedConfiguration? {
        guard let cacheFileURL = self.cacheFileURL else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(DecodedPrecomputedConfiguration.self, from: data)
            return config
        } catch {
            print("Error decoding precomputed configuration from disk: \(error)")
            return nil
        }
    }
}
