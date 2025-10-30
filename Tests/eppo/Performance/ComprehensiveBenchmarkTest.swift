//import XCTest
//@testable import EppoFlagging
//import Foundation
//
///**
// * Comprehensive Performance Benchmark: JSON vs Lazy Protobuf vs Pure Protobuf
// * Tests all three approaches on the large-scale flags-10000 dataset
// */
//final class ComprehensiveBenchmarkTest: XCTestCase {
//
//    func testComprehensivePerformanceBenchmark() throws {
//        print("🚀 Starting Comprehensive Performance Benchmark")
//        print("🎯 Comparing: JSON, Lazy Protobuf, and Pure Protobuf")
//        print("📊 Dataset: flags-10000 (large scale)")
//
//        // Load large-scale test data files
//        let jsonData = try loadTestDataFile("flags-10000.json")
//        let protobufData = try loadTestDataFile("flags-10000.pb")
//
//        print("\n📁 Data file sizes:")
//        print("   📄 JSON: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary))")
//        print("   🧠 Protobuf: \(ByteCountFormatter.string(fromByteCount: Int64(protobufData.count), countStyle: .binary))")
//
//        // === 1. JSON MODE BENCHMARK ===
//        print("\n📦 1. Benchmarking JSON Mode...")
//        let jsonStart = CFAbsoluteTimeGetCurrent()
//
//        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
//        let jsonClient = EppoClient.initializeOffline(
//            sdkKey: "json-test",
//            assignmentLogger: nil,
//            initialConfiguration: configuration
//        )
//
//        let jsonStartupTime = (CFAbsoluteTimeGetCurrent() - jsonStart) * 1000
//        let jsonFlagCount = configuration.flagsConfiguration.flags.count
//        print("   ⚡ JSON startup: \(Int(jsonStartupTime))ms (\(jsonFlagCount) flags)")
//
//        // === 2. LAZY PROTOBUF MODE BENCHMARK ===
//        print("\n📦 2. Benchmarking Lazy Protobuf Mode...")
//        let lazyProtobufStart = CFAbsoluteTimeGetCurrent()
//
//        let lazyProtobufClient = try ProtobufLazyClient(
//            sdkKey: "lazy-protobuf-test",
//            protobufData: protobufData,
//            obfuscated: false,
//            assignmentLogger: nil
//        )
//
//        let lazyProtobufStartupTime = (CFAbsoluteTimeGetCurrent() - lazyProtobufStart) * 1000
//        let lazyProtobufFlagCount = lazyProtobufClient.getAllFlagKeys().count
//        print("   ⚡ Lazy Protobuf startup: \(Int(lazyProtobufStartupTime))ms (\(lazyProtobufFlagCount) flags)")
//
//        // === 3. PURE PROTOBUF MODE BENCHMARK ===
//        print("\n📦 3. Benchmarking Pure Protobuf Mode...")
//        let pureProtobufStart = CFAbsoluteTimeGetCurrent()
//
//        let pureProtobufClient = try PurePBClient(
//            sdkKey: "pure-protobuf-test",
//            protobufData: protobufData,
//            obfuscated: false,
//            assignmentLogger: nil
//        )
//
//        let pureProtobufStartupTime = (CFAbsoluteTimeGetCurrent() - pureProtobufStart) * 1000
//        let pureProtobufFlagCount = pureProtobufClient.getAllFlagKeys().count
//        print("   ⚡ Pure Protobuf startup: \(Int(pureProtobufStartupTime))ms (\(pureProtobufFlagCount) flags)")
//
//        // === EVALUATION PERFORMANCE BENCHMARK ===
//        print("\n🔄 Running large-scale evaluation performance test...")
//
//        // Use 50 flags with 10 subjects each = 500 total evaluations
//        let testFlagKeys = Array(configuration.flagsConfiguration.flags.keys.prefix(50))
//        let numSubjects = 10
//        let totalEvaluations = testFlagKeys.count * numSubjects
//
//        print("   📊 Testing \(testFlagKeys.count) flags × \(numSubjects) subjects = \(totalEvaluations) evaluations")
//
//        // JSON evaluation benchmark
//        let jsonEvalStart = CFAbsoluteTimeGetCurrent()
//        var jsonEvaluationCount = 0
//        for flagKey in testFlagKeys {
//            if let flag = configuration.flagsConfiguration.flags[flagKey] {
//                for i in 0..<numSubjects {
//                    let subjectKey = "user_\(i)"
//                    let attributes: [String: EppoValue] = ["country": EppoValue(value: "US")]
//
//                    switch flag.variationType {
//                    case .boolean:
//                        _ = jsonClient.getBooleanAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: false
//                        )
//                    case .string:
//                        _ = jsonClient.getStringAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: ""
//                        )
//                    case .integer:
//                        _ = jsonClient.getIntegerAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: 0
//                        )
//                    case .numeric:
//                        _ = jsonClient.getNumericAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: 0.0
//                        )
//                    case .json:
//                        _ = jsonClient.getJSONStringAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: "{}"
//                        )
//                    }
//                    jsonEvaluationCount += 1
//                }
//            }
//        }
//        let jsonEvalTime = (CFAbsoluteTimeGetCurrent() - jsonEvalStart) * 1000
//
//        // Lazy Protobuf evaluation benchmark
//        let lazyEvalStart = CFAbsoluteTimeGetCurrent()
//        var lazyEvaluationCount = 0
//        for flagKey in testFlagKeys {
//            if let flagType = lazyProtobufClient.getFlagVariationType(flagKey: flagKey) {
//                for i in 0..<numSubjects {
//                    let subjectKey = "user_\(i)"
//                    let attributes: [String: EppoValue] = ["country": EppoValue(value: "US")]
//
//                    switch flagType {
//                    case .boolean:
//                        _ = lazyProtobufClient.getBooleanAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: false
//                        )
//                    case .string:
//                        _ = lazyProtobufClient.getStringAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: ""
//                        )
//                    case .integer:
//                        _ = lazyProtobufClient.getIntegerAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: 0
//                        )
//                    case .numeric:
//                        _ = lazyProtobufClient.getNumericAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: 0.0
//                        )
//                    case .json:
//                        _ = lazyProtobufClient.getJSONStringAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: "{}"
//                        )
//                    }
//                    lazyEvaluationCount += 1
//                }
//            }
//        }
//        let lazyEvalTime = (CFAbsoluteTimeGetCurrent() - lazyEvalStart) * 1000
//
//        // Pure Protobuf evaluation benchmark
//        let pureEvalStart = CFAbsoluteTimeGetCurrent()
//        var pureEvaluationCount = 0
//        for flagKey in testFlagKeys {
//            if let flagType = pureProtobufClient.getFlagVariationType(flagKey: flagKey) {
//                for i in 0..<numSubjects {
//                    let subjectKey = "user_\(i)"
//                    let attributes: [String: EppoValue] = ["country": EppoValue(value: "US")]
//
//                    switch flagType {
//                    case .boolean:
//                        _ = pureProtobufClient.getBooleanAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: false
//                        )
//                    case .string:
//                        _ = pureProtobufClient.getStringAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: ""
//                        )
//                    case .integer:
//                        _ = pureProtobufClient.getIntegerAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: 0
//                        )
//                    case .numeric:
//                        _ = pureProtobufClient.getNumericAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: 0.0
//                        )
//                    case .json:
//                        _ = pureProtobufClient.getJSONStringAssignment(
//                            flagKey: flagKey, subjectKey: subjectKey,
//                            subjectAttributes: attributes, defaultValue: "{}"
//                        )
//                    }
//                    pureEvaluationCount += 1
//                }
//            }
//        }
//        let pureEvalTime = (CFAbsoluteTimeGetCurrent() - pureEvalStart) * 1000
//
//        // === PERFORMANCE ANALYSIS ===
//        let jsonEvalsPerSec = Double(jsonEvaluationCount) / (jsonEvalTime / 1000.0)
//        let lazyEvalsPerSec = Double(lazyEvaluationCount) / (lazyEvalTime / 1000.0)
//        let pureEvalsPerSec = Double(pureEvaluationCount) / (pureEvalTime / 1000.0)
//
//        // Calculate speedups (vs JSON baseline)
//        let lazyStartupSpeedup = jsonStartupTime / lazyProtobufStartupTime
//        let pureStartupSpeedup = jsonStartupTime / pureProtobufStartupTime
//        let lazyEvalSpeedup = lazyEvalsPerSec / jsonEvalsPerSec
//        let pureEvalSpeedup = pureEvalsPerSec / jsonEvalsPerSec
//
//        print("\n🏆 COMPREHENSIVE PERFORMANCE RESULTS:")
//        print("═══════════════════════════════════════")
//
//        print("📊 1. JSON Mode (Baseline):")
//        print("   🎯 Startup: \(Int(jsonStartupTime))ms")
//        print("   ⚡ Evaluation: \(Int(jsonEvalsPerSec)) evals/sec (\(String(format: "%.2f", jsonEvalTime))ms for \(jsonEvaluationCount) evals)")
//        print("   📁 Flag Count: \(jsonFlagCount)")
//
//        print("📊 2. Lazy Protobuf Mode:")
//        print("   🎯 Startup: \(Int(lazyProtobufStartupTime))ms")
//        print("   ⚡ Evaluation: \(Int(lazyEvalsPerSec)) evals/sec (\(String(format: "%.2f", lazyEvalTime))ms for \(lazyEvaluationCount) evals)")
//        print("   📁 Flag Count: \(lazyProtobufFlagCount)")
//
//        print("📊 3. Pure Protobuf Mode:")
//        print("   🎯 Startup: \(Int(pureProtobufStartupTime))ms")
//        print("   ⚡ Evaluation: \(Int(pureEvalsPerSec)) evals/sec (\(String(format: "%.2f", pureEvalTime))ms for \(pureEvaluationCount) evals)")
//        print("   📁 Flag Count: \(pureProtobufFlagCount)")
//
//        print("\n🏁 PERFORMANCE COMPARISON (vs JSON baseline):")
//        print("═══════════════════════════════════════════════")
//        print("   ⚡ Startup Performance:")
//        print("      🧠 Lazy Protobuf: \(String(format: "%.1f", lazyStartupSpeedup))x faster")
//        print("      🚀 Pure Protobuf: \(String(format: "%.1f", pureStartupSpeedup))x faster")
//
//        print("   🚀 Evaluation Performance:")
//        print("      🧠 Lazy Protobuf: \(String(format: "%.1f", lazyEvalSpeedup))x performance")
//        print("      🚀 Pure Protobuf: \(String(format: "%.1f", pureEvalSpeedup))x performance")
//
//        print("\n📈 ARCHITECTURE COMPARISON:")
//        print("   📄 JSON: Slow startup, fast evaluation")
//        print("   🧠 Lazy Protobuf: Fast startup, on-demand conversion")
//        print("   🚀 Pure Protobuf: Slower startup, fastest evaluation")
//
//        // Performance assertions
//        XCTAssertGreaterThan(lazyStartupSpeedup, 1.0, "Lazy Protobuf should have faster startup than JSON")
//        XCTAssertGreaterThan(pureEvalsPerSec, jsonEvalsPerSec, "Pure Protobuf should have faster evaluation than JSON")
//        XCTAssertGreaterThan(pureEvalsPerSec, 1000, "Pure Protobuf should handle at least 1000 evaluations per second")
//
//        print("\n✅ Comprehensive benchmark completed successfully!")
//        print("🎯 Recommendation: Use Pure Protobuf for high-frequency evaluation scenarios")
//    }
//
//    // MARK: - Helper Methods
//
//    private func loadTestDataFile(_ filename: String) throws -> Data {
//        guard let fileURL = Bundle.module.url(
//            forResource: "Resources/test-data/ufc/\(filename)",
//            withExtension: ""
//        ) else {
//            throw TestError.fileNotFound("Could not find test data file: \(filename)")
//        }
//
//        return try Data(contentsOf: fileURL)
//    }
//}
