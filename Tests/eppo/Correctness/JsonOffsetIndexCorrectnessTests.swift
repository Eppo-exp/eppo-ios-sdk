import XCTest
@testable import EppoFlagging
import Foundation

/**
 * Correctness Tests for JsonOffsetIndexClient
 *
 * Validates that the offset indexing approach produces identical results
 * to the standard JSON evaluator across all test cases and flag types.
 */
final class JsonOffsetIndexCorrectnessTests: XCTestCase {

    func testJsonOffsetIndexVsStandardJsonCorrectness() throws {
        NSLog("🧪 Starting JsonOffsetIndex vs Standard JSON correctness validation...")

        // Load JSON test data
        let jsonData = try loadJSONData()

        // Create both evaluators
        let standardConfiguration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let standardClient = EppoClient.initializeOffline(
            sdkKey: "standard-json-test-key",
            assignmentLogger: nil,
            initialConfiguration: standardConfiguration
        )

        let offsetIndexClient = try JsonOffsetIndexClient(
            sdkKey: "offset-index-test-key",
            jsonData: jsonData,
            obfuscated: false,
            assignmentLogger: nil
        )

        // Get all test cases
        let testFiles = try getTestFiles()
        var totalTests = 0
        var passedTests = 0

        NSLog("📊 Testing against %d test case files...", testFiles.count)

        for testFile in testFiles {
            let testCase = try loadTestCase(from: testFile)
            let fileName = URL(fileURLWithPath: testFile).lastPathComponent

            NSLog("🎯 Testing file: %@ (flag: %@, type: %@)", fileName, testCase.flag, testCase.variationType)

            for subject in testCase.subjects {
                totalTests += 1

                // Convert subject attributes to EppoValue
                let subjectAttributes = subject.subjectAttributes.mapValues { value in
                    switch value.value {
                    case let string as String:
                        return EppoValue.valueOf(string)
                    case let int as Int:
                        return EppoValue.valueOf(int)
                    case let double as Double:
                        return EppoValue.valueOf(double)
                    case let bool as Bool:
                        return EppoValue.valueOf(bool)
                    case is NSNull:
                        return EppoValue.nullValue()
                    default:
                        return EppoValue.nullValue()
                    }
                }

                // Test each assignment type based on variation type
                switch testCase.variationType {
                case "BOOLEAN":
                    let defaultValue = (testCase.defaultValue.value as? Bool) ?? false
                    let standardResult = standardClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let offsetResult = offsetIndexClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )

                    if standardResult == offsetResult {
                        passedTests += 1
                    } else {
                        NSLog("❌ BOOLEAN mismatch for flag %@ subject %@: standard=%@ offset=%@",
                              testCase.flag, subject.subjectKey,
                              standardResult ? "true" : "false",
                              offsetResult ? "true" : "false")
                    }

                case "STRING":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let standardResult = standardClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let offsetResult = offsetIndexClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )

                    if standardResult == offsetResult {
                        passedTests += 1
                    } else {
                        NSLog("❌ STRING mismatch for flag %@ subject %@: standard=%@ offset=%@",
                              testCase.flag, subject.subjectKey, standardResult, offsetResult)
                    }

                case "NUMERIC":
                    let defaultValue = (testCase.defaultValue.value as? Double) ?? 0.0
                    let standardResult = standardClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let offsetResult = offsetIndexClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )

                    if abs(standardResult - offsetResult) < 0.0001 {
                        passedTests += 1
                    } else {
                        NSLog("❌ NUMERIC mismatch for flag %@ subject %@: standard=%f offset=%f",
                              testCase.flag, subject.subjectKey, standardResult, offsetResult)
                    }

                case "INTEGER":
                    let defaultValue = (testCase.defaultValue.value as? Int) ?? 0
                    let standardResult = standardClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let offsetResult = offsetIndexClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )

                    if standardResult == offsetResult {
                        passedTests += 1
                    } else {
                        NSLog("❌ INTEGER mismatch for flag %@ subject %@: standard=%d offset=%d",
                              testCase.flag, subject.subjectKey, standardResult, offsetResult)
                    }

                case "JSON":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let standardResult = standardClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let offsetResult = offsetIndexClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )

                    if standardResult == offsetResult {
                        passedTests += 1
                    } else {
                        NSLog("❌ JSON mismatch for flag %@ subject %@: standard=%@ offset=%@",
                              testCase.flag, subject.subjectKey, standardResult, offsetResult)
                    }

                default:
                    NSLog("⚠️ Unknown variation type: %@", testCase.variationType)
                    continue
                }
            }
        }

        // Report results
        NSLog("🏆 JsonOffsetIndex Correctness Results:")
        NSLog("   ✅ Passed: %d/%d tests (%.2f%%)", passedTests, totalTests, Double(passedTests)/Double(totalTests)*100)

        if passedTests == totalTests {
            NSLog("🎉 ALL TESTS PASSED! JsonOffsetIndex produces identical results to standard JSON evaluator")
        } else {
            NSLog("❌ %d tests failed - offset indexing has correctness issues", totalTests - passedTests)
        }

        // Assert 100% correctness
        XCTAssertEqual(passedTests, totalTests, "JsonOffsetIndexClient must produce identical results to standard JSON evaluator")
    }

    func testOffsetIndexCacheEffectiveness() throws {
        NSLog("🧪 Testing JsonOffsetIndex cache effectiveness...")

        let jsonData = try loadJSONData()
        let offsetIndexClient = try JsonOffsetIndexClient(
            sdkKey: "cache-test-key",
            jsonData: jsonData,
            obfuscated: false,
            assignmentLogger: nil
        )

        // Test repeated access to same flag should be faster (cached)
        let testAttributes: SubjectAttributes = ["country": EppoValue.valueOf("US")]

        // First access (should trigger parsing and caching)
        let firstStart = CFAbsoluteTimeGetCurrent()
        _ = offsetIndexClient.getBooleanAssignment(
            flagKey: "boolean-flag",
            subjectKey: "test-subject",
            subjectAttributes: testAttributes,
            defaultValue: false
        )
        let firstTime = (CFAbsoluteTimeGetCurrent() - firstStart) * 1000

        // Second access (should use cache)
        let secondStart = CFAbsoluteTimeGetCurrent()
        _ = offsetIndexClient.getBooleanAssignment(
            flagKey: "boolean-flag",
            subjectKey: "test-subject",
            subjectAttributes: testAttributes,
            defaultValue: false
        )
        let secondTime = (CFAbsoluteTimeGetCurrent() - secondStart) * 1000

        NSLog("📊 Cache performance: First access: %.3fms, Second access: %.3fms", firstTime, secondTime)
        NSLog("🚀 Cache speedup: %.1fx faster", firstTime / secondTime)

        // Second access should be significantly faster due to caching
        XCTAssertLessThan(secondTime, firstTime, "Cached access should be faster than initial parsing")
    }

    // MARK: - Helper Methods

    private func loadJSONData() throws -> Data {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-10000.json",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-10000.json")
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing JSON test data"])
        }
        return try Data(contentsOf: fileURL)
    }

    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(UFCTestCase.self, from: data)
    }
}