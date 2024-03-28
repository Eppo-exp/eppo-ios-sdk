import Foundation

public protocol AssignmentCache {
    func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool
    func setLastLoggedAssignment(key: AssignmentCacheKey)
}

public struct AssignmentCacheKey {
    var subjectKey: String
    var flagKey: String
    var allocationKey: String
    var variationValue: EppoValue
}

public class InMemoryAssignmentCache: AssignmentCache {
    private var cache: [String: String] = [:]

    // This empty constructor is required to be able to instantiate the class
    // within the constructor of EppoClient.
    public init() {
        // Initialization code here
    }

    public func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool {
        let cacheKey = getCacheKey(key: key)
        if !has(key: cacheKey) {
            return false
        }

        return get(key: cacheKey) == key.variationValue.toHashedString()
    }

    public func setLastLoggedAssignment(key: AssignmentCacheKey) {
        let cacheKey = getCacheKey(key: key)
        set(key: cacheKey, value: key.variationValue.toHashedString())
    }

    internal func get(key: String) -> String? {
        return cache[key]
    }

    internal func set(key: String, value: String) {
        cache[key] = value
    }

    internal func has(key: String) -> Bool {
        return cache[key] != nil
    }

    private func getCacheKey(key: AssignmentCacheKey) -> String {
        return ["subject:\(key.subjectKey)", "flag:\(key.flagKey)", "allocation:\(key.allocationKey)"].joined(separator: ";")
    }
}
