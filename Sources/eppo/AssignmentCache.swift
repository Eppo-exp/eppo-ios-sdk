import Foundation

public protocol AssignmentCache {
    @available(*, deprecated, message: "Use shouldLogAssignment() instead to avoid race conditions in concurrent environments")
    func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool
    
    func setLastLoggedAssignment(key: AssignmentCacheKey)
    
    /// Atomically check if assignment has been logged, and if not, mark it as logged.
    /// Returns true if the assignment should be logged (wasn't logged before), false if it was already logged.
    /// This method prevents race conditions by performing check-and-set in a single atomic operation.
    func shouldLogAssignment(key: AssignmentCacheKey) -> Bool
}

public struct AssignmentCacheKey {
    public var subjectKey: String
    public var flagKey: String
    public var allocationKey: String
    public var variationKey: String
    
    public init(subjectKey: String, flagKey: String, allocationKey: String, variationKey: String) {
        self.subjectKey = subjectKey
        self.flagKey = flagKey
        self.allocationKey = allocationKey
        self.variationKey = variationKey
    }
}

public class InMemoryAssignmentCache: AssignmentCache {
    private let queue = DispatchQueue(label: "cloud.eppo.assignmentcache", attributes: .concurrent)
    internal var cache: [CacheKey: CacheValue] = [:]

    internal struct CacheKey: Hashable {
        let subjectKey: String
        let flagKey: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(subjectKey)
            hasher.combine(flagKey)
        }
    }

    internal struct CacheValue: Equatable {
        let allocationKey: String
        let variationKey: String

        static func ==(lhs: CacheValue, rhs: CacheValue) -> Bool {
            return lhs.allocationKey == rhs.allocationKey && lhs.variationKey == rhs.variationKey
        }
    }

    // This empty constructor is required to be able to instantiate the class
    // within the constructor of EppoClient.
    public init() {
        // Initialization code here
    }

    @available(*, deprecated, message: "Use shouldLogAssignment() instead to avoid race conditions in concurrent environments")
    public func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool {
        return queue.sync {
            let cacheKey = CacheKey(subjectKey: key.subjectKey, flagKey: key.flagKey)
            return get(key: cacheKey) == CacheValue(allocationKey: key.allocationKey, variationKey: key.variationKey)
        }
    }

    public func setLastLoggedAssignment(key: AssignmentCacheKey) {
        queue.sync(flags: .barrier) {
            let cacheKey = CacheKey(subjectKey: key.subjectKey, flagKey: key.flagKey)
            set(key: cacheKey, value: CacheValue(allocationKey: key.allocationKey, variationKey: key.variationKey))
        }
    }
    
    public func shouldLogAssignment(key: AssignmentCacheKey) -> Bool {
        return queue.sync(flags: .barrier) {
            let cacheKey = CacheKey(subjectKey: key.subjectKey, flagKey: key.flagKey)
            let expectedValue = CacheValue(allocationKey: key.allocationKey, variationKey: key.variationKey)
            
            // Atomically check and set
            if get(key: cacheKey) == expectedValue {
                return false // Already logged
            } else {
                set(key: cacheKey, value: expectedValue)
                return true // Should log
            }
        }
    }

    internal func get(key: CacheKey) -> CacheValue? {
        return cache[key]
    }

    internal func set(key: CacheKey, value: CacheValue) {
        cache[key] = value
    }

    internal func has(key: CacheKey) -> Bool {
        return cache[key] != nil
    }
}
