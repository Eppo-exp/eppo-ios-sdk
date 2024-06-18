import Foundation;

// todo: make this a build argument (FF-1944)
let sdkVersion = "2.0.0"
let sdkName = "ios"

// todo: these exported errors could use some work. only ones here that are
// user actionable should be public; all others are for internal communication.
public enum Errors: Error {
    case notConfigured
    case apiKeyInvalid
    case hostInvalid
    case subjectKeyRequired
    case flagKeyRequired
    case featureFlagDisabled
    case allocationKeyNotDefined
    case invalidURL
    case configurationNotLoaded
    case flagConfigNotFound
}

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

public class EppoClient : Equatable {
    public typealias AssignmentLogger = (Assignment) -> Void
    
    private static var sharedInstance: EppoClient?
    
    private(set) var apiKey: String
    private(set) var host: String
    private(set) var assignmentLogger: AssignmentLogger?
    private(set) var assignmentCache: AssignmentCache?
    private(set) var configurationStore: ConfigurationStore
    
    private let state = EppoClientState()
    
    private init(
        apiKey: String,
        host: String,
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache()
    ) {
        self.apiKey = apiKey
        self.host = host
        self.assignmentLogger = assignmentLogger
        self.assignmentCache = assignmentCache
        
        let httpClient = NetworkEppoHttpClient(baseURL: host, apiKey: apiKey, sdkName: "sdkName", sdkVersion: "sdkVersion")
        let configurationRequester = ConfigurationRequester(httpClient: httpClient)
        self.configurationStore = ConfigurationStore(requester: configurationRequester)
    }
    
    public static func initialize(
        apiKey: String,
        host: String = "https://fscdn.eppo.cloud",
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache()
    ) async throws -> EppoClient {
        let tentativeNewInstance = EppoClient(
            apiKey: apiKey,
            host: host,
            assignmentLogger: assignmentLogger, 
            assignmentCache: assignmentCache
        )

        if let instance = sharedInstance, instance != tentativeNewInstance {
            // If the shared instance is not the same as the new client, update it.
            // Conditions for equality are defined in the `==` operator.
            sharedInstance = tentativeNewInstance
            try await sharedInstance!.loadIfNeeded()
        } else if sharedInstance == nil {
            // If the shared instance is nil, set it to the new client.
            sharedInstance = tentativeNewInstance
            try await sharedInstance!.loadIfNeeded()
        }
    
        return try shared()
    }
    
    public static func shared() throws -> EppoClient {
        guard let instance = sharedInstance else {
            throw Errors.notConfigured
        }
        return instance
    }
    
    public static func resetSharedInstance() {
        sharedInstance = nil
    }
    
    private func loadIfNeeded() async throws {
        let alreadyLoaded = await state.checkAndSetLoaded()
        guard !alreadyLoaded else { return }
        
        try await self.configurationStore.fetchAndStoreConfigurations()
    }
    
    public func getAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes) throws -> String?
    {
        return try getInternalAssignment(subjectKey, flagKey, subjectAttributes, false)?.stringValue()
    }
    
    public func getBoolAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes = SubjectAttributes()) throws -> Bool?
    {
        return try getInternalAssignment(subjectKey, flagKey, subjectAttributes, true)?.boolValue()
    }
    
    public func getJSONStringAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes = SubjectAttributes()) throws -> String?
    {
        return try getInternalAssignment(subjectKey, flagKey, subjectAttributes, false)?.stringValue()
    }
    
    public func getNumericAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes = SubjectAttributes()) throws -> Double?
    {
        return try getInternalAssignment(subjectKey, flagKey, subjectAttributes, true)?.doubleValue()
    }
    
    public func getStringAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes = SubjectAttributes()) throws -> String?
    {
        return try getInternalAssignment(subjectKey, flagKey, subjectAttributes, true)?.stringValue()
    }
    
    private func getInternalAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes,
        _ useTypedVariationValue: Bool) throws -> EppoValue?
    {
        try self.validate();
        
        if subjectKey.count == 0 { throw Errors.subjectKeyRequired }
        if flagKey.count == 0 { throw Errors.flagKeyRequired }
        if !self.configurationStore.isInitialized() { throw Errors.configurationNotLoaded }
        
        guard let flagConfig = self.configurationStore.getConfiguration(flagKey: flagKey) else {
            throw Errors.flagConfigNotFound;
        }
        
        if let subjectVariationOverride = self.getSubjectVariationOverrides(subjectKey, flagConfig) {
            return subjectVariationOverride;
        }
        
        if !flagConfig.enabled {
            //TODO: Log something here?
            return nil;
        }
        
        guard let rule = try RuleEvaluator.findMatchingRule(subjectAttributes, flagConfig.rules) else {
            //TODO: Log that no assigned variation exists?
            return nil;
        }
        
        guard let allocation = flagConfig.allocations[rule.allocationKey] else {
            throw Errors.allocationKeyNotDefined;
        }
        if !isInExperimentSample(
            subjectKey,
            flagKey,
            flagConfig.subjectShards,
            allocation.percentExposure
        )
        {
            //TODO: Log that no variation is assigned?
            return nil;
        }
        
        guard let assignedVariation = getAssignedVariation(
            subjectKey, flagKey, flagConfig.subjectShards, allocation.variations
        ) else {
            return nil;
        }
        
        // Optionally log assignment
        if let assignmentLogger = self.assignmentLogger {
            let assignment = Assignment(
                flagKey: flagKey,
                allocationKey: rule.allocationKey,
                variation: assignedVariation.value,
                subject: subjectKey,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                subjectAttributes: subjectAttributes
            )
            
            // Prepare the assignment cache key
            let assignmentCacheKey = AssignmentCacheKey(
                subjectKey: subjectKey,
                flagKey: flagKey,
                allocationKey: rule.allocationKey,
                variationValue: assignedVariation.typedValue
            )
            
            // Check if the assignment has already been logged, if the cache is defined
            if let cache = self.assignmentCache, cache.hasLoggedAssignment(key: assignmentCacheKey) {
                // The assignment has already been logged, do nothing
            } else {
                // Either the cache is not defined, or the assignment hasn't been logged yet
                assignmentLogger(assignment)
                self.assignmentCache?.setLastLoggedAssignment(key: assignmentCacheKey)
            }
        }
        
        if (useTypedVariationValue) {
            return assignedVariation.typedValue;
        } else {
            // Access the stringified JSON from `value` field until support for native JSON is available.
            // The legacy getAssignment method accesses the existing field to consistency return a stringified value.
            return EppoValue(value: assignedVariation.value, type: EppoValueType.String);
        }
    }
    
    public func validate() throws {
        if(self.apiKey.count == 0) {
            throw Errors.apiKeyInvalid;
        }
        
        if(self.host.count == 0) {
            throw Errors.hostInvalid;
        }
    }
    
    private func isInExperimentSample(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectShards: Int,
        _ percentageExposure: Float
    ) -> Bool
    {
        let shard = Utils.getShard("exposure-" + subjectKey + "-" + flagKey, subjectShards);
        return shard <= Int(percentageExposure * Float(subjectShards));
    }
    
    private func getSubjectVariationOverrides(_ subjectKey: String, _ flagConfig: FlagConfig) -> EppoValue? {
        let subjectHash = Utils.getMD5Hex(input: subjectKey);
        if let occurence = flagConfig.typedOverrides[subjectHash] {
            return occurence;
        }
        
        return nil;
    }
    
    private func getAssignedVariation(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectShards: Int,
        _ variations: [Variation]
    ) -> Variation?
    {
        let shard = Utils.getShard("assignment-" + subjectKey + "-" + flagKey, subjectShards);
        
        for variation in variations {
            if Utils.isShardInRange(shard, variation.shardRange) {
                return variation;
            }
        }
        
        return nil;
    }

    static public func ==(lhs: EppoClient, rhs: EppoClient) -> Bool {
        return lhs.apiKey == rhs.apiKey && lhs.host == rhs.host
    }
}
