import Foundation

/// Event data for bandit action logging.
/// This structure matches the IBanditEvent interface in the JS SDK.
public struct BanditEvent {
    /// ISO 8601 timestamp of when the event occurred
    public let timestamp: String

    /// The feature flag key associated with this bandit
    public let flagKey: String

    /// The bandit key
    public let banditKey: String

    /// The subject key (user identifier)
    public let subjectKey: String

    /// The selected action, or nil if no action was selected
    public let action: String?

    /// The probability of selecting this action
    public let actionProbability: Double

    /// The optimality gap for this action
    public let optimalityGap: Double

    /// The model version used for this assignment
    public let modelVersion: String

    /// Numeric attributes of the subject
    public let subjectNumericAttributes: [String: Double]

    /// Categorical attributes of the subject
    public let subjectCategoricalAttributes: [String: String]

    /// Numeric attributes of the selected action
    public let actionNumericAttributes: [String: Double]

    /// Categorical attributes of the selected action
    public let actionCategoricalAttributes: [String: String]

    /// Additional metadata about the assignment
    public let metaData: [String: String]

    public init(
        timestamp: String,
        flagKey: String,
        banditKey: String,
        subjectKey: String,
        action: String?,
        actionProbability: Double,
        optimalityGap: Double,
        modelVersion: String,
        subjectNumericAttributes: [String: Double],
        subjectCategoricalAttributes: [String: String],
        actionNumericAttributes: [String: Double],
        actionCategoricalAttributes: [String: String],
        metaData: [String: String]
    ) {
        self.timestamp = timestamp
        self.flagKey = flagKey
        self.banditKey = banditKey
        self.subjectKey = subjectKey
        self.action = action
        self.actionProbability = actionProbability
        self.optimalityGap = optimalityGap
        self.modelVersion = modelVersion
        self.subjectNumericAttributes = subjectNumericAttributes
        self.subjectCategoricalAttributes = subjectCategoricalAttributes
        self.actionNumericAttributes = actionNumericAttributes
        self.actionCategoricalAttributes = actionCategoricalAttributes
        self.metaData = metaData
    }
}

/// Type alias for the bandit logger callback
public typealias BanditLogger = (BanditEvent) -> Void
