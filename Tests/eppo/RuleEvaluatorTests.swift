import XCTest

@testable import eppo_flagging

final class ruleEvaluatorTests: XCTestCase {
    public func testMatchesAnyRuleWithEmptyConditions() throws {
        let targetingRuleWithEmptyConditions: TargetingRule = self.createRule([]);
        let targetingRules: [TargetingRule] = [targetingRuleWithEmptyConditions];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["name"] = EppoValue.valueOf("test");

        XCTAssertEqual(
            targetingRuleWithEmptyConditions,
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        );
    }
    
    public func testMatchesAnyRuleWithEmptyRules() throws {
        let targetingRules: [TargetingRule] = [];
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["name"] = EppoValue.valueOf("test");
        
        XCTAssertNil(try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules));
    }
    
    public func testMatchesAnyRuleWhenNoRuleMatches() throws {
        let targetingRules: [TargetingRule] = [];
        var targetingRule: TargetingRule = self.createRule([]);
        targetingRule.conditions.append(contentsOf: self.getNumericConditions());
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["price"] = EppoValue.valueOf("30");
        
        XCTAssertNil(try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules));
    }

    public func testMatchesAnyRuleWhenRuleMatches() throws {
        var targetingRule: TargetingRule = TargetingRule();
        targetingRule.conditions.append(contentsOf: self.getNumericConditions());
        let targetingRules: [TargetingRule] = [targetingRule];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["price"] = EppoValue.valueOf(15);
        
        XCTAssertEqual(
            targetingRule,
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        );
    }

    public func testMatchesAnyRuleWhenThrowInvalidSubjectAttribute() {
        var targetingRule: TargetingRule = self.createRule([]);
        targetingRule.conditions.append(contentsOf: self.getNumericConditions());
        let targetingRules: [TargetingRule] = [targetingRule];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["price"] = EppoValue.valueOf("abcd");
        
        XCTAssertNil(
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        );
    }
    
    public func testMatchesAnyRuleWithRegexCondition() throws {
        var targetingRule: TargetingRule = self.createRule([]);
        targetingRule.conditions.append(getRegexCondition());
        let targetingRules: [TargetingRule] = [targetingRule];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["match"] = EppoValue.valueOf("abcd");
        
        XCTAssertEqual(
            targetingRule,
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        )
    }

    public func testMatchesAnyRuleWithRegexConditionNotMatched() throws {
        var targetingRule: TargetingRule = self.createRule([]);
        targetingRule.conditions.append(self.getRegexCondition());
        let targetingRules: [TargetingRule] = [targetingRule];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["match"] = EppoValue.valueOf("123");
        
        XCTAssertNil(
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        );
    }

    public func testMatchesAnyRuleWithNotOneOfRule() throws {
        var targetingRule: TargetingRule = self.createRule([]);
        targetingRule.conditions.append(self.getNotOneOfCondition());
        let targetingRules: [TargetingRule] = [targetingRule];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["oneOf"] = EppoValue.valueOf("value3");
        
        XCTAssertEqual(
            targetingRule,
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        );
    }
    
    public func testMatchesAnyRuleWithNotOneOfRuleNotPassed() {
        var targetingRule: TargetingRule = TargetingRule();
        targetingRule.conditions.append(self.getNotOneOfCondition());
        let targetingRules: [TargetingRule] = [targetingRule];
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["oneOf"] = EppoValue.valueOf("value1");
        
        XCTAssertNil(
            try RuleEvaluator.findMatchingRule(subjectAttributes, targetingRules)
        );
    }

    private func createRule(_ conditions: [TargetingCondition]) -> TargetingRule {
        var targetingRule: TargetingRule = TargetingRule();
        targetingRule.conditions = conditions;
        return targetingRule;
    }

    private func getNumericConditions() -> [TargetingCondition] {
        var condition1: TargetingCondition = TargetingCondition();
        condition1.value = EppoValue.valueOf(10);
        condition1.attribute = "price";
        condition1.targetingOperator = OperatorType.GreaterThanEqualTo;
        
        var condition2: TargetingCondition = TargetingCondition();
        condition2.value = EppoValue.valueOf(20);
        condition2.attribute = "price";
        condition2.targetingOperator = OperatorType.LessThanEqualTo;
        
        return [condition1, condition2];
    }
    
    private func getRegexCondition() -> TargetingCondition {
        var condition: TargetingCondition = TargetingCondition();
        condition.value = EppoValue.valueOf("[a-z]+");
        condition.attribute = "match";
        condition.targetingOperator = OperatorType.Matches;
        
        return condition;
    }
    
    private func getNotOneOfCondition() -> TargetingCondition {
        var condition: TargetingCondition = TargetingCondition();
        let values: [String] = ["value1", "value2"];
        
        condition.value = EppoValue.valueOf(values);
        condition.attribute = "oneOf";
        condition.targetingOperator = OperatorType.NotOneOf;
        
        return condition;
    }
}
