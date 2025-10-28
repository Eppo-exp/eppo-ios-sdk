import Foundation
import EppoFlagging

// MARK: - Example: Using Pluggable JSON Parsing Interface

/**
 This example demonstrates how to implement and use custom JSON parsing providers
 with the Eppo iOS SDK for performance optimization.
 */

// MARK: - Example 1: Simple Custom Provider

class SimpleJSONParsingProvider: JSONParsingProvider {

    func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        // Use standard JSONDecoder with custom configuration
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UniversalFlagConfig.self, from: data)
    }

    func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(config)
    }

    func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String {
        let data = try encodeUniversalFlagConfig(config)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration {
        let flagsConfig = try decodeUniversalFlagConfig(from: data)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return Configuration(
            flagsConfiguration: flagsConfig,
            obfuscated: obfuscated,
            fetchedAt: timestamp,
            publishedAt: timestamp
        )
    }

    func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(configuration)
    }

    func decodeEncodedConfiguration(from data: Data) throws -> Configuration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Configuration.self, from: data)
    }
}

// MARK: - Example 2: Performance Monitoring Provider

class PerformanceMonitoringProvider: JSONParsingProvider {
    private let wrapped: JSONParsingProvider
    private let label: String

    init(wrapping provider: JSONParsingProvider, label: String = "Custom") {
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

// MARK: - Example 3: Caching Provider

class CachingJSONParsingProvider: JSONParsingProvider {
    private let wrapped: JSONParsingProvider
    private var cache: [Data: UniversalFlagConfig] = [:]
    private let cacheQueue = DispatchQueue(label: "json-parsing-cache", attributes: .concurrent)

    init(wrapping provider: JSONParsingProvider) {
        self.wrapped = provider
    }

    func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        return try cacheQueue.sync {
            if let cached = cache[data] {
                return cached
            }

            let result = try wrapped.decodeUniversalFlagConfig(from: data)
            cacheQueue.async(flags: .barrier) { [weak self] in
                self?.cache[data] = result
            }
            return result
        }
    }

    func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data {
        return try wrapped.encodeUniversalFlagConfig(config)
    }

    func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String {
        return try wrapped.encodeUniversalFlagConfigToString(config)
    }

    func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration {
        return try wrapped.decodeConfiguration(from: data, obfuscated: obfuscated)
    }

    func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        return try wrapped.encodeConfiguration(configuration)
    }

    func decodeEncodedConfiguration(from data: Data) throws -> Configuration {
        return try wrapped.decodeEncodedConfiguration(from: data)
    }

    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}

// MARK: - Usage Examples

func demonstratePluggableJSONParsing() {
    // Example 1: Using a simple custom provider
    let simpleProvider = SimpleJSONParsingProvider()
    JSONParsingFactory.configure(provider: simpleProvider)

    // Example 2: Using performance monitoring
    let monitoredProvider = PerformanceMonitoringProvider(
        wrapping: StandardJSONParsingProvider(),
        label: "Standard+Monitoring"
    )
    JSONParsingFactory.configure(provider: monitoredProvider)

    // Example 3: Using caching provider
    let cachedProvider = CachingJSONParsingProvider(
        wrapping: StandardJSONParsingProvider()
    )
    JSONParsingFactory.configure(provider: cachedProvider)

    // Example 4: Combining multiple providers
    let combinedProvider = PerformanceMonitoringProvider(
        wrapping: CachingJSONParsingProvider(
            wrapping: StandardJSONParsingProvider()
        ),
        label: "Cached+Monitored"
    )
    JSONParsingFactory.configure(provider: combinedProvider)

    // Reset to default
    JSONParsingFactory.useDefault()
}

// MARK: - Integration with High-Performance Libraries

/**
 For high-performance JSON parsing, you can integrate with libraries like:

 1. IkigaJSON - Fast JSON parsing library
 2. SwiftyJSON - Easy JSON handling
 3. Codable extensions with custom strategies

 Example with IkigaJSON (add as dependency):

 ```swift
 import IkigaJSON

 class IkigaJSONProvider: JSONParsingProvider {
     func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
         let decoder = IkigaJSONDecoder()
         // Configure decoder as needed
         return try decoder.decode(UniversalFlagConfig.self, from: data)
     }

     // Implement other required methods...
 }
 ```
 */

// MARK: - Best Practices

/**
 Best Practices for Custom JSON Parsing Providers:

 1. **Performance**: Profile your custom implementation against the standard provider
 2. **Error Handling**: Ensure error messages are helpful for debugging
 3. **Thread Safety**: Make providers thread-safe if they maintain state
 4. **Memory Management**: Avoid memory leaks in long-running applications
 5. **Testing**: Thoroughly test with your actual configuration data
 6. **Fallback**: Consider implementing fallback to standard provider on errors

 Example test:
 ```swift
 func testCustomProvider() {
     let customProvider = MyCustomProvider()
     let standardProvider = StandardJSONParsingProvider()

     // Test with actual data
     let testData = loadTestConfigurationData()

     let customResult = try customProvider.decodeUniversalFlagConfig(from: testData)
     let standardResult = try standardProvider.decodeUniversalFlagConfig(from: testData)

     // Verify results are equivalent
     XCTAssertEqual(customResult.flags.count, standardResult.flags.count)
     // Add more assertions...
 }
 ```
 */