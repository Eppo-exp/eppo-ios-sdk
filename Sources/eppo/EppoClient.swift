import Foundation;

// todo: make this a build argument (FF-1944)
public let sdkName = "ios"
public let sdkVersion = "3.0.0"

public enum Errors: Error {
    case notConfigured
    case apiKeyInvalid
    case hostInvalid
    case subjectKeyRequired
    case flagKeyRequired
    case variationTypeMismatch
    case variationWrongType
    case invalidURL
    case configurationNotLoaded
    case flagConfigNotFound
}

public typealias SubjectAttributes = [String: EppoValue];
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
    private var flagEvaluator: FlagEvaluator = FlagEvaluator(sharder: MD5Sharder())
    private(set) var isConfigObfuscated = true;
    
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
    
    public func setConfigObfuscation(obfuscated: Bool) {
        self.isConfigObfuscated = obfuscated
    }
    
    public func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = SubjectAttributes(),
        defaultValue: Bool) throws -> Bool
    {
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
        defaultValue: String) throws -> String
    {
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
        defaultValue: Int) throws -> Int
    {
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
        defaultValue: Double) throws -> Double
    {
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
        defaultValue: String) throws -> String
    {
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
    
    private func getInternalAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        expectedVariationType: UFC_VariationType) throws -> FlagEvaluation?
    {
        if (self.apiKey.count == 0) {
            throw Errors.apiKeyInvalid;
        }
        
        if (self.host.count == 0) {
            throw Errors.hostInvalid;
        }
        
        if subjectKey.count == 0 { throw Errors.subjectKeyRequired }
        if flagKey.count == 0 { throw Errors.flagKeyRequired }
        if !self.configurationStore.isInitialized() { throw Errors.configurationNotLoaded }
        
        let flagKeyForLookup = isConfigObfuscated ? getMD5Hex(flagKey) : flagKey
        
        guard let flagConfig = self.configurationStore.getConfiguration(flagKey: flagKeyForLookup) else {
            throw Errors.flagConfigNotFound
        }
        
        if flagConfig.variationType != expectedVariationType {
            throw Errors.variationTypeMismatch
        }
        
        let flagEvaluation = flagEvaluator.evaluateFlag(
            flag: flagConfig,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
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
                            "obfuscated": String(isConfigObfuscated),
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
        
        return flagEvaluation;
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

    static public func ==(lhs: EppoClient, rhs: EppoClient) -> Bool {
        return lhs.apiKey == rhs.apiKey && lhs.host == rhs.host
    }
}
