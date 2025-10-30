import Foundation
import SwiftProtobuf

/// Native protobuf evaluator that works directly with protobuf types without Swift struct conversion
public class NativeProtobufEvaluator: FlagEvaluatorProtocol {
    private let sharder: Sharder
    private let isPrewarmed: Bool

    // Parsed protobuf config (either parsed upfront or lazily on first access)
    private var universalFlagConfig: Eppo_Ufc_UniversalFlagConfig?
    private let configLock = NSLock()

    // Raw protobuf data for lazy parsing
    private let protobufData: Data

    init(protobufData: Data, prewarmCache: Bool = false) throws {
        self.sharder = MD5Sharder()
        self.isPrewarmed = prewarmCache
        self.protobufData = protobufData

        if prewarmCache {
            // Parse protobuf immediately
            let config = try Eppo_Ufc_UniversalFlagConfig(serializedBytes: protobufData)
            self.universalFlagConfig = config
            print("   🔄 Pre-parsed protobuf config: \(config.flags.count) flags")
        } else {
            // Lazy mode - parse only when first accessed
            self.universalFlagConfig = nil
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
        // Get protobuf flag directly
        guard let protobufFlag = getProtobufFlag(flagKey: flagKey) else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found"
            )
        }

        // Evaluate directly with protobuf types
        return evaluateProtobufFlag(
            protobufFlag: protobufFlag,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )
    }

    public func getAllFlagKeys() -> [String] {
        guard let config = getUniversalFlagConfig() else { return [] }
        return Array(config.flags.keys)
    }

    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        guard let protobufFlag = getProtobufFlag(flagKey: flagKey) else { return nil }
        return convertProtobufVariationType(protobufFlag.variationType)
    }

    // MARK: - Private Methods

    private func getUniversalFlagConfig() -> Eppo_Ufc_UniversalFlagConfig? {
        // Return immediately if already parsed (either upfront or lazily)
        if let config = universalFlagConfig {
            return config
        }

        // Lazy parsing path
        configLock.lock()
        defer { configLock.unlock() }

        // Double-check after acquiring lock
        if let config = universalFlagConfig {
            return config
        }

        // Parse protobuf data for the first time
        do {
            let config = try Eppo_Ufc_UniversalFlagConfig(serializedBytes: protobufData)
            self.universalFlagConfig = config
            return config
        } catch {
            print("❌ Failed to parse protobuf data: \(error)")
            return nil
        }
    }

    private func getProtobufFlag(flagKey: String) -> Eppo_Ufc_Flag? {
        guard let config = getUniversalFlagConfig() else { return nil }

        return config.flags[flagKey]
    }

    // MARK: - Native Protobuf Evaluation Logic

    private func evaluateProtobufFlag(
        protobufFlag: Eppo_Ufc_Flag,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation {
        // Check if flag is enabled
        if !protobufFlag.enabled {
            return FlagEvaluation.noneResult(
                flagKey: protobufFlag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                entityId: protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil
            )
        }

        // Check if flag key is empty
        if protobufFlag.key.isEmpty {
            return FlagEvaluation.noneResult(
                flagKey: protobufFlag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                entityId: protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil
            )
        }

        // Handle case where flag has no allocations
        if protobufFlag.allocations.isEmpty {
            return FlagEvaluation.noneResult(
                flagKey: protobufFlag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Unrecognized or disabled flag: \(protobufFlag.key)",
                entityId: protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil
            )
        }

        var unmatchedAllocations: [AllocationEvaluation] = []
        var unevaluatedAllocations: [AllocationEvaluation] = []
        var matchedRule: Eppo_Ufc_Rule? = nil
        var matchedAllocation: AllocationEvaluation? = nil

        for (index, allocation) in protobufFlag.allocations.enumerated() {
            let orderPosition = index + 1

            // Check if allocation is within time range
            if allocation.startAt > 0 {
                let startDate = parseUInt64Timestamp(allocation.startAt)
                if let startAt = startDate, Date() < startAt {
                    unmatchedAllocations.append(AllocationEvaluation(
                        key: allocation.key,
                        allocationEvaluationCode: .beforeStartTime,
                        orderPosition: orderPosition
                    ))
                    continue
                }
            }

            if allocation.endAt > 0 {
                let endDate = parseUInt64Timestamp(allocation.endAt)
                if let endAt = endDate, Date() > endAt {
                    unmatchedAllocations.append(AllocationEvaluation(
                        key: allocation.key,
                        allocationEvaluationCode: .afterEndTime,
                        orderPosition: orderPosition
                    ))
                    continue
                }
            }

            // Check if allocation has rules
            if !allocation.rules.isEmpty {
                var rulesMatch = false
                for rule in allocation.rules {
                    if evaluateProtobufRule(rule: rule, subjectAttributes: subjectAttributes) {
                        rulesMatch = true
                        matchedRule = rule
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

            // This allocation matches - now evaluate sharding
            let shardResult = evaluateSharding(
                allocation: allocation,
                subjectKey: subjectKey,
                flag: protobufFlag,
                isConfigObfuscated: isConfigObfuscated
            )

            if let shardResult = shardResult {
                matchedAllocation = AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .match,
                    orderPosition: orderPosition
                )

                // Get the variation
                if let variation = getProtobufVariation(flag: protobufFlag, variationKey: shardResult.variationKey) {
                    let eppoValue = convertProtobufValue(variation.value, variationType: protobufFlag.variationType)
                    let ufcVariation = UFC_Variation(key: variation.key, value: eppoValue)

                    return FlagEvaluation(
                        flagKey: protobufFlag.key,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        allocationKey: allocation.key,
                        variation: ufcVariation,
                        variationType: convertProtobufVariationType(protobufFlag.variationType),
                        extraLogging: shardResult.extraLogging ?? [:],
                        doLog: allocation.doLog,
                        matchedRule: matchedRule != nil ? convertProtobufRuleToUFC(matchedRule!) : nil,
                        matchedAllocation: nil,
                        unmatchedAllocations: unmatchedAllocations,
                        unevaluatedAllocations: unevaluatedAllocations,
                        flagEvaluationCode: .match,
                        flagEvaluationDescription: "Successful evaluation",
                        entityId: protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil
                    )
                }
            } else {
                unmatchedAllocations.append(AllocationEvaluation(
                    key: allocation.key,
                    allocationEvaluationCode: .unevaluated,
                    orderPosition: orderPosition
                ))
            }
        }

        // No matching allocation found
        return FlagEvaluation.noneResult(
            flagKey: protobufFlag.key,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            flagEvaluationCode: .flagUnrecognizedOrDisabled,
            flagEvaluationDescription: "No matching allocation",
            unmatchedAllocations: unmatchedAllocations,
            unevaluatedAllocations: unevaluatedAllocations,
            entityId: protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil
        )
    }

    private func evaluateProtobufRule(rule: Eppo_Ufc_Rule, subjectAttributes: SubjectAttributes) -> Bool {
        // All conditions in a rule must match (AND logic)
        for condition in rule.conditions {
            if !evaluateProtobufCondition(condition: condition, subjectAttributes: subjectAttributes) {
                return false
            }
        }
        return true
    }

    private func evaluateProtobufCondition(condition: Eppo_Ufc_TargetingRuleCondition, subjectAttributes: SubjectAttributes) -> Bool {
        let subjectValue = subjectAttributes[condition.attribute]

        switch condition.operator {
        case .isNull:
            let expectNull = condition.value.lowercased() == "true"
            return expectNull ? (subjectValue == nil) : (subjectValue != nil)

        case .matches:
            guard let subjectValue = subjectValue else { return false }
            let subjectString = (try? subjectValue.getStringValue()) ?? ""
            return Compare.matchesRegex(subjectString, condition.value)

        case .notMatches:
            guard let subjectValue = subjectValue else { return false }
            let subjectString = (try? subjectValue.getStringValue()) ?? ""
            return !Compare.matchesRegex(subjectString, condition.value)

        case .oneOf:
            guard let subjectValue = subjectValue else { return false }
            let subjectString = (try? subjectValue.getStringValue()) ?? ""
            if let data = condition.value.data(using: String.Encoding.utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return Compare.isOneOf(subjectString, array)
            }
            return false

        case .notOneOf:
            guard let subjectValue = subjectValue else { return false }
            let subjectString = (try? subjectValue.getStringValue()) ?? ""
            if let data = condition.value.data(using: String.Encoding.utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return !Compare.isOneOf(subjectString, array)
            }
            return true

        case .gte, .gt, .lte, .lt:
            guard let subjectValue = subjectValue else { return false }
            let subjectDouble = (try? subjectValue.getDoubleValue()) ?? 0.0
            let conditionDouble = Double(condition.value) ?? 0.0

            switch condition.operator {
            case .gte: return subjectDouble >= conditionDouble
            case .gt: return subjectDouble > conditionDouble
            case .lte: return subjectDouble <= conditionDouble
            case .lt: return subjectDouble < conditionDouble
            default: return false
            }

        case .UNRECOGNIZED:
            return false
        }
    }

    private func evaluateSharding(
        allocation: Eppo_Ufc_Allocation,
        subjectKey: String,
        flag: Eppo_Ufc_Flag,
        isConfigObfuscated: Bool
    ) -> (variationKey: String, extraLogging: [String: String]?)? {
        guard !allocation.splits.isEmpty else { return nil }

        // For each split, check if subject falls into any shard
        for split in allocation.splits {
            for shard in split.shards {
                let shardKey = isConfigObfuscated ? shard.salt : "\(flag.key)-\(allocation.key)-\(shard.salt)"
                let hashValue = sharder.getShard(input: shardKey, totalShards: Int(flag.totalShards))

                // Check if hash falls in any range of this shard
                for range in shard.ranges {
                    if hashValue >= Int(range.start) && hashValue < Int(range.end) {
                        return (variationKey: split.variationKey, extraLogging: nil) // TODO: Handle extraLogging if needed
                    }
                }
            }
        }

        return nil
    }

    private func getProtobufVariation(flag: Eppo_Ufc_Flag, variationKey: String) -> Eppo_Ufc_Variation? {
        for variation in flag.variations {
            if variation.key == variationKey {
                return variation
            }
        }
        return nil
    }

    // MARK: - Conversion Helper Methods

    private func convertProtobufVariationType(_ protobufType: Eppo_Ufc_VariationType) -> UFC_VariationType {
        switch protobufType {
        case .boolean: return .boolean
        case .string: return .string
        case .numeric: return .numeric
        case .integer: return .integer
        case .json: return .json
        case .UNRECOGNIZED: return .string // fallback
        }
    }

    private func convertProtobufValue(_ valueString: String, variationType: Eppo_Ufc_VariationType) -> EppoValue {
        switch variationType {
        case .boolean:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let boolValue = cleanValue.lowercased() == "true"
            return EppoValue(value: boolValue)
        case .integer:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let intValue = Int(cleanValue) ?? 0
            return EppoValue(value: intValue)
        case .numeric:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let doubleValue = Double(cleanValue) ?? 0.0
            return EppoValue(value: doubleValue)
        case .string:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return EppoValue(value: cleanValue)
        case .json:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let unescapedValue = cleanValue.replacingOccurrences(of: "\\\"", with: "\"")
            return EppoValue(value: unescapedValue)
        case .UNRECOGNIZED:
            return EppoValue(value: valueString)
        }
    }

    private func convertProtobufRuleToUFC(_ protobufRule: Eppo_Ufc_Rule) -> UFC_Rule? {
        var conditions: [UFC_TargetingRuleCondition] = []

        for protobufCondition in protobufRule.conditions {
            let operatorEnum: UFC_RuleConditionOperator
            switch protobufCondition.operator {
            case .lt: operatorEnum = .lessThan
            case .lte: operatorEnum = .lessThanEqual
            case .gt: operatorEnum = .greaterThan
            case .gte: operatorEnum = .greaterThanEqual
            case .matches: operatorEnum = .matches
            case .oneOf: operatorEnum = .oneOf
            case .notOneOf: operatorEnum = .notOneOf
            case .isNull: operatorEnum = .isNull
            case .notMatches: operatorEnum = .notMatches
            case .UNRECOGNIZED: continue
            }

            let conditionValue: EppoValue
            switch protobufCondition.operator {
            case .oneOf, .notOneOf:
                if let data = protobufCondition.value.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    conditionValue = EppoValue(array: array)
                } else {
                    conditionValue = EppoValue(array: [])
                }
            case .gte, .gt, .lte, .lt:
                let doubleValue = Double(protobufCondition.value) ?? 0.0
                conditionValue = EppoValue(value: doubleValue)
            case .isNull:
                let expectNull = protobufCondition.value.lowercased() == "true"
                conditionValue = EppoValue(value: expectNull)
            case .matches, .notMatches:
                conditionValue = EppoValue(value: protobufCondition.value)
            case .UNRECOGNIZED:
                continue
            }

            conditions.append(UFC_TargetingRuleCondition(
                operator: operatorEnum,
                attribute: protobufCondition.attribute,
                value: conditionValue
            ))
        }

        if conditions.isEmpty {
            return nil
        }

        return UFC_Rule(conditions: conditions)
    }

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