import Foundation

/// Eppo client for precomputed flag assignments
public class EppoPrecomputedClient {
    public typealias AssignmentLogger = (Assignment) -> Void
    public typealias ConfigurationChangeCallback = (PrecomputedConfiguration) -> Void
    
    public enum InitializationError: Error {
        case notConfigured
    }
    private static let sharedLock = NSLock()
    private static var sharedInstance: EppoPrecomputedClient?
    private static let initializerQueue = DispatchQueue(label: "cloud.eppo.precomputed.initializer")
    
    public static func shared() throws -> EppoPrecomputedClient {
        try sharedLock.withLock {
            guard let instance = sharedInstance else {
                throw InitializationError.notConfigured
            }
            return instance
        }
    }
    
    private let configurationStore: PrecomputedConfigurationStore
    private let subject: Subject
    private let assignmentLogger: AssignmentLogger?
    private let assignmentCache: AssignmentCache?
    
    private let sdkKey: String
    private var configurationChangeCallback: ConfigurationChangeCallback?
    
    private init(
        sdkKey: String,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        initialPrecomputedConfiguration: PrecomputedConfiguration? = nil,
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil
    ) {
        self.sdkKey = sdkKey
        
        // Extract subject from configuration or use placeholder
        if let configuration = initialPrecomputedConfiguration {
            self.subject = configuration.subject
            self.configurationStore = PrecomputedConfigurationStore(withPersistentCache: withPersistentCache)
            self.configurationStore.setConfiguration(configuration)
        } else {
            // Create a placeholder subject for offline-only initialization
            self.subject = Subject(subjectKey: "", subjectAttributes: [:])
            self.configurationStore = PrecomputedConfigurationStore(withPersistentCache: withPersistentCache)
        }
        
        self.assignmentLogger = assignmentLogger
        self.assignmentCache = assignmentCache
        self.configurationChangeCallback = configurationChangeCallback
    }
    
    
    /// Initialize the precomputed client offline with provided configuration
    /// The subject information is extracted from the precomputed configuration
    public static func initializeOffline(
        sdkKey: String,
        initialPrecomputedConfiguration: PrecomputedConfiguration,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil
    ) -> EppoPrecomputedClient {
        return Self.sharedLock.withLock {
            if let instance = sharedInstance {
                return instance
            }
            
            let instance = EppoPrecomputedClient(
                sdkKey: sdkKey,
                assignmentLogger: assignmentLogger,
                assignmentCache: assignmentCache,
                initialPrecomputedConfiguration: initialPrecomputedConfiguration,
                withPersistentCache: withPersistentCache,
                configurationChangeCallback: configurationChangeCallback
            )
            
            // Trigger configuration change callback
            instance.notifyConfigurationChange(initialPrecomputedConfiguration)
            
            sharedInstance = instance
            return instance
        }
    }
    
    // MARK: - Lifecycle Management
    
    /// Sets the configuration change callback
    public func onConfigurationChange(_ callback: @escaping ConfigurationChangeCallback) {
        configurationChangeCallback = callback
    }
    
    /// Notifies the registered callback when configuration changes
    private func notifyConfigurationChange(_ configuration: PrecomputedConfiguration) {
        configurationChangeCallback?(configuration)
    }
    
    /// Resets the client state (useful for testing)
    public static func resetForTesting() {
        sharedLock.withLock {
            sharedInstance = nil
        }
    }
    
    // MARK: - Assignment Methods (synchronous, type-specific)
    
    public func getStringAssignment(flagKey: String, defaultValue: String) -> String {
        return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .STRING)
    }
    
    public func getBooleanAssignment(flagKey: String, defaultValue: Bool) -> Bool {
        return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .BOOLEAN)
    }
    
    public func getIntegerAssignment(flagKey: String, defaultValue: Int) -> Int {
        return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .INTEGER)
    }
    
    public func getNumericAssignment(flagKey: String, defaultValue: Double) -> Double {
        return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .NUMERIC)
    }
    
    public func getJSONStringAssignment(flagKey: String, defaultValue: String) -> String {
        return getPrecomputedAssignment(flagKey: flagKey, defaultValue: defaultValue, expectedType: .JSON)
    }
    
    // MARK: - Internal Assignment Logic
    
    private func getPrecomputedAssignment<T>(
        flagKey: String,
        defaultValue: T,
        expectedType: VariationType
    ) -> T {
        guard configurationStore.isInitialized() else {
            return defaultValue
        }
        
        guard let salt = configurationStore.salt else {
            return defaultValue
        }
        
        guard let decodedSalt = base64Decode(salt) else {
            return defaultValue
        }
        
        let hashedFlagKey = getMD5Hex(flagKey, salt: decodedSalt)
        
        guard let flag = configurationStore.getFlag(forKey: hashedFlagKey) else {
            return defaultValue
        }
        
        guard flag.variationType == expectedType else {
            return defaultValue
        }
        
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
                    flag: flag
                )
            }
            
            return convertedValue
        } catch {
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
            // Precomputed configs are always obfuscated - decode base64 string
            let decodedValue = try base64DecodeOrThrow(stringValue)
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
            // Precomputed configs are always obfuscated - decode base64 JSON string
            let decodedValue = try base64DecodeOrThrow(stringValue)
            if let result = decodedValue as? T {
                return result
            }
        }
        
        throw Errors.variationWrongType
    }
    
    // MARK: - Assignment Logging
    
    private func logAssignment(
        flagKey: String,
        flag: PrecomputedFlag
    ) {
        
        var decodedAllocationKey: String = flag.allocationKey ?? ""
        if let allocationKey = flag.allocationKey,
           let decoded = base64Decode(allocationKey) {
            decodedAllocationKey = decoded
        }
        
        var decodedVariationKey: String = flag.variationKey ?? ""
        if let variationKey = flag.variationKey,
           let decoded = base64Decode(variationKey) {
            decodedVariationKey = decoded
        }
        
        // Decode extraLogging keys and values
        var decodedExtraLogging: [String: String] = [:]
        for (key, value) in flag.extraLogging {
            do {
                // Decode both key and value if they are base64 encoded
                let decodedKey = try base64DecodeOrThrow(key)
                let decodedValue = try base64DecodeOrThrow(value)
                decodedExtraLogging[decodedKey] = decodedValue
            } catch {
                print("Warning: Failed to decode extraLogging entry - key: \(key), value: \(value), error: \(error.localizedDescription)")
                // Skip this entry - don't add it to decodedExtraLogging
            }
        }
        
        let assignment = Assignment(
            flagKey: flagKey,
            allocationKey: decodedAllocationKey,
            variation: decodedVariationKey,
            subject: subject.subjectKey,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            subjectAttributes: subject.subjectAttributes,
            metaData: [
                "obfuscated": "true",
                "sdkName": sdkName,
                "sdkVersion": sdkVersion
            ],
            extraLogging: decodedExtraLogging
        )
        
        if shouldLogAssignment(assignment) {
            if let logger = assignmentLogger {
                logger(assignment)
            }
        }
    }
    
    private func shouldLogAssignment(_ assignment: Assignment) -> Bool {
        guard let cache = assignmentCache,
              let allocationKey = assignment.allocation.isEmpty ? nil : assignment.allocation,
              let variationKey = assignment.variation.isEmpty ? nil : assignment.variation else {
            return true
        }
        
        let cacheKey = AssignmentCacheKey(
            subjectKey: assignment.subject,
            flagKey: assignment.featureFlag,
            allocationKey: allocationKey,
            variationKey: variationKey
        )
        
        let shouldLog = !cache.hasLoggedAssignment(key: cacheKey)
        
        if shouldLog {
            cache.setLastLoggedAssignment(key: cacheKey)
        }
        
        return shouldLog
    }
}
