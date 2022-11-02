import Foundation;

typealias RefreshCallback = (Result<Void, Error>) -> ();
typealias AssignmentLogger = (Assignment) -> ();

class EppoClient {
    public private(set) var apiKey: String = "";
    public private(set) var host: String = "";
    public private(set) var assignmentLogger: AssignmentLogger?;
    public private(set) var httpClient: EppoHttpClient;
    
    enum Errors: Error {
        case apiKeyInvalid
        case hostInvalid
        case subjectKeyRequired
        case flagKeyRequired
        case featureFlagDisabled
        case allocationKeyNotDefined
    }

    public init(
        _ apiKey: String,
        _ host: String,
        _ assignmentLogger: AssignmentLogger?,
        _ refreshCallback: RefreshCallback?,
        httpClient: EppoHttpClient = NetworkEppoHttpClient()
    ) {
        self.apiKey = apiKey;
        self.host = host;
        self.assignmentLogger = assignmentLogger;
        self.httpClient = httpClient;

        self.refreshConfiguration(refreshCallback);
    }

    public func refreshConfiguration(_ refreshCallback: RefreshCallback?) {

    }

    public func getAssignment(_ subjectKey: String, _ flagKey: String) throws -> String? {
        return try getAssignment(subjectKey, flagKey, [:]);
    }

    public func getAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes) throws -> String?
    {
        try self.validate();

        if subjectKey.count == 0 { throw Errors.subjectKeyRequired }
        if flagKey.count == 0 { throw Errors.flagKeyRequired }

        let flagConfig = try requestFlagConfiguration(flagKey, self.httpClient);
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

        if self.assignmentLogger != nil {
            let assignment = Assignment(
                flagKey,
                assignedVariation.value,
                subjectKey,
                Utils.getISODate(Date()),
                subjectAttributes
            );
            self.assignmentLogger!(assignment);
        }

        return assignedVariation.value;
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

    private func getSubjectVariationOverrides(_ subjectKey: String, _ flagConfig: FlagConfig) -> String? {
        let subjectHash = Utils.getMD5Hex(input: subjectKey);
        if let occurence = flagConfig.overrides[subjectHash] {
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
