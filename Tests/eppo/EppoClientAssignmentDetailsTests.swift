import XCTest

@testable import EppoFlagging

final class EppoClientAssignmentDetailsTests: XCTestCase {
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

    func testMatchedRuleDetails() throws {
        let subjectAttributes: SubjectAttributes = [
            "email": EppoValue.valueOf("alice@mycompany.com"),
            "country": EppoValue.valueOf("US")
        ]

        let result = try eppoClient.getIntegerAssignmentDetails(
            flagKey: "integer-flag",
            subjectKey: "alice",
            subjectAttributes: subjectAttributes,
            defaultValue: 0
        )

        XCTAssertEqual(result.variation, 3)
        XCTAssertNil(result.action)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.variationKey, "three")
        XCTAssertEqual(try result.evaluationDetails.variationValue?.getDoubleValue(), 3)
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .match)
        XCTAssertEqual(
            result.evaluationDetails.flagEvaluationDescription,
            "Supplied attributes match rules defined in allocation \"targeted allocation\"."
        )
        
        XCTAssertGreaterThanOrEqual(
            UTC_ISO_DATE_FORMAT.date(from: result.evaluationDetails.configFetchedAt)?.timeIntervalSince1970 ?? 0,
            testStart.timeIntervalSince1970 - 1  // Allow for 1 second difference
        )
        XCTAssertEqual(
            result.evaluationDetails.configPublishedAt,
            configurationStore.getConfiguration()?.getFlagConfigDetails().configPublishedAt ?? ""
        )
        
        // Test matched rule
        guard let matchedRule = result.evaluationDetails.matchedRule else {
            XCTFail("Expected matchedRule to be non-nil")
            return
        }
        XCTAssertEqual(matchedRule.conditions.count, 1)
        let condition = matchedRule.conditions[0]
        XCTAssertEqual(condition.attribute, "country")
        XCTAssertEqual(condition.operator, .oneOf)
        XCTAssertEqual(try condition.value.getStringArrayValue(), ["US", "Canada", "Mexico"])

        // Test matched allocation
        guard let matchedAllocation = result.evaluationDetails.matchedAllocation else {
            XCTFail("Expected matchedAllocation to be non-nil")
            return
        }
        XCTAssertEqual(matchedAllocation.key, "targeted allocation")
        XCTAssertEqual(matchedAllocation.allocationEvaluationCode, .match)
        XCTAssertEqual(matchedAllocation.orderPosition, 1)

        // Test unmatched allocations
        XCTAssertEqual(result.evaluationDetails.unmatchedAllocations.count, 0)

        // Test unevaluated allocations
        XCTAssertEqual(result.evaluationDetails.unevaluatedAllocations.count, 1)
        let unevaluatedAllocation = result.evaluationDetails.unevaluatedAllocations[0]
        XCTAssertEqual(unevaluatedAllocation.key, "50/50 split")
        XCTAssertEqual(unevaluatedAllocation.allocationEvaluationCode, .unevaluated)
        XCTAssertEqual(unevaluatedAllocation.orderPosition, 2)
    }

    func testMatchedSplitDetails() throws {
        let subjectAttributes: SubjectAttributes = [
            "email": EppoValue.valueOf("alice@mycompany.com"),
            "country": EppoValue.valueOf("Brazil")
        ]

        let result = try eppoClient.getIntegerAssignmentDetails(
            flagKey: "integer-flag",
            subjectKey: "alice",
            subjectAttributes: subjectAttributes,
            defaultValue: 0
        )

        XCTAssertEqual(result.variation, 2)
        XCTAssertNil(result.action)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.variationKey, "two")
        XCTAssertEqual(try result.evaluationDetails.variationValue?.getDoubleValue(), 2)
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .match)
        XCTAssertEqual(
            result.evaluationDetails.flagEvaluationDescription,
            "alice belongs to the range of traffic assigned to \"two\" defined in allocation \"50/50 split\"."
        )

        // Test matched allocation
        guard let matchedAllocation = result.evaluationDetails.matchedAllocation else {
            XCTFail("Expected matchedAllocation to be non-nil")
            return
        }
        XCTAssertEqual(matchedAllocation.key, "50/50 split")
        XCTAssertEqual(matchedAllocation.allocationEvaluationCode, .match)
        XCTAssertEqual(matchedAllocation.orderPosition, 2)

        // Test unmatched allocations
        XCTAssertEqual(result.evaluationDetails.unmatchedAllocations.count, 1)
        let unmatchedAllocation = result.evaluationDetails.unmatchedAllocations[0]
        XCTAssertEqual(unmatchedAllocation.key, "targeted allocation")
        XCTAssertEqual(unmatchedAllocation.allocationEvaluationCode, .failingRule)
        XCTAssertEqual(unmatchedAllocation.orderPosition, 1)

        // Test unevaluated allocations
        XCTAssertEqual(result.evaluationDetails.unevaluatedAllocations.count, 0)
    }

    func testMatchedSplitWithRule() throws {
        let subjectAttributes: SubjectAttributes = [
            "id": EppoValue.valueOf("alice"),
            "email": EppoValue.valueOf("alice@external.com"),
            "country": EppoValue.valueOf("Brazil")
        ]

        let result = try eppoClient.getStringAssignmentDetails(
            flagKey: "new-user-onboarding",
            subjectKey: "alice",
            subjectAttributes: subjectAttributes,
            defaultValue: ""
        )

        XCTAssertEqual(result.variation, "control")
        XCTAssertNil(result.action)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .match)
        XCTAssertEqual(
            result.evaluationDetails.flagEvaluationDescription,
            "Supplied attributes match rules defined in allocation \"experiment\" and alice belongs to the range of traffic assigned to \"control\"."
        )
        XCTAssertEqual(result.evaluationDetails.variationKey, "control")
        XCTAssertEqual(try result.evaluationDetails.variationValue?.getStringValue(), "control")
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)

        // Test matched rule
        guard let matchedRule = result.evaluationDetails.matchedRule else {
            XCTFail("Expected matchedRule to be non-nil")
            return
        }
        XCTAssertEqual(matchedRule.conditions.count, 1)
        let condition = matchedRule.conditions[0]
        XCTAssertEqual(condition.attribute, "country")
        XCTAssertEqual(condition.operator, .notOneOf)
        XCTAssertEqual(try condition.value.getStringArrayValue(), ["US", "Canada", "Mexico"])

        // Test matched allocation
        guard let matchedAllocation = result.evaluationDetails.matchedAllocation else {
            XCTFail("Expected matchedAllocation to be non-nil")
            return
        }
        XCTAssertEqual(matchedAllocation.key, "experiment")
        XCTAssertEqual(matchedAllocation.allocationEvaluationCode, .match)
        XCTAssertEqual(matchedAllocation.orderPosition, 3)

        // Test unmatched allocations
        XCTAssertEqual(result.evaluationDetails.unmatchedAllocations.count, 2)
        let unmatchedAllocations = result.evaluationDetails.unmatchedAllocations
        XCTAssertEqual(unmatchedAllocations[0].key, "id rule")
        XCTAssertEqual(unmatchedAllocations[0].allocationEvaluationCode, .failingRule)
        XCTAssertEqual(unmatchedAllocations[0].orderPosition, 1)
        XCTAssertEqual(unmatchedAllocations[1].key, "internal users")
        XCTAssertEqual(unmatchedAllocations[1].allocationEvaluationCode, .failingRule)
        XCTAssertEqual(unmatchedAllocations[1].orderPosition, 2)

        // Test unevaluated allocations
        XCTAssertEqual(result.evaluationDetails.unevaluatedAllocations.count, 1)
        let unevaluatedAllocation = result.evaluationDetails.unevaluatedAllocations[0]
        XCTAssertEqual(unevaluatedAllocation.key, "rollout")
        XCTAssertEqual(unevaluatedAllocation.allocationEvaluationCode, .unevaluated)
        XCTAssertEqual(unevaluatedAllocation.orderPosition, 4)
    }

    func testUnrecognizedFlag() throws {
        let result = try eppoClient.getIntegerAssignmentDetails(
            flagKey: "asdf",
            subjectKey: "alice",
            subjectAttributes: [:],
            defaultValue: 0
        )

        XCTAssertEqual(result.variation ?? 0, 0)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .flagUnrecognizedOrDisabled)
        XCTAssertEqual(
            result.evaluationDetails.flagEvaluationDescription,
            "Unrecognized or disabled flag: asdf"
        )
        XCTAssertNil(result.evaluationDetails.variationKey)
        XCTAssertNil(result.evaluationDetails.variationValue)
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)
        XCTAssertNil(result.evaluationDetails.matchedRule)
        XCTAssertNil(result.evaluationDetails.matchedAllocation)
        XCTAssertEqual(result.evaluationDetails.unmatchedAllocations.count, 0)
        XCTAssertEqual(result.evaluationDetails.unevaluatedAllocations.count, 0)
    }

    func testTypeMismatch() throws {
        let result = try eppoClient.getBooleanAssignmentDetails(
            flagKey: "integer-flag",
            subjectKey: "alice",
            subjectAttributes: [:],
            defaultValue: true
        )

        XCTAssertEqual(result.variation ?? true, true)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .typeMismatch)
        XCTAssertEqual(
            result.evaluationDetails.flagEvaluationDescription,
            "Variation value does not have the correct type. Found INTEGER, but expected BOOLEAN for flag integer-flag"
        )
        XCTAssertNil(result.evaluationDetails.variationKey)
        XCTAssertNil(result.evaluationDetails.variationValue)
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)
        XCTAssertNil(result.evaluationDetails.matchedRule)
        XCTAssertNil(result.evaluationDetails.matchedAllocation)
        XCTAssertEqual(result.evaluationDetails.unmatchedAllocations.count, 0)
        XCTAssertEqual(result.evaluationDetails.unevaluatedAllocations.count, 2)
    }

    func testNumericAssignmentDetails() throws {
        let subjectAttributes: SubjectAttributes = [
            "email": EppoValue.valueOf("alice@mycompany.com"),
            "country": EppoValue.valueOf("US")
        ]

        let result = try eppoClient.getNumericAssignmentDetails(
            flagKey: "numeric_flag",
            subjectKey: "alice",
            subjectAttributes: subjectAttributes,
            defaultValue: 0.0
        )

        XCTAssertEqual(result.variation ?? 0.0, 3.1415926)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .match)
        XCTAssertEqual(result.evaluationDetails.variationKey, "pi")
        XCTAssertEqual(try result.evaluationDetails.variationValue?.getDoubleValue(), 3.1415926)
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)
    }

    func testBooleanAssignmentDetails() throws {
        let subjectAttributes: SubjectAttributes = [
            "email": EppoValue.valueOf("alice@mycompany.com"),
            "country": EppoValue.valueOf("US")
        ]

        let result = try eppoClient.getBooleanAssignmentDetails(
            flagKey: "kill-switch",
            subjectKey: "alice",
            subjectAttributes: subjectAttributes,
            defaultValue: false
        )

        XCTAssertEqual(result.variation ?? false, true)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .match)
        XCTAssertEqual(result.evaluationDetails.variationKey, "on")
        XCTAssertEqual(try result.evaluationDetails.variationValue?.getBoolValue(), true)
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)
    }

    func testJSONAssignmentDetails() throws {
        let subjectAttributes: SubjectAttributes = [
            "email": EppoValue.valueOf("alice@mycompany.com"),
            "country": EppoValue.valueOf("US")
        ]

        let result = try eppoClient.getJSONStringAssignmentDetails(
            flagKey: "json-config-flag",
            subjectKey: "alice",
            subjectAttributes: subjectAttributes,
            defaultValue: "{}"
        )

        // Helper function to normalize JSON strings
        func normalizeJSON(_ jsonString: String) -> String {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let normalizedData = try? JSONSerialization.data(withJSONObject: json, options: []),
                  let normalizedString = String(data: normalizedData, encoding: .utf8) else {
                return jsonString
            }
            return normalizedString
        }

        XCTAssertNotNil(result.variation)
        XCTAssertEqual(normalizeJSON(result.variation!), normalizeJSON("{\"integer\":1,\"string\":\"one\",\"float\":1.0}"))
        XCTAssertNil(result.action)
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .match)
        XCTAssertEqual(result.evaluationDetails.variationKey, "one")
        XCTAssertEqual(normalizeJSON(try result.evaluationDetails.variationValue?.getStringValue() ?? ""), normalizeJSON("{\"integer\":1,\"string\":\"one\",\"float\":1.0}"))
        XCTAssertNil(result.evaluationDetails.banditKey)
        XCTAssertNil(result.evaluationDetails.banditAction)

        // Test matched allocation
        guard let matchedAllocation = result.evaluationDetails.matchedAllocation else {
            XCTFail("Expected matchedAllocation to be non-nil")
            return
        }
        XCTAssertEqual(matchedAllocation.key, "50/50 split")
        XCTAssertEqual(matchedAllocation.allocationEvaluationCode, .match)
        XCTAssertEqual(matchedAllocation.orderPosition, 2)

        // Test unmatched allocations
        XCTAssertEqual(result.evaluationDetails.unmatchedAllocations.count, 1)
        let unmatchedAllocation = result.evaluationDetails.unmatchedAllocations[0]
        XCTAssertEqual(unmatchedAllocation.key, "Optionally Force Empty")
        XCTAssertEqual(unmatchedAllocation.allocationEvaluationCode, .failingRule)
        XCTAssertEqual(unmatchedAllocation.orderPosition, 1)

        // Test unevaluated allocations
        XCTAssertEqual(result.evaluationDetails.unevaluatedAllocations.count, 0)
    }

    func testAssignmentErrorWithInvalidValue() throws {
        let subjectAttributes: SubjectAttributes = [
            "country": EppoValue.valueOf("US")  // This will match the second allocation with the "pi" variation
        ]

        let result = try eppoClient.getIntegerAssignmentDetails(
            flagKey: "invalid-value-flag",
            subjectKey: "test-subject",
            subjectAttributes: subjectAttributes,
            defaultValue: 0
        )

        // Verify the error state
        XCTAssertEqual(result.variation, 0)  // Should return default value
        XCTAssertEqual(result.evaluationDetails.environmentName, "Test")
        XCTAssertEqual(result.evaluationDetails.flagEvaluationCode, .assignmentError)
        XCTAssertEqual(
            result.evaluationDetails.flagEvaluationDescription,
            "Variation (pi) is configured for type INTEGER, but is set to incompatible value (3.1415926)"
        )
        
        // For assignment errors, we expect no matched rule (since this allocation has no rules)
        XCTAssertNil(result.evaluationDetails.matchedRule)
        
        // For assignment errors, we should still have a matched allocation
        XCTAssertNotNil(result.evaluationDetails.matchedAllocation)
        if let matchedAllocation = result.evaluationDetails.matchedAllocation {
            XCTAssertEqual(matchedAllocation.key, "invalid")
            XCTAssertEqual(matchedAllocation.allocationEvaluationCode, .match)
        }
    }

    func testConfigPublishedAtTimestamp() throws {
        let result = try eppoClient.getIntegerAssignmentDetails(
            flagKey: "integer-flag",
            subjectKey: "alice",
            subjectAttributes: [:],
            defaultValue: 0
        )
        
        // Get the expected publishedAt from the configuration
        let expectedPublishedAt = configurationStore.getConfiguration()?.publishedAt
        
        // Verify the configPublishedAt timestamp matches the configuration
        XCTAssertEqual(
            result.evaluationDetails.configPublishedAt,
            expectedPublishedAt
        )
    }
} 
