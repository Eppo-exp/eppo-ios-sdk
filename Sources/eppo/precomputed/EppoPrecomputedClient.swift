import Foundation

/// Eppo client for precomputed flag assignments
public class EppoPrecomputedClient {
    public typealias AssignmentLogger = (Assignment) -> Void
    public typealias ConfigurationChangeCallback = (PrecomputedConfiguration) -> Void
    
    // MARK: - Error Types
    
    public enum InitializationError: Error {
        case alreadyInitialized
    }
    // MARK: - Singleton Pattern (matches regular EppoClient)
    private static let sharedLock = NSLock()
    private static var sharedInstance: EppoPrecomputedClient?
    private static var initialized = false
    private static var initializing = false
    
    public static var shared: EppoPrecomputedClient {
        sharedLock.withLock {
            if let instance = sharedInstance {
                return instance
            }
            let instance = EppoPrecomputedClient()
            sharedInstance = instance
            return instance
        }
    }
    
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
    private var host: String?
    private var configurationChangeCallback: ConfigurationChangeCallback?
    private var debugCallback: ((String, Double, Double) -> Void)?
    private var isInitialized: Bool {
        return Self.sharedLock.withLock { Self.initialized }
    }
    
    // MARK: - Initialization
    
    private init() {} // Singleton
    
    /// Initialize the precomputed client with online configuration fetch
    public static func initialize(
        sdkKey: String,
        subject: Subject,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        host: String? = nil,
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil,
        debugCallback: ((String, Double, Double) -> Void)? = nil
    ) async throws -> EppoPrecomputedClient {
        let startTime = Date()
        
        // Check if already initialized or initializing (synchronously)
        let (wasInitialized, wasInitializing) = sharedLock.withLock { 
            if initialized || initializing {
                return (initialized, initializing)
            } else {
                initializing = true
                return (false, false)
            }
        }
        
        if wasInitialized || wasInitializing {
            throw InitializationError.alreadyInitialized
        }
        
        // Track initialization timing
        debugCallback?("precomputed_client_initialize_start", 0, startTime.timeIntervalSince1970)
        
        // Setup components outside of sync block
        let resolvedHost = host ?? "https://fs-edge-assignment.eppo.cloud"
        let store = PrecomputedConfigurationStore()
        let requestor = PrecomputedRequestor(
            subject: subject,
            sdkKey: sdkKey,
            sdkName: sdkName,
            sdkVersion: sdkVersion,
            host: resolvedHost
        )
        
        // Fetch configuration asynchronously
        do {
            let fetchStartTime = Date()
            debugCallback?("precomputed_config_fetch_start", 0, fetchStartTime.timeIntervalSince1970)
            
            let configuration = try await requestor.fetchPrecomputedFlags()
            
            let fetchDuration = Date().timeIntervalSince(fetchStartTime)
            debugCallback?("precomputed_config_fetch_success", fetchDuration, Date().timeIntervalSince1970)
            
            // Now update state synchronously
            shared.accessQueue.sync(flags: .barrier) {
                // Double-check initialization state
                guard !initialized else { return }
                
                // Store initialization parameters
                shared.sdkKey = sdkKey
                shared.subject = subject
                shared.assignmentLogger = assignmentLogger
                shared.assignmentCache = assignmentCache
                shared.host = resolvedHost
                shared.configurationChangeCallback = configurationChangeCallback
                shared.debugCallback = debugCallback
                shared.configurationStore = store
                shared.requestor = requestor
                
                // Store configuration
                store.setConfiguration(configuration)
                
                // Mark as initialized and flush queued assignments
                initializing = false
                initialized = true
                shared.flushQueuedAssignments()
                
                // Notify configuration change callback
                configurationChangeCallback?(configuration)
            }
            
            let totalDuration = Date().timeIntervalSince(startTime)
            debugCallback?("precomputed_client_initialize_success", totalDuration, Date().timeIntervalSince1970)
            
            return shared
        } catch {
            let errorDuration = Date().timeIntervalSince(startTime)
            debugCallback?("precomputed_client_initialize_error", errorDuration, Date().timeIntervalSince1970)
            
            // Clean up on failure
            shared.accessQueue.sync(flags: .barrier) {
                shared.configurationStore = nil
                shared.requestor = nil
                shared.sdkKey = nil
                shared.subject = nil
                shared.assignmentLogger = nil
                shared.assignmentCache = nil
                shared.host = nil
                shared.configurationChangeCallback = nil
                shared.debugCallback = nil
                initializing = false  // Clear initializing flag on failure
            }
            
            throw error
        }
    }
    
    /// Initialize the precomputed client offline with provided configuration
    public static func initializeOffline(
        sdkKey: String,
        subject: Subject,
        initialPrecomputedConfiguration: PrecomputedConfiguration,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil,
        debugCallback: ((String, Double, Double) -> Void)? = nil
    ) -> EppoPrecomputedClient {
        let result = shared.accessQueue.sync(flags: .barrier) { () -> EppoPrecomputedClient in
            // Prevent re-initialization
            guard !initialized else {
                debugCallback?("precomputed_client_already_initialized", 0, Date().timeIntervalSince1970)
                return shared
            }
            
            let startTime = Date()
            debugCallback?("precomputed_client_offline_init_start", 0, startTime.timeIntervalSince1970)
            
            // Store initialization parameters
            shared.sdkKey = sdkKey
            shared.subject = subject
            shared.assignmentLogger = assignmentLogger
            shared.assignmentCache = assignmentCache
            shared.configurationChangeCallback = configurationChangeCallback
            shared.debugCallback = debugCallback
            
            // Create and populate configuration store
            let store = PrecomputedConfigurationStore()
            store.setConfiguration(initialPrecomputedConfiguration)
            shared.configurationStore = store
            
            // Notify configuration change callback
            configurationChangeCallback?(initialPrecomputedConfiguration)
            
            // Mark as initialized but DO NOT flush queued assignments inside sync block
            initialized = true
            
            let duration = Date().timeIntervalSince(startTime)
            debugCallback?("precomputed_client_offline_init_success", duration, Date().timeIntervalSince1970)
            
            return shared
        }
        
        // Flush queued assignments OUTSIDE the sync block to prevent crashes
        // This matches the safer pattern used in initializeForTesting()
        result.flushQueuedAssignments()
        
        return result
    }
    
    /// Temporary initialization for testing
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
    
    // MARK: - Configuration Management
    
    /// Sets or updates the assignment logger
    public func setAssignmentLogger(_ logger: @escaping AssignmentLogger) {
        accessQueue.sync(flags: .barrier) {
            assignmentLogger = logger
            // Flush any queued assignments
            flushQueuedAssignments()
        }
    }
    
    // MARK: - Lifecycle Management
    
    /// Stops the configuration polling
    @MainActor
    public func stopPolling() {
        poller?.stop()
    }
    
    /// Resets the client state (useful for testing)
    public static func resetForTesting() {
        sharedLock.withLock {
            initialized = false
            initializing = false
            sharedInstance = nil
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
        let isInitialized = Self.sharedLock.withLock { Self.initialized }
        guard isInitialized,
              let store = configurationStore,
              store.isInitialized() else {
            return defaultValue
        }
        
        // Get salt for MD5 hashing (always obfuscated for precomputed)
        guard let salt = store.salt else {
            return defaultValue
        }
        
        // Decode base64 salt (precomputed configs are always obfuscated)
        guard let decodedSalt = base64Decode(salt) else {
            return defaultValue
        }
        
        // Hash the flag key with decoded salt
        let hashedFlagKey = getMD5Hex(flagKey, salt: decodedSalt)
        
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
            
            // Log assignment if needed (now that initialization deadlock is fixed)
            if flag.doLog {
                logAssignment(
                    flagKey: flagKey,
                    flag: flag,
                    subject: subject
                )
            }
            
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
        guard let subj = subject else { return }
        
        // Decode base64 values for assignment logging (production data is base64 encoded)
        let decodedAllocationKey = base64Decode(flag.allocationKey ?? "") ?? flag.allocationKey ?? "__eppo_no_allocation"
        let decodedVariationKey = base64Decode(flag.variationKey ?? "") ?? flag.variationKey ?? "__eppo_no_variation"
        
        // Decode extraLogging keys and values
        var decodedExtraLogging: [String: String] = [:]
        for (key, value) in flag.extraLogging {
            let decodedKey = base64Decode(key) ?? key
            let decodedValue = base64Decode(value) ?? value
            decodedExtraLogging[decodedKey] = decodedValue
        }
        
        // Create assignment with decoded values
        let assignment = Assignment(
            flagKey: flagKey,
            allocationKey: decodedAllocationKey,
            variation: decodedVariationKey,
            subject: subj.subjectKey,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            subjectAttributes: subj.subjectAttributes,
            metaData: [
                "obfuscated": "true",
                "sdkName": sdkName,
                "sdkVersion": sdkVersion
            ],
            extraLogging: decodedExtraLogging
        )
        
        // Check deduplication and log
        if shouldLogAssignment(assignment) {
            if let logger = assignmentLogger {
                logger(assignment)
            } else {
                queueAssignment(assignment)
            }
        }
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