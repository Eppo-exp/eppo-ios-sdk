import Foundation

typealias ConditionFunc = (Int64, Int64) -> Bool;

class Compare {
    public static func compareNumber(_ a: Int64, _ b: Int64, _ conditionFunc: ConditionFunc) -> Bool {
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
        if let value = subjectAttributes[condition.attribute] {
            let operatorValue = OperatorType(rawValue: condition.targetingOperator);
            do {
                switch operatorValue {
                    case .GreaterThanEqualTo:
                        return try Compare.compareNumber(
                            value.longValue(),
                            condition.value.longValue(),
                            { (a: Int64, b: Int64) in return a >= b }
                        );
                    case .GreaterThan:
                        return try Compare.compareNumber(
                            value.longValue(),
                            condition.value.longValue(),
                            { (a: Int64, b: Int64) in return a > b }
                        )
                    case .LessThanEqualTo:
                        return try Compare.compareNumber(
                            value.longValue(),
                            condition.value.longValue(),
                            { (a: Int64, b: Int64) in return a <= b }
                        )
                    case .LessThan:
                        return try Compare.compareNumber(
                            value.longValue(),
                            condition.value.longValue(),
                            { (a: Int64, b: Int64) in return a < b }
                        )
                    case .Matches:
                        return try Compare.compareRegex(
                            value.stringValue(),
                            condition.value.stringValue()
                        )
                    case .OneOf:
                        return try Compare.isOneOf(
                            value.stringValue(),
                            condition.value.arrayValue()
                        )
                    case .NotOneOf:
                        return try !Compare.isOneOf(
                            value.stringValue(),
                            condition.value.arrayValue()
                        )
                    default:
                        throw Errors.UnexpectedValue
                }
            } catch {
                return false;
            }
        }
        
        return false;
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
