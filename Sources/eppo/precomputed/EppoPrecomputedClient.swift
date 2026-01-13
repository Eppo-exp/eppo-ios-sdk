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

    public static func shared() throws -> EppoPrecomputedClient {
        try sharedLock.withLock {
            guard let instance = sharedInstance else {
                throw InitializationError.notConfigured
            }
            return instance
        }
    }

    private let configurationStore: PrecomputedConfigurationStore
    private let assignmentLogger: AssignmentLogger?
    private let assignmentCache: AssignmentCache?

    // MARK: - Network Components  
    private var requestor: PrecomputedRequestor?
    private var poller: Poller?
    private let sdkKey: String
    private var host: String?
    private var configurationChangeCallback: ConfigurationChangeCallback?

    /// Get the current precompute configuration from the loaded configuration
    private var currentPrecompute: Precompute? {
        guard let config = configurationStore.getDecodedConfiguration() else { return nil }
        return Precompute(
            subjectKey: config.subject.subjectKey,
            subjectAttributes: config.subject.subjectAttributes
        )
    }

    private init(
        sdkKey: String,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        initialPrecomputedConfiguration: PrecomputedConfiguration? = nil,
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil
    ) {
        self.sdkKey = sdkKey
        self.assignmentLogger = assignmentLogger
        self.assignmentCache = assignmentCache
        self.configurationStore = PrecomputedConfigurationStore(withPersistentCache: withPersistentCache)
        self.configurationChangeCallback = configurationChangeCallback

        // Set initial configuration if provided
        if let configuration = initialPrecomputedConfiguration {
            self.configurationStore.setConfiguration(configuration)
        }
    }

    /// Initialize the precomputed client offline with provided configuration
    /// The subject information is extracted from the precomputed configuration
    public static func initializeOffline(
        sdkKey: String,
        initialPrecomputedConfiguration: PrecomputedConfiguration? = nil,
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

            // Trigger configuration change callback if configuration was set
            if let configuration = initialPrecomputedConfiguration {
                instance.notifyConfigurationChange(configuration)
            }

            sharedInstance = instance
            return instance
        }
    }

    /// Initialize the precomputed client with online configuration fetch
    public static func initialize(
        sdkKey: String,
        precompute: Precompute,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        host: String? = nil,
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil,
        pollingEnabled: Bool = false,
        pollingIntervalMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS,
        pollingJitterMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS / PollerConstants.DEFAULT_JITTER_INTERVAL_RATIO
    ) async throws -> EppoPrecomputedClient {
        // Initialize offline first (without initial configuration) - returns existing instance if already initialized
        let instance = initializeOffline(
            sdkKey: sdkKey,
            initialPrecomputedConfiguration: nil,
            assignmentLogger: assignmentLogger,
            assignmentCache: assignmentCache,
            withPersistentCache: withPersistentCache,
            configurationChangeCallback: configurationChangeCallback
        )

        // Load configuration from network - this will trigger the configuration callback
        try await instance.load(precompute: precompute, host: host)

        // Auto-start polling if enabled
        if pollingEnabled {
            try await instance.startPolling(intervalMs: pollingIntervalMs, jitterMs: pollingJitterMs)
        }

        return instance
    }

    /// Load configuration from network
    public func load(precompute: Precompute, host: String? = nil) async throws {
        let resolvedHost = host ?? precomputedBaseUrl

        let requestor = PrecomputedRequestor(
            precompute: precompute,
            sdkKey: self.sdkKey,
            sdkName: sdkName,
            sdkVersion: sdkVersion,
            host: resolvedHost
        )

        let networkConfig = try await requestor.fetchPrecomputedFlags()

        // Create full configuration preserving precompute info
        let fullConfig = PrecomputedConfiguration(
            flags: networkConfig.flags,
            salt: networkConfig.salt,
            format: networkConfig.format,
            configFetchedAt: networkConfig.configFetchedAt,
            subject: Subject(
                subjectKey: precompute.subjectKey,
                subjectAttributes: precompute.subjectAttributes
            ),
            configPublishedAt: networkConfig.configPublishedAt,
            environment: networkConfig.environment
        )

        Self.sharedLock.withLock {
            self.requestor = requestor
            self.host = resolvedHost
            self.configurationStore.setConfiguration(fullConfig)
            self.notifyConfigurationChange(fullConfig)
        }
    }

    // MARK: - Polling Management

    /// Starts configuration polling for regular updates
    @MainActor
    public func startPolling(
        intervalMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS,
        jitterMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS / PollerConstants.DEFAULT_JITTER_INTERVAL_RATIO
    ) async throws {
        // Stop existing polling if running
        stopPolling()

        poller = await Poller(
            intervalMs: intervalMs,
            jitterMs: jitterMs,
            callback: { [weak self] in
                guard let self = self else { return }

                // Handle gracefully if network components aren't initialized yet
                guard let requestor = self.requestor else {
                    // Skip this polling cycle - network not initialized yet
                    return
                }

                do {
                    let networkConfig = try await requestor.fetchPrecomputedFlags()

                    // Create full configuration preserving precompute info from requestor
                    let fullConfig = PrecomputedConfiguration(
                        flags: networkConfig.flags,
                        salt: networkConfig.salt,
                        format: networkConfig.format,
                        configFetchedAt: networkConfig.configFetchedAt,
                        subject: Subject(
                            subjectKey: requestor.precompute.subjectKey,
                            subjectAttributes: requestor.precompute.subjectAttributes
                        ),
                        configPublishedAt: networkConfig.configPublishedAt,
                        environment: networkConfig.environment
                    )

                    Self.sharedLock.withLock {
                        self.configurationStore.setConfiguration(fullConfig)
                        self.notifyConfigurationChange(fullConfig)
                    }
                } catch {
                    // Poller will handle retry logic
                    throw error
                }
            }
        )

        try await poller?.start()
    }

    /// Stops configuration polling
    @MainActor
    public func stopPolling() {
        poller?.stop()
        poller = nil
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

        guard let decodedConfig = configurationStore.getDecodedConfiguration() else {
            return defaultValue
        }

        let hashedFlagKey = getMD5Hex(flagKey, salt: decodedConfig.decodedSalt)

        guard let flag = configurationStore.getDecodedFlag(forKey: hashedFlagKey) else {
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
            if let result = stringValue as? T {
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
            if let result = stringValue as? T {
                return result
            }
        }
        throw Errors.variationWrongType
    }

    // MARK: - Assignment Logging

    private func logAssignment(
        flagKey: String,
        flag: DecodedPrecomputedFlag
    ) {
        guard let precompute = currentPrecompute else {
            return
        }

        let assignment = Assignment(
            flagKey: flagKey,
            allocationKey: flag.allocationKey ?? "",
            variation: flag.variationKey ?? "",
            subject: precompute.subjectKey,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            subjectAttributes: precompute.subjectAttributes,
            metaData: [
                "obfuscated": "true",
                "sdkName": sdkName,
                "sdkVersion": sdkVersion
            ],
            extraLogging: flag.extraLogging
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

        return cache.shouldLogAssignment(key: cacheKey)
    }
}
