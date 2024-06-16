import XCTest

@testable import eppo_flagging

final class flagEvaluationTests: XCTestCase {
    public func testNoneResult() {
        let flagEvaluation = FlagEvaluation.noneResult(
            flagKey: "test",
            subjectKey: "test",
            subjectAttributes: SubjectAttributes()
        );
        XCTAssertEqual(flagEvaluation.flagKey, "test");
        XCTAssertEqual(flagEvaluation.subjectKey, "test");
        XCTAssertEqual(flagEvaluation.subjectAttributes, SubjectAttributes());
        XCTAssertNil(flagEvaluation.allocationKey);
        XCTAssertNil(flagEvaluation.variation);
        XCTAssertEqual(flagEvaluation.extraLogging, [:]);
        XCTAssertFalse(flagEvaluation.doLog);
    }
}

final class flagEvaluatorTests: XCTestCase {
    var flagEvaluator: FlagEvaluator!

    let baseFlag = UFC_Flag(
        key: "test",
        enabled: true,
        variationType: UFC_VariationType.string,
        variations: [:],
        allocations: [],
        totalShards: 100
    );
    
    override func setUpWithError() throws {
        try super.setUpWithError()

        let lookup = ["subject_key": 50]
        let sharder = DeterministicSharder(lookup: lookup)
        flagEvaluator = FlagEvaluator(sharder: sharder)
    }

    public func testDisabledFlag() {
        let flag = createFlag(flag: baseFlag, rules: [], enabled: false);
        let flagEvaluation = flagEvaluator.evaluateFlag(
            flag: flag,
            subjectKey: "subject_key",
            subjectAttributes: SubjectAttributes(),
            isConfigObfuscated: false
        );

        XCTAssertFalse(flagEvaluation.doLog)
        XCTAssertNil(flagEvaluation.variation)
    }

    public func testMatchesAnyRuleWithEmptyConditions() throws {
        let targetingRuleWithEmptyConditions: UFC_Rule = UFC_Rule(conditions: []);
        let targetingRules: [UFC_Rule] = [targetingRuleWithEmptyConditions];
        let testFlag = createFlag(flag: baseFlag, rules: targetingRules);
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["name"] = EppoValue.valueOf("test");

        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertTrue(evaluationResult.doLog)
        XCTAssertEqual(try evaluationResult.variation?.value.getStringValue(), "Control")
    }
    
    public func testMatchesAnyRuleWithEmptyRules() throws {
        let targetingRules: [UFC_Rule] = [];
        let testFlag = createFlag(flag: baseFlag, rules: targetingRules);

        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["name"] = EppoValue.valueOf("test");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertTrue(evaluationResult.doLog)
        XCTAssertEqual(try evaluationResult.variation?.value.getStringValue(), "Control")
    }
    
    public func testMatchesAnyRuleWhenNoRuleMatches() throws {
        let targetingRule: UFC_Rule = UFC_Rule(conditions: self.getNumericConditions());
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);

        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["price"] = EppoValue.valueOf("30");

        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertFalse(evaluationResult.doLog)
        XCTAssertNil(evaluationResult.variation)
    }

    public func testMatchesAnyRuleWhenRuleMatches() throws {
        let targetingRule = UFC_Rule(conditions: self.getNumericConditions() + self.getSemVerConditions());
        let targetingRules = [targetingRule];
        let testFlag = createFlag(flag: baseFlag, rules: targetingRules);

        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["price"] = EppoValue.valueOf(15);
        subjectAttributes["appVersion"] = EppoValue.valueOf("2.3.5");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertTrue(evaluationResult.doLog)
        XCTAssertEqual(try evaluationResult.variation?.value.getStringValue(), "Control")
    }
    
    public func testNotMatchesAnyRuleWhenThrowInvalidSubjectAttribute() {
        let targetingRule = UFC_Rule(conditions: self.getNumericConditions());
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);

        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["price"] = EppoValue.valueOf("abcd");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertFalse(evaluationResult.doLog)
        XCTAssertNil(evaluationResult.variation)
    }
    
    public func testMatchesAnyRuleWithRegexCondition() throws {
        let targetingRule = UFC_Rule(conditions: [self.getRegexCondition()]);
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["match"] = EppoValue.valueOf("abcd");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertTrue(evaluationResult.doLog)
        XCTAssertEqual(try evaluationResult.variation?.value.getStringValue(), "Control")
    }

    public func testMatchesAnyRuleWithRegexConditionNotMatched() throws {
        let targetingRule = UFC_Rule(conditions: [self.getRegexCondition()]);
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["match"] = EppoValue.valueOf("123");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertFalse(evaluationResult.doLog)
        XCTAssertNil(evaluationResult.variation)
    }

    public func testMatchesAnyRuleWithNotOneOfRule() throws {
        let targetingRule = UFC_Rule(conditions: [self.getNotOneOfCondition()]);
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["oneOf"] = EppoValue.valueOf("value3");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertTrue(evaluationResult.doLog)
        XCTAssertEqual(try evaluationResult.variation?.value.getStringValue(), "Control")
    }
    
    public func testMatchesAnyRuleWithNotOneOfRuleNotPassed() {
        let targetingRule = UFC_Rule(conditions: [self.getNotOneOfCondition()]);
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["oneOf"] = EppoValue.valueOf("value1");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertFalse(evaluationResult.doLog)
        XCTAssertNil(evaluationResult.variation)
    }
    
    public func testMatchesInvalidSemVer() {
        let targetingRule = UFC_Rule(conditions: [self.getInvalidSemVerConditions()]);
        let testFlag = createFlag(flag: baseFlag, rules: [targetingRule]);
        
        var subjectAttributes: SubjectAttributes = SubjectAttributes();
        subjectAttributes["appVersion"] = EppoValue.valueOf("2.3.5");
        
        let evaluationResult = flagEvaluator.evaluateFlag(
            flag: testFlag,
            subjectKey: "subject_key",
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: false
        );
        XCTAssertFalse(evaluationResult.doLog)
        XCTAssertNil(evaluationResult.variation)
    }

    private func getNumericConditions() -> [UFC_TargetingRuleCondition] {
        let condition1 = UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.greaterThanEqual,
            attribute: "price",
            value: EppoValue.valueOf(10)
        );
        
        let condition2 = UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.lessThanEqual,
            attribute: "price",
            value: EppoValue.valueOf(20)
        );
        
        return [condition1, condition2];
    }
    
    private func getSemVerConditions() -> [UFC_TargetingRuleCondition] {
        let condition1 = UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.greaterThanEqual,
            attribute: "appVersion",
            value: EppoValue.valueOf("2.0.0")
        );
        
        let condition2 = UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.lessThanEqual,
            attribute: "appVersion",
            value: EppoValue.valueOf("3.5.0")
        );
        
        return [condition1, condition2];
    }
    
    private func getInvalidSemVerConditions() -> UFC_TargetingRuleCondition {
        return UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.greaterThanEqual,
            attribute: "appVersion",
            value: EppoValue.valueOf("xyz.2.0.0")
        );
    }
    
    private func getRegexCondition() -> UFC_TargetingRuleCondition {
        return UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.matches,
            attribute: "match",
            value: EppoValue.valueOf("[a-z]+")
        );
    }
    
    private func getNotOneOfCondition() -> UFC_TargetingRuleCondition {
        return UFC_TargetingRuleCondition(
            operator: UFC_RuleConditionOperator.notOneOf,
            attribute: "oneOf", // one of or not one off??
            value: EppoValue.valueOf(["value1", "value2"])
        );
    }

    private func createFlag(flag: UFC_Flag, rules: [UFC_Rule], enabled: Bool = true) -> UFC_Flag {
        return UFC_Flag(
            key: flag.key,
            enabled: enabled,
            variationType: flag.variationType,
            variations: [
                "control": UFC_Variation(
                    key: "control", 
                    value: EppoValue(value: "Control")
                )
            ],
            allocations: [
                UFC_Allocation(
                    key: "test",
                    rules: rules,
                    startAt: nil,
                    endAt: nil,
                    splits: [
                        UFC_Split(
                            variationKey: "control",
                            shards: [
                                UFC_Shard(
                                    salt: "salt",
                                    ranges: [
                                        UFC_Range(start: 0, end: 50),
                                        UFC_Range(start: 50, end: 100)
                                    ]
                                )
                            ],
                            extraLogging: nil)
                    ],
                    doLog: true
                )
            ],
            totalShards: flag.totalShards
        );
    }

}
