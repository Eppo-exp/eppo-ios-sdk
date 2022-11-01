typealias RefreshCompleteCallback = () -> ();
typealias RefreshFailedCallback = () -> ();
typealias AssignmentLogger = () -> ();

enum EppoClientError: Error {
    case apiKeyInvalid
    case hostInvalid
    case subjectKeyRequired
    case flagKeyRequired
}

struct RefreshCallback {
    var onComplete: RefreshCompleteCallback;
    var onFailure: RefreshFailedCallback;

    public init(
        _ onComplete: @escaping RefreshCompleteCallback,
        _ onFailure: @escaping RefreshFailedCallback
    ) {
        self.onComplete = onComplete;
        self.onFailure = onFailure;
    }
}

class EppoClient {
    public private(set) var apiKey: String = "";
    public private(set) var host: String = "";
    public private(set) var assignmentLogger: AssignmentLogger?;
    
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

        self.refreshConfiguration(refreshCallback);
    }

    public func refreshConfiguration(_ refreshCallback: RefreshCallback?) {

    }

    public func getAssignment(_ subjectKey: String, _ flagKey: String) throws -> String {
        return try getAssignment(subjectKey, flagKey, [:]);
    }

    public func getAssignment(
        _ subjectKey: String,
        _ flagKey: String,
        _ subjectAttributes: SubjectAttributes) throws -> String
    {
        try self.validate();

        if subjectKey.count == 0 { throw EppoClientError.subjectKeyRequired }
        if flagKey.count == 0 { throw EppoClientError.flagKeyRequired }

        return ""
    }

    public func validate() throws {
        if(self.apiKey.count == 0) {
            throw EppoClientError.apiKeyInvalid;
        }

        if(self.host.count == 0) {
            throw EppoClientError.hostInvalid;
        }
    }
}
