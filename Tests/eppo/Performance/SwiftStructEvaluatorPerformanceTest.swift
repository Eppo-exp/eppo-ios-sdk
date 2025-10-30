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

// Extend SwiftStructFromProtobufClient to conform to the protocol
extension SwiftStructFromProtobufClient: AssignmentClient {}

// Extend SwiftStructFromFlatBufferClient to conform to the protocol
extension SwiftStructFromFlatBufferClient: AssignmentClient {}

// Extend NativeProtobufClient to conform to the protocol
extension NativeProtobufClient: AssignmentClient {}

// MARK: - Performance Test Configuration

/// Number of times to run through the test data to measure cached performance
private let BENCHMARK_ITERATIONS = 3

/**
 * Evaluator Performance Benchmark
 * Tests startup time and evaluation performance comparing:
 * - Swift Struct Evaluators: JSON init, lazy PB, protobuf init, lazy FlatBuffer, and FlatBuffer init
 * - Native Evaluators (NO SWIFT STRUCTS): Native protobuf (lazy & prewarmed) - direct binary format evaluation
 *
 * Runs test data \(BENCHMARK_ITERATIONS)x to measure performance after caches are warmed up
 */
final class MultiwayLoadTest: XCTestCase {

    func testSwiftStructEvaluatorPerformance() throws {
        print("🚀 Evaluator Performance Benchmark")
        print("🎯 Dataset: flags-10000 (large scale)")
        print("🔄 Iterations: \(BENCHMARK_ITERATIONS)x per evaluator (to measure cached performance)")
        print("📋 Swift Struct Modes: JSON init (baseline), Lazy PB, Protobuf init, Lazy FlatBuffer, FlatBuffer init")
        print("📋 Native Modes: Native PB (Lazy & Prewarmed) - NO SWIFT STRUCTS")

        // Load test data
        let jsonData = try loadTestDataFile("flags-10000.json")
        let protobufData = try loadTestDataFile("flags-10000.pb")
        let flatBufferData = try loadTestDataFile("flags-10000.flatbuf")

        print("\n📁 Data file sizes:")
        print("   📄 JSON: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary))")
        print("   🧠 Protobuf: \(ByteCountFormatter.string(fromByteCount: Int64(protobufData.count), countStyle: .binary))")
        print("   📦 FlatBuffer: \(ByteCountFormatter.string(fromByteCount: Int64(flatBufferData.count), countStyle: .binary))")

        // === SWIFT STRUCT EVALUATOR (JSON INIT) BENCHMARK ===
        print("\n📦 1. Benchmarking Swift Struct Evaluator (JSON init)...")
        let jsonStartTime = CFAbsoluteTimeGetCurrent()

        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let jsonClient = EppoClient.initializeOffline(
            sdkKey: "json-test",
            assignmentLogger: nil,
            initialConfiguration: configuration
        )

        let jsonStartupTime = (CFAbsoluteTimeGetCurrent() - jsonStartTime) * 1000
        let jsonFlagCount = configuration.flagsConfiguration.flags.count
        print("   ⚡ Startup: \(formatNumber(Int(jsonStartupTime)))ms (swift structs populated from JSON - \(jsonFlagCount) flags)")

        // Swift Struct Evaluator (JSON init) Evaluation Performance
        let jsonResults = try performEvaluationBenchmark(client: jsonClient, clientName: "Swift Struct Evaluator (JSON init)")

        // Release JSON client memory
        let jsonClient_temp = jsonClient // Keep reference
        let jsonConfiguration_temp = configuration
        // Allow ARC to cleanup
        _ = jsonClient_temp
        _ = jsonConfiguration_temp

        // === SWIFT STRUCT EVALUATOR (LAZY PB) BENCHMARK ===
        print("\n📦 2. Benchmarking Swift Struct Evaluator (Lazy PB)...")
        let protobufStartTime = CFAbsoluteTimeGetCurrent()

        let lazyProtobufClient = try SwiftStructFromProtobufClient(
            sdkKey: "protobuf-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: false
        )

        let protobufStartupTime = (CFAbsoluteTimeGetCurrent() - protobufStartTime) * 1000
        print("   ⚡ Startup: \(formatNumber(Int(protobufStartupTime)))ms (protobuf parsed only - lazy swift struct conversion)")

        // Swift Struct Evaluator (Lazy PB) Evaluation Performance
        let protobufResults = try performEvaluationBenchmark(client: lazyProtobufClient, clientName: "Swift Struct Evaluator (Lazy PB)")

        // Release Lazy Protobuf client memory
        let lazyProtobufClient_temp = lazyProtobufClient // Keep reference
        // Allow ARC to cleanup
        _ = lazyProtobufClient_temp

        // === SWIFT STRUCT EVALUATOR (PROTOBUF INIT) BENCHMARK ===
        print("\n📦 3. Benchmarking Swift Struct Evaluator (Protobuf init)...")
        let pureProtobufStartTime = CFAbsoluteTimeGetCurrent()

        let pureProtobufClient = try SwiftStructFromProtobufClient(
            sdkKey: "protobuf-init-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: true
        )

        let pureProtobufStartupTime = (CFAbsoluteTimeGetCurrent() - pureProtobufStartTime) * 1000
        print("   ⚡ Startup: \(formatNumber(Int(pureProtobufStartupTime)))ms (swift structs populated from protobuf)")

        // Swift Struct Evaluator (Protobuf init) Evaluation Performance
        let pureProtobufResults = try performEvaluationBenchmark(client: pureProtobufClient, clientName: "Swift Struct Evaluator (Protobuf init)")

        // Release Pure Protobuf client memory
        let pureProtobufClient_temp = pureProtobufClient // Keep reference
        // Allow ARC to cleanup
        _ = pureProtobufClient_temp

        // === SWIFT STRUCT EVALUATOR (LAZY FLATBUFFER) BENCHMARK ===
        print("\n📦 4. Benchmarking Swift Struct Evaluator (Lazy FlatBuffer)...")
        let lazyFlatBufferStartTime = CFAbsoluteTimeGetCurrent()

        let lazyFlatBufferClient = try SwiftStructFromFlatBufferClient(
            sdkKey: "lazy-flatbuffer-test",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: false
        )

        let lazyFlatBufferStartupTime = (CFAbsoluteTimeGetCurrent() - lazyFlatBufferStartTime) * 1000
        print("   ⚡ Startup: \(formatNumber(Int(lazyFlatBufferStartupTime)))ms (FlatBuffer parsed only - lazy swift struct conversion)")

        // Swift Struct Evaluator (Lazy FlatBuffer) Evaluation Performance
        let lazyFlatBufferResults = try performEvaluationBenchmark(client: lazyFlatBufferClient, clientName: "Swift Struct Evaluator (Lazy FlatBuffer)")

        // Release Lazy FlatBuffer client memory
        let lazyFlatBufferClient_temp = lazyFlatBufferClient // Keep reference
        // Allow ARC to cleanup
        _ = lazyFlatBufferClient_temp

        // === SWIFT STRUCT EVALUATOR (FLATBUFFER INIT) BENCHMARK ===
        print("\n📦 5. Benchmarking Swift Struct Evaluator (FlatBuffer init)...")
        let flatBufferStartTime = CFAbsoluteTimeGetCurrent()

        let flatBufferClient = try SwiftStructFromFlatBufferClient(
            sdkKey: "flatbuffer-init-test",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: true
        )

        let flatBufferStartupTime = (CFAbsoluteTimeGetCurrent() - flatBufferStartTime) * 1000
        print("   ⚡ Startup: \(formatNumber(Int(flatBufferStartupTime)))ms (swift structs populated from FlatBuffer)")

        // Swift Struct Evaluator (FlatBuffer init) Evaluation Performance
        let flatBufferResults = try performEvaluationBenchmark(client: flatBufferClient, clientName: "Swift Struct Evaluator (FlatBuffer init)")

        // Release FlatBuffer client memory
        let flatBufferClient_temp = flatBufferClient // Keep reference
        // Allow ARC to cleanup
        _ = flatBufferClient_temp

        // === NATIVE EVALUATORS (NO SWIFT STRUCT CONVERSION) ===
        print("\n🔴 ============================================")
        print("🔴 NATIVE EVALUATORS (Direct Binary Format)")
        print("🔴 NO SWIFT STRUCT CONVERSION - Pure Binary")
        print("🔴 ============================================")

        // === NATIVE PROTOBUF EVALUATOR (LAZY) BENCHMARK ===
        print("\n📦 6. Benchmarking Native Protobuf Evaluator (Lazy)...")
        let nativeProtobufStartTime = CFAbsoluteTimeGetCurrent()

        let nativeProtobufClient = try NativeProtobufClient(
            sdkKey: "native-protobuf-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: false
        )

        let nativeProtobufStartupTime = (CFAbsoluteTimeGetCurrent() - nativeProtobufStartTime) * 1000
        print("   ⚡ Startup: \(formatNumber(Int(nativeProtobufStartupTime)))ms (Native protobuf evaluation - NO SWIFT STRUCTS)")

        // Native Protobuf Evaluator Evaluation Performance
        let nativeProtobufResults = try performEvaluationBenchmark(client: nativeProtobufClient, clientName: "Native Protobuf Evaluator (Lazy)")

        // Release Native Protobuf client memory
        let nativeProtobufClient_temp = nativeProtobufClient // Keep reference
        // Allow ARC to cleanup
        _ = nativeProtobufClient_temp

        // === NATIVE PROTOBUF EVALUATOR (PREWARMED) BENCHMARK ===
        print("\n📦 7. Benchmarking Native Protobuf Evaluator (Prewarmed)...")
        let nativeProtobufPrewarmedStartTime = CFAbsoluteTimeGetCurrent()

        let nativeProtobufPrewarmedClient = try NativeProtobufClient(
            sdkKey: "native-protobuf-prewarmed-test",
            protobufData: protobufData,
            obfuscated: false,
            assignmentLogger: nil,
            prewarmCache: true
        )

        let nativeProtobufPrewarmedStartupTime = (CFAbsoluteTimeGetCurrent() - nativeProtobufPrewarmedStartTime) * 1000
        print("   ⚡ Startup: \(formatNumber(Int(nativeProtobufPrewarmedStartupTime)))ms (Native protobuf prewarmed cache - NO SWIFT STRUCTS)")

        // Native Protobuf Evaluator (Prewarmed) Evaluation Performance
        let nativeProtobufPrewarmedResults = try performEvaluationBenchmark(client: nativeProtobufPrewarmedClient, clientName: "Native Protobuf Evaluator (Prewarmed)")

        // Release Native Protobuf Prewarmed client memory
        let nativeProtobufPrewarmedClient_temp = nativeProtobufPrewarmedClient // Keep reference
        // Allow ARC to cleanup
        _ = nativeProtobufPrewarmedClient_temp

        // === PERFORMANCE COMPARISON ===
        let lazyStartupSpeedup = jsonStartupTime / protobufStartupTime
        let pureStartupSpeedup = jsonStartupTime / pureProtobufStartupTime
        let lazyFlatBufferStartupSpeedup = jsonStartupTime / lazyFlatBufferStartupTime
        let flatBufferStartupSpeedup = jsonStartupTime / flatBufferStartupTime
        let nativeProtobufStartupSpeedup = jsonStartupTime / nativeProtobufStartupTime
        let nativeProtobufPrewarmedStartupSpeedup = jsonStartupTime / nativeProtobufPrewarmedStartupTime
        let lazyEvaluationSpeedRatio = protobufResults.evalsPerSec / jsonResults.evalsPerSec
        let pureEvaluationSpeedRatio = pureProtobufResults.evalsPerSec / jsonResults.evalsPerSec
        let lazyFlatBufferEvaluationSpeedRatio = lazyFlatBufferResults.evalsPerSec / jsonResults.evalsPerSec
        let flatBufferEvaluationSpeedRatio = flatBufferResults.evalsPerSec / jsonResults.evalsPerSec
        let nativeProtobufEvaluationSpeedRatio = nativeProtobufResults.evalsPerSec / jsonResults.evalsPerSec
        let nativeProtobufPrewarmedEvaluationSpeedRatio = nativeProtobufPrewarmedResults.evalsPerSec / jsonResults.evalsPerSec

        print("\n🏆 PERFORMANCE RESULTS:")
        print("═══════════════════════════════════════════════")
        print("📊 Swift Struct Evaluator (JSON init) - BASELINE:")
        print("   ⏱️ Startup: \(formatNumber(Int(jsonStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(jsonResults.evalsPerSec))) evals/sec")

        print("📊 Swift Struct Evaluator (Lazy PB):")
        print("   ⏱️ Startup: \(formatNumber(Int(protobufStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(protobufResults.evalsPerSec))) evals/sec")

        print("📊 Swift Struct Evaluator (Protobuf init):")
        print("   ⏱️ Startup: \(formatNumber(Int(pureProtobufStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(pureProtobufResults.evalsPerSec))) evals/sec")

        print("📊 Swift Struct Evaluator (Lazy FlatBuffer):")
        print("   ⏱️ Startup: \(formatNumber(Int(lazyFlatBufferStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(lazyFlatBufferResults.evalsPerSec))) evals/sec")

        print("📊 Swift Struct Evaluator (FlatBuffer init):")
        print("   ⏱️ Startup: \(formatNumber(Int(flatBufferStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(flatBufferResults.evalsPerSec))) evals/sec")

        print("")
        print("🔴 NATIVE EVALUATORS (NO SWIFT STRUCTS):")
        print("📊 Native Protobuf Evaluator (Lazy):")
        print("   ⏱️ Startup: \(formatNumber(Int(nativeProtobufStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(nativeProtobufResults.evalsPerSec))) evals/sec")

        print("📊 Native Protobuf Evaluator (Prewarmed):")
        print("   ⏱️ Startup: \(formatNumber(Int(nativeProtobufPrewarmedStartupTime)))ms")
        print("   🚀 Evaluation: \(formatNumber(Int(nativeProtobufPrewarmedResults.evalsPerSec))) evals/sec")

        print("\n🏁 COMPARISON (vs JSON init baseline):")
        print("   ⚡ Startup Performance:")
        print("      🧠 Lazy PB: \(String(format: "%.1f", lazyStartupSpeedup))x faster")
        print("      🚀 Protobuf init: \(String(format: "%.1f", pureStartupSpeedup))x faster")
        print("      🟦 Lazy FlatBuffer: \(String(format: "%.1f", lazyFlatBufferStartupSpeedup))x faster")
        print("      📦 FlatBuffer init: \(String(format: "%.1f", flatBufferStartupSpeedup))x faster")
        print("      🔴 Native PB (Lazy): \(String(format: "%.1f", nativeProtobufStartupSpeedup))x faster")
        print("      🔴 Native PB (Prewarmed): \(String(format: "%.1f", nativeProtobufPrewarmedStartupSpeedup))x faster")
        print("   🚀 Evaluation Performance:")
        print("      🧠 Lazy PB: \(String(format: "%.3f", lazyEvaluationSpeedRatio))x relative speed")
        print("      🚀 Protobuf init: \(String(format: "%.1f", pureEvaluationSpeedRatio))x relative speed")
        print("      🟦 Lazy FlatBuffer: \(String(format: "%.3f", lazyFlatBufferEvaluationSpeedRatio))x relative speed")
        print("      📦 FlatBuffer init: \(String(format: "%.1f", flatBufferEvaluationSpeedRatio))x relative speed")
        print("      🔴 Native PB (Lazy): \(String(format: "%.3f", nativeProtobufEvaluationSpeedRatio))x relative speed")
        print("      🔴 Native PB (Prewarmed): \(String(format: "%.1f", nativeProtobufPrewarmedEvaluationSpeedRatio))x relative speed")

        print("\n🎯 ARCHITECTURE TRADEOFFS:")
        print("   📄 JSON init: Slow startup (\(formatNumber(Int(jsonStartupTime)))ms - swift structs populated from JSON), fast evaluation (Swift structs)")
        print("   🧠 Lazy PB: Fast startup (\(formatNumber(Int(protobufStartupTime)))ms - protobuf parsed only), slow evaluation (on-demand conversion)")
        print("   🚀 Protobuf init: Medium startup (\(formatNumber(Int(pureProtobufStartupTime)))ms - swift structs populated from protobuf), fast evaluation (pre-converted Swift structs)")
        print("   🟦 Lazy FlatBuffer: Fast startup (\(formatNumber(Int(lazyFlatBufferStartupTime)))ms - FlatBuffer parsed only), slow evaluation (on-demand conversion)")
        print("   📦 FlatBuffer init: Medium startup (\(formatNumber(Int(flatBufferStartupTime)))ms - swift structs populated from FlatBuffer), fast evaluation (pre-converted Swift structs)")
        print("   🔴 Native PB (Lazy): Fast startup (\(formatNumber(Int(nativeProtobufStartupTime)))ms - NO SWIFT STRUCTS), native protobuf evaluation")
        print("   🔴 Native PB (Prewarmed): Medium startup (\(formatNumber(Int(nativeProtobufPrewarmedStartupTime)))ms - cached protobuf lookups), fast native protobuf evaluation")

        // Performance assertions
        XCTAssertGreaterThan(lazyStartupSpeedup, 1.0, "Lazy Protobuf should have faster startup than JSON")
        XCTAssertGreaterThan(pureStartupSpeedup, 1.0, "Pure Protobuf should have faster startup than JSON")
        XCTAssertGreaterThan(lazyFlatBufferStartupSpeedup, 1.0, "Lazy FlatBuffer should have faster startup than JSON")
        XCTAssertGreaterThan(flatBufferStartupSpeedup, 1.0, "FlatBuffer should have faster startup than JSON")
        XCTAssertGreaterThan(nativeProtobufStartupSpeedup, 1.0, "Native Protobuf (Lazy) should have faster startup than JSON")
        XCTAssertGreaterThan(nativeProtobufPrewarmedStartupSpeedup, 1.0, "Native Protobuf (Prewarmed) should have faster startup than JSON")
        XCTAssertGreaterThan(pureEvaluationSpeedRatio, lazyEvaluationSpeedRatio, "Pure Protobuf should evaluate faster than Lazy Protobuf")
        XCTAssertGreaterThan(flatBufferEvaluationSpeedRatio, lazyEvaluationSpeedRatio, "FlatBuffer should evaluate faster than Lazy Protobuf")
        XCTAssertGreaterThan(flatBufferEvaluationSpeedRatio, lazyFlatBufferEvaluationSpeedRatio, "FlatBuffer init should evaluate faster than Lazy FlatBuffer")
        XCTAssertGreaterThan(nativeProtobufPrewarmedEvaluationSpeedRatio, nativeProtobufEvaluationSpeedRatio, "Native Protobuf (Prewarmed) should evaluate faster than Native Protobuf (Lazy)")
        XCTAssertGreaterThan(jsonResults.evalsPerSec, 100, "JSON should handle at least 100 evaluations per second")
        XCTAssertGreaterThan(nativeProtobufResults.evalsPerSec, 100, "Native Protobuf (Lazy) should handle at least 100 evaluations per second")
        XCTAssertGreaterThan(nativeProtobufPrewarmedResults.evalsPerSec, 100, "Native Protobuf (Prewarmed) should handle at least 100 evaluations per second")

        print("\n✅ Performance benchmark completed successfully!")
    }

    // MARK: - Helper Methods

    private func performEvaluationBenchmark(client: AssignmentClient, clientName: String) throws -> (evaluationCount: Int, evalTime: Double, evalsPerSec: Double) {
        let evalStart = CFAbsoluteTimeGetCurrent()
        var evaluationCount = 0

        // Get all test case files once
        let testFiles = try getTestFiles()
        let testCases = try testFiles.map { try loadTestCase(from: $0) }

        // Run through the test data multiple times to measure cached performance
        for iteration in 1...BENCHMARK_ITERATIONS {
            if iteration == 1 {
                print("   🔥 First iteration (warming up caches/parsing)...")
            } else {
                print("   💨 Iteration \(iteration) (cached performance)...")
            }

            let iterationStart = CFAbsoluteTimeGetCurrent()
            var iterationEvalCount = 0

            for testCase in testCases {
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
                    iterationEvalCount += 1
                }
            }

            let iterationTime = (CFAbsoluteTimeGetCurrent() - iterationStart) * 1000
            let iterationEvalsPerSec = Double(iterationEvalCount) / (iterationTime / 1000.0)
            print("      -> \(formatNumber(iterationEvalCount)) evals in \(formatNumber(Int(iterationTime)))ms = \(formatNumber(Int(iterationEvalsPerSec))) evals/sec")
        }

        let evalTime = (CFAbsoluteTimeGetCurrent() - evalStart) * 1000
        let evalsPerSec = Double(evaluationCount) / (evalTime / 1000.0)
        print("   🏁 \(clientName) TOTAL: \(formatNumber(Int(evalsPerSec))) evals/sec (\(formatNumber(evaluationCount)) evals in \(formatNumber(Int(evalTime)))ms over \(BENCHMARK_ITERATIONS) iterations)")

        return (evaluationCount, evalTime, evalsPerSec)
    }

    // MARK: - Number Formatting Helper

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
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
