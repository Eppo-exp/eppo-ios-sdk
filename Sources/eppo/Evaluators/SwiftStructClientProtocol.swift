import Foundation

/// Protocol for Swift struct-based clients that wrap evaluators
public protocol SwiftStructClientProtocol {
    typealias AssignmentLogger = (Assignment) -> Void

    /// The underlying flag evaluator that handles flag evaluation logic
    var evaluator: FlagEvaluatorProtocol { get }

    /// Optional assignment logger for tracking flag assignments
    var assignmentLogger: AssignmentLogger? { get }

    /// Whether the configuration is obfuscated
    var isObfuscated: Bool { get }

    /// The SDK key for this client
    var sdkKey: String { get }

    // MARK: - Assignment Methods

    /// Gets a boolean assignment for the given flag and subject
    func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Bool
    ) -> Bool

    /// Gets a string assignment for the given flag and subject
    func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String
    ) -> String

    /// Gets a numeric (double) assignment for the given flag and subject
    func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Double
    ) -> Double

    /// Gets an integer assignment for the given flag and subject
    func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Int
    ) -> Int

    /// Gets a JSON string assignment for the given flag and subject
    func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String
    ) -> String

    // MARK: - Utility Methods

    /// Gets all available flag keys (useful for benchmarking)
    func getAllFlagKeys() -> [String]

    /// Gets the variation type for a specific flag
    func getFlagVariationType(flagKey: String) -> UFC_VariationType?
}

// MARK: - Default Implementation

/// Default implementations that handle assignment logging
public extension SwiftStructClientProtocol {

    func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Bool
    ) -> Bool {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isObfuscated,
            expectedVariationType: .boolean
        )

        // Log the assignment if logger is available
        if let logger = assignmentLogger, evaluation.doLog {
            let assignment = Assignment(
                flagKey: flagKey,
                allocationKey: evaluation.allocationKey ?? "",
                variation: evaluation.variation?.key ?? "",
                subject: subjectKey,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                subjectAttributes: subjectAttributes,
                extraLogging: evaluation.extraLogging
            )
            logger(assignment)
        }

        // Return the boolean value or default
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
        defaultValue: String
    ) -> String {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isObfuscated,
            expectedVariationType: .string
        )

        // Log the assignment if logger is available
        if let logger = assignmentLogger, evaluation.doLog {
            let assignment = Assignment(
                flagKey: flagKey,
                allocationKey: evaluation.allocationKey ?? "",
                variation: evaluation.variation?.key ?? "",
                subject: subjectKey,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                subjectAttributes: subjectAttributes,
                extraLogging: evaluation.extraLogging
            )
            logger(assignment)
        }

        // Return the string value or default
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
        defaultValue: Double
    ) -> Double {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isObfuscated,
            expectedVariationType: .numeric
        )

        // Log the assignment if logger is available
        if let logger = assignmentLogger, evaluation.doLog {
            let assignment = Assignment(
                flagKey: flagKey,
                allocationKey: evaluation.allocationKey ?? "",
                variation: evaluation.variation?.key ?? "",
                subject: subjectKey,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                subjectAttributes: subjectAttributes,
                extraLogging: evaluation.extraLogging
            )
            logger(assignment)
        }

        // Return the double value or default
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
        defaultValue: Int
    ) -> Int {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isObfuscated,
            expectedVariationType: .integer
        )

        // Log the assignment if logger is available
        if let logger = assignmentLogger, evaluation.doLog {
            let assignment = Assignment(
                flagKey: flagKey,
                allocationKey: evaluation.allocationKey ?? "",
                variation: evaluation.variation?.key ?? "",
                subject: subjectKey,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                subjectAttributes: subjectAttributes,
                extraLogging: evaluation.extraLogging
            )
            logger(assignment)
        }

        // Return the integer value or default
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
        defaultValue: String
    ) -> String {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isObfuscated,
            expectedVariationType: .json
        )

        // Log the assignment if logger is available
        if let logger = assignmentLogger, evaluation.doLog {
            let assignment = Assignment(
                flagKey: flagKey,
                allocationKey: evaluation.allocationKey ?? "",
                variation: evaluation.variation?.key ?? "",
                subject: subjectKey,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                subjectAttributes: subjectAttributes,
                extraLogging: evaluation.extraLogging
            )
            logger(assignment)
        }

        // Return the JSON string value or default
        if let variation = evaluation.variation {
            do {
                return try variation.value.getStringValue()
            } catch {
                return defaultValue
            }
        }
        return defaultValue
    }

    func getAllFlagKeys() -> [String] {
        return evaluator.getAllFlagKeys()
    }

    func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return evaluator.getFlagVariationType(flagKey: flagKey)
    }
}