import Foundation

public enum Errors: Error {
    case notConfigured
    case sdkKeyInvalid
    case hostInvalid
    case subjectKeyRequired
    case flagKeyRequired
    case variationTypeMismatch
    case variationWrongType
    case invalidURL
    case configurationNotLoaded
    case flagConfigNotFound
}

public typealias SubjectAttributes = [String: EppoValue]
public typealias ConfigurationChangeCallback = (Configuration) -> Void
actor EppoClientState {
    private(set) var isLoaded: Bool = false

    func checkAndSetLoaded() -> Bool {
        if !isLoaded {
            isLoaded = true
            return false
        }
        return true
    }
}

public class EppoClient {
    public typealias AssignmentLogger = (Assignment) -> Void

    private static let sharedLock = NSLock()
    private static var sharedInstance: EppoClient?
    private static let initializerQueue = DispatchQueue(label: "cloud.eppo.client.initializer")

    private var flagEvaluator: FlagEvaluator = FlagEvaluator(sharder: MD5Sharder())

    private(set) var sdkKey: SDKKey
    private(set) var host: String
    private(set) var assignmentLogger: AssignmentLogger?
    private(set) var assignmentCache: AssignmentCache?
    public private(set) var configurationStore: ConfigurationStore
    private var configurationRequester: ConfigurationRequester
    private var poller: Poller?
    private var configurationChangeCallback: ConfigurationChangeCallback?

    private let state = EppoClientState()
    private let debugCallback: ((String, Double, Double) -> Void)?
    private var debugInitStartTime: Date?
    private var debugLastStepTime: Date?

    private init(
        sdkKey: String,
        host: String? = nil,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        initialConfiguration: Configuration?,
        withPersistentCache: Bool = true,
        loadInitialConfigurationImmediately: Bool = false,
        debugCallback: ((String, Double, Double) -> Void)? = nil
    ) {
        self.sdkKey = SDKKey(sdkKey)
        self.assignmentLogger = assignmentLogger
        self.assignmentCache = assignmentCache
        self.debugCallback = debugCallback
        self.debugInitStartTime = nil
        self.debugLastStepTime = nil

        let endpoints = ApiEndpoints(baseURL: host, sdkKey: self.sdkKey)
        self.host = endpoints.baseURL

        let httpClient = NetworkEppoHttpClient(baseURL: self.host, sdkKey: self.sdkKey.token, sdkName: sdkName, sdkVersion: sdkVersion)
        self.configurationRequester = ConfigurationRequester(httpClient: httpClient)

        self.configurationStore = ConfigurationStore(withPersistentCache: withPersistentCache)
        if loadInitialConfigurationImmediately {
            configurationStore.loadInitialConfiguration()
            // cache miss?
            if configurationStore.getConfiguration() == nil,
            let initialConfiguration {
                configurationStore.setConfiguration(configuration: initialConfiguration)
            }
        } else { //immediate cache load disabled
            if let configuration = initialConfiguration {
                self.configurationStore.setConfiguration(configuration: configuration)
                // Note: Callbacks will be registered after init, so initial config callback will be triggered during loadIfNeeded
            }
        }
        
        // Set up debug logging for ConfigurationRequester and ConfigurationStore after all properties are initialized
        if debugCallback != nil {
            self.configurationRequester.setDebugLogger { [weak self] message in
                self?.debugLog(message)
            }
            self.configurationStore.setDebugLogger { [weak self] message in
                self?.debugLog(message)
            }
        }
    }

    /// Initialize client without loading remote configuration.
    ///
    /// Configuration can later be loaded with `load()` method.
    public static func initializeOffline(
        sdkKey: String,
        host: String? = nil,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        initialConfiguration: Configuration?,
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil,
        debugCallback: ((String, Double, Double) -> Void)? = nil
    ) -> EppoClient {
        return sharedLock.withLock {
            if let instance = sharedInstance {
                return instance
            } else {
                let instance = EppoClient(
                  sdkKey: sdkKey,
                  host: host,
                  assignmentLogger: assignmentLogger,
                  assignmentCache: assignmentCache,
                  initialConfiguration: initialConfiguration,
                  withPersistentCache: withPersistentCache,
                  loadInitialConfigurationImmediately: true,
                  debugCallback: debugCallback
                )
                
                if let callback = configurationChangeCallback {
                    instance.onConfigurationChange(callback)
                }
                
                sharedInstance = instance
                return instance
            }
        }
    }

    public static func initialize(
        sdkKey: String,
        host: String? = nil,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        initialConfiguration: Configuration? = nil,
        pollingEnabled: Bool = false,
        pollingIntervalMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS,
        pollingJitterMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS / PollerConstants.DEFAULT_JITTER_INTERVAL_RATIO,
        withPersistentCache: Bool = true,
        configurationChangeCallback: ConfigurationChangeCallback? = nil,
        debugCallback: ((String, Double, Double) -> Void)? = nil
    ) async throws -> EppoClient {
        let instance = Self.initializeOffline(
            sdkKey: sdkKey,
            host: host,
            assignmentLogger: assignmentLogger,
            assignmentCache: assignmentCache,
            initialConfiguration: initialConfiguration,
            withPersistentCache: withPersistentCache,
            configurationChangeCallback: configurationChangeCallback,
            debugCallback: debugCallback
        )

        return try await withCheckedThrowingContinuation { continuation in
            initializerQueue.async {
                Task {
                    do {
                        instance.resetDebugTiming()
                        instance.debugLog("Starting Eppo SDK initialization")
                        
                        // Ensure persistent storage is loaded with debug timing
                        instance.configurationStore.loadInitialConfiguration()
                        
                        try await instance.loadIfNeeded()
                        
                        instance.debugLog("Configuration loading completed")
                        
                        if pollingEnabled {
                            instance.debugLog("Starting polling setup")
                            
                            try await instance.startPolling(
                                intervalMs: pollingIntervalMs,
                                jitterMs: pollingJitterMs
                            )
                            
                            instance.debugLog("Polling setup completed")
                        }
                        
                        instance.debugLog("Total SDK initialization completed")
                        
                        continuation.resume(returning: instance)
                    } catch {
                        instance.debugLog("SDK initialization failed with error: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    public static func shared() throws -> EppoClient {
        try self.sharedLock.withLock {
            guard let instance = sharedInstance else {
                throw Errors.notConfigured
            }
            return instance
        }
    }

    // Loads the configuration from the remote source on-demand. Can be used to refresh as desired.
    //
    // This function can be called from multiple threads; synchronization is provided to safely update
    // the configuration cache but each invocation will execute a new network request with billing impact.
    public func load() async throws {
        debugLog("Starting configuration fetch from remote")
        
        let config = try await self.configurationRequester.fetchConfigurations()
        
        debugLog("Network fetch and parsing completed")
        
        debugLog("Starting configuration storage")
        
        self.configurationStore.setConfiguration(configuration: config)
        notifyConfigurationChange(config)
        
        debugLog("Configuration storage and load completed")
    }

    public static func resetSharedInstance() {
        self.sharedLock.withLock {
            sharedInstance = nil
        }
    }

    private func loadIfNeeded() async throws {
        debugLog("Checking if SDK already loaded")
        let alreadyLoaded = await state.checkAndSetLoaded()
        guard !alreadyLoaded else { 
            debugLog("SDK already loaded, using existing configuration")
            // If already loaded but we have an existing configuration, notify callbacks
            if let existingConfig = configurationStore.getConfiguration() {
                notifyConfigurationChange(existingConfig)
            }
            return 
        }

        debugLog("First-time initialization detected, loading configuration")
        try await self.load()
    }

    public func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Bool) -> Bool {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.boolean
            )?.variation?.value.getBoolValue() ?? defaultValue
        } catch {
            return defaultValue
        }
    }

    public func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String) -> String {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.json
            )?.variation?.value.getStringValue() ?? defaultValue
        } catch {
            return defaultValue
        }
    }

    public func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Int) -> Int {
        do {
            let assignment = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.integer
            )
            
            // If we got an assignment error, return the default value
            if assignment?.flagEvaluationCode == .assignmentError {
                return defaultValue
            }
            
            // Get the double value and check if it's an integer
            guard let doubleValue = try? assignment?.variation?.value.getDoubleValue(),
                  doubleValue.isInteger else {
                return defaultValue
            }
            
            return Int(doubleValue)
        } catch {
            return defaultValue
        }
    }

    public func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Double) -> Double {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.numeric
            )?.variation?.value.getDoubleValue() ?? defaultValue
        } catch {
            return defaultValue
        }
    }

    public func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: String) -> String {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.string
            )?.variation?.value.getStringValue() ?? defaultValue
        } catch {
            return defaultValue
        }
    }

    /// Returns the current configuration stored in the client.
    public func getFlagsConfiguration() -> Configuration? {
        return self.configurationStore.getConfiguration()
    }

    private func getMatchedEvaluationCodeAndDescription(
        variation: UFC_Variation,
        allocation: UFC_Allocation,
        split: UFC_Split,
        subjectKey: String,
        expectedVariationType: UFC_VariationType
    ) -> (flagEvaluationCode: FlagEvaluationCode, flagEvaluationDescription: String) {
        guard isValueOfType(expectedType: expectedVariationType, variationValue: variation.value) else {
            return (
                flagEvaluationCode: .assignmentError,
                flagEvaluationDescription: "Variation (\(variation.key)) is configured for type \(expectedVariationType), but is set to incompatible value (\(variation.value))"
            )
        }

        let hasDefinedRules = !(allocation.rules?.isEmpty ?? true)
        let isExperiment = allocation.splits.count > 1
        let isPartialRollout = split.shards.count > 1
        let isExperimentOrPartialRollout = isExperiment || isPartialRollout

        return (
            flagEvaluationCode: .match,
            flagEvaluationDescription: EvaluationDescription.getDescription(
                hasDefinedRules: hasDefinedRules,
                isExperimentOrPartialRollout: isExperimentOrPartialRollout,
                allocationKey: allocation.key,
                subjectKey: subjectKey,
                variationKey: split.variationKey
            )
        )
    }

    private func getInternalAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        expectedVariationType: UFC_VariationType) throws -> FlagEvaluation? {
        if self.sdkKey.token.count == 0 {
            throw Errors.sdkKeyInvalid
        }

        if self.host.count == 0 {
            throw Errors.hostInvalid
        }

        if subjectKey.count == 0 { throw Errors.subjectKeyRequired }
        if flagKey.count == 0 { throw Errors.flagKeyRequired }

        guard let configuration = self.configurationStore.getConfiguration() else {
            throw Errors.configurationNotLoaded
        }

        let flagKeyForLookup = configuration.obfuscated ? getMD5Hex(flagKey) : flagKey

        guard let flagConfig = configuration.getFlag(flagKey: flagKeyForLookup) else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Unrecognized or disabled flag: \(flagKey)",
                entityId: nil
            )
        }

        if flagConfig.variationType != expectedVariationType {
            // Get all allocations from the flag config
            let allAllocations = flagConfig.allocations.enumerated().map { index, allocation in
                AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .unevaluated,
                    orderPosition: index + 1
                )
            }
            
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .typeMismatch,
                flagEvaluationDescription: "Variation value does not have the correct type. Found \(flagConfig.variationType.rawValue.uppercased()), but expected \(expectedVariationType.rawValue.uppercased()) for flag \(flagKey)",
                unmatchedAllocations: [],
                unevaluatedAllocations: allAllocations,
                entityId: flagConfig.entityId
            )
        }

        let flagEvaluation = flagEvaluator.evaluateFlag(
            flag: flagConfig,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: configuration.obfuscated
        )

        // Optionally log assignment
        if flagEvaluation.doLog && flagEvaluation.flagEvaluationCode != .assignmentError {
            if let assignmentLogger = self.assignmentLogger {
                let allocationKey = flagEvaluation.allocationKey ?? "__eppo_no_allocation"
                let variationKey = flagEvaluation.variation?.key ?? "__eppo_no_variation"

                // Prepare the assignment cache key
                let assignmentCacheKey = AssignmentCacheKey(
                    subjectKey: subjectKey,
                    flagKey: flagKey,
                    allocationKey: allocationKey,
                    variationKey: variationKey
                )

                // Check if the assignment has already been logged, if the cache is defined
                if let cache = self.assignmentCache, cache.hasLoggedAssignment(key: assignmentCacheKey) {
                    // The assignment has already been logged, do nothing
                } else {
                    // Either the cache is not defined, or the assignment hasn't been logged yet
                    // Perform assignment.
                    let entityId = flagEvaluation.entityId
                    let assignment = Assignment(
                        flagKey: flagKey,
                        allocationKey: allocationKey,
                        variation: variationKey,
                        subject: subjectKey,
                        timestamp: ISO8601DateFormatter().string(from: Date()),
                        subjectAttributes: subjectAttributes,
                        metaData: [
                            "obfuscated": String(configuration.obfuscated),
                            "sdkName": sdkName,
                            "sdkVersion": sdkVersion
                        ],
                        extraLogging: flagEvaluation.extraLogging,
                        entityId: entityId
                    )

                    assignmentLogger(assignment)
                    self.assignmentCache?.setLastLoggedAssignment(key: assignmentCacheKey)
                }
            }
        }

        return flagEvaluation
    }

    public struct AssignmentDetails<T> {
        public let variation: T?
        public let action: String?
        public let evaluationDetails: FlagEvaluationDetails
    }

    public struct FlagEvaluationDetails {
        public let environmentName: String
        public let flagEvaluationCode: FlagEvaluationCode
        public let flagEvaluationDescription: String
        public let variationKey: String?
        public let variationValue: EppoValue?
        public let banditKey: String?
        public let banditAction: String?
        public let configFetchedAt: String
        public let configPublishedAt: String
        public let matchedRule: UFC_Rule?
        public let matchedAllocation: AllocationEvaluation?
        public let unmatchedAllocations: [AllocationEvaluation]
        public let unevaluatedAllocations: [AllocationEvaluation]
    }

    public enum FlagEvaluationCode: String {
        case match = "MATCH"
        case flagUnrecognizedOrDisabled = "FLAG_UNRECOGNIZED_OR_DISABLED"
        case typeMismatch = "TYPE_MISMATCH"
        case assignmentError = "ASSIGNMENT_ERROR"
        case defaultAllocationNull = "DEFAULT_ALLOCATION_NULL"
        case noActionsSuppliedForBandit = "NO_ACTIONS_SUPPLIED_FOR_BANDIT"
        case banditError = "BANDIT_ERROR"
        case unknown = "UNKNOWN"
    }

    public enum AllocationEvaluationCode: String {
        case unevaluated = "UNEVALUATED"
        case match = "MATCH"
        case beforeStartTime = "BEFORE_START_TIME"
        case trafficExposureMiss = "TRAFFIC_EXPOSURE_MISS"
        case afterEndTime = "AFTER_END_TIME"
        case failingRule = "FAILING_RULE"
    }

    public typealias AllocationEvaluation = EppoFlagging.AllocationEvaluation

    public func getStringAssignmentDetails(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: String) -> AssignmentDetails<String> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.string
            )
            
            let variation = try flagEvaluation?.variation?.value.getStringValue() ?? defaultValue
            
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation,
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
            )
            
            return AssignmentDetails(
                variation: variation,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .unknown,
                    flagEvaluationDescription: "An error occurred: \(error.localizedDescription)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: nil,
                    matchedAllocation: nil,
                    unmatchedAllocations: [],
                    unevaluatedAllocations: []
                )
            )
        }
    }

    public func getJSONStringAssignmentDetails(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: String) -> AssignmentDetails<String> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.json
            )
            
            // Only use defaultValue if we have a variation but failed to get its string value
            let variation: String?
            if let flagVariation = flagEvaluation?.variation {
                variation = try flagVariation.value.getStringValue()
            } else {
                variation = nil
            }
            
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation,
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
            )
            
            // If we have no variation and the flag evaluation code is FLAG_UNRECOGNIZED_OR_DISABLED,
            // return nil instead of the default value
            let finalVariation = (variation == nil && flagEvaluation?.flagEvaluationCode == .flagUnrecognizedOrDisabled) ? nil : (variation ?? defaultValue)
            
            return AssignmentDetails(
                variation: finalVariation,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .unknown,
                    flagEvaluationDescription: "An error occurred: \(error.localizedDescription)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: nil,
                    matchedAllocation: nil,
                    unmatchedAllocations: [],
                    unevaluatedAllocations: []
                )
            )
        }
    }

    public func getBooleanAssignmentDetails(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Bool) -> AssignmentDetails<Bool> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.boolean
            )
            
            let variation = try flagEvaluation?.variation?.value.getBoolValue()
            
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation,
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
            )
            
            return AssignmentDetails(
                variation: variation ?? defaultValue,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .unknown,
                    flagEvaluationDescription: "An error occurred: \(error.localizedDescription)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: nil,
                    matchedAllocation: nil,
                    unmatchedAllocations: [],
                    unevaluatedAllocations: []
                )
            )
        }
    }

    public func getIntegerAssignmentDetails(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Int) -> AssignmentDetails<Int> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: .integer
            )
            
            // If we have an assignment error, return the error details with the default value
            if flagEvaluation?.flagEvaluationCode == .assignmentError {
                let details = AssignmentDetails(
                    variation: defaultValue,
                    action: nil,
                    evaluationDetails: FlagEvaluationDetails(
                        environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                        flagEvaluationCode: .assignmentError,
                        flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                        variationKey: flagEvaluation?.variation?.key,
                        variationValue: flagEvaluation?.variation?.value,
                        banditKey: nil,
                        banditAction: nil,
                        configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                        configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                        matchedRule: flagEvaluation?.matchedRule,
                        matchedAllocation: flagEvaluation?.matchedAllocation,
                        unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                        unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
                    )
                )
                return details
            }
            
            // Check if the value is a valid integer
            if let doubleValue = try? flagEvaluation?.variation?.value.getDoubleValue(),
               doubleValue.isInteger {
                let variation = Int(doubleValue)
                
                let evaluationDetails = FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                    flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                    variationKey: flagEvaluation?.variation?.key,
                    variationValue: flagEvaluation?.variation?.value,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: flagEvaluation?.matchedRule,
                    matchedAllocation: flagEvaluation?.matchedAllocation,
                    unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                    unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
                )
                
                return AssignmentDetails(
                    variation: variation,
                    action: nil,
                    evaluationDetails: evaluationDetails
                )
            }
            
            // If we get here, either there's no variation or it's not a valid integer
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .flagUnrecognizedOrDisabled,
                    flagEvaluationDescription: "Unrecognized or disabled flag: \(flagKey)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: nil,
                    matchedAllocation: nil,
                    unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                    unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
                )
            )
        } catch {
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .unknown,
                    flagEvaluationDescription: "An error occurred: \(error.localizedDescription)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: nil,
                    matchedAllocation: nil,
                    unmatchedAllocations: [],
                    unevaluatedAllocations: []
                )
            )
        }
    }

    public func getNumericAssignmentDetails(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Double) -> AssignmentDetails<Double> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.numeric
            )
            
            let variation = try flagEvaluation?.variation?.value.getDoubleValue()
            
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation,
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations ?? []
            )
            
            return AssignmentDetails(
                variation: variation ?? defaultValue,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .unknown,
                    flagEvaluationDescription: "An error occurred: \(error.localizedDescription)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                    matchedRule: nil,
                    matchedAllocation: nil,
                    unmatchedAllocations: [],
                    unevaluatedAllocations: []
                )
            )
        }
    }

    public func startPolling(
        intervalMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS,
        jitterMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS / PollerConstants.DEFAULT_JITTER_INTERVAL_RATIO
    ) async throws {
        // Stop any existing poller
        await poller?.stop()
        
        // Create a new poller with the load callback
        poller = await Poller(
            intervalMs: intervalMs,
            jitterMs: jitterMs,
            callback: { [weak self] in
                guard let self = self else { return }
                try await self.load()
            }
        )
        
        // Start the poller
        try await poller?.start()
    }

    @MainActor
    public func stopPolling() {
        poller?.stop()
        poller = nil
    }
    
    /// Registers a callback for when a new configuration is applied to the EppoClient instance.
    public func onConfigurationChange(_ callback: @escaping ConfigurationChangeCallback) {
        configurationChangeCallback = callback
    }
    
    /// Notifies the registered callback when configuration changes.
    private func notifyConfigurationChange(_ configuration: Configuration) {
        configurationChangeCallback?(configuration)
    }
    
    /// Internal debug logging with timing context
    private func resetDebugTiming() {
        debugInitStartTime = nil
        debugLastStepTime = nil
    }
    
    private func debugLog(_ message: String) {
        guard let callback = debugCallback else { return }
        
        let now = Date()
        
        // Initialize timing on first call
        if debugInitStartTime == nil {
            debugInitStartTime = now
            debugLastStepTime = now
            callback(message, 0.0, 0.0)
            return
        }
        
        // Calculate elapsed and step times in milliseconds
        let elapsedTimeMs = now.timeIntervalSince(debugInitStartTime!) * 1000.0
        let stepDurationMs = debugLastStepTime != nil ? now.timeIntervalSince(debugLastStepTime!) * 1000.0 : 0.0
        
        debugLastStepTime = now
        callback(message, elapsedTimeMs, stepDurationMs)
    }
    
}

func isValueOfType(expectedType: UFC_VariationType, variationValue: EppoValue) -> Bool {
    switch expectedType {
    case .json, .string:
        return variationValue.isString()
    case .integer:
        let doubleValue = try? variationValue.getDoubleValue()
        return variationValue.isNumeric() && doubleValue != nil && floor(doubleValue!) == doubleValue!
    case .numeric:
        return variationValue.isNumeric()
    case .boolean:
        return variationValue.isBool()
    }
}

extension Double {
    var isInteger: Bool {
        return self.truncatingRemainder(dividingBy: 1) == 0
    }
}
