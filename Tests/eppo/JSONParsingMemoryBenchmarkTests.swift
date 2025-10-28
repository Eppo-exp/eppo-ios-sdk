import XCTest
import Foundation
@testable import EppoFlagging

/// Comprehensive benchmark test suite for measuring memory allocation during JSON parsing operations
///
/// This test class measures memory usage and performance characteristics of:
/// - Configuration parsing from JSON data
/// - EppoValue polymorphic type parsing
/// - Disk persistence operations
/// - Large configuration stress testing
/// - Memory leaks and retention cycles
final class JSONParsingMemoryBenchmarkTests: XCTestCase {

    // MARK: - Test Data Generation

    /// Small configuration JSON for basic benchmarks (~1KB)
    private let smallConfigurationJSON = """
    {
      "createdAt": "2024-04-17T19:40:53.716Z",
      "environment": { "name": "Test" },
      "flags": {
        "simple_flag": {
          "key": "simple_flag",
          "enabled": true,
          "variationType": "BOOLEAN",
          "variations": {
            "on": { "key": "on", "value": true },
            "off": { "key": "off", "value": false }
          },
          "allocations": [{
            "key": "rollout",
            "doLog": true,
            "splits": [{ "variationKey": "on", "shards": [] }]
          }],
          "totalShards": 10000
        }
      }
    }
    """

    /// Medium configuration JSON for moderate load testing (~10KB)
    private func generateMediumConfigurationJSON() -> String {
        var flags: [String] = []

        for i in 1...50 {
            let flagJSON = """
            "flag_\(i)": {
              "key": "flag_\(i)",
              "enabled": true,
              "variationType": "\(["BOOLEAN", "STRING", "NUMERIC", "INTEGER"].randomElement()!)",
              "variations": {
                "var1": { "key": "var1", "value": "\(i)" },
                "var2": { "key": "var2", "value": "\(i * 2)" }
              },
              "allocations": [{
                "key": "allocation_\(i)",
                "doLog": true,
                "startAt": "2024-01-01T00:00:00.000Z",
                "endAt": "2024-12-31T23:59:59.999Z",
                "splits": [
                  { "variationKey": "var1", "shards": [{ "salt": "salt_\(i)", "ranges": [{ "start": 0, "end": 5000 }] }] },
                  { "variationKey": "var2", "shards": [{ "salt": "salt_\(i)", "ranges": [{ "start": 5000, "end": 10000 }] }] }
                ]
              }],
              "totalShards": 10000
            }
            """
            flags.append(flagJSON)
        }

        return """
        {
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": { "name": "BenchmarkTest" },
          "flags": { \(flags.joined(separator: ",\n    ")) }
        }
        """
    }

    /// Large configuration JSON for stress testing (~100KB)
    private func generateLargeConfigurationJSON() -> String {
        var flags: [String] = []

        for i in 1...500 {
            let allocations = (1...5).map { allocIndex in
                let rules = (1...3).map { ruleIndex in
                    """
                    {
                      "conditions": [{
                        "operator": "ONE_OF",
                        "attribute": "user_segment_\(ruleIndex)",
                        "value": ["premium", "standard", "basic"]
                      }]
                    }
                    """
                }.joined(separator: ",\n          ")

                return """
                {
                  "key": "allocation_\(i)_\(allocIndex)",
                  "doLog": true,
                  "startAt": "2024-01-\(String(format: "%02d", allocIndex))T00:00:00.000Z",
                  "endAt": "2024-12-31T23:59:59.999Z",
                  "rules": [\(rules)],
                  "splits": [
                    { "variationKey": "variation_a", "shards": [{ "salt": "salt_\(i)_\(allocIndex)", "ranges": [{ "start": 0, "end": 3333 }] }] },
                    { "variationKey": "variation_b", "shards": [{ "salt": "salt_\(i)_\(allocIndex)", "ranges": [{ "start": 3333, "end": 6666 }] }] },
                    { "variationKey": "variation_c", "shards": [{ "salt": "salt_\(i)_\(allocIndex)", "ranges": [{ "start": 6666, "end": 10000 }] }] }
                  ]
                }
                """
            }.joined(separator: ",\n        ")

            let flagJSON = """
            "complex_flag_\(i)": {
              "key": "complex_flag_\(i)",
              "enabled": true,
              "variationType": "JSON",
              "variations": {
                "variation_a": { "key": "variation_a", "value": "{\\"feature\\": \\"a\\", \\"config\\": {\\"timeout\\": \(i * 100), \\"retries\\": 3}}" },
                "variation_b": { "key": "variation_b", "value": "{\\"feature\\": \\"b\\", \\"config\\": {\\"timeout\\": \(i * 200), \\"retries\\": 5}}" },
                "variation_c": { "key": "variation_c", "value": "{\\"feature\\": \\"c\\", \\"config\\": {\\"timeout\\": \(i * 150), \\"retries\\": 2}}" }
              },
              "allocations": [\(allocations)],
              "totalShards": 10000
            }
            """
            flags.append(flagJSON)
        }

        return """
        {
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": { "name": "StressTest" },
          "flags": { \(flags.joined(separator: ",\n    ")) }
        }
        """
    }

    /// Generate JSON with diverse EppoValue types for polymorphic parsing benchmarks
    private func generateEppoValueTestJSON() -> String {
        return """
        {
          "string_value": "test_string_value_with_some_length",
          "boolean_value_true": true,
          "boolean_value_false": false,
          "integer_value": 42,
          "double_value": 3.14159265359,
          "large_number": 1234567890.123456789,
          "string_array": ["item1", "item2", "item3", "item4", "item5"],
          "large_string_array": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"],
          "null_value": null,
          "empty_string": "",
          "zero_number": 0,
          "negative_number": -999.999,
          "very_long_string": "This is a very long string that contains a significant amount of text to test memory allocation patterns when parsing longer string values in the EppoValue polymorphic type decoder implementation."
        }
        """
    }

    // MARK: - Configuration Parsing Benchmarks

    /// Benchmark memory allocation for small configuration parsing
    func testConfigurationParsingSmall() {
        let jsonData = Data(smallConfigurationJSON.utf8)

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse small configuration: \(error)")
                }
            }
        }
    }

    /// Benchmark memory allocation for medium configuration parsing
    func testConfigurationParsingMedium() {
        let jsonData = Data(generateMediumConfigurationJSON().utf8)

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse medium configuration: \(error)")
                }
            }
        }
    }

    /// Benchmark memory allocation for large configuration parsing (stress test)
    func testConfigurationParsingLarge() {
        let jsonData = Data(generateLargeConfigurationJSON().utf8)
        print("Large JSON size: \(jsonData.count / 1024) KB")

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse large configuration: \(error)")
                }
            }
        }
    }

    /// Benchmark memory allocation for obfuscated configuration parsing
    func testConfigurationParsingObfuscated() {
        let jsonData = Data(generateMediumConfigurationJSON().utf8)

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: true)
                } catch {
                    XCTFail("Failed to parse obfuscated configuration: \(error)")
                }
            }
        }
    }

    // MARK: - EppoValue Polymorphic Parsing Benchmarks

    /// Benchmark memory allocation for EppoValue polymorphic type parsing
    func testEppoValuePolymorphicParsing() {
        let jsonData = Data(generateEppoValueTestJSON().utf8)
        let decoder = JSONDecoder()

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try decoder.decode([String: EppoValue].self, from: jsonData)
                } catch {
                    XCTFail("Failed to parse EppoValue types: \(error)")
                }
            }
        }
    }

    /// Benchmark memory allocation for repeated EppoValue parsing (worst-case scenario)
    func testEppoValueRepeatedParsing() {
        let jsonObjects = [
            #"{"value": "string"}"#,
            #"{"value": 42}"#,
            #"{"value": 3.14}"#,
            #"{"value": true}"#,
            #"{"value": ["a", "b", "c"]}"#,
            #"{"value": null}"#
        ]

        let decoder = JSONDecoder()

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                for _ in 0..<100 {
                    for jsonString in jsonObjects {
                        do {
                            let jsonData = Data(jsonString.utf8)
                            let _ = try decoder.decode([String: EppoValue].self, from: jsonData)
                        } catch {
                            XCTFail("Failed to parse EppoValue: \(error)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Disk Persistence Benchmarks

    /// Benchmark memory allocation for configuration disk persistence operations
    func testConfigurationDiskPersistence() throws {
        let jsonData = Data(generateMediumConfigurationJSON().utf8)
        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let store = ConfigurationStore()

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                // Test saving and loading configuration
                store.setConfiguration(configuration: configuration)
                let _ = store.getConfiguration()
            }
        }
    }

    /// Benchmark memory allocation for repeated disk operations
    func testRepeatedDiskOperations() throws {
        let jsonData = Data(smallConfigurationJSON.utf8)
        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let store = ConfigurationStore()

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                for _ in 0..<50 {
                    store.setConfiguration(configuration: configuration)
                    let _ = store.getConfiguration()
                }
            }
        }
    }

    // MARK: - JSON Serialization Benchmarks

    /// Benchmark memory allocation for JSON serialization (Configuration -> JSON)
    func testJSONSerializationBenchmark() throws {
        let jsonData = Data(generateMediumConfigurationJSON().utf8)
        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try configuration.toJsonString()
                } catch {
                    XCTFail("Failed to serialize configuration to JSON: \(error)")
                }
            }
        }
    }

    // MARK: - Memory Leak Detection Tests (Simplified)

    /// Test configuration parsing without memory leaks
    func testConfigurationParsingStressTest() {
        let jsonData = Data(generateMediumConfigurationJSON().utf8)

        // Perform multiple parsing operations to test for memory accumulation
        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                for _ in 0..<10 {
                    do {
                        let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                    } catch {
                        XCTFail("Failed to parse configuration: \(error)")
                    }
                }
            }
        }
    }

    /// Test EppoValue parsing stress test
    func testEppoValueParsingStressTest() {
        let jsonData = Data(generateEppoValueTestJSON().utf8)
        let decoder = JSONDecoder()

        // Perform multiple parsing operations to test for memory accumulation
        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                for _ in 0..<50 {
                    do {
                        let _ = try decoder.decode([String: EppoValue].self, from: jsonData)
                    } catch {
                        XCTFail("Failed to parse EppoValue: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Performance Comparison Tests

    /// Compare memory allocation between small, medium, and large configurations
    func testMemoryScalingComparison() {
        let smallData = Data(smallConfigurationJSON.utf8)
        let mediumData = Data(generateMediumConfigurationJSON().utf8)
        let largeData = Data(generateLargeConfigurationJSON().utf8)

        print("JSON Sizes - Small: \(smallData.count) bytes, Medium: \(mediumData.count) bytes, Large: \(largeData.count) bytes")

        // Small configuration
        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: smallData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse small configuration: \(error)")
                }
            }
        }

        // Medium configuration
        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: mediumData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse medium configuration: \(error)")
                }
            }
        }

        // Large configuration
        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: largeData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse large configuration: \(error)")
                }
            }
        }
    }

    // MARK: - Edge Case Memory Tests

    /// Test memory behavior with deeply nested JSON structures
    func testDeeplyNestedJSONMemory() {
        // Create a JSON with deeply nested allocations and rules
        let nestedJSON = """
        {
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": { "name": "NestedTest" },
          "flags": {
            "nested_flag": {
              "key": "nested_flag",
              "enabled": true,
              "variationType": "JSON",
              "variations": {
                "nested": { "key": "nested", "value": "{\\"level1\\": {\\"level2\\": {\\"level3\\": {\\"level4\\": {\\"level5\\": \\"deep_value\\"}}}}}" }
              },
              "allocations": [{
                "key": "nested_allocation",
                "doLog": true,
                "rules": [
                  { "conditions": [{ "operator": "ONE_OF", "attribute": "attr1", "value": ["val1", "val2"] }] },
                  { "conditions": [{ "operator": "MATCHES", "attribute": "attr2", "value": "pattern.*" }] },
                  { "conditions": [{ "operator": "GT", "attribute": "attr3", "value": 100 }] }
                ],
                "splits": [{ "variationKey": "nested", "shards": [] }]
              }],
              "totalShards": 10000
            }
          }
        }
        """

        let jsonData = Data(nestedJSON.utf8)

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse nested configuration: \(error)")
                }
            }
        }
    }

    /// Test memory behavior with empty/minimal JSON structures
    func testMinimalJSONMemory() {
        let minimalJSON = """
        {
          "createdAt": "2024-04-17T19:40:53.716Z",
          "environment": { "name": "Minimal" },
          "flags": {}
        }
        """

        let jsonData = Data(minimalJSON.utf8)

        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                do {
                    let _ = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                } catch {
                    XCTFail("Failed to parse minimal configuration: \(error)")
                }
            }
        }
    }
}