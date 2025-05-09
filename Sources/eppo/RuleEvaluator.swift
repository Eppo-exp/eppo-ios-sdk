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

        // Check if flag is unrecognized
        if flag.key.isEmpty {
            return FlagEvaluation.noneResult(
                flagKey: flag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes
            )
        }

        // Handle case where flag has no allocations
        if flag.allocations.isEmpty {
            let result = FlagEvaluation.noneResult(
                flagKey: flag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Unrecognized or disabled flag: \(flag.key)"
            )
            return result
        }

        var unmatchedAllocations: [AllocationEvaluation] = []
        var unevaluatedAllocations: [AllocationEvaluation] = []
        var matchedRule: UFC_Rule? = nil
        var matchedAllocation: AllocationEvaluation? = nil

        for (index, allocation) in flag.allocations.enumerated() {
            let orderPosition = index + 1

            // Check if allocation is within time range
            if let startAt = allocation.startAt {
                if Date() < startAt {
                    unmatchedAllocations.append(AllocationEvaluation(
                        key: allocation.key,
                        allocationEvaluationCode: .beforeStartTime,
                        orderPosition: orderPosition
                    ))
                    continue
                }
            }

            if let endAt = allocation.endAt {
                if Date() > endAt {
                    unmatchedAllocations.append(AllocationEvaluation(
                        key: allocation.key,
                        allocationEvaluationCode: .afterEndTime,
                        orderPosition: orderPosition
                    ))
                    continue
                }
            }

            // Check if allocation has rules
            if let rules = allocation.rules, !rules.isEmpty {
                var rulesMatch = false
                for rule in rules {
                    if matchesRule(
                        subjectAttributes: subjectAttributes,
                        rule: rule,
                        isConfigObfuscated: isConfigObfuscated,
                        subjectKey: subjectKey
                    ) {
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

            // Check if subject is in any traffic range
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
                    // Mark remaining allocations as unevaluated
                    for remainingIndex in (index + 1)..<flag.allocations.count {
                        unevaluatedAllocations.append(AllocationEvaluation(
                            key: flag.allocations[remainingIndex].key,
                            allocationEvaluationCode: .unevaluated,
                            orderPosition: remainingIndex + 1
                        ))
                    }

                    matchedAllocation = AllocationEvaluation(
                        key: allocation.key,
                        allocationEvaluationCode: .match,
                        orderPosition: orderPosition
                    )
                    
                    let variation = flag.variations[split.variationKey]

                    // Check for assignment errors
                    if flag.variationType == .integer {
                        if let variation = variation {
                            // First try to get double value directly
                            if let doubleValue = try? variation.value.getDoubleValue() {
                                if !doubleValue.isInteger {
                                    // Create a new variation with the original double value
                                    let errorVariation = UFC_Variation(
                                        key: variation.key,
                                        value: EppoValue.valueOf(doubleValue)
                                    )
                                    let evaluation = FlagEvaluation(
                                        flagKey: flag.key,
                                        subjectKey: subjectKey,
                                        subjectAttributes: subjectAttributes,
                                        allocationKey: allocation.key,
                                        variation: errorVariation,
                                        variationType: flag.variationType,
                                        extraLogging: split.extraLogging ?? [:],
                                        doLog: allocation.doLog,
                                        matchedRule: matchedRule,
                                        matchedAllocation: matchedAllocation,
                                        unmatchedAllocations: unmatchedAllocations,
                                        unevaluatedAllocations: unevaluatedAllocations,
                                        flagEvaluationCode: .assignmentError,
                                        flagEvaluationDescription: "Variation (\(variation.key)) is configured for type INTEGER, but is set to incompatible value (\(doubleValue))"
                                    )
                                    return evaluation
                                }
                                // Create a new variation with the double value
                                let decodedVariation = UFC_Variation(
                                    key: variation.key,
                                    value: EppoValue.valueOf(doubleValue)
                                )
                                return FlagEvaluation.matchedResult(
                                    flagKey: flag.key,
                                    subjectKey: subjectKey,
                                    subjectAttributes: subjectAttributes,
                                    allocationKey: allocation.key,
                                    variation: decodedVariation,
                                    variationType: flag.variationType,
                                    extraLogging: split.extraLogging ?? [:],
                                    doLog: allocation.doLog,
                                    isConfigObfuscated: isConfigObfuscated,
                                    matchedRule: matchedRule,
                                    matchedAllocation: matchedAllocation,
                                    allocation: allocation,
                                    unmatchedAllocations: unmatchedAllocations,
                                    unevaluatedAllocations: unevaluatedAllocations
                                )
                            }
                            
                            // If not a double, try string value
                            if let stringValue = try? variation.value.getStringValue() {
                                var decodedValue: String? = stringValue
                                if isConfigObfuscated {
                                    decodedValue = base64Decode(stringValue)
                                }
                                if let finalValue = decodedValue, let doubleValue = Double(finalValue) {
                                    if !doubleValue.isInteger {
                                        // Create a new variation with the original double value
                                        let errorVariation = UFC_Variation(
                                            key: variation.key,
                                            value: EppoValue.valueOf(doubleValue)
                                        )
                                        return FlagEvaluation(
                                            flagKey: flag.key,
                                            subjectKey: subjectKey,
                                            subjectAttributes: subjectAttributes,
                                            allocationKey: allocation.key,
                                            variation: errorVariation,
                                            variationType: flag.variationType,
                                            extraLogging: split.extraLogging ?? [:],
                                            doLog: allocation.doLog,
                                            matchedRule: matchedRule,
                                            matchedAllocation: matchedAllocation,
                                            unmatchedAllocations: unmatchedAllocations,
                                            unevaluatedAllocations: unevaluatedAllocations,
                                            flagEvaluationCode: .assignmentError,
                                            flagEvaluationDescription: "Variation (\(variation.key)) is configured for type INTEGER, but is set to incompatible value (\(doubleValue))"
                                        )
                                    }
                                    // Create a new variation with the decoded value
                                    let decodedVariation = UFC_Variation(
                                        key: variation.key,
                                        value: EppoValue.valueOf(doubleValue)
                                    )
                                    return FlagEvaluation.matchedResult(
                                        flagKey: flag.key,
                                        subjectKey: subjectKey,
                                        subjectAttributes: subjectAttributes,
                                        allocationKey: allocation.key,
                                        variation: decodedVariation,
                                        variationType: flag.variationType,
                                        extraLogging: split.extraLogging ?? [:],
                                        doLog: allocation.doLog,
                                        isConfigObfuscated: isConfigObfuscated,
                                        matchedRule: matchedRule,
                                        matchedAllocation: matchedAllocation,
                                        allocation: allocation,
                                        unmatchedAllocations: unmatchedAllocations,
                                        unevaluatedAllocations: unevaluatedAllocations
                                    )
                                }
                            }
                            return FlagEvaluation(
                                flagKey: flag.key,
                                subjectKey: subjectKey,
                                subjectAttributes: subjectAttributes,
                                allocationKey: allocation.key,
                                variation: variation,
                                variationType: flag.variationType,
                                extraLogging: split.extraLogging ?? [:],
                                doLog: allocation.doLog,
                                matchedRule: matchedRule,
                                matchedAllocation: matchedAllocation,
                                unmatchedAllocations: unmatchedAllocations,
                                unevaluatedAllocations: unevaluatedAllocations,
                                flagEvaluationCode: .assignmentError,
                                flagEvaluationDescription: "Variation (\(variation.key)) is configured for type INTEGER, but is set to incompatible value"
                            )
                        } else {
                            return FlagEvaluation.noneResult(
                                flagKey: flag.key,
                                subjectKey: subjectKey,
                                subjectAttributes: subjectAttributes,
                                unmatchedAllocations: unmatchedAllocations,
                                unevaluatedAllocations: unevaluatedAllocations
                            )
                        }
                    }
                    
                    return FlagEvaluation.matchedResult(
                        flagKey: flag.key,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        allocationKey: allocation.key,
                        variation: variation,
                        variationType: flag.variationType,
                        extraLogging: split.extraLogging ?? [:],
                        doLog: allocation.doLog,
                        isConfigObfuscated: isConfigObfuscated,
                        matchedRule: matchedRule,
                        matchedAllocation: matchedAllocation,
                        allocation: allocation,
                        unmatchedAllocations: unmatchedAllocations,
                        unevaluatedAllocations: unevaluatedAllocations
                    )
                }
            }

            // If we get here, the subject is not in any traffic range
            unmatchedAllocations.append(AllocationEvaluation(
                key: allocation.key,
                allocationEvaluationCode: .trafficExposureMiss,
                orderPosition: orderPosition
            ))
        }

        // If we get here, no allocation matched
        return FlagEvaluation.noneResult(
            flagKey: flag.key,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            unmatchedAllocations: unmatchedAllocations,
            unevaluatedAllocations: unevaluatedAllocations
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

    private func matchesRule(
        subjectAttributes: SubjectAttributes,
        rule: UFC_Rule,
        isConfigObfuscated: Bool,
        subjectKey: String
    ) -> Bool {
        // Check that all conditions within the rule are met
        return rule.conditions.allSatisfy { condition in
            // If the condition throws an error, consider this not matching.
            return evaluateCondition(
                subjectAttributes: subjectAttributes,
                condition: condition,
                isConfigObfuscated: isConfigObfuscated,
                subjectKey: subjectKey
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
        isConfigObfuscated: Bool,
        subjectKey: String
    ) -> Bool {
        // attribute names are hashed if obfuscated
        let attributeKey = condition.attribute
        var attributeValue: EppoValue?
        
        // First check if the attribute exists in subject attributes
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
        
        // If not found in attributes and the attribute is "id", use the subject key
        if attributeValue == nil {
            if !isConfigObfuscated && attributeKey == "id" {
                attributeValue = EppoValue.valueOf(subjectKey)
            } else if isConfigObfuscated && attributeKey == getMD5Hex("id") {
                attributeValue = EppoValue.valueOf(subjectKey)
            }
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
