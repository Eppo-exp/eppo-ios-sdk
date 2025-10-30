import XCTest
@testable import EppoFlagging
import Foundation
import SwiftProtobuf



// Data structures are defined in UFCTestDataStructures.swift

final class ProtobufLazyCorrectnessTests: XCTestCase {
    var configurationStore: ConfigurationStore!
    var eppoClient: ProtobufLazyClient!
    let testStart = Date()
    var UFCTestJSON: Data!
    
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
        
        // Create protobuf lazy client
        eppoClient = try ProtobufLazyClient(
            sdkKey: "protobuf-lazy-test-key",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil
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
                    let result = eppoClient.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? Bool) ?? false
                    )
                    XCTAssertEqual(result, subject.assignment.value as? Bool)
                case "NUMERIC":
                    let result = eppoClient.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? Double) ?? 0.0
                    )
                    XCTAssertEqual(result, subject.assignment.value as? Double)
                case "INTEGER":
                    let result = eppoClient.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? Int) ?? 0
                    )
                    XCTAssertEqual(result, subject.assignment.value as? Int)
                case "STRING":
                    let result = eppoClient.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? String) ?? ""
                    )
                    XCTAssertEqual(result, subject.assignment.value as? String)
                case "JSON":
                    // Handle JSON assignments
                    let defaultValue = (testCase.defaultValue.value as? String) ?? ""
                    let result = eppoClient.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: defaultValue
                    )
                    // For JSON values, we need to handle nil variations
                    if subject.assignment.value is NSNull {
                        // ProtobufLazyClient returns empty string for null assignments
                        XCTAssertEqual(result, "")
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
                            XCTAssertEqual(normalizeJSON(result), normalizeJSON(expectedJSON))
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
                        XCTAssertEqual(normalizeJSON(result), normalizeJSON(expectedJSON))
                    } else {
                        XCTAssertEqual(result, subject.assignment.value as? String)
                    }
                default:
                    XCTFail("Unknown variation type: \(testCase.variationType)")
                    continue
                }
            }
        }
    }
    
    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(UFCTestCase.self, from: data)
    }
}
