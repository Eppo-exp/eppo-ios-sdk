typealias RefreshCompleteCallback = () -> ();
typealias RefreshFailedCallback = () -> ();
typealias AssignmentLogger = () -> ();

enum EppoClientError: Error {
    case apiKeyInvalid
    case hostInvalid
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
    ) throws {
        if(self.apiKey.count == 0) {
            throw EppoClientError.apiKeyInvalid;
        }

        if(self.host.count == 0) {
            throw EppoClientError.hostInvalid;
        }

        self.apiKey = apiKey;
        self.host = host;
        self.assignmentLogger = assignmentLogger;

        self.refreshConfiguration(refreshCallback);
    }

    public func refreshConfiguration(_ refreshCallback: RefreshCallback?)
    {

    }
}
