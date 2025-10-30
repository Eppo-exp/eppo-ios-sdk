import XCTest
@testable import EppoFlagging
import Foundation

// Protocol for performance testing - allows all clients to be tested with the same code
protocol AssignmentClient {
    func getBooleanAssignment(flagKey: String, subjectKey: String, subjectAttributes: SubjectAttributes, defaultValue: Bool) -> Bool
    func getStringAssignment(flagKey: String, subjectKey: String, subjectAttributes: SubjectAttributes, defaultValue: String) -> String
    func getNumericAssignment(flagKey: String, subjectKey: String, subjectAttributes: SubjectAttributes, defaultValue: Double) -> Double
    func getIntegerAssignment(flagKey: String, subjectKey: String, subjectAttributes: SubjectAttributes, defaultValue: Int) -> Int
    func getJSONStringAssignment(flagKey: String, subjectKey: String, subjectAttributes: SubjectAttributes, defaultValue: String) -> String
}

// Extend EppoClient to conform to the protocol
extension EppoClient: AssignmentClient {}

// Extend ProtobufLazyClient to conform to the protocol
extension ProtobufLazyClient: AssignmentClient {}

// Extend PurePBClient to conform to the protocol
extension PurePBClient: AssignmentClient {}

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

        // JSON Evaluation Performance
        let jsonResults = try performEvaluationBenchmark(client: jsonClient, clientName: "JSON")

        // Release JSON client memory
        let jsonClient_temp = jsonClient // Keep reference
        let jsonConfiguration_temp = configuration
        // Allow ARC to cleanup
        _ = jsonClient_temp
        _ = jsonConfiguration_temp

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

        // Protobuf Evaluation Performance
        let protobufResults = try performEvaluationBenchmark(client: lazyProtobufClient, clientName: "Protobuf")

        // Release Lazy Protobuf client memory
        let lazyProtobufClient_temp = lazyProtobufClient // Keep reference
        // Allow ARC to cleanup
        _ = lazyProtobufClient_temp

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

        // Pure Protobuf Evaluation Performance
        let pureProtobufResults = try performEvaluationBenchmark(client: pureProtobufClient, clientName: "Pure Protobuf")

        // Release Pure Protobuf client memory
        let pureProtobufClient_temp = pureProtobufClient // Keep reference
        // Allow ARC to cleanup
        _ = pureProtobufClient_temp

        // === PERFORMANCE COMPARISON ===
        let lazyStartupSpeedup = jsonStartupTime / protobufStartupTime
        let pureStartupSpeedup = jsonStartupTime / pureProtobufStartupTime
        let lazyEvaluationSpeedRatio = protobufResults.evalsPerSec / jsonResults.evalsPerSec
        let pureEvaluationSpeedRatio = pureProtobufResults.evalsPerSec / jsonResults.evalsPerSec

        print("\n🏆 PERFORMANCE RESULTS:")
        print("═══════════════════════════════════════════════")
        print("📊 JSON Mode (Baseline):")
        print("   🎯 Startup: \(Int(jsonStartupTime))ms")
        print("   🚀 Evaluation: \(Int(jsonResults.evalsPerSec)) evals/sec")

        print("📊 Lazy Protobuf Mode:")
        print("   🎯 Startup: \(Int(protobufStartupTime))ms")
        print("   🚀 Evaluation: \(Int(protobufResults.evalsPerSec)) evals/sec")

        print("📊 Pure Protobuf Mode:")
        print("   🎯 Startup: \(Int(pureProtobufStartupTime))ms")
        print("   🚀 Evaluation: \(Int(pureProtobufResults.evalsPerSec)) evals/sec")

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
        XCTAssertGreaterThan(jsonResults.evalsPerSec, 100, "JSON should handle at least 100 evaluations per second")

        print("\n✅ Performance benchmark completed successfully!")
    }

    // MARK: - Helper Methods

    private func performEvaluationBenchmark(client: AssignmentClient, clientName: String) throws -> (evaluationCount: Int, evalTime: Double, evalsPerSec: Double) {
        let evalStart = CFAbsoluteTimeGetCurrent()
        var evaluationCount = 0

        // Get all test case files and iterate through them
        let testFiles = try getTestFiles()
        for testFile in testFiles {
            let testCase = try loadTestCase(from: testFile)

            for subject in testCase.subjects {
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

                // Get assignment based on variation type
                switch testCase.variationType {
                case "BOOLEAN":
                    _ = client.getBooleanAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? Bool) ?? false
                    )
                case "STRING":
                    _ = client.getStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? String) ?? ""
                    )
                case "NUMERIC":
                    _ = client.getNumericAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? Double) ?? 0.0
                    )
                case "INTEGER":
                    _ = client.getIntegerAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? Int) ?? 0
                    )
                case "JSON":
                    _ = client.getJSONStringAssignment(
                        flagKey: testCase.flag,
                        subjectKey: subject.subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: (testCase.defaultValue.value as? String) ?? ""
                    )
                default:
                    continue
                }
                evaluationCount += 1
            }
        }

        let evalTime = (CFAbsoluteTimeGetCurrent() - evalStart) * 1000
        let evalsPerSec = Double(evaluationCount) / (evalTime / 1000.0)
        print("   🚀 \(clientName) evaluation: \(Int(evalsPerSec)) evals/sec (\(evaluationCount) evals in \(Int(evalTime))ms)")

        return (evaluationCount, evalTime, evalsPerSec)
    }

    private func loadTestDataFile(_ filename: String) throws -> Data {
        guard let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/\(filename)",
            withExtension: ""
        ) else {
            throw TestError.fileNotFound("Could not find test data file: \(filename)")
        }

        return try Data(contentsOf: fileURL)
    }

    private func loadTestCase(from filePath: String) throws -> UFCTestCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(UFCTestCase.self, from: data)
    }
}