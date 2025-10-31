import Foundation

/**
 * Aaron Claude Evaluator - Optimized JSON parsing for EppoValue performance
 *
 * Key optimizations:
 * 1. Avoid expensive try-catch chains in EppoValue type inference
 * 2. Pre-analyze JSON structure for faster parsing paths
 * 3. Use Swift Foundation optimally for JSON deserialization
 * 4. Direct value extraction without multiple type attempts
 */
public class AaronClaudeEvaluator: FlagEvaluatorProtocol {
    private let flagsConfiguration: [String: OptimizedFlag]
    private let flagEvaluator: FlagEvaluator
    private let isConfigObfuscated: Bool

    // Optimized flag structure that pre-processes EppoValues
    private struct OptimizedFlag {
        let key: String
        let enabled: Bool
        let totalShards: Int
        let variationType: UFC_VariationType
        let variations: [String: OptimizedVariation]
        let allocations: [OptimizedAllocation]
        let entityId: Int?
    }

    private struct OptimizedVariation {
        let key: String
        let value: EppoValue
        let precomputedType: EppoValueType  // Pre-determined to avoid runtime inference
    }

    private struct OptimizedAllocation {
        let key: String
        let startAt: UInt64?
        let endAt: UInt64?
        let doLog: Bool
        let rules: [OptimizedRule]
        let splits: [OptimizedSplit]
    }

    private struct OptimizedRule {
        let conditions: [OptimizedCondition]
    }

    private struct OptimizedCondition {
        let attribute: String
        let `operator`: UFC_RuleConditionOperator  // Using backticks because 'operator' is a Swift keyword
        let value: EppoValue
        let precomputedOperandType: EppoValueType  // Pre-analyzed for faster comparison
    }

    private struct OptimizedSplit {
        let variationKey: String
        let shards: [OptimizedShard]
    }

    private struct OptimizedShard {
        let salt: String
        let ranges: [OptimizedRange]
    }

    private struct OptimizedRange {
        let start: Int
        let end: Int
    }

    public init(jsonData: Data, obfuscated: Bool) throws {
        self.isConfigObfuscated = obfuscated
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())

        NSLog("🧠 Aaron Claude: Starting optimized JSON parsing...")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Parse JSON with optimizations
        self.flagsConfiguration = try Self.parseOptimizedJSON(data: jsonData)

        let parseTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        NSLog("🧠 Aaron Claude: Parsed %d flags in %.2fms with EppoValue optimizations",
              flagsConfiguration.count, parseTime)
    }

    private static func parseOptimizedJSON(data: Data) throws -> [String: OptimizedFlag] {
        // First, parse the raw JSON to understand structure
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flagsDict = jsonObject["flags"] as? [String: Any] else {
            throw AaronClaudeError.invalidJSONStructure
        }

        var optimizedFlags: [String: OptimizedFlag] = [:]

        for (flagKey, flagData) in flagsDict {
            guard let flagDict = flagData as? [String: Any] else { continue }

            // Extract basic flag properties
            let enabled = flagDict["enabled"] as? Bool ?? false
            let totalShards = flagDict["totalShards"] as? Int ?? 10000
            let entityId = flagDict["entityId"] as? Int

            // Parse variation type with optimization
            let variationTypeString = flagDict["variationType"] as? String ?? "STRING"
            let variationType = parseVariationType(variationTypeString)

            // Parse variations with pre-analyzed EppoValues
            let variations = try parseOptimizedVariations(
                flagDict["variations"] as? [String: Any] ?? [:],
                expectedType: variationType
            )

            // Parse allocations with optimized structures
            let allocations = try parseOptimizedAllocations(
                flagDict["allocations"] as? [[String: Any]] ?? []
            )

            let optimizedFlag = OptimizedFlag(
                key: flagKey,
                enabled: enabled,
                totalShards: totalShards,
                variationType: variationType,
                variations: variations,
                allocations: allocations,
                entityId: entityId
            )

            optimizedFlags[flagKey] = optimizedFlag
        }

        return optimizedFlags
    }

    private static func parseOptimizedVariations(
        _ variationsDict: [String: Any],
        expectedType: UFC_VariationType
    ) throws -> [String: OptimizedVariation] {
        var variations: [String: OptimizedVariation] = [:]

        for (key, valueData) in variationsDict {
            guard let variationDict = valueData as? [String: Any],
                  let valueString = variationDict["value"] as? String else {
                continue
            }

            // OPTIMIZATION: Create EppoValue directly based on expected type
            // This avoids the expensive try-catch chains in EppoValue.init(from decoder)
            let (eppoValue, detectedType) = createOptimizedEppoValue(
                valueString: valueString,
                expectedType: expectedType
            )

            variations[key] = OptimizedVariation(
                key: key,
                value: eppoValue,
                precomputedType: detectedType
            )
        }

        return variations
    }

    private static func parseOptimizedAllocations(_ allocationsArray: [[String: Any]]) throws -> [OptimizedAllocation] {
        return try allocationsArray.map { allocationDict in
            let key = allocationDict["key"] as? String ?? ""
            let startAt = allocationDict["startAt"] as? UInt64
            let endAt = allocationDict["endAt"] as? UInt64
            let doLog = allocationDict["doLog"] as? Bool ?? true

            // Parse rules with optimization
            let rulesArray = allocationDict["rules"] as? [[String: Any]] ?? []
            let rules = try parseOptimizedRules(rulesArray)

            // Parse splits with optimization
            let splitsArray = allocationDict["splits"] as? [[String: Any]] ?? []
            let splits = try parseOptimizedSplits(splitsArray)

            return OptimizedAllocation(
                key: key,
                startAt: startAt,
                endAt: endAt,
                doLog: doLog,
                rules: rules,
                splits: splits
            )
        }
    }

    private static func parseOptimizedRules(_ rulesArray: [[String: Any]]) throws -> [OptimizedRule] {
        return try rulesArray.map { ruleDict in
            let conditionsArray = ruleDict["conditions"] as? [[String: Any]] ?? []
            let conditions = try parseOptimizedConditions(conditionsArray)

            return OptimizedRule(conditions: conditions)
        }
    }

    private static func parseOptimizedConditions(_ conditionsArray: [[String: Any]]) throws -> [OptimizedCondition] {
        return conditionsArray.map { conditionDict in
            let attribute = conditionDict["attribute"] as? String ?? ""
            let operatorString = conditionDict["operator"] as? String ?? ""
            let valueString = conditionDict["value"] as? String ?? ""

            let operatorEnum = parseRuleOperator(operatorString)

            // OPTIMIZATION: Pre-analyze the condition value type based on operator
            let (eppoValue, valueType) = createOptimizedConditionValue(
                valueString: valueString,
                operator: operatorEnum
            )

            return OptimizedCondition(
                attribute: attribute,
                operator: operatorEnum,
                value: eppoValue,
                precomputedOperandType: valueType
            )
        }
    }

    private static func parseOptimizedSplits(_ splitsArray: [[String: Any]]) throws -> [OptimizedSplit] {
        return splitsArray.map { splitDict in
            let variationKey = splitDict["variationKey"] as? String ?? ""
            let shardsArray = splitDict["shards"] as? [[String: Any]] ?? []

            let shards = shardsArray.map { shardDict -> OptimizedShard in
                let salt = shardDict["salt"] as? String ?? ""
                let rangesArray = shardDict["ranges"] as? [[String: Any]] ?? []

                let ranges = rangesArray.map { rangeDict -> OptimizedRange in
                    let start = rangeDict["start"] as? Int ?? 0
                    let end = rangeDict["end"] as? Int ?? 0
                    return OptimizedRange(start: start, end: end)
                }

                return OptimizedShard(salt: salt, ranges: ranges)
            }

            return OptimizedSplit(variationKey: variationKey, shards: shards)
        }
    }

    // OPTIMIZATION: Direct EppoValue creation without expensive try-catch inference
    private static func createOptimizedEppoValue(
        valueString: String,
        expectedType: UFC_VariationType
    ) -> (EppoValue, EppoValueType) {

        switch expectedType {
        case .boolean:
            let boolValue = valueString.lowercased() == "true"
            return (EppoValue(value: boolValue), .Boolean)

        case .integer:
            if let intValue = Int(valueString) {
                return (EppoValue(value: intValue), .Numeric)
            }
            // Fallback to string if parsing fails
            return (EppoValue(value: valueString), .String)

        case .numeric:
            if let doubleValue = Double(valueString) {
                return (EppoValue(value: doubleValue), .Numeric)
            }
            // Fallback to string if parsing fails
            return (EppoValue(value: valueString), .String)

        case .string:
            return (EppoValue(value: valueString), .String)

        case .json:
            return (EppoValue(value: valueString), .String)
        }
    }

    // OPTIMIZATION: Pre-analyze condition values based on operators
    private static func createOptimizedConditionValue(
        valueString: String,
        operator: UFC_RuleConditionOperator
    ) -> (EppoValue, EppoValueType) {

        switch `operator` {
        case .oneOf, .notOneOf:
            // These expect JSON arrays
            if let data = valueString.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return (EppoValue(array: array), .ArrayOfStrings)
            }
            return (EppoValue(value: valueString), .String)

        case .greaterThan, .greaterThanEqual, .lessThan, .lessThanEqual:
            // These expect numeric values
            if let doubleValue = Double(valueString) {
                return (EppoValue(value: doubleValue), .Numeric)
            }
            return (EppoValue(value: valueString), .String)

        case .isNull:
            // Boolean expectation
            let boolValue = valueString.lowercased() == "true"
            return (EppoValue(value: boolValue), .Boolean)

        case .matches, .notMatches:
            // String patterns
            return (EppoValue(value: valueString), .String)
        }
    }

    // Helper parsing methods
    private static func parseVariationType(_ typeString: String) -> UFC_VariationType {
        switch typeString.uppercased() {
        case "BOOLEAN": return .boolean
        case "INTEGER": return .integer
        case "NUMERIC": return .numeric
        case "JSON": return .json
        default: return .string
        }
    }

    private static func parseRuleOperator(_ operatorString: String) -> UFC_RuleConditionOperator {
        switch operatorString {
        case "GT": return .greaterThan
        case "GTE": return .greaterThanEqual
        case "LT": return .lessThan
        case "LTE": return .lessThanEqual
        case "ONE_OF": return .oneOf
        case "NOT_ONE_OF": return .notOneOf
        case "MATCHES": return .matches
        case "NOT_MATCHES": return .notMatches
        case "IS_NULL": return .isNull
        default: return .oneOf
        }
    }

    // MARK: - FlagEvaluatorProtocol Implementation

    public func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType? = nil
    ) -> FlagEvaluation {

        guard let optimizedFlag = flagsConfiguration[flagKey] else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found"
            )
        }

        // Convert optimized flag back to UFC_Flag for existing evaluation logic
        let ufcFlag = convertToUFCFlag(optimizedFlag)

        return flagEvaluator.evaluateFlag(
            flag: ufcFlag,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )
    }

    public func getAllFlagKeys() -> [String] {
        return Array(flagsConfiguration.keys)
    }

    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return flagsConfiguration[flagKey]?.variationType
    }

    // Convert optimized structures back to UFC structures for evaluation
    private func convertToUFCFlag(_ optimizedFlag: OptimizedFlag) -> UFC_Flag {
        let variations = Dictionary(uniqueKeysWithValues: optimizedFlag.variations.map { (key, optVar) in
            (key, UFC_Variation(key: optVar.key, value: optVar.value))
        })

        let allocations = optimizedFlag.allocations.map { optAllocation in
            let rules = optAllocation.rules.map { optRule in
                let conditions = optRule.conditions.map { optCondition in
                    UFC_TargetingRuleCondition(
                        operator: optCondition.`operator`,
                        attribute: optCondition.attribute,
                        value: optCondition.value
                    )
                }
                return UFC_Rule(conditions: conditions)
            }

            let splits = optAllocation.splits.map { optSplit in
                let shards = optSplit.shards.map { optShard in
                    let ranges = optShard.ranges.map { optRange in
                        UFC_Range(start: optRange.start, end: optRange.end)
                    }
                    return UFC_Shard(salt: optShard.salt, ranges: ranges)
                }
                return UFC_Split(variationKey: optSplit.variationKey, shards: shards, extraLogging: [:])
            }

            return UFC_Allocation(
                key: optAllocation.key,
                rules: rules,
                startAt: optAllocation.startAt != nil ? parseUInt64Timestamp(optAllocation.startAt!) : nil,
                endAt: optAllocation.endAt != nil ? parseUInt64Timestamp(optAllocation.endAt!) : nil,
                splits: splits,
                doLog: optAllocation.doLog
            )
        }

        return UFC_Flag(
            key: optimizedFlag.key,
            enabled: optimizedFlag.enabled,
            variationType: optimizedFlag.variationType,
            variations: variations,
            allocations: allocations,
            totalShards: optimizedFlag.totalShards,
            entityId: optimizedFlag.entityId
        )
    }

    // Helper method to parse UInt64 timestamp to Date
    private func parseUInt64Timestamp(_ timestamp: UInt64) -> Date? {
        guard timestamp > 0 else { return nil }

        let timeInterval: TimeInterval
        if timestamp > 1_000_000_000_000 {
            // Likely milliseconds since Unix epoch
            timeInterval = TimeInterval(timestamp) / 1000.0
        } else {
            // Likely seconds since Unix epoch
            timeInterval = TimeInterval(timestamp)
        }

        return Date(timeIntervalSince1970: timeInterval)
    }
}

// MARK: - Error Types

enum AaronClaudeError: Error {
    case invalidJSONStructure
    case unsupportedValueType
    case optimizationFailed(String)
}

/**
 * Aaron Claude Client - Wrapper for the optimized evaluator
 */
public class AaronClaudeClient {
    public typealias AssignmentLogger = (Assignment) -> Void

    private let evaluator: AaronClaudeEvaluator
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
        self.evaluator = try AaronClaudeEvaluator(jsonData: jsonData, obfuscated: obfuscated)
        self.assignmentLogger = assignmentLogger
        self.isObfuscated = obfuscated

        NSLog("🧠 Aaron Claude Client initialized for SDK key: %@", sdkKey)
    }

    // MARK: - Assignment Methods (same interface as other clients)

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