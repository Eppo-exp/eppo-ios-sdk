import Foundation

/// Eppo client for precomputed flag assignments
public class EppoPrecomputedClient {
    public typealias AssignmentLogger = (Assignment) -> Void
    // MARK: - Singleton Pattern (matches regular EppoClient)
    public static let shared = EppoPrecomputedClient()
    private static var initialized = false
    
    // MARK: - Thread Safety (matches regular EppoClient approach)
    private let accessQueue = DispatchQueue(label: "cloud.eppo.precomputed.access", qos: .userInitiated)
    
    // MARK: - Core Components
    private var configurationStore: PrecomputedConfigurationStore?
    private var subject: Subject?
    private var assignmentLogger: AssignmentLogger?
    private var assignmentCache: AssignmentCache?
    private var poller: Poller?
    
    // MARK: - Network Components
    private var requestor: PrecomputedRequestor?
    
    // MARK: - Event Queuing (before logger is set)
    private var queuedAssignments: [Assignment] = []
    private let maxEventQueueSize = 100  // Match JS MAX_EVENT_QUEUE_SIZE
    
    // MARK: - Client State
    private var sdkKey: String?
    private var isInitialized: Bool {
        return Self.initialized
    }
    
    // MARK: - Initialization
    
    private init() {} // Singleton
    
    /// Temporary initialization for testing Phase 4B
    /// Full implementation will be in Phase 5
    internal static func initializeForTesting(
        configurationStore: PrecomputedConfigurationStore,
        subject: Subject,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = nil
    ) {
        shared.accessQueue.sync(flags: .barrier) {
            shared.configurationStore = configurationStore
            shared.subject = subject
            shared.assignmentLogger = assignmentLogger
            shared.assignmentCache = assignmentCache
            initialized = true
        }
        
        // Flush any queued assignments
        shared.flushQueuedAssignments()
    }
    
    // MARK: - Lifecycle Management
    
    /// Stops the configuration polling
    @MainActor
    public func stopPolling() {
        poller?.stop()
    }
    
    /// Resets the client state (useful for testing)
    internal static func resetForTesting() {
        initialized = false
        shared.accessQueue.sync(flags: .barrier) {
            shared.configurationStore = nil
            shared.subject = nil
            shared.assignmentLogger = nil
            shared.assignmentCache = nil
            // Note: We can't call stop() here as it's MainActor-isolated
            // The poller will be replaced/cleaned up when set to nil
            shared.poller = nil
            shared.requestor = nil
            shared.queuedAssignments.removeAll()
            shared.sdkKey = nil
        }
    }
    
    // MARK: - Queue Management
    
    /// Adds an assignment to the queue (called before logger is set)
    private func queueAssignment(_ assignment: Assignment) {
        accessQueue.sync(flags: .barrier) {
            // Limit queue size to prevent memory issues
            if queuedAssignments.count < maxEventQueueSize {
                queuedAssignments.append(assignment)
            }
        }
    }
    
    /// Flushes queued assignments to the logger
    private func flushQueuedAssignments() {
        guard let logger = assignmentLogger else { return }
        
        accessQueue.sync(flags: .barrier) {
            for assignment in queuedAssignments {
                logger(assignment)
            }
            queuedAssignments.removeAll()
        }
    }
    
    // MARK: - Assignment Methods (synchronous, type-specific)
    
    public func getStringAssignment(flagKey: String, defaultValue: String) -> String {
        return accessQueue.sync {
            return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .STRING)
        }
    }
    
    public func getBooleanAssignment(flagKey: String, defaultValue: Bool) -> Bool {
        return accessQueue.sync {
            return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .BOOLEAN)
        }
    }
    
    public func getIntegerAssignment(flagKey: String, defaultValue: Int) -> Int {
        return accessQueue.sync {
            return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .INTEGER)
        }
    }
    
    public func getNumericAssignment(flagKey: String, defaultValue: Double) -> Double {
        return accessQueue.sync {
            return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .NUMERIC)
        }
    }
    
    public func getJSONStringAssignment(flagKey: String, defaultValue: String) -> String {
        return accessQueue.sync {
            return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .JSON)
        }
    }
    
    // MARK: - Internal Assignment Logic
    
    private func getPrecomputedAssignment<T>(
        flagKey: String,
        defaultValue: T,
        expectedType: VariationType
    ) -> T {
        // Check if client is initialized
        guard Self.initialized,
              let store = configurationStore,
              store.isInitialized() else {
            return defaultValue
        }
        
        // Get salt for MD5 hashing (always obfuscated for precomputed)
        guard let salt = store.salt else {
            return defaultValue
        }
        
        // Hash the flag key with salt
        let hashedFlagKey = getMD5Hex(flagKey, salt: salt)
        
        // Look up the precomputed flag
        guard let flag = store.getFlag(forKey: hashedFlagKey) else {
            return defaultValue
        }
        
        // Validate type matches expected
        guard flag.variationType == expectedType else {
            return defaultValue
        }
        
        // Convert value based on type
        do {
            let convertedValue = try convertValue(
                flag.variationValue,
                expectedType: expectedType,
                defaultValue: defaultValue
            )
            
            // Log assignment if needed
            logAssignment(
                flagKey: flagKey,
                flag: flag,
                subject: subject
            )
            
            return convertedValue
        } catch {
            // Type conversion failed, return default
            return defaultValue
        }
    }
    
    // MARK: - Value Conversion
    
    private func convertValue<T>(
        _ eppoValue: EppoValue,
        expectedType: VariationType,
        defaultValue: T
    ) throws -> T {
        switch expectedType {
        case .STRING:
            let stringValue = try eppoValue.getStringValue()
            // Decode base64 if it's an obfuscated string
            let decodedValue = base64Decode(stringValue) ?? stringValue
            if let result = decodedValue as? T {
                return result
            }
            
        case .BOOLEAN:
            let boolValue = try eppoValue.getBoolValue()
            if let result = boolValue as? T {
                return result
            }
            
        case .INTEGER:
            let doubleValue = try eppoValue.getDoubleValue()
            let intValue = Int(doubleValue)
            if let result = intValue as? T {
                return result
            }
            
        case .NUMERIC:
            let doubleValue = try eppoValue.getDoubleValue()
            if let result = doubleValue as? T {
                return result
            }
            
        case .JSON:
            let stringValue = try eppoValue.getStringValue()
            // Decode base64 if it's an obfuscated JSON string
            let decodedValue = base64Decode(stringValue) ?? stringValue
            if let result = decodedValue as? T {
                return result
            }
        }
        
        throw Errors.variationWrongType
    }
    
    // MARK: - Assignment Logging
    
    private func logAssignment(
        flagKey: String,
        flag: PrecomputedFlag,
        subject: Subject?
    ) {
        guard flag.doLog,
              let subj = subject else {
            return
        }
        
        // Decode extra logging if obfuscated
        let decodedExtraLogging = decodeExtraLogging(flag.extraLogging)
        
        let assignment = Assignment(
            flagKey: flagKey,
            allocationKey: decodeBase64OrOriginal(flag.allocationKey ?? ""),
            variation: decodeBase64OrOriginal(flag.variationKey ?? ""),
            subject: subj.subjectKey,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            subjectAttributes: subj.subjectAttributes,
            extraLogging: decodedExtraLogging
        )
        
        // Check if we should log this assignment (deduplication)
        if shouldLogAssignment(assignment) {
            if let logger = assignmentLogger {
                logger(assignment)
            } else {
                // Queue for later when logger is set
                queueAssignment(assignment)
            }
        }
    }
    
    private func decodeExtraLogging(_ extraLogging: [String: String]) -> [String: String] {
        var decoded: [String: String] = [:]
        for (key, value) in extraLogging {
            let decodedKey = decodeBase64OrOriginal(key)
            let decodedValue = decodeBase64OrOriginal(value)
            decoded[decodedKey] = decodedValue
        }
        return decoded
    }
    
    private func decodeBase64OrOriginal(_ value: String) -> String {
        return base64Decode(value) ?? value
    }
    
    private func shouldLogAssignment(_ assignment: Assignment) -> Bool {
        guard let cache = assignmentCache,
              let allocationKey = assignment.allocation.isEmpty ? nil : assignment.allocation,
              let variationKey = assignment.variation.isEmpty ? nil : assignment.variation else {
            // No cache or missing keys, always log
            return true
        }
        
        let cacheKey = AssignmentCacheKey(
            subjectKey: assignment.subject,
            flagKey: assignment.featureFlag,
            allocationKey: allocationKey,
            variationKey: variationKey
        )
        
        // Log if not in cache
        let shouldLog = !cache.hasLoggedAssignment(key: cacheKey)
        
        if shouldLog {
            // Add to cache
            cache.setLastLoggedAssignment(key: cacheKey)
        }
        
        return shouldLog
    }
}