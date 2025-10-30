import XCTest
@testable import EppoFlagging
import Foundation
import SwiftProtobuf

/**
 * ProtobufLazyCorrectnessTests verifies that Protobuf Lazy and standard JSON modes produce identical assignment results.
 * This test loads the same flag configuration in both formats and compares assignment values.
 * The lazy approach uses SwiftProtobuf for fast startup with on-demand Swift object conversion.
 */
final class ProtobufLazyCorrectnessTests: XCTestCase {
    var jsonClient: EppoClient!
    var protobufLazyClient: ProtobufLazyClient!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Reset any existing instances
        EppoClient.resetSharedInstance()

        // Only set up file-based clients if we're running the full correctness test
        // The synthetic test will set up its own clients in-method
    }

    override func tearDownWithError() throws {
        jsonClient = nil
        protobufLazyClient = nil
        try super.tearDownWithError()
    }

    func testProtobufLazyCorrectnessAgainstJSON() throws {
        // Set up file-based clients for this test
        try setUpFileBasedClients()

        // Get all test case files (same as EppoClientUFCTests)
        let testFiles = try getTestFiles()
        var totalComparisons = 0
        var successfulComparisons = 0

        print("🧪 Starting Protobuf Lazy vs JSON correctness comparison")
        print("📊 Found \(testFiles.count) test case files")

        for testFile in testFiles {
            let fileName = (testFile as NSString).lastPathComponent
            let testCase = try loadTestCase(from: testFile)

            print("📝 Testing flag: \(testCase.flag) (type: \(testCase.variationType))")

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

                totalComparisons += 1

                // Compare assignments based on variation type
                var assignmentsMatch = false
                switch testCase.variationType {
                case "BOOLEAN":
                    let defaultValue = (testCase.defaultValue.value as? Bool) ?? false
                    let jsonResult = jsonClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let protobufLazyResult = protobufLazyClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    assignmentsMatch = (jsonResult == protobufLazyResult)
                    if !assignmentsMatch {
                        print("   ❌ MISMATCH: Boolean flag \(testCase.flag) for subject \(subject.subjectKey)")
                        print("      JSON: \(jsonResult), Protobuf Lazy: \(protobufLazyResult)")
                    }

                case "NUMERIC":
                    let defaultValue = (testCase.defaultValue.value as? Double) ?? 0.0
                    let jsonResult = jsonClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let protobufLazyResult = protobufLazyClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    assignmentsMatch = (jsonResult == protobufLazyResult)
                    if !assignmentsMatch {
                        print("   ❌ MISMATCH: Numeric flag \(testCase.flag) for subject \(subject.subjectKey)")
                        print("      JSON: \(jsonResult), Protobuf Lazy: \(protobufLazyResult)")
                    }

                case "INTEGER":
                    let defaultValue = (testCase.defaultValue.value as? Int) ?? 0
                    let jsonResult = jsonClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let protobufLazyResult = protobufLazyClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    assignmentsMatch = (jsonResult == protobufLazyResult)
                    if !assignmentsMatch {
                        print("   ❌ MISMATCH: Integer flag \(testCase.flag) for subject \(subject.subjectKey)")
                        print("      JSON: \(jsonResult), Protobuf Lazy: \(protobufLazyResult)")
                    }

                case "STRING":
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let jsonResult = jsonClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let protobufLazyResult = protobufLazyClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    assignmentsMatch = (jsonResult == protobufLazyResult)
                    if !assignmentsMatch {
                        print("   ❌ MISMATCH: String flag \(testCase.flag) for subject \(subject.subjectKey)")
                        print("      JSON: '\(jsonResult)', Protobuf Lazy: '\(protobufLazyResult)'")
                    }

                case "JSON":
                    let defaultValue = ""
                    let jsonResult = jsonClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    let protobufLazyResult = protobufLazyClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    assignmentsMatch = (jsonResult == protobufLazyResult)
                    if !assignmentsMatch {
                        print("   ❌ MISMATCH: JSON flag \(testCase.flag) for subject \(subject.subjectKey)")
                        print("      JSON: '\(jsonResult)', Protobuf Lazy: '\(protobufLazyResult)'")
                    }

                default:
                    XCTFail("Unknown variation type: \(testCase.variationType)")
                    continue
                }

                // XCTAssert for each comparison
                XCTAssertTrue(assignmentsMatch,
                    "Assignment mismatch for flag '\(testCase.flag)' (\(testCase.variationType)) and subject '\(subject.subjectKey)'")

                if assignmentsMatch {
                    successfulComparisons += 1
                }
            }
        }

        print("✅ Protobuf Lazy vs JSON correctness test completed:")
        print("   📊 Total comparisons: \(totalComparisons)")
        print("   ✅ Successful matches: \(successfulComparisons)")
        print("   ❌ Mismatches: \(totalComparisons - successfulComparisons)")
        print("   📈 Match rate: \(String(format: "%.1f", Double(successfulComparisons) / Double(totalComparisons) * 100))%")

        // Overall test should pass if all assignments match
        XCTAssertEqual(successfulComparisons, totalComparisons,
                      "Protobuf Lazy and JSON modes should produce identical assignment results")
    }

    func testProtobufLazyWithSampleData() throws {
        // This test can work without external protobuf files by creating protobuf data in-memory
        // For now, we'll create a simple synthetic test

        // Create a simple protobuf config in memory
        var ufcConfig = Eppo_Ufc_UniversalFlagConfig()
        ufcConfig.createdAt = UInt64(Date().timeIntervalSince1970 * 1000)
        ufcConfig.format = .client

        // Create a simple boolean flag
        var flag = Eppo_Ufc_Flag()
        flag.key = "test-flag"
        flag.enabled = true
        flag.variationType = .boolean
        flag.totalShards = 10000

        // Create a variation
        var variation = Eppo_Ufc_Variation()
        variation.key = "control"
        variation.value = "true" // Boolean stored as string in protobuf

        flag.variations = [variation]

        // Create an allocation with splits
        var allocation = Eppo_Ufc_Allocation()
        allocation.key = "test-allocation"
        allocation.doLog = true

        var split = Eppo_Ufc_Split()
        split.variationKey = "control"

        // Create a shard that covers all traffic
        var shard = Eppo_Ufc_Shard()
        shard.salt = "test-salt"

        var range = Eppo_Ufc_Range()
        range.start = 0
        range.end = 10000

        shard.ranges = [range]
        split.shards = [shard]
        allocation.splits = [split]

        flag.allocations = [allocation]
        ufcConfig.flags = [flag]

        // Serialize to protobuf data
        let protobufData = try ufcConfig.serializedData()

        // Create protobuf lazy client
        let protobufClient = try ProtobufLazyClient(
            sdkKey: "test-sdk-key",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil
        )

        // Test the assignment
        let result = protobufClient.getBooleanAssignment(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: [:],
            defaultValue: false
        )

        XCTAssertTrue(result, "Should return true for the test flag")

        print("🎉 Protobuf lazy client synthetic test passed!")
        print("   📊 Test flag evaluated successfully")
        print("   ✅ Boolean assignment: \(result)")
    }

    // MARK: - Helper Methods

    private func setUpFileBasedClients() throws {
        // Load JSON configuration
        let jsonFileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.json",
            withExtension: ""
        )
        guard let jsonFileURL = jsonFileURL else {
            XCTFail("Could not find flags-v1.json")
            return
        }
        let jsonData = try Data(contentsOf: jsonFileURL)
        let jsonConfiguration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)

        // Create standard JSON-based client
        jsonClient = EppoClient.initializeOffline(
            sdkKey: "json-test-key",
            assignmentLogger: nil,
            initialConfiguration: jsonConfiguration
        )

        // Load protobuf data (this file needs to be created)
        // TODO: Create flags-v1.pb file with same data as flags-v1.json
        let protobufFileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.pb",
            withExtension: ""
        )
        guard let protobufFileURL = protobufFileURL else {
            XCTFail("Could not find flags-v1.pb - protobuf data file needs to be created")
            return
        }
        let protobufData = try Data(contentsOf: protobufFileURL)

        // Create Protobuf Lazy client using the same data in protobuf format
        do {
            protobufLazyClient = try ProtobufLazyClient(
                sdkKey: "protobuf-lazy-test-key",
                protobufData: protobufData,
                obfuscated: false,
                assignmentLogger: nil
            )
        } catch {
            print("❌ Failed to create ProtobufLazyClient: \(error)")
            print("📊 Protobuf data size: \(protobufData.count) bytes")
            print("🔍 First 50 bytes: \(protobufData.prefix(50))")

            // Try to parse manually for debugging
            do {
                let config = try Eppo_Ufc_UniversalFlagConfig(serializedBytes: protobufData)
                print("✅ Manual parsing succeeded! Flags count: \(config.flags.count)")
            } catch {
                print("❌ Manual parsing also failed: \(error)")
            }

            throw error
        }
    }

    private func getTestFiles() throws -> [String] {
        let testDir = Bundle.module.path(forResource: "Resources/test-data/ufc/tests", ofType: nil) ?? ""
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: testDir)
        return files.map { "\(testDir)/\($0)" }
    }

    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(UFCTestCase.self, from: data)
    }
}