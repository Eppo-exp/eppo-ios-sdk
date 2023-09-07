import Foundation;

public let version = "1.0.0"

public struct FlagConfigJSON : Decodable {
    var flags: [String : FlagConfig];
}

public class EppoClient {
    public private(set) var apiKey: String = "";
    public private(set) var host: String = "";
    public private(set) var flagConfigs: FlagConfigJSON = FlagConfigJSON(flags: [:]);
    
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
        _ apiKey: String,
        host: String = "https://fscdn.eppo.cloud"
    ) {
        self.apiKey = apiKey;
        self.host = host;
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
        _ experimentKey: String,
        _ subjectShards: Int,
        _ percentageExposure: Float
    ) -> Bool
    {
        let shard = Utils.getShard("exposure-" + subjectKey + "-" + experimentKey, subjectShards);
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
        _ experimentKey: String,
        _ subjectShards: Int,
        _ variations: [Variation]
    ) -> Variation?
    {
        let shard = Utils.getShard("assignment-" + subjectKey + "-" + experimentKey, subjectShards);

        for variation in variations {
            if Utils.isShardInRange(shard, variation.shardRange) {
                return variation;
            }
        }

        return nil;
    }
}
