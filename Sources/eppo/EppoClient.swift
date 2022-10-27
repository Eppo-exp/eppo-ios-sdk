typealias InitializationCallback = () -> ();
typealias AssignmentLogger = () -> ();

class EppoClient {
    public private(set) var apiKey: String = "";
    public private(set) var host: String = "";
    public var initializationCallback: InitializationCallback;
    public var assignmentLogger: AssignmentLogger;
    
    public init(
        _ apiKey: String,
        _ host: String,
        _ initializationCallback: @escaping InitializationCallback,
        _ assignmentLogger: @escaping AssignmentLogger
    ) {
        self.apiKey = apiKey;
        self.host = host;
        self.initializationCallback = initializationCallback;
        self.assignmentLogger = assignmentLogger;
    }
}
