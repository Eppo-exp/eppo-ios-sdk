import XCTest
@testable import EppoFlagging

/// Tests to verify the pluggable JSON parsing interface works correctly
class JSONParsingInterfaceTests: XCTestCase {

    override func tearDown() {
        // Always reset to default provider after tests
        JSONParsingFactory.useDefault()
        super.tearDown()
    }

    func testCanConfigureCustomProvider() {
        // Arrange
        let originalProvider = JSONParsingFactory.currentProvider
        let customProvider = MockJSONParsingProvider()

        // Act
        JSONParsingFactory.configure(provider: customProvider)

        // Assert
        XCTAssertTrue(JSONParsingFactory.currentProvider is MockJSONParsingProvider)
    }

    func testCanResetToDefault() {
        // Arrange
        let customProvider = MockJSONParsingProvider()
        JSONParsingFactory.configure(provider: customProvider)

        // Act
        JSONParsingFactory.useDefault()

        // Assert
        XCTAssertTrue(JSONParsingFactory.currentProvider is StandardJSONParsingProvider)
        XCTAssertFalse(JSONParsingFactory.currentProvider is MockJSONParsingProvider)
    }

    func testCustomProviderIsUsedByConfiguration() {
        // Arrange
        let mockProvider = MockJSONParsingProvider()
        JSONParsingFactory.configure(provider: mockProvider)

        let testJSON = """
        {
            "format": "universal_flag_config_v1",
            "createdAt": "2023-10-28T10:15:30.123Z",
            "environment": {"name": "test"},
            "flags": {}
        }
        """.data(using: .utf8)!

        // Act & Assert
        do {
            _ = try Configuration(flagsConfigurationJson: testJSON, obfuscated: false)
            XCTAssertTrue(mockProvider.decodeConfigurationCalled, "Custom provider should be called")
        } catch {
            // Expected since our mock provider doesn't actually parse JSON
            XCTAssertTrue(mockProvider.decodeConfigurationCalled, "Custom provider should be called even if it fails")
        }
    }

    func testUniversalFlagConfigUsesCustomProvider() {
        // Arrange
        let mockProvider = MockJSONParsingProvider()
        JSONParsingFactory.configure(provider: mockProvider)

        let testJSON = """
        {
            "format": "universal_flag_config_v1",
            "createdAt": "2023-10-28T10:15:30.123Z",
            "environment": {"name": "test"},
            "flags": {}
        }
        """.data(using: .utf8)!

        // Act & Assert
        do {
            _ = try UniversalFlagConfig.decodeFromJSON(from: testJSON)
            XCTAssertTrue(mockProvider.decodeUniversalFlagConfigCalled, "Custom provider should be called")
        } catch {
            // Expected since our mock provider doesn't actually parse JSON
            XCTAssertTrue(mockProvider.decodeUniversalFlagConfigCalled, "Custom provider should be called even if it fails")
        }
    }

    func testStandardProviderActuallyWorks() throws {
        // Load actual test data to verify standard provider works
        guard let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1.json", withExtension: ""),
              let jsonData = try? Data(contentsOf: fileURL) else {
            throw XCTSkip("Could not load test JSON file")
        }

        // Ensure we're using the standard provider
        JSONParsingFactory.useDefault()
        let standardProvider = JSONParsingFactory.currentProvider

        // Test that standard provider can actually parse real data
        XCTAssertNoThrow(try standardProvider.decodeUniversalFlagConfig(from: jsonData))

        // Test that Configuration can use it
        XCTAssertNoThrow(try Configuration(flagsConfigurationJson: jsonData, obfuscated: false))
    }

    func testPerformanceMonitoringProvider() throws {
        // Create a performance monitoring wrapper around the standard provider
        let standardProvider = StandardJSONParsingProvider()
        let monitoringProvider = PerformanceMonitoringJSONParsingProvider(
            wrapping: standardProvider,
            label: "Test"
        )

        guard let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1.json", withExtension: ""),
              let jsonData = try? Data(contentsOf: fileURL) else {
            throw XCTSkip("Could not load test JSON file")
        }

        // Configure the monitoring provider
        JSONParsingFactory.configure(provider: monitoringProvider)

        // Test that it works (should print timing info)
        XCTAssertNoThrow(try Configuration(flagsConfigurationJson: jsonData, obfuscated: false))

        // Verify the wrapper was used
        XCTAssertTrue(monitoringProvider.decodeConfigurationCalled)
    }
}

// MARK: - Mock Provider for Testing

class MockJSONParsingProvider: JSONParsingProvider {
    var decodeUniversalFlagConfigCalled = false
    var encodeUniversalFlagConfigCalled = false
    var encodeUniversalFlagConfigToStringCalled = false
    var decodeConfigurationCalled = false
    var encodeConfigurationCalled = false
    var decodeEncodedConfigurationCalled = false

    func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        decodeUniversalFlagConfigCalled = true
        throw TestError.mockError
    }

    func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data {
        encodeUniversalFlagConfigCalled = true
        throw TestError.mockError
    }

    func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String {
        encodeUniversalFlagConfigToStringCalled = true
        throw TestError.mockError
    }

    func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration {
        decodeConfigurationCalled = true
        throw TestError.mockError
    }

    func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        encodeConfigurationCalled = true
        throw TestError.mockError
    }

    func decodeEncodedConfiguration(from data: Data) throws -> Configuration {
        decodeEncodedConfigurationCalled = true
        throw TestError.mockError
    }

    enum TestError: Error {
        case mockError
    }
}

// MARK: - Performance Monitoring Provider for Testing

class PerformanceMonitoringJSONParsingProvider: JSONParsingProvider {
    private let wrapped: JSONParsingProvider
    private let label: String

    var decodeConfigurationCalled = false

    init(wrapping provider: JSONParsingProvider, label: String = "Test") {
        self.wrapped = provider
        self.label = label
    }

    func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        return try measureTime(operation: "decodeUniversalFlagConfig", dataSize: data.count) {
            try wrapped.decodeUniversalFlagConfig(from: data)
        }
    }

    func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data {
        return try measureTime(operation: "encodeUniversalFlagConfig") {
            try wrapped.encodeUniversalFlagConfig(config)
        }
    }

    func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String {
        return try measureTime(operation: "encodeUniversalFlagConfigToString") {
            try wrapped.encodeUniversalFlagConfigToString(config)
        }
    }

    func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration {
        decodeConfigurationCalled = true
        return try measureTime(operation: "decodeConfiguration", dataSize: data.count) {
            try wrapped.decodeConfiguration(from: data, obfuscated: obfuscated)
        }
    }

    func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        return try measureTime(operation: "encodeConfiguration") {
            try wrapped.encodeConfiguration(configuration)
        }
    }

    func decodeEncodedConfiguration(from data: Data) throws -> Configuration {
        return try measureTime(operation: "decodeEncodedConfiguration", dataSize: data.count) {
            try wrapped.decodeEncodedConfiguration(from: data)
        }
    }

    private func measureTime<T>(operation: String, dataSize: Int? = nil, block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            let sizeInfo = dataSize.map { " (\($0) bytes)" } ?? ""
            print("[\(label)] \(operation): \(String(format: "%.2f", duration * 1000))ms\(sizeInfo)")
        }
        return try block()
    }
}