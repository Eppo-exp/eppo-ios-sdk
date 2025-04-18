import Foundation
import Semver

typealias ConditionFunc = (Double, Double) -> Bool

class Compare {
    public static func matchesRegex(_ a: String, _ pattern: String) -> Bool {
        return a.range(of: pattern, options: .regularExpression) != nil
    }

    public static func isOneOf(_ a: String, _ values: [String]) -> Bool {
        // the comparison is case-sensitive
        return values.contains(a)
    }
}

struct FlagEvaluation {
    let flagKey: String
    let subjectKey: String
    let subjectAttributes: SubjectAttributes
    let allocationKey: String?
    let variation: UFC_Variation?
    let variationType: UFC_VariationType?
    let extraLogging: [String: String]
    let doLog: Bool

    static func matchedResult(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        allocationKey: String?,
        variation: UFC_Variation?,
        variationType: UFC_VariationType?,
        extraLogging: [String: String],
        doLog: Bool,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation {
        // If the config is obfuscated, we need to unobfuscate the allocation key.
        var decodedAllocationKey: String = allocationKey ?? ""
        if isConfigObfuscated,
           let allocationKey = allocationKey,
           let decoded = base64Decode(allocationKey) {
            decodedAllocationKey = decoded
        }

        var decodedVariation: UFC_Variation? = variation
        if isConfigObfuscated,
           let variation = variation,
           let variationType = variationType,
           let decodedVariationKey = base64Decode(variation.key),
           let variationValue = try? variation.value.getStringValue(),
           let decodedVariationValue = base64Decode(variationValue) {

            var decodedValue: EppoValue = EppoValue.nullValue()

            switch variationType {
            case .boolean:
                decodedValue = EppoValue(value: "true" == decodedVariationValue)
            case .integer, .numeric:
                if let doubleValue = Double(decodedVariationValue) {
                    decodedValue = EppoValue(value: doubleValue)
                }
            case .string, .json:
                decodedValue = EppoValue(value: decodedVariationValue)
            }

            decodedVariation = UFC_Variation(key: decodedVariationKey, value: decodedValue)
        }

        return FlagEvaluation(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: decodedAllocationKey,
            variation: decodedVariation,
            variationType: variationType,
            extraLogging: extraLogging,
            doLog: doLog
        )
    }

    static func noneResult(flagKey: String, subjectKey: String, subjectAttributes: SubjectAttributes) -> FlagEvaluation {
        return FlagEvaluation(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: Optional<String>.none,
            variation: Optional<UFC_Variation>.none,
            variationType: Optional<UFC_VariationType>.none,
            extraLogging: [:],
            doLog: false
        )
    }
}

public class FlagEvaluator {

    let sharder: Sharder

    init(sharder: Sharder) {
        self.sharder = sharder
    }

    enum Errors: Error {
        case UnexpectedValue
    }

    func evaluateFlag(
        flag: UFC_Flag,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation {
        if !flag.enabled {
            return FlagEvaluation.noneResult(
                flagKey: flag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes
            )
        }

        let now = Date()
        for allocation in flag.allocations {
            // # Skip allocations that are not active
            if let startAt = allocation.startAt, now < startAt {
                continue
            }
            if let endAt = allocation.endAt, now > endAt {
                continue
            }

            // Add the subject key as an attribute so rules can use it
            // If the "id" attribute is already present, keep the existing value
            let subjectAttributesWithID = subjectAttributes.merging(["id": EppoValue.valueOf(subjectKey)]) { (old, _) in old }
            if matchesRules(
                subjectAttributes: subjectAttributesWithID,
                rules: allocation.rules ?? [],
                isConfigObfuscated: isConfigObfuscated
            ) {
                // Split needs to match all shards
                for split in allocation.splits {
                    let allShardsMatch = split.shards.allSatisfy { shard in
                        matchesShard(
                            shard: shard,
                            subjectKey: subjectKey,
                            totalShards: flag.totalShards,
                            isConfigObfuscated: isConfigObfuscated
                        )
                    }
                    if allShardsMatch {
                        return FlagEvaluation.matchedResult(
                            flagKey: flag.key,
                            subjectKey: subjectKey,
                            subjectAttributes: subjectAttributes,
                            allocationKey: String?.some(allocation.key),
                            variation: flag.variations[split.variationKey],
                            variationType: flag.variationType,
                            extraLogging: split.extraLogging ?? [:],
                            doLog: allocation.doLog,
                            isConfigObfuscated: isConfigObfuscated
                        )
                    }
                }
            }
        }

        return FlagEvaluation.noneResult(
            flagKey: flag.key,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes
        )
    }

    private func matchesShard(
        shard: UFC_Shard,
        subjectKey: String,
        totalShards: Int,
        isConfigObfuscated: Bool
    ) -> Bool {
        assert(totalShards > 0, "Expect totalShards to be strictly positive")

        let salt = isConfigObfuscated ? base64Decode(shard.salt) : shard.salt

        if let salt = salt {
            let h = self.sharder.getShard(input: hashKey(salt: salt, subjectKey: subjectKey), totalShards: totalShards)
            return shard.ranges.contains { range in
                isInShardRange(shard: h, range: range)
            }
        }

        // If the salt is not valid, return false
        return false
    }

    private func matchesRules(
        subjectAttributes: SubjectAttributes,
        rules: [UFC_Rule],
        isConfigObfuscated: Bool
    ) -> Bool {
        if rules.isEmpty {
            return true
        }

        // If any rule matches, return true.
        return rules.contains { rule in
            return matchesRule(
                subjectAttributes: subjectAttributes,
                rule: rule,
                isConfigObfuscated: isConfigObfuscated
            )
        }
    }

    private func matchesRule(
        subjectAttributes: SubjectAttributes,
        rule: UFC_Rule,
        isConfigObfuscated: Bool
    ) -> Bool {
        // Check that all conditions within the rule are met
        return rule.conditions.allSatisfy { condition in
            // If the condition throws an error, consider this not matching.
            return evaluateCondition(
                subjectAttributes: subjectAttributes,
                condition: condition,
                isConfigObfuscated: isConfigObfuscated
            )

        }
    }

    private func isInShardRange(shard: Int, range: UFC_Range) -> Bool {
        return range.start <= shard && shard < range.end
    }

    private func hashKey(salt: String, subjectKey: String) -> String {
        return salt + "-" + subjectKey
    }

    private func evaluateCondition(
        subjectAttributes: SubjectAttributes,
        condition: UFC_TargetingRuleCondition,
        isConfigObfuscated: Bool
    ) -> Bool {
        // attribute names are hashed if obfuscated
        let attributeKey = condition.attribute
        var attributeValue: EppoValue?
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

        // First we do any NULL check
        let attributeValueIsNull = attributeValue?.isNull() ?? true
        if condition.operator == .isNull {
            if isConfigObfuscated, let value: String = try? condition.value.getStringValue() {
                let expectNull: Bool = getMD5Hex("true") == value
                return expectNull == attributeValueIsNull
            } else if let value = try? condition.value.getBoolValue() {
                let expectNull: Bool = value
                return expectNull == attributeValueIsNull
            }
        } else if attributeValueIsNull {
            // Any check other than IS NULL should fail if the attribute value is null
            return false
        }

        // Safely unwrap attributeValue for further use
        guard let value = attributeValue else {
            // Handle the nil case, perhaps throw an error or return a default value
            return false
        }

        switch condition.operator {
        case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
            let valueStr = try? value.getStringValue()

            // If the config is obfuscated, we need to unobfuscate the condition value
            var conditionValueStr: String? = try? condition.value.getStringValue()
            if isConfigObfuscated,
               let cvs = conditionValueStr,
               let decoded = base64Decode(cvs) {
                conditionValueStr = decoded
            }

            if let valueVersion = valueStr.flatMap(Semver.init), let conditionVersion = conditionValueStr.flatMap(Semver.init) {
                // If both strings are valid Semver strings, perform a Semver comparison
                switch condition.operator {
                case .greaterThanEqual:
                    return valueVersion >= conditionVersion
                case .greaterThan:
                    return valueVersion > conditionVersion
                case .lessThanEqual:
                    return valueVersion <= conditionVersion
                case .lessThan:
                    return valueVersion < conditionVersion
                default:
                    return false
                }
            } else {
                // If either string is not a valid Semver, fall back to double comparison
                guard let valueDouble = try? value.getDoubleValue() else {
                    return false
                }

                // If the config is obfuscated, we need to unobfuscate the condition value
                var conditionDouble: Double
                if isConfigObfuscated,
                   let cvs = conditionValueStr,
                   let doubleValue = Double(cvs) {
                    conditionDouble = doubleValue
                } else if let doubleValue = try? condition.value.getDoubleValue() {
                    conditionDouble = doubleValue
                } else {
                    return false
                }

                switch condition.operator {
                case .greaterThanEqual:
                    return valueDouble >= conditionDouble
                case .greaterThan:
                    return valueDouble > conditionDouble
                case .lessThanEqual:
                    return valueDouble <= conditionDouble
                case .lessThan:
                    return valueDouble < conditionDouble
                default:
                    return false
                }
            }
        case .matches, .notMatches:
            if let conditionString = try? condition.value.toEppoString(),
               let valueString = try? value.toEppoString() {

                if isConfigObfuscated,
                   let decoded = base64Decode(conditionString) {
                    return condition.operator == .matches ? Compare.matchesRegex(valueString, decoded) : !Compare.matchesRegex(valueString, decoded)
                } else {
                    return condition.operator == .matches ? Compare.matchesRegex(valueString, conditionString) : !Compare.matchesRegex(valueString, conditionString)
                }
            }

            return false
        case .oneOf, .notOneOf:
            if let valueString = try? value.toEppoString(),
               let conditionArray = try? condition.value.getStringArrayValue() {

                if isConfigObfuscated {
                    let valueStringHash = getMD5Hex(valueString)
                    return condition.operator == .oneOf ? Compare.isOneOf(valueStringHash, conditionArray) : !Compare.isOneOf(valueStringHash, conditionArray)
                } else {
                    return condition.operator == .oneOf ? Compare.isOneOf(valueString, conditionArray) : !Compare.isOneOf(valueString, conditionArray)
                }
            }

            return false
        default:
            return false
        }
    }
}
