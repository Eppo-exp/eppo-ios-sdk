import Foundation

/// Protocol for evaluators that convert binary data (protobuf/FlatBuffers) to Swift structs with caching
public protocol SwiftStructEvaluatorProtocol: FlagEvaluatorProtocol {

    // MARK: - Cache Requirements

    /// Cache for converted UFC_Flag objects (key = flagKey, value = UFC_Flag)
    var flagCache: [String: UFC_Flag] { get set }

    /// Cache for flag variation types (key = flagKey, value = UFC_VariationType)
    var flagTypeCache: [String: UFC_VariationType] { get set }

    /// Whether this evaluator pre-converts all flags on initialization (true) or converts lazily (false)
    var isPrewarmed: Bool { get }

    // MARK: - Thread Safety
    // Note: Thread safety is now handled by individual evaluator implementations
    // using concurrent DispatchQueues with barrier writes for optimal performance

    // MARK: - Cache Management

    /// Clears all cached flags and types (useful for memory management)
    mutating func clearCaches()

    /// Pre-converts all flags from binary format to Swift structs (for prewarmed mode)
    func prewarmAllFlags() throws

    /// Gets a flag from cache or loads it on-demand (for lazy mode)
    func getOrLoadFlag(flagKey: String) -> UFC_Flag?
}

// MARK: - Default Implementation

public extension SwiftStructEvaluatorProtocol {

    mutating func clearCaches() {
        // Clear the caches - thread safety is handled by individual implementations
        flagCache.removeAll()
        flagTypeCache.removeAll()
    }
}