import Foundation

/// Protocol that defines the common interface for all flag evaluators.
/// Evaluators can implement low-level flag evaluation or high-level assignment methods.
public protocol FlagEvaluatorProtocol {
    // MARK: - Core Evaluation Method

    /// Evaluates a flag and returns detailed evaluation information
    func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType?
    ) -> FlagEvaluation

    // MARK: - Assignment Methods

    /// Gets a boolean assignment for the given flag and subject
    func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Bool,
        isConfigObfuscated: Bool
    ) -> Bool

    /// Gets a string assignment for the given flag and subject
    func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String,
        isConfigObfuscated: Bool
    ) -> String

    /// Gets a numeric (double) assignment for the given flag and subject
    func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Double,
        isConfigObfuscated: Bool
    ) -> Double

    /// Gets an integer assignment for the given flag and subject
    func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Int,
        isConfigObfuscated: Bool
    ) -> Int

    /// Gets a JSON string assignment for the given flag and subject
    func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String,
        isConfigObfuscated: Bool
    ) -> String

    // MARK: - Utility Methods

    /// Gets all available flag keys (useful for benchmarking)
    func getAllFlagKeys() -> [String]

    /// Gets the variation type for a specific flag
    func getFlagVariationType(flagKey: String) -> UFC_VariationType?
}

// MARK: - Default Implementation

/// Default implementations of assignment methods using evaluateFlag
public extension FlagEvaluatorProtocol {

    func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Bool,
        isConfigObfuscated: Bool
    ) -> Bool {
        let evaluation = evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated,
            expectedVariationType: .boolean
        )

        if let variation = evaluation.variation {
            do {
                return try variation.value.getBoolValue()
            } catch {
                return defaultValue
            }
        }
        return defaultValue
    }

    func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String,
        isConfigObfuscated: Bool
    ) -> String {
        let evaluation = evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated,
            expectedVariationType: .string
        )

        if let variation = evaluation.variation {
            do {
                return try variation.value.getStringValue()
            } catch {
                return defaultValue
            }
        }
        return defaultValue
    }

    func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Double,
        isConfigObfuscated: Bool
    ) -> Double {
        let evaluation = evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated,
            expectedVariationType: .numeric
        )

        if let variation = evaluation.variation {
            do {
                return try variation.value.getDoubleValue()
            } catch {
                return defaultValue
            }
        }
        return defaultValue
    }

    func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Int,
        isConfigObfuscated: Bool
    ) -> Int {
        let evaluation = evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated,
            expectedVariationType: .integer
        )

        if let variation = evaluation.variation {
            do {
                // Convert from double to int since EppoValue stores integers as doubles
                let doubleValue = try variation.value.getDoubleValue()
                return Int(doubleValue)
            } catch {
                return defaultValue
            }
        }
        return defaultValue
    }

    func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String,
        isConfigObfuscated: Bool
    ) -> String {
        let evaluation = evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated,
            expectedVariationType: .json
        )

        if let variation = evaluation.variation {
            do {
                return try variation.value.getStringValue()
            } catch {
                return defaultValue
            }
        }
        return defaultValue
    }
}