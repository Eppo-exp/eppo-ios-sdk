import Foundation

/// Protocol that defines the interface for flag evaluators
/// This allows for different evaluator implementations (JSON, Protobuf, etc.)
/// to be used interchangeably in the EppoClient
protocol FlagEvaluatorProtocol {
    /// Evaluates a flag for a given subject and returns the evaluation result
    ///
    /// - Parameters:
    ///   - configuration: The configuration containing the flag data
    ///   - flagKey: The key of the flag to evaluate (before any obfuscation)
    ///   - subjectKey: The subject identifier
    ///   - subjectAttributes: Additional attributes for the subject
    ///   - isConfigObfuscated: Whether the configuration is obfuscated
    /// - Returns: FlagEvaluation containing the result of the evaluation
    func evaluateFlag(
        configuration: Configuration,
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation
}