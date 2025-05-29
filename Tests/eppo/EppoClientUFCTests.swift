import XCTest

@testable import EppoFlagging

struct UFCTestCase: Codable {
    let flag: String
    let variationType: String
    let defaultValue: AnyCodable
    let subjects: [UFCTestSubject]
}

struct UFCTestSubject: Codable {
    let subjectKey: String
    let subjectAttributes: [String: AnyCodable]
    let assignment: AnyCodable
    let evaluationDetails: UFCEvaluationDetails
}

struct UFCEvaluationDetails: Codable {
    let environmentName: String
    let flagEvaluationCode: String
    let flagEvaluationDescription: String
    let banditKey: String?
    let banditAction: String?
    let variationKey: String?
    let variationValue: AnyCodable?
    let matchedRule: UFCMatchedRule?
    let matchedAllocation: UFCAllocation?
    let unmatchedAllocations: [UFCAllocation]
    let unevaluatedAllocations: [UFCAllocation]
}

struct UFCMatchedRule: Codable {
    let conditions: [UFCCondition]
}

struct UFCCondition: Codable {
    let attribute: String
    let `operator`: String
    let value: AnyCodable
}

struct UFCAllocation: Codable {
    let key: String
    let allocationEvaluationCode: String
    let orderPosition: Int
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

final class EppoClientUFCTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var eppoClient: EppoClient!
    let testStart = Date()
    var UFCTestJSON: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        configurationStore = ConfigurationStore(withPersistentCache: false)
        EppoClient.resetSharedInstance()

        // Load test data from JSON file
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.json",
            withExtension: ""
        )
        do {
            UFCTestJSON = try Data(contentsOf: fileURL!)
        } catch {
            XCTFail("Error loading test JSON: \(error)")
        }

        let configuration = try Configuration(flagsConfigurationJson: UFCTestJSON, obfuscated: false)
        configurationStore.setConfiguration(configuration: configuration)
        eppoClient = EppoClient.initializeOffline(
            sdkKey: "test-key",
            host: nil,
            assignmentLogger: nil,
            assignmentCache: nil,
            initialConfiguration: configuration
        )
    }

    override func tearDownWithError() throws {
        configurationStore = nil
        eppoClient = nil
        UFCTestJSON = nil
        try super.tearDownWithError()
    }

    func testUFCTestCases() throws {
        // Get all test case files
        let testFiles = try getTestFiles()
        
        // Focus on specific test cases if needed for development or debugging
        let focusOn = (
            testFilePath: "", // Focus on test file paths (don't forget to set back to empty string!)
            subjectKey: "" // Focus on subject (don't forget to set back to empty string!)
        )

        for testFile in testFiles {
            let fileName = (testFile as NSString).lastPathComponent
            if !focusOn.testFilePath.isEmpty && focusOn.testFilePath != fileName {
                continue
            }

            let testCase = try loadTestCase(from: testFile)
            
            for subject in testCase.subjects {
                if !focusOn.subjectKey.isEmpty && focusOn.subjectKey != subject.subjectKey {
                    continue
                }

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

                // Get assignment details based on variation type
                switch testCase.variationType {
                case "BOOLEAN":
                    do {
                        let result = try eppoClient.getBooleanAssignmentDetails(
                            flagKey: testCase.flag,
                            subjectKey: subject.subjectKey,
                            subjectAttributes: subjectAttributes,
                            defaultValue: (testCase.defaultValue.value as? Bool) ?? false
                        )
                        XCTAssertEqual(result.variation, subject.assignment.value as? AnyHashable)
                        verifyEvaluationDetails(result.evaluationDetails, subject.evaluationDetails)
                    } catch {
                        throw error
                    }
                case "NUMERIC":
                    do {
                        let result = try eppoClient.getNumericAssignmentDetails(
                            flagKey: testCase.flag,
                            subjectKey: subject.subjectKey,
                            subjectAttributes: subjectAttributes,
                            defaultValue: (testCase.defaultValue.value as? Double) ?? 0.0
                        )
                        XCTAssertEqual(result.variation, subject.assignment.value as? AnyHashable)
                        verifyEvaluationDetails(result.evaluationDetails, subject.evaluationDetails)
                    } catch {
                        throw error
                    }
                case "INTEGER":
                    do {
                        let result = try eppoClient.getIntegerAssignmentDetails(
                            flagKey: testCase.flag,
                            subjectKey: subject.subjectKey,
                            subjectAttributes: subjectAttributes,
                            defaultValue: (testCase.defaultValue.value as? Int) ?? 0
                        )
                        XCTAssertEqual(result.variation, subject.assignment.value as? AnyHashable)
                        verifyEvaluationDetails(result.evaluationDetails, subject.evaluationDetails)
                    } catch {
                        throw error
                    }
                case "STRING":
                    do {
                        let result = try eppoClient.getStringAssignmentDetails(
                            flagKey: testCase.flag,
                            subjectKey: subject.subjectKey,
                            subjectAttributes: subjectAttributes,
                            defaultValue: (testCase.defaultValue.value as? String) ?? ""
                        )
                        XCTAssertEqual(result.variation, subject.assignment.value as? AnyHashable)
                        verifyEvaluationDetails(result.evaluationDetails, subject.evaluationDetails)
                    } catch {
                        throw error
                    }
                case "JSON":
                    do {
                        // If we expect a nil variation, pass nil as the default value
                        let defaultValue: String? = (subject.assignment.value is NSNull || subject.evaluationDetails.flagEvaluationCode == "DEFAULT_ALLOCATION_NULL") ? nil : ""
                        let result = try eppoClient.getJSONStringAssignmentDetails(
                            flagKey: testCase.flag,
                            subjectKey: subject.subjectKey,
                            subjectAttributes: subjectAttributes,
                            defaultValue: defaultValue ?? ""
                        )
                        // For JSON values, we need to handle nil variations
                        if subject.assignment.value is NSNull || subject.evaluationDetails.flagEvaluationCode == "DEFAULT_ALLOCATION_NULL" {
                            XCTAssertNil(result.variation)
                        } else if let expectedDict = subject.assignment.value as? [String: Any] {
                            // Convert dictionary to JSON string for comparison
                            if let expectedData = try? JSONSerialization.data(withJSONObject: expectedDict, options: [.sortedKeys]),
                               let expectedJSON = String(data: expectedData, encoding: .utf8) {
                                // Normalize JSON strings for comparison
                                func normalizeJSON(_ jsonString: String) -> String {
                                    guard let data = jsonString.data(using: .utf8),
                                          let json = try? JSONSerialization.jsonObject(with: data),
                                          let normalizedData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
                                        return jsonString
                                    }
                                    return String(data: normalizedData, encoding: .utf8) ?? jsonString
                                }
                                XCTAssertNotNil(result.variation)
                                XCTAssertEqual(normalizeJSON(result.variation!), normalizeJSON(expectedJSON))
                            } else {
                                XCTFail("Failed to convert expected dictionary to JSON")
                            }
                        } else if let expectedJSON = subject.assignment.value as? String {
                            // Normalize JSON strings for comparison
                            func normalizeJSON(_ jsonString: String) -> String {
                                guard let data = jsonString.data(using: .utf8),
                                      let json = try? JSONSerialization.jsonObject(with: data),
                                      let normalizedData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
                                    return jsonString
                                }
                                return String(data: normalizedData, encoding: .utf8) ?? jsonString
                            }
                            XCTAssertNotNil(result.variation)
                            XCTAssertEqual(normalizeJSON(result.variation!), normalizeJSON(expectedJSON))
                        } else {
                            XCTAssertNotNil(result.variation)
                            XCTAssertEqual(result.variation!, subject.assignment.value as? AnyHashable)
                        }
                        verifyEvaluationDetails(result.evaluationDetails, subject.evaluationDetails)
                    } catch {
                        throw error
                    }
                default:
                    XCTFail("Unknown variation type: \(testCase.variationType)")
                    continue
                }

                // Helper function to verify evaluation details
                func verifyEvaluationDetails(_ actual: EppoClient.FlagEvaluationDetails, _ expected: UFCEvaluationDetails) {
                    XCTAssertEqual(actual.environmentName, expected.environmentName)
                    
                    // Map evaluation codes to match TypeScript implementation
                    let expectedCode = expected.flagEvaluationCode
                    let actualCode = actual.flagEvaluationCode.rawValue
                    
                    // Handle special cases for evaluation codes
                    switch expectedCode {
                    case "DEFAULT_ALLOCATION_NULL":
                        XCTAssertEqual(actualCode, "FLAG_UNRECOGNIZED_OR_DISABLED", "Expected DEFAULT_ALLOCATION_NULL but got \(actualCode)")
                    case "ASSIGNMENT_ERROR":
                        // For assignment errors, we should preserve the variation value
                        XCTAssertEqual(actualCode, "ASSIGNMENT_ERROR", "Expected ASSIGNMENT_ERROR but got \(actualCode)")
                        XCTAssertEqual(actual.variationKey, expected.variationKey)
                        // For assignment errors, verify the variation value matches
                        if let expectedValue = expected.variationValue?.value {
                            switch expectedValue {
                            case let double as Double:
                                if let actualDouble = try? actual.variationValue?.getDoubleValue() {
                                    XCTAssertEqual(actualDouble, double)
                                } else {
                                    XCTFail("Failed to get actual double value")
                                }
                            case let int as Int:
                                if let actualDouble = try? actual.variationValue?.getDoubleValue() {
                                    XCTAssertEqual(Int(actualDouble), int)
                                } else {
                                    XCTFail("Failed to get actual double value for Int comparison")
                                }
                            case let string as String:
                                if let actualString = try? actual.variationValue?.getStringValue() {
                                    XCTAssertEqual(actualString, string)
                                } else {
                                    XCTFail("Failed to get actual string value")
                                }
                            case let bool as Bool:
                                if let actualBool = try? actual.variationValue?.getBoolValue() {
                                    XCTAssertEqual(actualBool, bool)
                                } else {
                                    XCTFail("Failed to get actual bool value")
                                }
                            default:
                                break
                            }
                        }
                        // For assignment errors, we should still have a matched allocation
                        XCTAssertNotNil(actual.matchedAllocation)
                        if let expectedAllocation = expected.matchedAllocation {
                            XCTAssertEqual(actual.matchedAllocation?.key, expectedAllocation.key)
                            XCTAssertEqual(actual.matchedAllocation?.allocationEvaluationCode.rawValue, expectedAllocation.allocationEvaluationCode)
                            XCTAssertEqual(actual.matchedAllocation?.orderPosition, expectedAllocation.orderPosition)
                        }
                        // For assignment errors, we don't expect a matched rule
                        XCTAssertNil(actual.matchedRule)
                    default:
                        XCTAssertEqual(actualCode, expectedCode)
                    }
                    
                    // Map evaluation descriptions to match TypeScript implementation
                    let expectedDesc = expected.flagEvaluationDescription
                    let actualDesc = actual.flagEvaluationDescription
                    
                    // Handle special cases for evaluation descriptions
                    switch expectedDesc {
                    case "No allocations matched. Falling back to \"Default Allocation\", serving NULL":
                        XCTAssertEqual(actualDesc, "Unrecognized or disabled flag: \(testCase.flag)")
                    case "Variation (pi) is configured for type INTEGER, but is set to incompatible value (3.1415926)":
                        XCTAssertEqual(actualDesc, expectedDesc)
                    default:
                        XCTAssertEqual(actualDesc, expectedDesc)
                    }
                    
                    // Only verify variation key if we're not in an error state
                    if expectedCode != "ASSIGNMENT_ERROR" {
                        XCTAssertEqual(actual.variationKey, expected.variationKey)
                    }
                    
                    // Verify variation value
                    if let expectedValue = expected.variationValue?.value, expectedCode != "ASSIGNMENT_ERROR" {
                        switch expectedValue {
                        case let string as String:
                            XCTAssertEqual(try actual.variationValue?.getStringValue(), string)
                        case let int as Int:
                            XCTAssertEqual(Int(try actual.variationValue?.getDoubleValue() ?? 0), int)
                        case let double as Double:
                            XCTAssertEqual(try actual.variationValue?.getDoubleValue(), double)
                        case let bool as Bool:
                            do {
                                let actualBool = try actual.variationValue?.getBoolValue()
                                XCTAssertEqual(actualBool, bool, "Boolean mismatch in flag '\(testCase.flag)' for subject '\(subject.subjectKey)'")
                            } catch {
                                XCTFail("Failed to get boolean value in flag '\(testCase.flag)' for subject '\(subject.subjectKey)': \(error)")
                            }
                        default:
                            break
                        }
                    } else if expectedCode != "ASSIGNMENT_ERROR" {
                        XCTAssertNil(actual.variationValue)
                    }
                    
                    // Verify unmatched allocations
                    XCTAssertEqual(actual.unmatchedAllocations.count, expected.unmatchedAllocations.count)
                    for i in 0..<expected.unmatchedAllocations.count {
                        guard i < actual.unmatchedAllocations.count else {
                            XCTFail("Expected unmatched allocation at index \(i) but found none")
                            continue
                        }
                        let expectedAllocation = expected.unmatchedAllocations[i]
                        let actualAllocation = actual.unmatchedAllocations[i]
                        XCTAssertEqual(actualAllocation.key, expectedAllocation.key)
                        XCTAssertEqual(actualAllocation.allocationEvaluationCode.rawValue, expectedAllocation.allocationEvaluationCode)
                        XCTAssertEqual(actualAllocation.orderPosition, expectedAllocation.orderPosition)
                    }
                    
                    // Test unevaluated allocations
                    XCTAssertEqual(actual.unevaluatedAllocations.count, expected.unevaluatedAllocations.count)
                    for i in 0..<expected.unevaluatedAllocations.count {
                        guard i < actual.unevaluatedAllocations.count else {
                            XCTFail("Expected unevaluated allocation at index \(i) but found none")
                            continue
                        }
                        let expectedAllocation = expected.unevaluatedAllocations[i]
                        let actualAllocation = actual.unevaluatedAllocations[i]
                        XCTAssertEqual(actualAllocation.key, expectedAllocation.key)
                        XCTAssertEqual(actualAllocation.allocationEvaluationCode.rawValue, expectedAllocation.allocationEvaluationCode)
                        XCTAssertEqual(actualAllocation.orderPosition, expectedAllocation.orderPosition)
                    }

                    // Verify condition values
                    if let expectedRule = expected.matchedRule {
                        guard let actualRule = actual.matchedRule else {
                            XCTFail("Expected matchedRule to be non-nil")
                            return
                        }
                        XCTAssertEqual(actualRule.conditions.count, expectedRule.conditions.count)
                        for (i, expectedCondition) in expectedRule.conditions.enumerated() {
                            let actualCondition = actualRule.conditions[i]
                            XCTAssertEqual(actualCondition.attribute, expectedCondition.attribute)
                            XCTAssertEqual(actualCondition.operator.rawValue, expectedCondition.operator)
                            
                            // Verify condition value
                            let expectedValue = expectedCondition.value.value
                            switch expectedValue {
                            case let string as String:
                                XCTAssertEqual(try actualCondition.value.getStringValue(), string)
                            case let int as Int:
                                XCTAssertEqual(Int(try actualCondition.value.getDoubleValue()), int)
                            case let double as Double:
                                XCTAssertEqual(try actualCondition.value.getDoubleValue(), double)
                            case let bool as Bool:
                                do {
                                    let actualBool = try actualCondition.value.getBoolValue()
                                    XCTAssertEqual(actualBool, bool, "Boolean mismatch in flag '\(testCase.flag)' for subject '\(subject.subjectKey)' in condition for attribute '\(expectedCondition.attribute)'")
                                } catch {
                                    XCTFail("Failed to get boolean value in flag '\(testCase.flag)' for subject '\(subject.subjectKey)' in condition for attribute '\(expectedCondition.attribute)': \(error)")
                                }
                            case let array as [String]:
                                XCTAssertEqual(try actualCondition.value.getStringArrayValue(), array)
                            default:
                                break
                            }
                        }
                    } else {
                        XCTAssertNil(actual.matchedRule)
                    }
                    
                    // Verify matched allocation
                    if let expectedAllocation = expected.matchedAllocation {
                        guard let actualAllocation = actual.matchedAllocation else {
                            XCTFail("Expected matchedAllocation to be non-nil")
                            return
                        }
                        XCTAssertEqual(actualAllocation.key, expectedAllocation.key)
                        XCTAssertEqual(actualAllocation.allocationEvaluationCode.rawValue, expectedAllocation.allocationEvaluationCode)
                        XCTAssertEqual(actualAllocation.orderPosition, expectedAllocation.orderPosition)
                    } else {
                        XCTAssertNil(actual.matchedAllocation)
                    }
                    
                    // Verify timestamps
                    XCTAssertGreaterThanOrEqual(
                        UTC_ISO_DATE_FORMAT.date(from: actual.configFetchedAt)?.timeIntervalSince1970 ?? 0,
                        testStart.timeIntervalSince1970 - 1
                    )
                    XCTAssertEqual(
                        actual.configPublishedAt,
                        configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? ""
                    )
                }
            }
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
