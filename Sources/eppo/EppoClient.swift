import Foundation;

public let version = "3.0.0"

public struct FlagConfigJSON : Decodable {
    var flags: [String : FlagConfig];
}

public class EppoClient {
    public private(set) var apiKey: String = "";
    public private(set) var host: String = "";
    public private(set) var flagConfigs: FlagConfigJSON = FlagConfigJSON(flags: [:]);
    private var assignmentCache: AssignmentCache?;
    
    public typealias AssignmentLogger = (Assignment) -> Void
    public var assignmentLogger: AssignmentLogger?

    enum Errors: Error {
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

    public init(
        apiKey: String,
        host: String = "https://fscdn.eppo.cloud",
        assignmentLogger: AssignmentLogger? = nil,
        assignmentCache: AssignmentCache? = InMemoryAssignmentCache()
    ) {
        self.apiKey = apiKey;
        self.host = host;
        self.assignmentLogger = assignmentLogger;
        self.assignmentCache = assignmentCache
    }

    public func load(httpClient: EppoHttpClient = NetworkEppoHttpClient()) async throws {
        var urlString = self.host + "/api/randomized_assignment/v3/config";
        urlString += "?sdkName=ios";
        urlString += "&sdkVersion=" + version;
        urlString += "&apiKey=" + self.apiKey;

        guard let url = URL(string: urlString) else {
            throw Errors.invalidURL;
        }

        let (urlData, _) = try await httpClient.get(url);
        self.flagConfigs = try JSONDecoder().decode(FlagConfigJSON.self, from: urlData);
    }

    public func getBoolAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Bool) throws -> Bool
    {
        return try getInternalAssignment(
            flagKey: flagKey, 
            subjectKey: subjectKey, 
            subjectAttributes: subjectAttributes, 
            useTypedVariationValue: true
        )?.boolValue() ?? defaultValue
    }
    
    public func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String) throws -> String
    {
        return try getInternalAssignment(
            flagKey: flagKey, 
            subjectKey: subjectKey, 
            subjectAttributes: subjectAttributes, 
            useTypedVariationValue: false
        )?.stringValue() ?? defaultValue
    }
    
    public func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Double) throws -> Double
    {
        return try getInternalAssignment(
            flagKey: flagKey, 
            subjectKey: subjectKey, 
            subjectAttributes: subjectAttributes, 
            useTypedVariationValue: true
        )?.doubleValue() ?? defaultValue
    }
    
    public func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: String) throws -> String
    {
        return try getInternalAssignment(
            flagKey: flagKey, 
            subjectKey: subjectKey, 
            subjectAttributes: subjectAttributes, 
            useTypedVariationValue: true
        )?.stringValue() ?? defaultValue
    }
    
    private func getInternalAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        useTypedVariationValue: Bool) throws -> EppoValue?
    {
        try self.validate();

        if subjectKey.count == 0 { throw Errors.subjectKeyRequired }
        if flagKey.count == 0 { throw Errors.flagKeyRequired }
        if self.flagConfigs.flags.count == 0 { throw Errors.configurationNotLoaded }

        guard let flagConfig = self.flagConfigs.flags[flagKey] else {
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
}
