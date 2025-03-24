import Foundation

public protocol AssignmentCache {
    func hasLoggedAssignment(key: AssignmentCacheKey) -> Bool
    func setLastLoggedAssignment(key: AssignmentCacheKey)
}

public struct AssignmentCacheKey {
    var subjectKey: String
    var flagKey: String
    var allocationKey: String
    var variationKey: String
}

public class InMemoryAssignmentCache: AssignmentCache {
    private let queue = DispatchQueue(label: "com.eppo.assignmentcache", attributes: .concurrent)
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
