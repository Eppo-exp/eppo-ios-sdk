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

    private func getMatchedEvaluationCodeAndDescription(
        variation: UFC_Variation,
        allocation: UFC_Allocation,
        split: UFC_Split,
        subjectKey: String,
        expectedVariationType: UFC_VariationType
    ) -> (flagEvaluationCode: FlagEvaluationCode, flagEvaluationDescription: String) {
        // Check for type mismatch
        if !isValueOfType(expectedType: expectedVariationType, variationValue: variation.value) {
            return (
                flagEvaluationCode: .assignmentError,
                flagEvaluationDescription: "Variation (\(variation.key)) is configured for type \(expectedVariationType), but is set to incompatible value (\(variation.value))"
            )
        }

        let hasDefinedRules = !(allocation.rules?.isEmpty ?? true)
        let isExperiment = allocation.splits.count > 1
        let isPartialRollout = split.shards.count > 1
        let isExperimentOrPartialRollout = isExperiment || isPartialRollout

        if hasDefinedRules && isExperimentOrPartialRollout {
            return (
                flagEvaluationCode: .match,
                flagEvaluationDescription: "Supplied attributes match rules defined in allocation \"\(allocation.key)\" and \(subjectKey) belongs to the range of traffic assigned to \"\(split.variationKey)\"."
            )
        }
        if hasDefinedRules && !isExperimentOrPartialRollout {
            return (
                flagEvaluationCode: .match,
                flagEvaluationDescription: "Supplied attributes match rules defined in allocation \"\(allocation.key)\"."
            )
        }
        return (
            flagEvaluationCode: .match,
            flagEvaluationDescription: "\(subjectKey) belongs to the range of traffic assigned to \"\(split.variationKey)\" defined in allocation \"\(allocation.key)\"."
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
            print("DEBUG: Flag config not found for key: \(flagKey)")
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Unrecognized or disabled flag: \(flagKey)",
                variationValue: nil
            )
        }

        print("DEBUG: Found flag config: \(flagConfig)")

        if flagConfig.variationType != expectedVariationType {
            print("DEBUG: Type mismatch - Expected: \(expectedVariationType), Got: \(flagConfig.variationType)")
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
                variationValue: nil
            )
        }

        let flagEvaluation = flagEvaluator.evaluateFlag(
            flag: flagConfig,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: configuration.obfuscated
        )

        print("DEBUG: Flag evaluation result: \(flagEvaluation)")

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

    public typealias AllocationEvaluation = EppoFlagging.AllocationEvaluation

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
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) },
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? []
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
        defaultValue: String) throws -> AssignmentDetails<String> {
        do {
            let flagEvaluation = try getInternalAssignment(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                expectedVariationType: UFC_VariationType.json
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
                matchedAllocation: flagEvaluation?.matchedAllocation.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) },
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? []
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
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) },
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? []
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
        defaultValue: Int
    ) -> AssignmentDetails<Int> {
        print("Getting integer assignment details for flag: \(flagKey), subject: \(subjectKey)")
        
        let flagEvaluation = getInternalAssignment(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            expectedVariationType: .integer
        )
        print("Flag evaluation result: \(String(describing: flagEvaluation))")
        
        // Return the default value with evaluation details when there's an error
        if let error = flagEvaluation?.flagEvaluationCode, error == .assignmentError {
            print("Assignment error detected: \(error)")
            return AssignmentDetails(
                value: defaultValue,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagKey: flagKey,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    variationKey: flagEvaluation?.variation?.key,
                    variationValue: flagEvaluation?.variationValue,
                    flagEvaluationCode: error,
                    flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription,
                    matchedAllocation: flagEvaluation?.matchedAllocation,
                    unmatchedAllocations: flagEvaluation?.unmatchedAllocations,
                    unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations
                )
            )
        }
        
        // Try to get the integer value
        if let value = flagEvaluation?.variationValue {
            if let intValue = try? value.getIntegerValue() {
                return AssignmentDetails(
                    value: intValue,
                    evaluationDetails: FlagEvaluationDetails(
                        environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        variationKey: flagEvaluation?.variation?.key,
                        variationValue: value,
                        flagEvaluationCode: flagEvaluation?.flagEvaluationCode,
                        flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription,
                        matchedAllocation: flagEvaluation?.matchedAllocation,
                        unmatchedAllocations: flagEvaluation?.unmatchedAllocations,
                        unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations
                    )
                )
            }
            
            // If we have a value but it's not a valid integer, return an assignment error
            return AssignmentDetails(
                value: defaultValue,
                evaluationDetails: FlagEvaluationDetails(
                    environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                    flagKey: flagKey,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    variationKey: flagEvaluation?.variation?.key,
                    variationValue: value,
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription: "Variation (\(flagEvaluation?.variation?.key ?? "")) is configured for type INTEGER, but is set to incompatible value (\(value))",
                    matchedAllocation: flagEvaluation?.matchedAllocation,
                    unmatchedAllocations: flagEvaluation?.unmatchedAllocations,
                    unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations
                )
            )
        }
        
        // Return default value with error details if we have no value
        return AssignmentDetails(
            value: defaultValue,
            evaluationDetails: FlagEvaluationDetails(
                environmentName: configurationStore.getConfiguration()?.getFlagConfigDetails().configEnvironment.name ?? "",
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variationValue,
                flagEvaluationCode: .assignmentError,
                flagEvaluationDescription: "Invalid value type for integer flag",
                matchedAllocation: flagEvaluation?.matchedAllocation,
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations,
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations
            )
        )
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
                flagEvaluationCode: flagEvaluation?.flagEvaluationCode ?? .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: flagEvaluation?.flagEvaluationDescription ?? "No assignment found",
                variationKey: flagEvaluation?.variation?.key,
                variationValue: flagEvaluation?.variation?.value,
                banditKey: nil,
                banditAction: nil,
                configFetchedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configFetchedAt ?? "",
                configPublishedAt: configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? "",
                matchedRule: flagEvaluation?.matchedRule,
                matchedAllocation: flagEvaluation?.matchedAllocation.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) },
                unmatchedAllocations: flagEvaluation?.unmatchedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? [],
                unevaluatedAllocations: flagEvaluation?.unevaluatedAllocations.map { AllocationEvaluation(key: $0.key, allocationEvaluationCode: $0.allocationEvaluationCode, orderPosition: $0.orderPosition) } ?? []
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
