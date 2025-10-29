import Foundation
import FlatBuffers

public class FlatBufferClient {
    private let evaluator: FlatBufferRuleEvaluator
    private let obfuscated: Bool
    private let sdkKey: String
    private let assignmentLogger: EppoClient.AssignmentLogger?

    public init(sdkKey: String, flatBufferData: Data, obfuscated: Bool = false, assignmentLogger: EppoClient.AssignmentLogger? = nil) throws {
        self.sdkKey = sdkKey
        self.obfuscated = obfuscated
        self.assignmentLogger = assignmentLogger
        self.evaluator = try FlatBufferRuleEvaluator(flatBufferData: flatBufferData)
    }

    public func getStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String
    ) -> String {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: obfuscated
        )

        if let variation = evaluation.variation {
            let result = (try? variation.value.getStringValue()) ?? defaultValue
            logAssignment(evaluation: evaluation, result: result)
            return result
        }
        logAssignment(evaluation: evaluation, result: defaultValue)
        return defaultValue
    }

    public func getNumericAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Double
    ) -> Double {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: obfuscated
        )

        if let variation = evaluation.variation {
            let result = (try? variation.value.getDoubleValue()) ?? defaultValue
            logAssignment(evaluation: evaluation, result: result)
            return result
        }
        logAssignment(evaluation: evaluation, result: defaultValue)
        return defaultValue
    }

    public func getIntegerAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Int
    ) -> Int {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: obfuscated
        )

        if let variation = evaluation.variation {
            // Convert from double to int since EppoValue stores integers as doubles
            if let doubleValue = try? variation.value.getDoubleValue() {
                let result = Int(doubleValue)
                logAssignment(evaluation: evaluation, result: result)
                return result
            }
            logAssignment(evaluation: evaluation, result: defaultValue)
            return defaultValue
        }
        logAssignment(evaluation: evaluation, result: defaultValue)
        return defaultValue
    }

    public func getBooleanAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: Bool
    ) -> Bool {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: obfuscated
        )

        if let variation = evaluation.variation {
            let result = (try? variation.value.getBoolValue()) ?? defaultValue
            logAssignment(evaluation: evaluation, result: result)
            return result
        }
        logAssignment(evaluation: evaluation, result: defaultValue)
        return defaultValue
    }

    public func getJSONStringAssignment(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        defaultValue: String
    ) -> String {
        let evaluation = evaluator.evaluateFlag(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: obfuscated
        )

        if let variation = evaluation.variation {
            return (try? variation.value.getStringValue()) ?? defaultValue
        }
        return defaultValue
    }

    // For benchmark use
    internal func getAllFlagKeys() -> [String] {
        return evaluator.getAllFlagKeys()
    }

    internal func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return evaluator.getFlagVariationType(flagKey: flagKey)
    }

    private func logAssignment<T>(evaluation: FlagEvaluation, result: T) {
        guard let assignmentLogger = assignmentLogger else { return }

        // Create timestamp string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        // Create assignment similar to EppoClient
        let assignment = Assignment(
            flagKey: evaluation.flagKey,
            allocationKey: evaluation.allocationKey ?? "",
            variation: evaluation.variation?.key ?? "",
            subject: evaluation.subjectKey,
            timestamp: timestamp,
            subjectAttributes: evaluation.subjectAttributes,
            metaData: [
                "sdkName": "eppo-ios-sdk",
                "sdkVersion": "1.0.0", // Simplified for benchmark
                "flagEvaluationCode": evaluation.flagEvaluationCode.rawValue,
                "flagEvaluationDescription": evaluation.flagEvaluationDescription,
                "flatBuffer": "true" // Indicate this came from FlatBuffer evaluation
            ],
            extraLogging: evaluation.extraLogging
        )

        assignmentLogger(assignment)
    }
}