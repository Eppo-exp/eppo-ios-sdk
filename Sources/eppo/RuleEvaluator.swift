import Foundation
import Semver

typealias ConditionFunc = (Double, Double) -> Bool;

class Compare {
    public static func compareNumber(_ a: Double, _ b: Double, _ conditionFunc: ConditionFunc) -> Bool {
        return conditionFunc(a, b);
    }

    public static func compareRegex(_ a: String, _ pattern: String) -> Bool {
        return a.range(of: pattern, options:.regularExpression) != nil;
    }

    public static func isOneOf(_ a: String, _ values: [String]) -> Bool {
        return values.map({ $0.lowercased() })
                     .contains(a.lowercased());
    }
}

public class RuleEvaluator {
    enum Errors : Error {
        case UnexpectedValue
    }

    static func findMatchingRule(
        _ subjectAttributes: SubjectAttributes,
        _ rules: [TargetingRule]) throws -> TargetingRule?
    {
        for rule in rules {
            if try matchesRule(subjectAttributes, rule) {
                return rule;
            }
        }
        
        return nil;
    }
    
    static func matchesRule(
        _ subjectAttributes: SubjectAttributes,
        _ rule: TargetingRule) throws -> Bool
    {
        let conditionEvaluations = try evaluateRuleConditions(subjectAttributes, rule.conditions);
        return !conditionEvaluations.contains(false);
    }
    
    static func evaluateCondition(
        _ subjectAttributes: SubjectAttributes,
        _ condition: TargetingCondition
    ) throws -> Bool
    {
        guard let value = subjectAttributes[condition.attribute] else {
           return false
        }
        
        do {
            let comparisonResult: Bool
            switch condition.targetingOperator {
            case .GreaterThanEqualTo, .GreaterThan, .LessThanEqualTo, .LessThan:
                do {
                    let valueStr = try value.stringValue()
                    let conditionValueStr = try condition.value.stringValue()
                    if let valueVersion = Semver(valueStr), let conditionVersion = Semver(conditionValueStr) {
                        // If both strings are valid Semver strings, perform a Semver comparison
                        switch condition.targetingOperator {
                        case .GreaterThanEqualTo:
                            comparisonResult = valueVersion >= conditionVersion
                        case .GreaterThan:
                            comparisonResult = valueVersion > conditionVersion
                        case .LessThanEqualTo:
                            comparisonResult = valueVersion <= conditionVersion
                        case .LessThan:
                            comparisonResult = valueVersion < conditionVersion
                        default:
                            throw Errors.UnexpectedValue
                        }
                    } else {
                        // If either string is not a valid Semver, fall back to double comparison
                        let valueDouble = try value.doubleValue()
                        let conditionDouble = try condition.value.doubleValue()
                        switch condition.targetingOperator {
                        case .GreaterThanEqualTo:
                            comparisonResult = valueDouble >= conditionDouble
                        case .GreaterThan:
                            comparisonResult = valueDouble > conditionDouble
                        case .LessThanEqualTo:
                            comparisonResult = valueDouble <= conditionDouble
                        case .LessThan:
                            comparisonResult = valueDouble < conditionDouble
                        default:
                            throw Errors.UnexpectedValue
                        }
                    }
                } catch {
                    // If stringValue() or doubleValue() throws, or Semver creation fails
                    return false
                }
            case .Matches:
                comparisonResult = try Compare.compareRegex(
                    value.stringValue(),
                    condition.value.stringValue()
                )
            case .OneOf:
                comparisonResult = try Compare.isOneOf(
                    value.stringValue(),
                    condition.value.arrayValue()
                )
            case .NotOneOf:
                comparisonResult = try !Compare.isOneOf(
                    value.stringValue(),
                    condition.value.arrayValue()
                )
            default:
                throw Errors.UnexpectedValue
            }
            return comparisonResult
        } catch {
            // Handle or log the error
            return false
        }
    }
    
    static func evaluateRuleConditions(
        _ subjectAttributes: SubjectAttributes,
        _ conditions: [TargetingCondition]
    ) throws -> [Bool]
    {
        var evaluations = [Bool]();
        for condition in conditions {
            try evaluations.append(evaluateCondition(subjectAttributes, condition));
        }
        
        return evaluations;
    }
}
