import Foundation

/**
 * JSON Offset Index Client - Revolutionary ultra-fast startup JSON evaluation
 *
 * This client implements the breakthrough offset indexing approach:
 * - Startup: Manual JSON buffer scanning to build byte offset index (NO JSONSerialization!)
 * - Runtime: Extract individual flags on-demand and cache as Swift structs
 * - Benefits: Lightning startup + Swift struct evaluation performance + memory efficiency
 */
public class JsonOffsetIndexClient {
    public typealias AssignmentLogger = (Assignment) -> Void

    private let evaluator: JsonOffsetIndexEvaluator
    private let assignmentLogger: AssignmentLogger?
    private let isObfuscated: Bool
    private let sdkKey: String

    public init(
        sdkKey: String,
        jsonData: Data,
        obfuscated: Bool,
        assignmentLogger: AssignmentLogger?
    ) throws {
        self.sdkKey = sdkKey
        self.evaluator = try JsonOffsetIndexEvaluator(jsonData: jsonData, obfuscated: obfuscated)
        self.assignmentLogger = assignmentLogger
        self.isObfuscated = obfuscated

        NSLog("🚀 JsonOffsetIndexClient initialized with revolutionary offset indexing for SDK key: %@", sdkKey)
    }

    // MARK: - Assignment Methods

    public func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = [:],
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

    public func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = [:],
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

    public func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = [:],
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

    public func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = [:],
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

    public func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes = [:],
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
}