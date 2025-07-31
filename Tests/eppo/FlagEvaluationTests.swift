import XCTest
@testable import EppoFlagging

final class FlagEvaluationTests: XCTestCase {
    
    func testExtraLoggingUnobfuscation() {
        // Test that extraLogging is properly unobfuscated when config is obfuscated
        let obfuscatedExtraLogging = [
            "aG9sZG91dEtleQ==": "c2hvcnQtdGVybS1ob2xkb3V0",  // "holdoutKey": "short-term-holdout"
            "aG9sZG91dFZhcmlhdGlvbg==": "c3RhdHVzX3F1bw=="  // "holdoutVariation": "status_quo"
        ]
        
        let flagEvaluation = FlagEvaluation.matchedResult(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: SubjectAttributes(),
            allocationKey: "test-allocation",
            variation: nil,
            variationType: nil,
            extraLogging: obfuscatedExtraLogging,
            doLog: true,
            isConfigObfuscated: true
        )
        
        XCTAssertEqual(flagEvaluation.extraLogging, [
            "holdoutKey": "short-term-holdout",
            "holdoutVariation": "status_quo"
        ])
    }
    
    func testExtraLoggingNoUnobfuscationWhenNotObfuscated() {
        // Test that extraLogging is not modified when config is not obfuscated
        let normalExtraLogging = [
            "holdoutKey": "short-term-holdout",
            "holdoutVariation": "status_quo"
        ]
        
        let flagEvaluation = FlagEvaluation.matchedResult(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: SubjectAttributes(),
            allocationKey: "test-allocation",
            variation: nil,
            variationType: nil,
            extraLogging: normalExtraLogging,
            doLog: true,
            isConfigObfuscated: false
        )
        
        XCTAssertEqual(flagEvaluation.extraLogging, normalExtraLogging)
    }
    
    func testExtraLoggingMixedObfuscation() {
        // Test that mixed obfuscated and non-obfuscated values are handled correctly
        let mixedExtraLogging = [
            "aG9sZG91dEtleQ==": "c2hvcnQtdGVybS1ob2xkb3V0",  // obfuscated key and value
            "normalKey": "normalValue",                       // non-obfuscated
            "obfuscatedKey": "bm9ybWFsVmFsdWU="              // obfuscated value only
        ]
        
        let flagEvaluation = FlagEvaluation.matchedResult(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: SubjectAttributes(),
            allocationKey: "test-allocation",
            variation: nil,
            variationType: nil,
            extraLogging: mixedExtraLogging,
            doLog: true,
            isConfigObfuscated: true
        )
        
        // Only valid base64 entries should remain (non-obfuscated entries are skipped)
        XCTAssertEqual(flagEvaluation.extraLogging, [
            "holdoutKey": "short-term-holdout"
        ])
    }
    
    func testExtraLoggingEmptyDictionary() {
        // Test that empty extraLogging is handled correctly
        let emptyExtraLogging: [String: String] = [:]
        
        let flagEvaluation = FlagEvaluation.matchedResult(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: SubjectAttributes(),
            allocationKey: "test-allocation",
            variation: nil,
            variationType: nil,
            extraLogging: emptyExtraLogging,
            doLog: true,
            isConfigObfuscated: true
        )
        
        XCTAssertEqual(flagEvaluation.extraLogging, [:])
    }
    
    func testExtraLoggingInvalidBase64() {
        // Test that invalid base64 strings are handled gracefully by being skipped
        let invalidExtraLogging = [
            "invalid-base64-key": "invalid-base64-value",
            "aG9sZG91dEtleQ==": "invalid-base64-value",  // valid key, invalid value
            "another-invalid-key": "c2hvcnQtdGVybS1ob2xkb3V0"  // invalid key, valid value
        ]
        
        let flagEvaluation = FlagEvaluation.matchedResult(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: SubjectAttributes(),
            allocationKey: "test-allocation",
            variation: nil,
            variationType: nil,
            extraLogging: invalidExtraLogging,
            doLog: true,
            isConfigObfuscated: true
        )
        
        // Invalid entries should be skipped, only valid ones should remain
        XCTAssertEqual(flagEvaluation.extraLogging, [:])
    }
    
    func testExtraLoggingPartialFailures() {
        // Test that some entries can be decoded while others fail
        let mixedExtraLogging = [
            "aG9sZG91dEtleQ==": "c2hvcnQtdGVybS1ob2xkb3V0",  // valid key and value
            "invalid-key": "invalid-value",                   // invalid key and value
            "aG9sZG91dFZhcmlhdGlvbg==": "c3RhdHVzX3F1bw=="  // valid key and value
        ]
        
        let flagEvaluation = FlagEvaluation.matchedResult(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: SubjectAttributes(),
            allocationKey: "test-allocation",
            variation: nil,
            variationType: nil,
            extraLogging: mixedExtraLogging,
            doLog: true,
            isConfigObfuscated: true
        )
        
        // Only valid entries should remain
        XCTAssertEqual(flagEvaluation.extraLogging, [
            "holdoutKey": "short-term-holdout",
            "holdoutVariation": "status_quo"
        ])
    }
} 