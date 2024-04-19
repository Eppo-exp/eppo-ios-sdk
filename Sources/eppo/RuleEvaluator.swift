import Foundation
import Semver

typealias ConditionFunc = (Double, Double) -> Bool;

class Compare {
    public static func matchesRegex(_ a: String, _ pattern: String) -> Bool {
        return a.range(of: pattern, options:.regularExpression) != nil;
    }
    
    public static func isOneOf(_ a: String, _ values: [String]) -> Bool {
        // the comparison is case-sensitive
        return values.contains(a);
    }
}

struct FlagEvaluation {
    let flagKey: String
    let subjectKey: String
    let subjectAttributes: SubjectAttributes
    let allocationKey: Optional<String>
    let variation: Optional<UFC_Variation>
    let variationType: [UFC_VariationType]
    let extraLogging: [String: String]
    let doLog: Bool
    
    static func matchedResult(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        allocationKey: Optional<String>,
        variation: Optional<UFC_Variation>,
        variationType: [UFC_VariationType],
        extraLogging: [String: String],
        doLog: Bool
    ) -> FlagEvaluation {
        return FlagEvaluation(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: allocationKey,
            variation: variation,
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
            variationType: [],
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
    
    enum Errors : Error {
        case UnexpectedValue
    }
    
    func evaluateFlag(
        flag: UFC_Flag,
        subjectKey: String,
        subjectAttributes: SubjectAttributes
    ) -> FlagEvaluation {
        if (!flag.enabled) {
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
            if matchesRules(subjectAttributes: subjectAttributesWithID, rules: allocation.rules ?? []) {
                // Split needs to match all shards
                for split in allocation.splits {
                    let allShardsMatch = split.shards.allSatisfy { shard in
                        matchesShard(shard: shard, subjectKey: subjectKey, totalShards: flag.totalShards)
                    }
                    if allShardsMatch {
                        return FlagEvaluation.matchedResult(
                            flagKey: flag.key,
                            subjectKey: subjectKey,
                            subjectAttributes: subjectAttributes,
                            allocationKey: Optional<String>.some(allocation.key),
                            variation: flag.variations[split.variationKey],
                            variationType: [flag.variationType],
                            extraLogging: split.extraLogging ?? [:],
                            doLog: allocation.doLog
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
        totalShards: Int
    ) -> Bool {
        assert(totalShards > 0, "Expect totalShards to be strictly positive")
        let h = self.sharder.getShard(input: hashKey(salt: shard.salt, subjectKey: subjectKey), totalShards: totalShards)
        return shard.ranges.contains { range in
            isInShardRange(shard: h, range: range)
        }
    }
    
    private func matchesRules(
        subjectAttributes: SubjectAttributes,
        rules: [UFC_Rule]
    ) -> Bool {
        if rules.isEmpty {
            return true
        }
        
        // If any rule matches, return true.
        return rules.contains { rule in
            return matchesRule(subjectAttributes: subjectAttributes, rule: rule)
        }
    }
    
    private func matchesRule(
        subjectAttributes: SubjectAttributes,
        rule: UFC_Rule) -> Bool
    {
        // Check that all conditions within the rule are met
        return rule.conditions.allSatisfy { condition in
            // If the condition throws an error, consider this not matching.
            return (try? evaluateCondition(subjectAttributes: subjectAttributes, condition: condition)) ?? false
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
        condition: UFC_TargetingRuleCondition
    ) throws -> Bool
    {
        
        let attributeValue: EppoValue? = subjectAttributes[condition.attribute]
        
        // First we do any NULL check
        let attributeValueIsNull = attributeValue?.isNull() ?? true
        if condition.operator == .isNull {
            let expectNull: Bool = try condition.value.getBoolValue()
            return expectNull == attributeValueIsNull
        } else if attributeValueIsNull {
            // Any check other than IS NULL should fail if the attribute value is null
            return false
        }

        // Safely unwrap attributeValue for further use
        guard let value = attributeValue else {
            // Handle the nil case, perhaps throw an error or return a default value
            return false
        }

        // Safely unwrap attributeValue for further use
        guard let value = attributeValue else {
            // Handle the nil case, perhaps throw an error or return a default value
            return false
        }

        do {
            switch condition.operator {
            case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
                do {
                    let valueStr = try? value.getStringValue()
                    let conditionValueStr = try? condition.value.getStringValue()
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
                            throw Errors.UnexpectedValue
                        }
                    } else {
                        // If either string is not a valid Semver, fall back to double comparison
                        let valueDouble = try value.getDoubleValue()
                        let conditionDouble = try condition.value.getDoubleValue()
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
                            throw Errors.UnexpectedValue
                        }
                    }
                } catch let e {
                    // If stringValue() or doubleValue() throws, or Semver creation fails
                    return false
                }
            case .matches:
                return try Compare.matchesRegex(
                    value.getStringValue(),
                    condition.value.getStringValue()
                )
            case .oneOf:
                return try Compare.isOneOf(
                    value.getStringValue(),
                    condition.value.getStringArrayValue()
                )
            case .notOneOf:
                return try !Compare.isOneOf(
                    value.getStringValue(),
                    condition.value.getStringArrayValue()
                )
            default:
                return false;
            }
        } catch {
            // Handle or log the error
            return false
        }
    }
}
