import Foundation
import CommonCrypto

/**
 * OptimizedJSONEvaluator - High-Performance JSON Configuration Evaluator
 *
 * This evaluator optimizes JSON parsing and evaluation through several key techniques:
 * 1. Direct EppoValue creation based on operator context (eliminates try-catch type inference)
 * 2. Pre-computed condition values to avoid runtime type checking
 * 3. Inline evaluation logic to eliminate function call overhead
 * 4. Foundation-only parsing for maximum compatibility
 *
 * Performance targets:
 * - Startup: 3-4x faster than standard JSON parsing
 * - Evaluation: 10-15% faster than standard JSON evaluation
 * - Correctness: 100% identical results to baseline JSON evaluator
 */
public class OptimizedJSONEvaluator {

    // MARK: - Optimized Data Structures

    /// Pre-computed value structure that eliminates try-catch overhead during evaluation
    private struct OptimizedValue {
        let stringValue: String?
        let doubleValue: Double?
        let boolValue: Bool?
        let arrayValue: [String]?
        let type: EppoValueType

        /// Create optimized value from EppoValue, pre-computing all possible accessors
        init(from eppoValue: EppoValue) {
            self.type = eppoValue.isNull() ? EppoValueType.Null :
                       eppoValue.isBool() ? EppoValueType.Boolean :
                       eppoValue.isNumeric() ? EppoValueType.Numeric :
                       eppoValue.isString() ? EppoValueType.String : EppoValueType.ArrayOfStrings

            // Pre-compute all possible values to eliminate runtime try-catch
            self.stringValue = try? eppoValue.getStringValue()
            self.doubleValue = try? eppoValue.getDoubleValue()
            self.boolValue = try? eppoValue.getBoolValue()
            self.arrayValue = try? eppoValue.getStringArrayValue()
        }
    }

    /// Optimized condition with pre-computed value for fast evaluation
    private struct OptimizedCondition {
        let attribute: String
        let `operator`: UFC_RuleConditionOperator
        let value: OptimizedValue
    }

    /// Optimized rule containing pre-processed conditions
    private struct OptimizedRule {
        let conditions: [OptimizedCondition]
    }

    /// Optimized allocation structure
    private struct OptimizedAllocation {
        let key: String
        let startAt: UInt64?
        let endAt: UInt64?
        let doLog: Bool
        let rules: [OptimizedRule]
        let splits: [OptimizedSplit]
    }

    /// Optimized split structure
    private struct OptimizedSplit {
        let variationKey: String
        let shards: [OptimizedShard]
    }

    /// Optimized shard structure
    private struct OptimizedShard {
        let salt: String
        let ranges: [OptimizedRange]
    }

    /// Optimized range structure
    private struct OptimizedRange {
        let start: Int
        let end: Int
    }

    /// Optimized variation with pre-computed type
    private struct OptimizedVariation {
        let key: String
        let value: EppoValue
        let precomputedType: EppoValueType
    }

    /// Optimized flag structure containing all pre-processed elements
    private struct OptimizedFlag {
        let key: String
        let enabled: Bool
        let totalShards: Int
        let variationType: UFC_VariationType
        let variations: [String: OptimizedVariation]
        let allocations: [OptimizedAllocation]
        let entityId: Int?
    }

    // MARK: - Properties

    /// Pre-parsed flag configurations optimized for fast evaluation
    private let flagsConfiguration: [String: OptimizedFlag]
    private let isConfigObfuscated: Bool
    private let sharder: Sharder

    // MARK: - Initialization

    public init(jsonData: Data, obfuscated: Bool = false) throws {
        NSLog("🚀 OptimizedJSONEvaluator: Fast upfront parsing initialization...")
        let startTime = CFAbsoluteTimeGetCurrent()

        self.isConfigObfuscated = obfuscated
        self.sharder = MD5Sharder()

        // UPFRONT PARSING: Parse all flags immediately but efficiently
        self.flagsConfiguration = try Self.parseOptimizedJSON(data: jsonData)
        // JSON data is no longer needed after parsing - saves memory!

        let initTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        NSLog("🚀 OptimizedJSONEvaluator: Fast upfront parsing complete in %.2fms (%d flags parsed)", initTime, flagsConfiguration.count)
    }

    // MARK: - JSON Parsing with Optimizations

    private static func parseOptimizedJSON(data: Data) throws -> [String: OptimizedFlag] {
        // Parse JSON using Foundation's high-performance JSONSerialization
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flags = json["flags"] as? [String: Any] else {
            throw NSError(domain: "OptimizedJSONEvaluator", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])
        }

        var optimizedFlags: [String: OptimizedFlag] = [:]

        // Process each flag with optimizations
        for (flagKey, flagValue) in flags {
            guard let flagDict = flagValue as? [String: Any] else { continue }

            let enabled = flagDict["enabled"] as? Bool ?? false
            let totalShards = flagDict["totalShards"] as? Int ?? 10000
            let variationType = parseVariationType(flagDict["variationType"] as? String)
            let entityId = flagDict["entityId"] as? Int

            // Parse variations with type pre-computation
            let variations = parseOptimizedVariations(flagDict["variations"] as? [String: Any] ?? [:])

            // Parse allocations with rule optimization
            let allocations = try parseOptimizedAllocations(flagDict["allocations"] as? [[String: Any]] ?? [])

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


    /// Parse a single flag from JSON data
    private static func parseOptimizedFlag(flagKey: String, flagData: [String: Any]) throws -> OptimizedFlag {
        let enabled = flagData["enabled"] as? Bool ?? false
        let variationType = flagData["variationType"] as? String ?? "BOOLEAN"

        var variations: [String: OptimizedVariation] = [:]
        if let variationsData = flagData["variations"] as? [String: [String: Any]] {
            for (varKey, varData) in variationsData {
                if let value = varData["value"] {
                    let eppoValue = createEppoValueFromAny(value)
                    let optimizedValue = OptimizedValue(from: eppoValue)
                    variations[varKey] = OptimizedVariation(
                        key: varKey,
                        value: eppoValue,
                        precomputedType: optimizedValue.type
                    )
                }
            }
        }

        var allocations: [OptimizedAllocation] = []
        if let allocationsData = flagData["allocations"] as? [[String: Any]] {
            for allocationData in allocationsData {
                let key = allocationData["key"] as? String ?? ""

                var conditions: [OptimizedCondition] = []
                if let rulesData = allocationData["rules"] as? [[String: Any]] {
                    for ruleData in rulesData {
                        if let conditionsData = ruleData["conditions"] as? [[String: Any]] {
                            for conditionData in conditionsData {
                                if let attribute = conditionData["attribute"] as? String,
                                   let operatorStr = conditionData["operator"] as? String,
                                   let value = conditionData["value"] {
                                    let operatorEnum = UFC_RuleConditionOperator(rawValue: operatorStr) ?? .matches
                                    let eppoValue = createEppoValueFromAny(value)
                                    let optimizedValue = OptimizedValue(from: eppoValue)
                                    conditions.append(OptimizedCondition(
                                        attribute: attribute,
                                        operator: operatorEnum,
                                        value: optimizedValue
                                    ))
                                }
                            }
                        }
                    }
                }

                var splits: [OptimizedSplit] = []
                if let splitsData = allocationData["splits"] as? [[String: Any]] {
                    for splitData in splitsData {
                        if let variationKey = splitData["variationKey"] as? String,
                           let shardsData = splitData["shards"] as? [[String: Any]] {
                            var optimizedShards: [OptimizedShard] = []
                            for shardData in shardsData {
                                let salt = shardData["salt"] as? String ?? ""
                                var shardRanges: [OptimizedRange] = []
                                if let ranges = shardData["ranges"] as? [[String: Any]] {
                                    for rangeData in ranges {
                                        let start = rangeData["start"] as? Int ?? 0
                                        let end = rangeData["end"] as? Int ?? 0
                                        shardRanges.append(OptimizedRange(start: start, end: end))
                                    }
                                }
                                optimizedShards.append(OptimizedShard(salt: salt, ranges: shardRanges))
                            }
                            splits.append(OptimizedSplit(
                                variationKey: variationKey,
                                shards: optimizedShards
                            ))
                        }
                    }
                }

                // Convert conditions to rules
                let rules = conditions.isEmpty ? [] : [OptimizedRule(conditions: conditions)]

                allocations.append(OptimizedAllocation(
                    key: key,
                    startAt: nil,
                    endAt: nil,
                    doLog: false,
                    rules: rules,
                    splits: splits
                ))
            }
        }

        let totalShards = flagData["totalShards"] as? Int ?? 10000
        let entityId = flagData["entityId"] as? Int

        return OptimizedFlag(
            key: flagKey,
            enabled: enabled,
            totalShards: totalShards,
            variationType: UFC_VariationType(rawValue: variationType) ?? .boolean,
            variations: variations,
            allocations: allocations,
            entityId: entityId
        )
    }

    private static func parseVariationType(_ typeString: String?) -> UFC_VariationType {
        switch typeString?.uppercased() {
        case "BOOLEAN": return .boolean
        case "STRING": return .string
        case "NUMERIC": return .numeric
        case "INTEGER": return .integer
        case "JSON": return .json
        default: return .string
        }
    }

    private static func parseOptimizedVariations(_ variationsDict: [String: Any]) -> [String: OptimizedVariation] {
        var variations: [String: OptimizedVariation] = [:]

        for (key, value) in variationsDict {
            guard let variationDict = value as? [String: Any],
                  let variationKey = variationDict["key"] as? String,
                  let variationValue = variationDict["value"] else { continue }

            let eppoValue = createEppoValueFromAny(variationValue)
            let precomputedType = eppoValue.isNull() ? EppoValueType.Null :
                                 eppoValue.isBool() ? EppoValueType.Boolean :
                                 eppoValue.isNumeric() ? EppoValueType.Numeric :
                                 eppoValue.isString() ? EppoValueType.String : EppoValueType.ArrayOfStrings

            variations[key] = OptimizedVariation(
                key: variationKey,
                value: eppoValue,
                precomputedType: precomputedType
            )
        }

        return variations
    }

    private static func parseOptimizedAllocations(_ allocationsArray: [[String: Any]]) throws -> [OptimizedAllocation] {
        return try allocationsArray.map { allocationDict in
            let key = allocationDict["key"] as? String ?? ""
            let startAt = parseUInt64(allocationDict["startAt"])
            let endAt = parseUInt64(allocationDict["endAt"])
            let doLog = allocationDict["doLog"] as? Bool ?? false

            let rules = try parseOptimizedRules(allocationDict["rules"] as? [[String: Any]] ?? [])
            let splits = parseOptimizedSplits(allocationDict["splits"] as? [[String: Any]] ?? [])

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
            let conditions = try parseOptimizedConditions(ruleDict["conditions"] as? [[String: Any]] ?? [])
            return OptimizedRule(conditions: conditions)
        }
    }

    private static func parseOptimizedConditions(_ conditionsArray: [[String: Any]]) throws -> [OptimizedCondition] {
        return conditionsArray.map { conditionDict in
            let attribute = conditionDict["attribute"] as? String ?? ""
            let operatorString = conditionDict["operator"] as? String ?? ""
            let valueString = conditionDict["value"] as? String ?? ""

            let operatorEnum = parseRuleOperator(operatorString)

            // OPTIMIZATION: Create EppoValue based on operator context for faster parsing
            let eppoValue = createOptimizedConditionValue(
                valueString: valueString,
                operator: operatorEnum
            )

            return OptimizedCondition(
                attribute: attribute,
                operator: operatorEnum,
                value: OptimizedValue(from: eppoValue)
            )
        }
    }

    private static func parseOptimizedSplits(_ splitsArray: [[String: Any]]) -> [OptimizedSplit] {
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

    // MARK: - Optimized EppoValue Creation

    /// Create EppoValue based on operator context to avoid expensive type inference
    private static func createOptimizedConditionValue(
        valueString: String,
        operator operatorEnum: UFC_RuleConditionOperator
    ) -> EppoValue {

        switch operatorEnum {
        case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
            // Numeric operators - try to create numeric value directly
            if let doubleValue = Double(valueString) {
                return EppoValue(value: doubleValue)
            }

        case .oneOf, .notOneOf:
            // Array operators - parse as JSON array if possible
            if let jsonData = valueString.data(using: .utf8),
               let stringArray = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
                return EppoValue(array: stringArray)
            }

        case .isNull:
            // Boolean operators for null checks
            if valueString.lowercased() == "true" || valueString.lowercased() == "false" {
                return EppoValue(value: valueString.lowercased() == "true")
            }

        default:
            break
        }

        // Default to string value
        return EppoValue(value: valueString)
    }

    // MARK: - Helper Functions

    private static func createEppoValueFromAny(_ value: Any) -> EppoValue {
        if let stringValue = value as? String {
            return EppoValue(value: stringValue)
        } else if let boolValue = value as? Bool {
            return EppoValue(value: boolValue)
        } else if let doubleValue = value as? Double {
            return EppoValue(value: doubleValue)
        } else if let intValue = value as? Int {
            return EppoValue(value: intValue)
        } else if let arrayValue = value as? [String] {
            return EppoValue(array: arrayValue)
        }

        return EppoValue.nullValue()
    }

    private static func parseUInt64(_ value: Any?) -> UInt64? {
        if let stringValue = value as? String {
            return UInt64(stringValue)
        } else if let intValue = value as? Int {
            return UInt64(intValue)
        } else if let doubleValue = value as? Double {
            return UInt64(doubleValue)
        }
        return nil
    }

    private static func parseRuleOperator(_ operatorString: String) -> UFC_RuleConditionOperator {
        switch operatorString.lowercased() {
        case "gte": return .greaterThanEqual
        case "gt": return .greaterThan
        case "lte": return .lessThanEqual
        case "lt": return .lessThan
        case "matches": return .matches
        case "not_matches": return .notMatches
        case "one_of": return .oneOf
        case "not_one_of": return .notOneOf
        case "is_null": return .isNull
        default: return .matches
        }
    }

    // MARK: - Flag Evaluation Interface

    func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType? = nil
    ) -> FlagEvaluation {

        // Handle obfuscated flag key lookup (critical fix!)
        let flagKeyForLookup = isConfigObfuscated ? getMD5Hex(flagKey) : flagKey

        // Direct lookup from pre-parsed flags
        guard let optimizedFlag = flagsConfiguration[flagKeyForLookup] else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found: \(flagKey)"
            )
        }

        // Direct evaluation on optimized structures - no conversion overhead!
        return evaluateOptimizedFlag(
            optimizedFlag: optimizedFlag,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )
    }

    func getAllFlagKeys() -> [String] {
        return Array(flagsConfiguration.keys)
    }

    func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return flagsConfiguration[flagKey]?.variationType
    }

    // MARK: - Optimized Flag Evaluation

    private func evaluateOptimizedFlag(
        optimizedFlag: OptimizedFlag,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation {

        // Check if flag is enabled
        guard optimizedFlag.enabled else {
            return FlagEvaluation.noneResult(
                flagKey: optimizedFlag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                entityId: optimizedFlag.entityId
            )
        }

        // Handle case where flag has no allocations
        guard !optimizedFlag.allocations.isEmpty else {
            return FlagEvaluation.noneResult(
                flagKey: optimizedFlag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "No allocations available",
                entityId: optimizedFlag.entityId
            )
        }

        var unmatchedAllocations: [AllocationEvaluation] = []
        var matchedAllocation: AllocationEvaluation? = nil

        // Iterate through allocations to find a match
        for (index, allocation) in optimizedFlag.allocations.enumerated() {
            let orderPosition = index + 1

            // Check time bounds
            let now = Date()
            if let startAt = parseTimestamp(allocation.startAt), now < startAt {
                unmatchedAllocations.append(AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .beforeStartTime,
                    orderPosition: orderPosition
                ))
                continue
            }

            if let endAt = parseTimestamp(allocation.endAt), now > endAt {
                unmatchedAllocations.append(AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .afterEndTime,
                    orderPosition: orderPosition
                ))
                continue
            }

            // Check rules using optimized evaluation
            if !allocation.rules.isEmpty {
                var rulesMatch = false
                for rule in allocation.rules {
                    if matchesOptimizedRule(
                        subjectAttributes: subjectAttributes,
                        rule: rule,
                        isConfigObfuscated: isConfigObfuscated,
                        subjectKey: subjectKey
                    ) {
                        rulesMatch = true
                        break
                    }
                }

                if !rulesMatch {
                    unmatchedAllocations.append(AllocationEvaluation(
                        key: allocation.key,
                        allocationEvaluationCode: .failingRule,
                        orderPosition: orderPosition
                    ))
                    continue
                }
            }

            // Found matching allocation
            matchedAllocation = AllocationEvaluation(
                key: allocation.key,
                allocationEvaluationCode: .match,
                orderPosition: orderPosition
            )

            // Determine variation using sharding
            let variationKey = determineVariation(
                allocation: allocation,
                subjectKey: subjectKey,
                totalShards: optimizedFlag.totalShards
            )

            // If no variation found, this allocation doesn't match
            if variationKey.isEmpty {
                unmatchedAllocations.append(AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .trafficExposureMiss,
                    orderPosition: orderPosition
                ))
                continue
            }

            if let variation = optimizedFlag.variations[variationKey] {
                // Convert OptimizedVariation to UFC_Variation
                let ufcVariation = UFC_Variation(key: variation.key, value: variation.value)

                return FlagEvaluation(
                    flagKey: optimizedFlag.key,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    allocationKey: matchedAllocation?.key,
                    variation: ufcVariation,
                    variationType: optimizedFlag.variationType,
                    extraLogging: [:],
                    doLog: allocation.doLog,
                    matchedRule: nil,
                    matchedAllocation: matchedAllocation,
                    unmatchedAllocations: unmatchedAllocations,
                    unevaluatedAllocations: [],
                    flagEvaluationCode: .match,
                    flagEvaluationDescription: "Match found",
                    entityId: optimizedFlag.entityId
                )
            } else {
                // Variation key exists but variation not found - this shouldn't happen but handle gracefully
                unmatchedAllocations.append(AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .trafficExposureMiss,
                    orderPosition: orderPosition
                ))
                continue
            }
        }

        // No allocation matched
        return FlagEvaluation.noneResult(
            flagKey: optimizedFlag.key,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            flagEvaluationCode: .flagUnrecognizedOrDisabled,
            flagEvaluationDescription: "No matching allocation found",
            unmatchedAllocations: unmatchedAllocations,
            unevaluatedAllocations: [],
            entityId: optimizedFlag.entityId
        )
    }

    // MARK: - Optimized Rule Evaluation (Inline for Performance)

    private func matchesOptimizedRule(
        subjectAttributes: SubjectAttributes,
        rule: OptimizedRule,
        isConfigObfuscated: Bool,
        subjectKey: String
    ) -> Bool {
        // All conditions in the rule must match
        return rule.conditions.allSatisfy { condition in
            evaluateOptimizedCondition(
                subjectAttributes: subjectAttributes,
                condition: condition,
                isConfigObfuscated: isConfigObfuscated,
                subjectKey: subjectKey
            )
        }
    }

    private func evaluateOptimizedCondition(
        subjectAttributes: SubjectAttributes,
        condition: OptimizedCondition,
        isConfigObfuscated: Bool,
        subjectKey: String
    ) -> Bool {
        // Get attribute value efficiently
        let attributeKey = condition.attribute
        var attributeValue: EppoValue?

        // Handle obfuscated vs clear attribute lookup
        if isConfigObfuscated {
            for (key, value) in subjectAttributes {
                if getMD5Hex(key) == attributeKey {
                    attributeValue = value
                    break
                }
            }
        } else {
            attributeValue = subjectAttributes[condition.attribute]
        }

        // Handle "id" attribute special case
        if attributeValue == nil {
            let idKey = isConfigObfuscated ? getMD5Hex("id") : "id"
            if attributeKey == idKey {
                attributeValue = EppoValue.valueOf(subjectKey)
            }
        }

        // Handle NULL checks first
        let attributeValueIsNull = attributeValue?.isNull() ?? true

        if condition.operator == .isNull {
            if isConfigObfuscated, let conditionStringValue = condition.value.stringValue {
                let expectNull: Bool = getMD5Hex("true") == conditionStringValue
                return expectNull == attributeValueIsNull
            } else {
                let expectNull = condition.value.boolValue ?? false
                return expectNull == attributeValueIsNull
            }
        } else if attributeValueIsNull {
            // Any non-NULL check fails if attribute is null
            return false
        }

        guard let value = attributeValue else { return false }

        // OPTIMIZATION: Inline all evaluation logic to eliminate function call overhead
        switch condition.operator {
        case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
            guard let conditionNumeric = condition.value.doubleValue,
                  let subjectNumeric = try? value.getDoubleValue() else { return false }

            switch condition.operator {
            case .greaterThanEqual: return subjectNumeric >= conditionNumeric
            case .greaterThan: return subjectNumeric > conditionNumeric
            case .lessThanEqual: return subjectNumeric <= conditionNumeric
            case .lessThan: return subjectNumeric < conditionNumeric
            default: return false
            }

        case .matches, .notMatches:
            guard let subjectString = try? value.getStringValue(),
                  let conditionString = condition.value.stringValue else { return false }

            let pattern = isConfigObfuscated ? (base64Decode(conditionString) ?? conditionString) : conditionString
            let matches = subjectString.range(of: pattern, options: .regularExpression) != nil
            return condition.operator == .matches ? matches : !matches

        case .oneOf, .notOneOf:
            guard let subjectString = try? value.getStringValue(),
                  let conditionArray = condition.value.arrayValue else { return false }

            let isOneOf = conditionArray.contains(subjectString)
            return condition.operator == .oneOf ? isOneOf : !isOneOf

        default:
            return false
        }
    }

    // MARK: - Helper Methods

    private func parseTimestamp(_ timestamp: UInt64?) -> Date? {
        guard let timestamp = timestamp else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }

    private func determineVariation(allocation: OptimizedAllocation, subjectKey: String, totalShards: Int) -> String {
        // Use proper sharding logic to determine variation
        for split in allocation.splits {
            for shard in split.shards {
                // Handle obfuscated salt
                let salt = isConfigObfuscated ? (base64Decode(shard.salt) ?? shard.salt) : shard.salt

                // Create hash key like the standard evaluator
                let hashKey = salt + "-" + subjectKey
                let shardValue = sharder.getShard(input: hashKey, totalShards: totalShards)

                for range in shard.ranges {
                    if shardValue >= range.start && shardValue < range.end {
                        return split.variationKey
                    }
                }
            }
        }

        // No matching shard found - return empty string (should result in default)
        return ""
    }

    private func getMD5Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let baseAddress = bytes.baseAddress {
                CC_MD5(baseAddress, CC_LONG(data.count), &digest)
            }
        }

        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func base64Decode(_ input: String) -> String? {
        guard let data = Data(base64Encoded: input) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}