typealias RefreshCallback = (Result<Void, Error>) -> ();
typealias AssignmentLogger = () -> ();

enum EppoClientError: Error {
    case apiKeyInvalid
    case hostInvalid
    case subjectKeyRequired
    case flagKeyRequired
    case featureFlagDisabled
}

class EppoClient {
    public private(set) var apiKey: String = "";
    public private(set) var host: String = "";
    public private(set) var assignmentLogger: AssignmentLogger?;
    public private(set) var httpClient: EppoHttpClient;
    
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

        if subjectKey.count == 0 { throw EppoClientError.subjectKeyRequired }
        if flagKey.count == 0 { throw EppoClientError.flagKeyRequired }

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

        return nil;
    }

    public func validate() throws {
        if(self.apiKey.count == 0) {
            throw EppoClientError.apiKeyInvalid;
        }

        if(self.host.count == 0) {
            throw EppoClientError.hostInvalid;
        }
    }

    private func getSubjectVariationOverrides(_ subjectKey: String, _ flagConfig: FlagConfig) -> String? {
        let subjectHash = Utils.getMD5Hex(input: subjectKey);
        if let occurence = flagConfig.overrides[subjectHash] {
            return occurence;
        }

        return nil;
    }
}
