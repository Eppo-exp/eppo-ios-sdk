import XCTest
@testable import EppoFlagging
import Foundation
import SwiftProtobuf

/**
 * NativeProtobufCorrectnessTests verifies that the Native Protobuf evaluator and Swift Struct evaluator produce identical results.
 * This ensures that working directly with protobuf types produces the same assignments as converting to Swift structs first.
 */
final class NativeProtobufCorrectnessTests: XCTestCase {
    var nativeProtobufClient: NativeProtobufClient!
    var swiftStructClient: SwiftStructFromProtobufClient!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Load protobuf data
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.pb",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-v1.pb")
            return
        }
        let protobufData = try Data(contentsOf: fileURL)

        // Create both clients with same data - lazy mode for fair comparison
        nativeProtobufClient = try NativeProtobufClient(
            sdkKey: "native-protobuf-test-key",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: false
        )

        swiftStructClient = try SwiftStructFromProtobufClient(
            sdkKey: "swift-struct-test-key",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: false
        )
    }

    override func tearDownWithError() throws {
        nativeProtobufClient = nil
        swiftStructClient = nil
        try super.tearDownWithError()
    }

    func testNativeProtobufVsSwiftStructCorrectness() throws {
        print("🔍 Testing Native Protobuf vs Swift Struct correctness...")

        // Get all test case files
        let testFiles = try getTestFiles()
        var totalComparisons = 0
        var successfulComparisons = 0

        for testFile in testFiles {
            let testCase = try loadTestCase(from: testFile)

            for subject in testCase.subjects {
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

                // Get assignments from both evaluators based on variation type
                let comparisonResult: Bool
                switch testCase.variationType {
                case "BOOLEAN":
                    let defaultValue = (testCase.defaultValue.value as? Bool) ?? false
                    let nativeResult = nativeProtobufClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let swiftStructResult = swiftStructClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nativeResult == swiftStructResult)

                    if !comparisonResult {
                        print("❌ BOOLEAN mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': native=\(nativeResult), swiftStruct=\(swiftStructResult)")
                    }

                case "NUMERIC":
                    let defaultValue = (testCase.defaultValue.value as? Double) ?? 0.0
                    let nativeResult = nativeProtobufClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let swiftStructResult = swiftStructClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nativeResult == swiftStructResult)

                    if !comparisonResult {
                        print("❌ NUMERIC mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': native=\(nativeResult), swiftStruct=\(swiftStructResult)")
                    }

                case "INTEGER":
                    let defaultValue = (testCase.defaultValue.value as? Int) ?? 0
                    let nativeResult = nativeProtobufClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let swiftStructResult = swiftStructClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nativeResult == swiftStructResult)

                    if !comparisonResult {
                        print("❌ INTEGER mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': native=\(nativeResult), swiftStruct=\(swiftStructResult)")
                    }

                case "STRING":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let nativeResult = nativeProtobufClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let swiftStructResult = swiftStructClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nativeResult == swiftStructResult)

                    if !comparisonResult {
                        print("❌ STRING mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': native='\(nativeResult)', swiftStruct='\(swiftStructResult)'")
                    }

                case "JSON":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let nativeResult = nativeProtobufClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let swiftStructResult = swiftStructClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )

                    // Normalize JSON strings for comparison
                    func normalizeJSON(_ jsonString: String) -> String {
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data),
                              let normalizedData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
                            return jsonString
                        }
                        return String(data: normalizedData, encoding: .utf8) ?? jsonString
                    }
                    comparisonResult = (normalizeJSON(nativeResult) == normalizeJSON(swiftStructResult))

                    if !comparisonResult {
                        print("❌ JSON mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)':")
                        print("   native: '\(nativeResult)'")
                        print("   swiftStruct: '\(swiftStructResult)'")
                    }

                default:
                    print("⚠️ Unknown variation type: \(testCase.variationType)")
                    continue
                }

                totalComparisons += 1
                if comparisonResult {
                    successfulComparisons += 1
                } else {
                    // Fail immediately on mismatch for easier debugging
                    XCTFail("Native Protobuf and Swift Struct evaluators produced different results for flag '\(testCase.flag)' subject '\(subject.subjectKey)'")
                }
            }
        }

        print("✅ Native Protobuf vs Swift Struct correctness: \(successfulComparisons)/\(totalComparisons) comparisons successful")

        // All comparisons should match
        XCTAssertEqual(successfulComparisons, totalComparisons, "Native Protobuf evaluator should produce identical results to Swift Struct evaluator")
    }

    func testPrewarmedModeCorrectness() throws {
        // Load protobuf data
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.pb",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-v1.pb")
            return
        }
        let protobufData = try Data(contentsOf: fileURL)

        // Create both clients with same data - prewarmed mode
        let prewarmedNativeClient = try NativeProtobufClient(
            sdkKey: "native-protobuf-prewarmed-test-key",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: true
        )

        let prewarmedSwiftStructClient = try SwiftStructFromProtobufClient(
            sdkKey: "swift-struct-prewarmed-test-key",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: true
        )

        print("🔍 Testing prewarmed mode correctness...")

        // Test a few key evaluations to ensure prewarmed mode works correctly
        let testSubjectKey = "test-subject"
        let testAttributes: SubjectAttributes = [
            "country": EppoValue.valueOf("US"),
            "age": EppoValue.valueOf(25)
        ]

        // Get all flag keys and test a sample
        let flagKeys = prewarmedNativeClient.getAllFlagKeys()
        let sampleFlagKeys = Array(flagKeys.prefix(10)) // Test first 10 flags

        for flagKey in sampleFlagKeys {
            guard let variationType = prewarmedNativeClient.getFlagVariationType(flagKey: flagKey) else { continue }

            switch variationType {
            case .boolean:
                let nativeResult = prewarmedNativeClient.getBooleanAssignment(
                    flagKey: flagKey,
                    subjectKey: testSubjectKey,
                    subjectAttributes: testAttributes,
                    defaultValue: false
                )
                let swiftStructResult = prewarmedSwiftStructClient.getBooleanAssignment(
                    flagKey: flagKey,
                    subjectKey: testSubjectKey,
                    subjectAttributes: testAttributes,
                    defaultValue: false
                )
                XCTAssertEqual(nativeResult, swiftStructResult, "Prewarmed boolean results should match for flag \(flagKey)")

            case .string:
                let nativeResult = prewarmedNativeClient.getStringAssignment(
                    flagKey: flagKey,
                    subjectKey: testSubjectKey,
                    subjectAttributes: testAttributes,
                    defaultValue: ""
                )
                let swiftStructResult = prewarmedSwiftStructClient.getStringAssignment(
                    flagKey: flagKey,
                    subjectKey: testSubjectKey,
                    subjectAttributes: testAttributes,
                    defaultValue: ""
                )
                XCTAssertEqual(nativeResult, swiftStructResult, "Prewarmed string results should match for flag \(flagKey)")

            default:
                // Test other types as needed
                break
            }
        }

        print("✅ Prewarmed mode correctness validated")
    }

    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(UFCTestCase.self, from: data)
    }
}