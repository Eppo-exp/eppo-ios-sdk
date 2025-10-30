import Foundation

/// Shared caching and synchronization component for Swift struct evaluators
/// Handles both prewarmed (direct access) and lazy (concurrent access) modes
public class SwiftStructFlagCache<SourceFlag> {
    public let isPrewarmed: Bool

    // For prewarmed mode - all flags and types pre-cached (NO synchronization)
    private var prewarmedFlags: [String: UFC_Flag]
    private var prewarmedFlagTypeCache: [String: UFC_VariationType]

    // For lazy mode - flags and types loaded on-demand (WITH synchronization)
    public var flagCache: [String: UFC_Flag] = [:]
    public var flagTypeCache: [String: UFC_VariationType] = [:]
    private let cacheQueue = DispatchQueue(label: "com.eppo.swift-struct-flag-cache", attributes: .concurrent)

    // Function types for format-specific operations
    public typealias FindSourceFlagFunc = (String) -> SourceFlag?
    public typealias ConvertToUFCFlagFunc = (SourceFlag) throws -> UFC_Flag
    public typealias GetVariationTypeFunc = (SourceFlag) -> UFC_VariationType

    private let findSourceFlag: FindSourceFlagFunc
    private let convertToUFCFlag: ConvertToUFCFlagFunc
    private let getVariationType: GetVariationTypeFunc

    public init(
        flagKeys: [String],
        prewarmCache: Bool,
        findSourceFlag: @escaping FindSourceFlagFunc,
        convertToUFCFlag: @escaping ConvertToUFCFlagFunc,
        getVariationType: @escaping GetVariationTypeFunc
    ) {
        self.isPrewarmed = prewarmCache
        self.findSourceFlag = findSourceFlag
        self.convertToUFCFlag = convertToUFCFlag
        self.getVariationType = getVariationType

        if prewarmCache {
            // Prewarm mode - pre-convert all flags
            self.prewarmedFlags = [:]
            self.prewarmedFlagTypeCache = [:]

            print("   🔄 Pre-converting \(flagKeys.count) flags to UFC objects...")

            for flagKey in flagKeys {
                guard let sourceFlag = findSourceFlag(flagKey) else { continue }

                // Cache the type
                let variationType = getVariationType(sourceFlag)
                self.prewarmedFlagTypeCache[flagKey] = variationType

                // Convert and cache the full flag
                if let ufcFlag = try? convertToUFCFlag(sourceFlag) {
                    self.prewarmedFlags[flagKey] = ufcFlag
                }
            }

            print("   ✅ Pre-converted \(prewarmedFlags.count) flags successfully")
        } else {
            // Lazy mode - no upfront conversion
            self.prewarmedFlags = [:]
            self.prewarmedFlagTypeCache = [:]
        }
    }

    /// Get flag using optimal strategy (prewarmed = direct access, lazy = concurrent access)
    public func getFlag(flagKey: String) -> UFC_Flag? {
        if isPrewarmed {
            // Prewarm mode - get pre-converted flag (NO synchronization - direct dictionary access)
            return prewarmedFlags[flagKey]
        } else {
            // Lazy mode - get or load flag on-demand (WITH synchronization - concurrent queue access)
            return getOrLoadFlag(flagKey: flagKey)
        }
    }

    /// Get flag variation type using optimal strategy
    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        if isPrewarmed {
            return prewarmedFlagTypeCache[flagKey]
        } else {
            // Concurrent read - check cache first
            let cachedType = cacheQueue.sync {
                return flagTypeCache[flagKey]
            }

            if let variationType = cachedType {
                return variationType
            }

            // Barrier write - find and cache the type
            return cacheQueue.sync(flags: .barrier) {
                // Double-check after acquiring write lock
                if let cachedType = flagTypeCache[flagKey] {
                    return cachedType
                }

                // Find and cache the type
                guard let sourceFlag = findSourceFlag(flagKey) else {
                    return nil
                }

                let variationType = getVariationType(sourceFlag)
                flagTypeCache[flagKey] = variationType
                return variationType
            }
        }
    }

    /// Get all cached flag keys for benchmarking
    public func getAllFlagKeys() -> [String] {
        if isPrewarmed {
            return Array(prewarmedFlags.keys)
        } else {
            // For lazy mode, return currently cached keys
            return Array(flagCache.keys)
        }
    }

    /// Prewarm all flags after lazy initialization (for protocol compliance)
    public func prewarmAllFlags(allFlagKeys: [String]) {
        guard !isPrewarmed else { return } // Already prewarmed during init

        cacheQueue.sync(flags: .barrier) {
            for flagKey in allFlagKeys {
                guard flagCache[flagKey] == nil else { continue } // Skip already cached
                guard let sourceFlag = findSourceFlag(flagKey) else { continue }

                // Cache type and flag
                let variationType = getVariationType(sourceFlag)
                flagTypeCache[flagKey] = variationType

                if let ufcFlag = try? convertToUFCFlag(sourceFlag) {
                    flagCache[flagKey] = ufcFlag
                }
            }

            print("   ✅ Pre-converted \(flagCache.count) flags successfully")
        }
    }

    // MARK: - Private Methods (Lazy Loading)

    private func getOrLoadFlag(flagKey: String) -> UFC_Flag? {
        // Try to get from cache first (concurrent read)
        let cachedFlag = cacheQueue.sync {
            return flagCache[flagKey]
        }

        if let flag = cachedFlag {
            return flag
        }

        // Not in cache, load it with a barrier write
        return cacheQueue.sync(flags: .barrier) {
            // Double-check after acquiring write lock
            if let cachedFlag = flagCache[flagKey] {
                return cachedFlag
            }

            // Find and convert source flag
            guard let sourceFlag = findSourceFlag(flagKey) else {
                return nil
            }

            guard let ufcFlag = try? convertToUFCFlag(sourceFlag) else {
                return nil
            }

            // Cache the converted flag and type
            flagCache[flagKey] = ufcFlag
            flagTypeCache[flagKey] = getVariationType(sourceFlag)
            return ufcFlag
        }
    }
}