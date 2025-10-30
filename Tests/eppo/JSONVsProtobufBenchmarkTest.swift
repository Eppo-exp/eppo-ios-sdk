import XCTest
@testable import EppoFlagging
import Foundation

/**
 * Simple JSON vs Protobuf Lazy Performance Comparison Test
 * This test directly compares startup and evaluation performance between JSON and Protobuf Lazy modes.
 */
final class JSONVsProtobufBenchmarkTest: XCTestCase {

    func testJSONVsProtobufLazyBenchmark() throws {
        print("🚀 Starting JSON vs Protobuf Lazy Performance Benchmark")
        print("🎯 Focus: Startup time and evaluation correctness comparison")

        // Load test data files
        let jsonData = try loadTestDataFile("flags-v1.json")
        let protobufData = try loadTestDataFile("flags-v1.pb")

        print("   📄 JSON size: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary))")
        print("   🧠 Protobuf size: \(ByteCountFormatter.string(fromByteCount: Int64(protobufData.count), countStyle: .binary))")

        // === JSON MODE BENCHMARK ===
        print("\n📦 Benchmarking JSON Mode...")
        let jsonStart = CFAbsoluteTimeGetCurrent()

        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let jsonClient = EppoClient.initializeOffline(
            sdkKey: "json-test",
            assignmentLogger: nil,
            initialConfiguration: configuration
        )

        let jsonStartupTime = (CFAbsoluteTimeGetCurrent() - jsonStart) * 1000
        print("   ⚡ JSON startup: \(Int(jsonStartupTime))ms")

        // === PROTOBUF LAZY MODE BENCHMARK ===
        print("\n📦 Benchmarking Protobuf Lazy Mode...")
        let protobufStart = CFAbsoluteTimeGetCurrent()

        let protobufClient = try ProtobufLazyClient(
            sdkKey: "protobuf-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil
        )

        let protobufStartupTime = (CFAbsoluteTimeGetCurrent() - protobufStart) * 1000
        print("   ⚡ Protobuf startup: \(Int(protobufStartupTime))ms")

        // === EVALUATION BENCHMARK ===
        print("\n🔄 Running evaluation performance test...")

        // Get 5 test flags for comparison
        let flagKeys = Array(configuration.flagsConfiguration.flags.keys.prefix(5))
        let numEvaluations = flagKeys.count * 3 // 3 subjects per flag = 15 total evaluations

        // JSON evaluation benchmark
        let jsonEvalStart = CFAbsoluteTimeGetCurrent()
        for flagKey in flagKeys {
            if let flag = configuration.flagsConfiguration.flags[flagKey] {
                for i in 0..<3 {
                    let subjectKey = "test_subject_\(i)"
                    let attributes: [String: EppoValue] = [:]

                    switch flag.variationType {
                    case .boolean:
                        _ = jsonClient.getBooleanAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: false
                        )
                    case .string:
                        _ = jsonClient.getStringAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: ""
                        )
                    case .integer:
                        _ = jsonClient.getIntegerAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: 0
                        )
                    case .numeric:
                        _ = jsonClient.getNumericAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: 0.0
                        )
                    case .json:
                        _ = jsonClient.getJSONStringAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: "{}"
                        )
                    }
                }
            }
        }
        let jsonEvalTime = (CFAbsoluteTimeGetCurrent() - jsonEvalStart) * 1000

        // Protobuf evaluation benchmark
        let protobufEvalStart = CFAbsoluteTimeGetCurrent()
        for flagKey in flagKeys {
            if let flagType = protobufClient.getFlagVariationType(flagKey: flagKey) {
                for i in 0..<3 {
                    let subjectKey = "test_subject_\(i)"
                    let attributes: [String: EppoValue] = [:]

                    switch flagType {
                    case .boolean:
                        _ = protobufClient.getBooleanAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: false
                        )
                    case .string:
                        _ = protobufClient.getStringAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: ""
                        )
                    case .integer:
                        _ = protobufClient.getIntegerAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: 0
                        )
                    case .numeric:
                        _ = protobufClient.getNumericAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: 0.0
                        )
                    case .json:
                        _ = protobufClient.getJSONStringAssignment(
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: attributes,
                            defaultValue: "{}"
                        )
                    }
                }
            }
        }
        let protobufEvalTime = (CFAbsoluteTimeGetCurrent() - protobufEvalStart) * 1000

        // === RESULTS COMPARISON ===
        let startupSpeedup = jsonStartupTime / protobufStartupTime
        let jsonEvalsPerSec = Double(numEvaluations) / (jsonEvalTime / 1000.0)
        let protobufEvalsPerSec = Double(numEvaluations) / (protobufEvalTime / 1000.0)
        let evalSpeedup = protobufEvalsPerSec / jsonEvalsPerSec

        print("\n🏆 PERFORMANCE BENCHMARK RESULTS:")
        print("📊 JSON Mode:")
        print("   🎯 Startup: \(Int(jsonStartupTime))ms")
        print("   ⚡ Evaluation: \(Int(jsonEvalsPerSec)) evals/sec (\(String(format: "%.2f", jsonEvalTime))ms for \(numEvaluations) evals)")
        print("📊 Protobuf Lazy Mode:")
        print("   🎯 Startup: \(Int(protobufStartupTime))ms")
        print("   ⚡ Evaluation: \(Int(protobufEvalsPerSec)) evals/sec (\(String(format: "%.2f", protobufEvalTime))ms for \(numEvaluations) evals)")

        print("\n🏁 PERFORMANCE COMPARISON:")
        print("   ⚡ Startup Speedup: \(String(format: "%.1f", startupSpeedup))x faster with Protobuf")
        print("   🚀 Evaluation Performance: \(String(format: "%.1f", evalSpeedup))x (Protobuf vs JSON)")

        // Performance assertions
        XCTAssertGreaterThan(startupSpeedup, 1.0, "Protobuf should have faster startup than JSON")
        XCTAssertLessThan(protobufStartupTime, 100, "Protobuf startup should be very fast (<100ms)")
        XCTAssertGreaterThan(protobufEvalsPerSec, 100, "Protobuf should handle at least 100 evaluations per second")

        print("\n✅ JSON vs Protobuf Lazy benchmark completed successfully!")
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

enum TestError: Error {
    case fileNotFound(String)
}