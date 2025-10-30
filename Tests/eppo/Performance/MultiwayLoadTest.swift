import XCTest
@testable import EppoFlagging
import Foundation

/**
 * JSON vs Lazy Protobuf vs Pure Protobuf Performance Benchmark
 * Tests startup time and evaluation performance on flags-10000 dataset
 */
final class MultiwayLoadTest: XCTestCase {

    func testMultiwayPerformanceBenchmark() throws {
        print("🚀 JSON vs Lazy Protobuf vs Pure Protobuf Performance Benchmark")
        print("🎯 Dataset: flags-10000 (large scale)")
        print("📋 Modes: JSON (baseline), Lazy PB (fast startup), Pure PB (pre-converted)")

        // Load test data
        let jsonData = try loadTestDataFile("flags-10000.json")
        let protobufData = try loadTestDataFile("flags-10000.pb")

        print("\n📁 Data file sizes:")
        print("   📄 JSON: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary))")
        print("   🧠 Protobuf: \(ByteCountFormatter.string(fromByteCount: Int64(protobufData.count), countStyle: .binary))")

        // === JSON MODE BENCHMARK ===
        print("\n📦 1. Benchmarking JSON Mode...")
        let jsonStartTime = CFAbsoluteTimeGetCurrent()

        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let jsonClient = EppoClient.initializeOffline(
            sdkKey: "json-test",
            assignmentLogger: nil,
            initialConfiguration: configuration
        )

        let jsonStartupTime = (CFAbsoluteTimeGetCurrent() - jsonStartTime) * 1000
        let jsonFlagCount = configuration.flagsConfiguration.flags.count
        print("   ⚡ JSON startup: \(Int(jsonStartupTime))ms (\(jsonFlagCount) flags)")

        // JSON Evaluation Performance (1000 evaluations)
        let jsonEvalStart = CFAbsoluteTimeGetCurrent()
        var jsonEvaluationCount = 0
        let numEvaluations = 1000

        for i in 0..<numEvaluations {
            let subjectKey = "user_\(i % 100)" // Cycle through 100 users
            let attributes = ["country": EppoValue.valueOf("US"), "age": EppoValue.valueOf(25)]

            // Test a few different flag types
            _ = jsonClient.getBooleanAssignment(flagKey: "kill-switch", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: false)
            _ = jsonClient.getStringAssignment(flagKey: "header-text", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: "")
            _ = jsonClient.getNumericAssignment(flagKey: "banner-height", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: 0.0)
            jsonEvaluationCount += 3
        }

        let jsonEvalTime = (CFAbsoluteTimeGetCurrent() - jsonEvalStart) * 1000
        let jsonEvalsPerSec = Double(jsonEvaluationCount) / (jsonEvalTime / 1000.0)
        print("   🚀 JSON evaluation: \(Int(jsonEvalsPerSec)) evals/sec (\(jsonEvaluationCount) evals in \(Int(jsonEvalTime))ms)")

        // === LAZY PROTOBUF MODE BENCHMARK ===
        print("\n📦 2. Benchmarking Lazy Protobuf Mode...")
        let protobufStartTime = CFAbsoluteTimeGetCurrent()

        let lazyProtobufClient = try ProtobufLazyClient(
            sdkKey: "protobuf-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil
        )

        let protobufStartupTime = (CFAbsoluteTimeGetCurrent() - protobufStartTime) * 1000
        print("   ⚡ Protobuf startup: \(Int(protobufStartupTime))ms")

        // Protobuf Evaluation Performance (1000 evaluations)
        let protobufEvalStart = CFAbsoluteTimeGetCurrent()
        var protobufEvaluationCount = 0

        for i in 0..<numEvaluations {
            let subjectKey = "user_\(i % 100)" // Cycle through 100 users
            let attributes = ["country": EppoValue.valueOf("US"), "age": EppoValue.valueOf(25)]

            // Test the same flag types as JSON
            _ = lazyProtobufClient.getBooleanAssignment(flagKey: "kill-switch", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: false)
            _ = lazyProtobufClient.getStringAssignment(flagKey: "header-text", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: "")
            _ = lazyProtobufClient.getNumericAssignment(flagKey: "banner-height", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: 0.0)
            protobufEvaluationCount += 3
        }

        let protobufEvalTime = (CFAbsoluteTimeGetCurrent() - protobufEvalStart) * 1000
        let protobufEvalsPerSec = Double(protobufEvaluationCount) / (protobufEvalTime / 1000.0)
        print("   🚀 Protobuf evaluation: \(Int(protobufEvalsPerSec)) evals/sec (\(protobufEvaluationCount) evals in \(Int(protobufEvalTime))ms)")

        // === PURE PROTOBUF MODE BENCHMARK ===
        print("\n📦 3. Benchmarking Pure Protobuf Mode...")
        let pureProtobufStartTime = CFAbsoluteTimeGetCurrent()

        let pureProtobufClient = try PurePBClient(
            sdkKey: "pure-protobuf-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil
        )

        let pureProtobufStartupTime = (CFAbsoluteTimeGetCurrent() - pureProtobufStartTime) * 1000
        print("   ⚡ Pure Protobuf startup: \(Int(pureProtobufStartupTime))ms")

        // Pure Protobuf Evaluation Performance (1000 evaluations)
        let pureProtobufEvalStart = CFAbsoluteTimeGetCurrent()
        var pureProtobufEvaluationCount = 0

        for i in 0..<numEvaluations {
            let subjectKey = "user_\(i % 100)" // Cycle through 100 users
            let attributes = ["country": EppoValue.valueOf("US"), "age": EppoValue.valueOf(25)]

            // Test the same flag types as JSON and Lazy Protobuf
            _ = pureProtobufClient.getBooleanAssignment(flagKey: "kill-switch", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: false)
            _ = pureProtobufClient.getStringAssignment(flagKey: "header-text", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: "")
            _ = pureProtobufClient.getNumericAssignment(flagKey: "banner-height", subjectKey: subjectKey, subjectAttributes: attributes, defaultValue: 0.0)
            pureProtobufEvaluationCount += 3
        }

        let pureProtobufEvalTime = (CFAbsoluteTimeGetCurrent() - pureProtobufEvalStart) * 1000
        let pureProtobufEvalsPerSec = Double(pureProtobufEvaluationCount) / (pureProtobufEvalTime / 1000.0)
        print("   🚀 Pure Protobuf evaluation: \(Int(pureProtobufEvalsPerSec)) evals/sec (\(pureProtobufEvaluationCount) evals in \(Int(pureProtobufEvalTime))ms)")

        // === PERFORMANCE COMPARISON ===
        let lazyStartupSpeedup = jsonStartupTime / protobufStartupTime
        let pureStartupSpeedup = jsonStartupTime / pureProtobufStartupTime
        let lazyEvaluationSpeedRatio = protobufEvalsPerSec / jsonEvalsPerSec
        let pureEvaluationSpeedRatio = pureProtobufEvalsPerSec / jsonEvalsPerSec

        print("\n🏆 PERFORMANCE RESULTS:")
        print("═══════════════════════════════════════════════")
        print("📊 JSON Mode (Baseline):")
        print("   🎯 Startup: \(Int(jsonStartupTime))ms")
        print("   🚀 Evaluation: \(Int(jsonEvalsPerSec)) evals/sec")

        print("📊 Lazy Protobuf Mode:")
        print("   🎯 Startup: \(Int(protobufStartupTime))ms")
        print("   🚀 Evaluation: \(Int(protobufEvalsPerSec)) evals/sec")

        print("📊 Pure Protobuf Mode:")
        print("   🎯 Startup: \(Int(pureProtobufStartupTime))ms")
        print("   🚀 Evaluation: \(Int(pureProtobufEvalsPerSec)) evals/sec")

        print("\n🏁 COMPARISON (vs JSON baseline):")
        print("   ⚡ Startup Performance:")
        print("      🧠 Lazy Protobuf: \(String(format: "%.1f", lazyStartupSpeedup))x faster")
        print("      🚀 Pure Protobuf: \(String(format: "%.1f", pureStartupSpeedup))x faster")
        print("   🚀 Evaluation Performance:")
        print("      🧠 Lazy Protobuf: \(String(format: "%.3f", lazyEvaluationSpeedRatio))x relative speed")
        print("      🚀 Pure Protobuf: \(String(format: "%.1f", pureEvaluationSpeedRatio))x relative speed")

        print("\n🎯 ARCHITECTURE TRADEOFFS:")
        print("   📄 JSON: Slow startup (\(Int(jsonStartupTime))ms), fast evaluation")
        print("   🧠 Lazy PB: Fast startup (\(Int(protobufStartupTime))ms), slow evaluation (on-demand conversion)")
        print("   🚀 Pure PB: Medium startup (\(Int(pureProtobufStartupTime))ms), fast evaluation (pre-converted)")

        // Performance assertions
        XCTAssertGreaterThan(lazyStartupSpeedup, 1.0, "Lazy Protobuf should have faster startup than JSON")
        XCTAssertGreaterThan(pureStartupSpeedup, 1.0, "Pure Protobuf should have faster startup than JSON")
        XCTAssertGreaterThan(pureEvaluationSpeedRatio, lazyEvaluationSpeedRatio, "Pure Protobuf should evaluate faster than Lazy Protobuf")
        XCTAssertGreaterThan(jsonEvalsPerSec, 100, "JSON should handle at least 100 evaluations per second")

        print("\n✅ Performance benchmark completed successfully!")
    }

    // MARK: - Helper Methods

    private func loadTestDataFile(_ filename: String) throws -> Data {
        guard let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/\(filename)",
            withExtension: ""
        ) else {
            throw TestError.fileNotFound("Could not find test data file: \(filename)")
        }

        return try Data(contentsOf: fileURL)
    }
}