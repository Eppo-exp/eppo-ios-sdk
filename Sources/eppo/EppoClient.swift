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
    private(set) var configurationStore: ConfigurationStore
    private var configurationRequester: ConfigurationRequester
    private var poller: Poller?

    private let state = EppoClientState()

    private init(
        sdkKey: String,
        host: String? = nil,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache(),
        initialConfiguration: Configuration?,
        withPersistentCache: Bool = true
    ) {
        self.sdkKey = SDKKey(sdkKey)
        self.assignmentLogger = assignmentLogger
        self.assignmentCache = assignmentCache

        let endpoints = ApiEndpoints(baseURL: host, sdkKey: self.sdkKey)
        self.host = endpoints.baseURL

        let httpClient = NetworkEppoHttpClient(baseURL: self.host, sdkKey: self.sdkKey.token, sdkName: "sdkName", sdkVersion: sdkVersion)
        self.configurationRequester = ConfigurationRequester(httpClient: httpClient)

        self.configurationStore = ConfigurationStore(withPersistentCache: withPersistentCache)
        if let configuration = initialConfiguration {
            self.configurationStore.setConfiguration(configuration: configuration)
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
        withPersistentCache: Bool = true
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
                  withPersistentCache: withPersistentCache
                )
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
        pollingJitterMs: Int = PollerConstants.DEFAULT_POLL_INTERVAL_MS / PollerConstants.DEFAULT_JITTER_INTERVAL_RATIO
    ) async throws -> EppoClient {
        let instance = Self.initializeOffline(
            sdkKey: sdkKey,
            host: host,
            assignmentLogger: assignmentLogger,
            assignmentCache: assignmentCache,
            initialConfiguration: initialConfiguration
        )

        return try await withCheckedThrowingContinuation { continuation in
            initializerQueue.async {
                Task {
                    do {
                        try await instance.loadIfNeeded()
                        if pollingEnabled {
                            try await instance.startPolling(
                                intervalMs: pollingIntervalMs,
                                jitterMs: pollingJitterMs
                            )
                        }
                        continuation.resume(returning: instance)
                    } catch {
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
        let config = try await self.configurationRequester.fetchConfigurations()
        self.configurationStore.setConfiguration(configuration: config)
    }

    public static func resetSharedInstance() {
        self.sharedLock.withLock {
            sharedInstance = nil
        }
    }

    private func loadIfNeeded() async throws {
        let alreadyLoaded = await state.checkAndSetLoaded()
        guard !alreadyLoaded else { return }

        try await self.load()
    }

    public func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Bool) throws -> Bool {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.boolean
            )?.variation?.value.getBoolValue() ?? defaultValue
        } catch {
            // todo: implement graceful mode
            return defaultValue
        }
    }

    public func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String) throws -> String {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.json
            )?.variation?.value.getStringValue() ?? defaultValue
        } catch {
            // todo: implement graceful mode
            return defaultValue
        }
    }

    public func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Int) throws -> Int {
        do {
            let assignment = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.integer
            )
            return Int(try assignment?.variation?.value.getDoubleValue() ?? Double(defaultValue))
        } catch {
            // todo: implement graceful mode
            return defaultValue
        }
    }

    public func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Double) throws -> Double {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.numeric
            )?.variation?.value.getDoubleValue() ?? defaultValue
        } catch {
            // todo: implement graceful mode
            return defaultValue
        }
    }

    public func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: String) throws -> String {
        do {
            return try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.string
            )?.variation?.value.getStringValue() ?? defaultValue
        } catch {
            // todo: implement graceful mode
            return defaultValue
        }
    }

    /// Returns the current configuration stored in the client.
    public func getFlagsConfiguration() -> Configuration? {
        return self.configurationStore.getConfiguration()
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
            throw Errors.flagConfigNotFound
        }

        if flagConfig.variationType != expectedVariationType {
            throw Errors.variationTypeMismatch
        }

        let flagEvaluation = flagEvaluator.evaluateFlag(
            flag: flagConfig,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: configuration.obfuscated
        )

        if let variation = flagEvaluation.variation, !isValueOfType(expectedType: expectedVariationType, variationValue: variation.value) {
            throw Errors.variationWrongType
        }

        // Optionally log assignment
        if flagEvaluation.doLog {
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
                        extraLogging: flagEvaluation.extraLogging
                    )

                    assignmentLogger(assignment)
                    self.assignmentCache?.setLastLoggedAssignment(key: assignmentCacheKey)
                }
            }
        }

        return flagEvaluation
    }

    public struct AssignmentDetails<T> {
        public let variation: T
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
    }

    public enum AllocationEvaluationCode: String {
        case unevaluated = "UNEVALUATED"
        case match = "MATCH"
        case beforeStartTime = "BEFORE_START_TIME"
        case trafficExposureMiss = "TRAFFIC_EXPOSURE_MISS"
        case afterEndTime = "AFTER_END_TIME"
        case failingRule = "FAILING_RULE"
    }

    public struct AllocationEvaluation {
        public let key: String
        public let allocationEvaluationCode: AllocationEvaluationCode
        public let orderPosition: Int
    }

    public func getStringAssignmentDetails(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: String) throws -> AssignmentDetails<String> {
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
                flagEvaluationCode: flagEvaluation?.doLog == true ? .match : .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.doLog == true ? "Assignment successful" : "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: nil,
                matchedAllocation: nil,
                unmatchedAllocations: [],
                unevaluatedAllocations: []
            )
            
            return AssignmentDetails(
                variation: variation,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            // todo: implement graceful mode
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription: "Error getting assignment: \(error.localizedDescription)",
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
        defaultValue: Bool) throws -> AssignmentDetails<Bool> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.boolean
            )
            
            let variation = try flagEvaluation?.variation?.value.getBoolValue() ?? defaultValue
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.doLog == true ? .match : .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.doLog == true ? "Assignment successful" : "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: nil,
                matchedAllocation: nil,
                unmatchedAllocations: [],
                unevaluatedAllocations: []
            )
            
            return AssignmentDetails(
                variation: variation,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            // todo: implement graceful mode
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription: "Error getting assignment: \(error.localizedDescription)",
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
        defaultValue: Int) throws -> AssignmentDetails<Int> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.integer
            )
            
            let variation = Int(try flagEvaluation?.variation?.value.getDoubleValue() ?? Double(defaultValue))
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.doLog == true ? .match : .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.doLog == true ? "Assignment successful" : "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: nil,
                matchedAllocation: nil,
                unmatchedAllocations: [],
                unevaluatedAllocations: []
            )
            
            return AssignmentDetails(
                variation: variation,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            // todo: implement graceful mode
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription: "Error getting assignment: \(error.localizedDescription)",
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
        defaultValue: Double) throws -> AssignmentDetails<Double> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.numeric
            )
            
            let variation = try flagEvaluation?.variation?.value.getDoubleValue() ?? defaultValue
            let evaluationDetails = FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagEvaluationCode: flagEvaluation?.doLog == true ? .match : .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.doLog == true ? "Assignment successful" : "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: nil,
                matchedAllocation: nil,
                unmatchedAllocations: [],
                unevaluatedAllocations: []
            )
            
            return AssignmentDetails(
                variation: variation,
                action: nil,
                evaluationDetails: evaluationDetails
            )
        } catch {
            // todo: implement graceful mode
            return AssignmentDetails(
                variation: defaultValue,
                action: nil,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription: "Error getting assignment: \(error.localizedDescription)",
                    variationKey: nil,
                    variationValue: nil,
                    banditKey: nil,
                    banditAction: nil,
                    configFetchedAt: configurationStore.getConfiguration()?.fetchedAt ?? "",
                    configPublishedAt: configurationStore.getConfiguration()?.publishedAt ?? "",
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
