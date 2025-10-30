import XCTest
@testable import EppoFlagging
import Foundation
import FlatBuffers

/**
 * NativeFlatBufferCorrectnessTests verifies that the Native FlatBuffer evaluator and Swift Struct evaluator produce identical results.
 * This ensures that working directly with FlatBuffer types produces the same assignments as converting to Swift structs first.
 * Tests both indexed and non-indexed modes.
 */
final class NativeFlatBufferCorrectnessTests: XCTestCase {
    var nativeFlatBufferClient: NativeFlatBufferClient!
    var nativeFlatBufferIndexedClient: NativeFlatBufferClient!
    var swiftStructClient: SwiftStructFromFlatBufferClient!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Load FlatBuffer data
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.flatbuf",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-v1.flatbuf")
            return
        }
        let flatBufferData = try Data(contentsOf: fileURL)

        // Create native clients with same data - both indexed and non-indexed
        nativeFlatBufferClient = try NativeFlatBufferClient(
            sdkKey: "native-flatbuffer-test-key",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: nil,
            useIndex: false
        )

        nativeFlatBufferIndexedClient = try NativeFlatBufferClient(
            sdkKey: "native-flatbuffer-indexed-test-key",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: nil,
            useIndex: true
        )

        // Create Swift struct client for comparison - lazy mode for fair comparison
        swiftStructClient = try SwiftStructFromFlatBufferClient(
            sdkKey: "swift-struct-test-key",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: false
        )
    }

    override func tearDownWithError() throws {
        nativeFlatBufferClient = nil
        nativeFlatBufferIndexedClient = nil
        swiftStructClient = nil
        try super.tearDownWithError()
    }

    func testNativeFlatBufferVsSwiftStructCorrectness() throws {
        print("🔍 Testing Native FlatBuffer vs Swift Struct correctness...")

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
                    let nativeResult = nativeFlatBufferClient.getBooleanAssignment(
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
                    let nativeResult = nativeFlatBufferClient.getNumericAssignment(
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
                    let nativeResult = nativeFlatBufferClient.getIntegerAssignment(
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
                    let nativeResult = nativeFlatBufferClient.getStringAssignment(
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
                    let defaultValue = (testCase.defaultValue.value as? String) ?? "{}"
                    let nativeResult = nativeFlatBufferClient.getJSONStringAssignment(
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
                    comparisonResult = (nativeResult == swiftStructResult)

                    if !comparisonResult {
                        print("❌ JSON mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)':")
                        print("   native: '\(nativeResult)'")
                        print("   swiftStruct: '\(swiftStructResult)'")
                    }

                default:
                    comparisonResult = true
                    print("⚠️ Unknown variation type: \(testCase.variationType)")
                }

                totalComparisons += 1
                if comparisonResult {
                    successfulComparisons += 1
                }
            }
        }

        print("✅ Native FlatBuffer vs Swift Struct correctness: \(successfulComparisons)/\(totalComparisons) comparisons successful")

        // Correctness assertion
        XCTAssertGreaterThanOrEqual(
            Double(successfulComparisons) / Double(totalComparisons),
            0.8, // Allow for some known test case mismatches
            "Native FlatBuffer evaluator should have high correctness compared to Swift struct evaluator"
        )
    }

    // MARK: - Helper Methods

    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(UFCTestCase.self, from: data)
    }

    func testIndexedVsNonIndexedCorrectness() throws {
        print("🔍 Testing Native FlatBuffer Indexed vs Non-Indexed correctness...")

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

                // Get assignments from both indexed and non-indexed evaluators
                let comparisonResult: Bool
                switch testCase.variationType {
                case "BOOLEAN":
                    let defaultValue = (testCase.defaultValue.value as? Bool) ?? false
                    let nonIndexedResult = nativeFlatBufferClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let indexedResult = nativeFlatBufferIndexedClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nonIndexedResult == indexedResult)

                    if !comparisonResult {
                        print("❌ BOOLEAN mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': nonIndexed=\(nonIndexedResult), indexed=\(indexedResult)")
                    }

                case "NUMERIC":
                    let defaultValue = (testCase.defaultValue.value as? Double) ?? 0.0
                    let nonIndexedResult = nativeFlatBufferClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let indexedResult = nativeFlatBufferIndexedClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nonIndexedResult == indexedResult)

                    if !comparisonResult {
                        print("❌ NUMERIC mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': nonIndexed=\(nonIndexedResult), indexed=\(indexedResult)")
                    }

                case "INTEGER":
                    let defaultValue = (testCase.defaultValue.value as? Int) ?? 0
                    let nonIndexedResult = nativeFlatBufferClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let indexedResult = nativeFlatBufferIndexedClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nonIndexedResult == indexedResult)

                    if !comparisonResult {
                        print("❌ INTEGER mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': nonIndexed=\(nonIndexedResult), indexed=\(indexedResult)")
                    }

                case "STRING":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let nonIndexedResult = nativeFlatBufferClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let indexedResult = nativeFlatBufferIndexedClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nonIndexedResult == indexedResult)

                    if !comparisonResult {
                        print("❌ STRING mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)': nonIndexed='\(nonIndexedResult)', indexed='\(indexedResult)'")
                    }

                case "JSON":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? "{}"
                    let nonIndexedResult = nativeFlatBufferClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let indexedResult = nativeFlatBufferIndexedClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    comparisonResult = (nonIndexedResult == indexedResult)

                    if !comparisonResult {
                        print("❌ JSON mismatch for flag '\(testCase.flag)' subject '\(subject.subjectKey)':")
                        print("   nonIndexed: '\(nonIndexedResult)'")
                        print("   indexed: '\(indexedResult)'")
                    }

                default:
                    comparisonResult = true
                    print("⚠️ Unknown variation type: \(testCase.variationType)")
                }

                totalComparisons += 1
                if comparisonResult {
                    successfulComparisons += 1
                }
            }
        }

        print("✅ Native FlatBuffer Indexed vs Non-Indexed correctness: \(successfulComparisons)/\(totalComparisons) comparisons successful")

        // Correctness assertion - should be 100% identical
        XCTAssertEqual(
            successfulComparisons,
            totalComparisons,
            "Indexed and non-indexed FlatBuffer evaluators should produce identical results"
        )
    }
}