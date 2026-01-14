import XCTest
@testable import EppoFlagging

/// Dedicated performance tests for measuring SDK startup times with different configuration sizes
final class PerformanceTests: XCTestCase {

    // MARK: - 1K Flag Performance Tests

    func testSDKStartupPerformance1KFlags() {
        guard let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-1k.json",
            withExtension: ""
        ) else {
            XCTFail("Could not find flags-1k.json test file")
            return
        }

        guard let configData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load flags-1k.json")
            return
        }

        // Measure total SDK startup time
        let startTime = Date()

        do {
            let config = try Configuration(flagsConfigurationJson: configData, obfuscated: false)
            let initTime = Date().timeIntervalSince(startTime) * 1000

            print("[PERF] SDK Startup (1K flags): \(String(format: "%.2f", initTime))ms")

            // Verify we loaded expected number of flags
            XCTAssertGreaterThan(config.flagsConfiguration.flags.count, 900, "Should have loaded ~1,000 flags")
            XCTAssertLessThan(config.flagsConfiguration.flags.count, 1100, "Should have loaded ~1,000 flags")

        } catch {
            XCTFail("Failed to initialize configuration: \(error)")
        }
    }

    func testSDKStartupPerformance1KObfuscatedFlags() {
        guard let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-1k-obfuscated.json",
            withExtension: ""
        ) else {
            XCTFail("Could not find flags-1k-obfuscated.json test file")
            return
        }

        guard let configData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load flags-1k-obfuscated.json")
            return
        }

        // Measure total SDK startup time with obfuscated configuration
        let startTime = Date()

        do {
            let config = try Configuration(flagsConfigurationJson: configData, obfuscated: true)
            let initTime = Date().timeIntervalSince(startTime) * 1000

            print("[PERF] SDK Startup (1K obfuscated flags): \(String(format: "%.2f", initTime))ms")

            // Verify we loaded expected number of flags
            XCTAssertGreaterThan(config.flagsConfiguration.flags.count, 900, "Should have loaded ~1,000 obfuscated flags")
            XCTAssertLessThan(config.flagsConfiguration.flags.count, 1100, "Should have loaded ~1,000 obfuscated flags")

        } catch {
            XCTFail("Failed to initialize obfuscated configuration: \(error)")
        }
    }

    // MARK: - Granular Performance Breakdown

    func testJSONDecodingPerformance1K() {
        guard let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-1k.json",
            withExtension: ""
        ) else {
            XCTFail("Could not find flags-1k.json test file")
            return
        }

        guard let configData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load flags-1k.json")
            return
        }

        // Measure just JSON decoding performance
        let startTime = Date()

        do {
            let config = try UniversalFlagConfig.decodeFromJSON(from: configData)
            let decodeTime = Date().timeIntervalSince(startTime) * 1000

            print("[PERF] JSON Decoding (1K flags): \(String(format: "%.2f", decodeTime))ms")

            // Verify decoding worked
            XCTAssertGreaterThan(config.flags.count, 900)

        } catch {
            XCTFail("Failed to decode JSON: \(error)")
        }
    }

    func testJSONDecodingPerformance1KObfuscated() {
        guard let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-1k-obfuscated.json",
            withExtension: ""
        ) else {
            XCTFail("Could not find flags-1k-obfuscated.json test file")
            return
        }

        guard let configData = try? Data(contentsOf: fileURL) else {
            XCTFail("Could not load flags-1k-obfuscated.json")
            return
        }

        // Measure just JSON decoding performance for obfuscated config
        let startTime = Date()

        do {
            let config = try UniversalFlagConfig.decodeFromJSON(from: configData)
            let decodeTime = Date().timeIntervalSince(startTime) * 1000

            print("[PERF] JSON Decoding (1K obfuscated flags): \(String(format: "%.2f", decodeTime))ms")

            // Verify decoding worked
            XCTAssertGreaterThan(config.flags.count, 900)

        } catch {
            XCTFail("Failed to decode obfuscated JSON: \(error)")
        }
    }

    // MARK: - Baseline Comparison Tests

    func testBaselinePerformanceComparison() {
        // Test with original v1 files for comparison
        guard let v1URL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1.json",
            withExtension: ""
        ) else {
            XCTFail("Could not find flags-v1.json")
            return
        }

        guard let v1Data = try? Data(contentsOf: v1URL) else {
            XCTFail("Could not load flags-v1.json")
            return
        }

        let startTime = Date()

        do {
            _ = try Configuration(flagsConfigurationJson: v1Data, obfuscated: false)
            let initTime = Date().timeIntervalSince(startTime) * 1000

            print("[PERF] SDK Startup (v1 baseline): \(String(format: "%.2f", initTime))ms")

        } catch {
            XCTFail("Failed to initialize v1 configuration: \(error)")
        }
    }

    func testBaselineObfuscatedPerformanceComparison() {
        // Test with original v1 obfuscated files for comparison
        guard let v1URL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
            withExtension: ""
        ) else {
            XCTFail("Could not find flags-v1-obfuscated.json")
            return
        }

        guard let v1Data = try? Data(contentsOf: v1URL) else {
            XCTFail("Could not load flags-v1-obfuscated.json")
            return
        }

        let startTime = Date()

        do {
            _ = try Configuration(flagsConfigurationJson: v1Data, obfuscated: true)
            let initTime = Date().timeIntervalSince(startTime) * 1000

            print("[PERF] SDK Startup (v1 obfuscated baseline): \(String(format: "%.2f", initTime))ms")

        } catch {
            XCTFail("Failed to initialize v1 obfuscated configuration: \(error)")
        }
    }
}