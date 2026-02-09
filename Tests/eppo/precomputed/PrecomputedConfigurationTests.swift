import XCTest
@testable import EppoFlagging

class PrecomputedConfigurationTests: XCTestCase {

    // MARK: - Test Data

    private func createSampleFlags() -> [String: PrecomputedFlag] {
        return [
            "flag1": PrecomputedFlag(
                allocationKey: "allocation-1",
                variationKey: "variation-1",
                variationType: .string,
                variationValue: .valueOf("value1"),
                extraLogging: [:],
                doLog: true
            ),
            "flag2": PrecomputedFlag(
                allocationKey: "allocation-2",
                variationKey: "variation-2",
                variationType: .boolean,
                variationValue: .valueOf(true),
                extraLogging: ["holdoutKey": "experiment-holdout", "holdoutVariation": "status_quo"],
                doLog: false
            )
        ]
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        let flags = createSampleFlags()
        let publishedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -3600)) // 1 hour ago
        let environment = Environment(name: "production")
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])

        let config = PrecomputedConfiguration(
            flags: flags,
            salt: "test-salt",
            format: "PRECOMPUTED",
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: publishedAt,
            environment: environment
        )

        XCTAssertEqual(config.flags.count, 2)
        XCTAssertEqual(config.salt, "test-salt")
        XCTAssertEqual(config.format, "PRECOMPUTED")
        XCTAssertEqual(config.publishedAt, publishedAt)
        XCTAssertEqual(config.environment?.name, "production")
    }

    func testInitializationWithMinimalData() {
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let publishedAt = ISO8601DateFormatter().string(from: Date())
        let config = PrecomputedConfiguration(
            flags: [:],
            salt: "minimal-salt",
            format: "PRECOMPUTED",
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: publishedAt
        )

        XCTAssertTrue(config.flags.isEmpty)
        XCTAssertEqual(config.salt, "minimal-salt")
        XCTAssertEqual(config.publishedAt, publishedAt)
        XCTAssertNil(config.environment)
    }

    // MARK: - Codable Tests

    func testJSONEncodingDecoding() throws {
        let testPrecompute = Precompute(subjectKey: "test-user", subjectAttributes: [:])
        let originalConfig = PrecomputedConfiguration(
            flags: createSampleFlags(),
            salt: "encode-test-salt",
            format: "PRECOMPUTED",
            subject: Subject(subjectKey: testPrecompute.subjectKey, subjectAttributes: testPrecompute.subjectAttributes),
            publishedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -3600)),
            environment: Environment(name: "staging")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalConfig)

        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(PrecomputedConfiguration.self, from: data)

        XCTAssertEqual(decodedConfig.flags.count, originalConfig.flags.count)
        XCTAssertEqual(decodedConfig.salt, originalConfig.salt)
        XCTAssertEqual(decodedConfig.format, originalConfig.format)
        XCTAssertEqual(decodedConfig.environment?.name, originalConfig.environment?.name)
    }

    func testPublicStringAPIWithComplexFlags() throws {
        // Test public String API with multiple flags and complex scenarios
        let wireFormatJSON = """
        {
            "version": 1,
            "precomputed": {
                "subjectKey": "test-user",
                "subjectAttributes": {
                    "categoricalAttributes": {},
                    "numericAttributes": {}
                },
                "fetchedAt": "2024-11-18T14:23:25.123Z",
                "response": "{\\"createdAt\\":\\"2024-11-18T14:23:25.123Z\\",\\"format\\":\\"PRECOMPUTED\\",\\"salt\\":\\"c29kaXVtY2hsb3JpZGU=\\",\\"obfuscated\\":true,\\"environment\\":{\\"name\\":\\"Test\\"},\\"flags\\":{\\"string-flag\\":{\\"allocationKey\\":\\"YWxsb2NhdGlvbi0xMjM=\\",\\"variationKey\\":\\"dmFyaWF0aW9uLTEyMw==\\",\\"variationType\\":\\"STRING\\",\\"variationValue\\":\\"cmVk\\",\\"extraLogging\\":{},\\"doLog\\":true},\\"boolean-flag\\":{\\"allocationKey\\":\\"YWxsb2NhdGlvbi0xMjQ=\\",\\"variationKey\\":\\"dmFyaWF0aW9uLTEyNA==\\",\\"variationType\\":\\"BOOLEAN\\",\\"variationValue\\":true,\\"extraLogging\\":{\\"aG9sZG91dEtleQ==\\":\\"ZmVhdHVyZS1yb2xsb3V0\\",\\"aG9sZG91dFZhcmlhdGlvbg==\\":\\"YWxsX3NoaXBwZWQ=\\"},\\"doLog\\":false}}}"
            }
        }
        """

        let config = try PrecomputedConfiguration(precomputedConfiguration: wireFormatJSON)

        XCTAssertEqual(config.salt, "c29kaXVtY2hsb3JpZGU=")
        XCTAssertEqual(config.format, "PRECOMPUTED")
        XCTAssertEqual(config.environment?.name, "Test")
        XCTAssertEqual(config.flags.count, 2)

        let stringFlag = config.flags["string-flag"]
        XCTAssertNotNil(stringFlag)
        XCTAssertEqual(stringFlag?.variationKey, "dmFyaWF0aW9uLTEyMw==")
        XCTAssertEqual(stringFlag?.variationType, .string)
        XCTAssertEqual(stringFlag?.variationValue, .valueOf("cmVk"))
        XCTAssertTrue(stringFlag?.doLog ?? false)

        let boolFlag = config.flags["boolean-flag"]
        XCTAssertNotNil(boolFlag)
        XCTAssertEqual(boolFlag?.variationType, .boolean)
        XCTAssertEqual(try boolFlag?.variationValue.getBoolValue(), true)
        XCTAssertFalse(boolFlag?.doLog ?? true)
    }

    func testStringAPIWithInvalidJSON() {
        let invalidJSON = "{ invalid json }"

        XCTAssertThrowsError(try PrecomputedConfiguration(precomputedConfiguration: invalidJSON)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testPublicStringAPIWithSubjectParsing() throws {
        // Test public String API with rich subject attribute parsing
        let wireFormatJSON = """
        {
            "version": 1,
            "precomputed": {
                "subjectKey": "test-subject-key",
                "subjectAttributes": {
                    "categoricalAttributes": {
                        "platform": "ios",
                        "language": "en-US"
                    },
                    "numericAttributes": {
                        "age": 25,
                        "score": 98.5
                    }
                },
                "fetchedAt": "2024-11-18T14:23:39.456Z",
                "response": "{\\"createdAt\\":\\"2024-11-18T14:23:25.123Z\\",\\"format\\":\\"PRECOMPUTED\\",\\"salt\\":\\"dGVzdC1zYWx0\\",\\"environment\\":{\\"name\\":\\"Test\\"},\\"flags\\":{\\"test-flag\\":{\\"allocationKey\\":\\"YWxsb2NhdGlvbi0xMjM=\\",\\"variationKey\\":\\"dmFyaWF0aW9uLTEyMw==\\",\\"variationType\\":\\"STRING\\",\\"variationValue\\":\\"dGVzdC12YWx1ZQ==\\",\\"extraLogging\\":{},\\"doLog\\":true}}}"
            }
        }
        """

        let config = try PrecomputedConfiguration(precomputedConfiguration: wireFormatJSON)

        // Verify configuration properties
        XCTAssertEqual(config.salt, "dGVzdC1zYWx0")
        XCTAssertEqual(config.format, "PRECOMPUTED")
        XCTAssertEqual(config.environment?.name, "Test")
        XCTAssertEqual(config.flags.count, 1)

        // Verify subject was parsed correctly
        XCTAssertEqual(config.subject.subjectKey, "test-subject-key")
        XCTAssertEqual(try config.subject.subjectAttributes["platform"]?.getStringValue(), "ios")
        XCTAssertEqual(try config.subject.subjectAttributes["language"]?.getStringValue(), "en-US")
        XCTAssertEqual(try config.subject.subjectAttributes["age"]?.getDoubleValue(), 25.0)
        XCTAssertEqual(try config.subject.subjectAttributes["score"]?.getDoubleValue(), 98.5)

        // Verify flag was parsed correctly
        let testFlag = config.flags["test-flag"]
        XCTAssertNotNil(testFlag)
        XCTAssertEqual(testFlag?.allocationKey, "YWxsb2NhdGlvbi0xMjM=")
        XCTAssertEqual(testFlag?.variationType, .string)
        XCTAssertTrue(testFlag?.doLog ?? false)
    }

    // MARK: - Salt Validation Tests

    func testSaltIsRequired() throws {
        let json = """
        {
            "format": "PRECOMPUTED",
            "flags": {}
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(PrecomputedConfiguration.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testEmptySaltIsValid() throws {
        // Empty salt is allowed (though not expected)
        let json = """
        {
            "salt": "",
            "format": "PRECOMPUTED",
            "flags": {},
            "createdAt": "2024-11-18T14:23:25.123Z",
            "subject": {
                "subjectKey": "test-user",
                "subjectAttributes": {}
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(PrecomputedConfiguration.self, from: data)

        XCTAssertEqual(config.salt, "")
    }
}
