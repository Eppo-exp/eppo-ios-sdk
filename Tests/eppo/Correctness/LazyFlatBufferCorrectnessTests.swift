//import XCTest
//@testable import EppoFlagging
//import Foundation
//
///**
// * LazyFlatBufferCorrectnessTests verifies that Lazy FlatBuffer and JSON modes produce identical assignment results.
// * This test loads the same flag configuration in both formats and compares assignment values.
// * The lazy approach uses FlatBuffer as canonical source with on-demand Swift object conversion.
// */
//final class LazyFlatBufferCorrectnessTests: XCTestCase {
//    var jsonClient: EppoClient!
//    var lazyFlatBufferClient: LazyFlatBufferClient!
//
//    override func setUpWithError() throws {
//        try super.setUpWithError()
//
//        // Reset any existing instances
//        EppoClient.resetSharedInstance()
//
//        // Load JSON configuration
//        let jsonFileURL = Bundle.module.url(
//            forResource: "Resources/test-data/ufc/flags-v1.json",
//            withExtension: ""
//        )
//        guard let jsonFileURL = jsonFileURL else {
//            XCTFail("Could not find flags-v1.json")
//            return
//        }
//        let jsonData = try Data(contentsOf: jsonFileURL)
//        let jsonConfiguration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
//
//        // Create JSON-based client
//        jsonClient = EppoClient.initializeOffline(
//            sdkKey: "json-test-key",
//            assignmentLogger: nil,
//            initialConfiguration: jsonConfiguration
//        )
//
//        // Load FlatBuffer configuration
//        let flatBufferFileURL = Bundle.module.url(
//            forResource: "Resources/test-data/ufc/flags-v1.flatbuf",
//            withExtension: ""
//        )
//        guard let flatBufferFileURL = flatBufferFileURL else {
//            XCTFail("Could not find flags-v1.flatbuf")
//            return
//        }
//        let flatBufferData = try Data(contentsOf: flatBufferFileURL)
//
//        // Create Lazy FlatBuffer-based client
//        lazyFlatBufferClient = try LazyFlatBufferClient(
//            sdkKey: "lazy-flatbuffer-test-key",
//            flatBufferData: flatBufferData,
//            obfuscated: false,
//            assignmentLogger: nil
//        )
//    }
//
//    override func tearDownWithError() throws {
//        jsonClient = nil
//        lazyFlatBufferClient = nil
//        try super.tearDownWithError()
//    }
//
//    func testLazyFlatBufferCorrectnessAgainstJSON() throws {
//        // Get all test case files (same as EppoClientUFCTests)
//        let testFiles = try getTestFiles()
//        var totalComparisons = 0
//        var successfulComparisons = 0
//
//        print("🧪 Starting Lazy FlatBuffer vs JSON correctness comparison")
//        print("📊 Found \(testFiles.count) test case files")
//
//        for testFile in testFiles {
//            let fileName = (testFile as NSString).lastPathComponent
//            let testCase = try loadTestCase(from: testFile)
//
//            print("📝 Testing flag: \(testCase.flag) (type: \(testCase.variationType))")
//
//            for subject in testCase.subjects {
//                // Convert subject attributes to EppoValue
//                let subjectAttributes = subject.subjectAttributes.mapValues { value in
//                    switch value.value {
//                    case let string as String:
//                        return EppoValue.valueOf(string)
//                    case let int as Int:
//                        return EppoValue.valueOf(int)
//                    case let double as Double:
//                        return EppoValue.valueOf(double)
//                    case let bool as Bool:
//                        return EppoValue.valueOf(bool)
//                    case is NSNull:
//                        return EppoValue.nullValue()
//                    default:
//                        return EppoValue.nullValue()
//                    }
//                }
//
//                totalComparisons += 1
//
//                // Compare assignments based on variation type
//                var assignmentsMatch = false
//                switch testCase.variationType {
//                case "BOOLEAN":
//                    let defaultValue = (testCase.defaultValue.value as? Bool) ?? false
//                    let jsonResult = jsonClient.getBooleanAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    let lazyFlatBufferResult = lazyFlatBufferClient.getBooleanAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    assignmentsMatch = (jsonResult == lazyFlatBufferResult)
//                    if !assignmentsMatch {
//                        print("   ❌ MISMATCH: Boolean flag \(testCase.flag) for subject \(subject.subjectKey)")
//                        print("      JSON: \(jsonResult), Lazy FlatBuffer: \(lazyFlatBufferResult)")
//                    }
//
//                case "NUMERIC":
//                    let defaultValue = (testCase.defaultValue.value as? Double) ?? 0.0
//                    let jsonResult = jsonClient.getNumericAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    let lazyFlatBufferResult = lazyFlatBufferClient.getNumericAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    assignmentsMatch = (jsonResult == lazyFlatBufferResult)
//                    if !assignmentsMatch {
//                        print("   ❌ MISMATCH: Numeric flag \(testCase.flag) for subject \(subject.subjectKey)")
//                        print("      JSON: \(jsonResult), Lazy FlatBuffer: \(lazyFlatBufferResult)")
//                    }
//
//                case "INTEGER":
//                    let defaultValue = (testCase.defaultValue.value as? Int) ?? 0
//                    let jsonResult = jsonClient.getIntegerAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    let lazyFlatBufferResult = lazyFlatBufferClient.getIntegerAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    assignmentsMatch = (jsonResult == lazyFlatBufferResult)
//                    if !assignmentsMatch {
//                        print("   ❌ MISMATCH: Integer flag \(testCase.flag) for subject \(subject.subjectKey)")
//                        print("      JSON: \(jsonResult), Lazy FlatBuffer: \(lazyFlatBufferResult)")
//                    }
//
//                case "STRING":
//                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
//                    let jsonResult = jsonClient.getStringAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    let lazyFlatBufferResult = lazyFlatBufferClient.getStringAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    assignmentsMatch = (jsonResult == lazyFlatBufferResult)
//                    if !assignmentsMatch {
//                        print("   ❌ MISMATCH: String flag \(testCase.flag) for subject \(subject.subjectKey)")
//                        print("      JSON: '\(jsonResult)', Lazy FlatBuffer: '\(lazyFlatBufferResult)'")
//                    }
//
//                case "JSON":
//                    let defaultValue = ""
//                    let jsonResult = jsonClient.getJSONStringAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    let lazyFlatBufferResult = lazyFlatBufferClient.getJSONStringAssignment(
//                        flagKey: testCase.flag,
//                        subjectKey: subject.subjectKey,
//                        subjectAttributes: subjectAttributes,
//                        defaultValue: defaultValue
//                    )
//                    assignmentsMatch = (jsonResult == lazyFlatBufferResult)
//                    if !assignmentsMatch {
//                        print("   ❌ MISMATCH: JSON flag \(testCase.flag) for subject \(subject.subjectKey)")
//                        print("      JSON: '\(jsonResult)', Lazy FlatBuffer: '\(lazyFlatBufferResult)'")
//                    }
//
//                default:
//                    XCTFail("Unknown variation type: \(testCase.variationType)")
//                    continue
//                }
//
//                // XCTAssert for each comparison
//                XCTAssertTrue(assignmentsMatch,
//                    "Assignment mismatch for flag '\(testCase.flag)' (\(testCase.variationType)) and subject '\(subject.subjectKey)'")
//
//                if assignmentsMatch {
//                    successfulComparisons += 1
//                }
//            }
//        }
//
//        print("✅ Lazy FlatBuffer vs JSON correctness test completed:")
//        print("   📊 Total comparisons: \(totalComparisons)")
//        print("   ✅ Successful matches: \(successfulComparisons)")
//        print("   ❌ Mismatches: \(totalComparisons - successfulComparisons)")
//        print("   📈 Match rate: \(String(format: "%.1f", Double(successfulComparisons) / Double(totalComparisons) * 100))%")
//
//        // Overall test should pass if all assignments match
//        XCTAssertEqual(successfulComparisons, totalComparisons,
//                      "Lazy FlatBuffer and JSON modes should produce identical assignment results")
//    }
//
//    // MARK: - Helper Methods
//
//    private func getTestFiles() throws -> [String] {
//        let testDir = Bundle.module.path(forResource: "Resources/test-data/ufc/tests", ofType: nil) ?? ""
//        let fileManager = FileManager.default
//        let files = try fileManager.contentsOfDirectory(atPath: testDir)
//        return files.map { "\(testDir)/\($0)" }
//    }
//
//    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
//        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
//        return try JSONDecoder().decode(UFCTestCase.self, from: data)
//    }
//}
