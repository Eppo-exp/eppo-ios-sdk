import XCTest
@testable import EppoFlagging
import Foundation

class LargeFlagPerformanceTests: XCTestCase {

    func testJSONPerformanceBenchmark() throws {
        // This test benchmarks JSON mode performance with focus on startup (key metric) and evaluation (important)
        // Structured to enable easy comparison with FlatBuffer mode in the future

        print("🚀 Starting JSON Performance Benchmark")
        print("🎯 Key Focus: Startup performance (JSON->objects conversion)")
        print("📊 Secondary: Evaluation performance across test cases")

        // PHASE 1: DATA LOADING (wrapped for memory management)
        let jsonResults = try autoreleasepool {
            let dataLoadStart = CFAbsoluteTimeGetCurrent()
            let jsonData = try loadTestDataFile("flags-10000.json")
            let testCases = try loadAllGeneratedTestCases()
            let dataLoadTime = (CFAbsoluteTimeGetCurrent() - dataLoadStart) * 1000

            print("\n📦 Data loaded: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary)) + \(testCases.count) test cases (\(String(format: "%.2f", dataLoadTime))ms)")

            // Measure JSON mode performance
            return try benchmarkJSONMode(jsonData: jsonData, testCases: testCases)
        }

        // FUTURE: Add FlatBuffer mode benchmark here
        // let flatBufferResults = try benchmarkFlatBufferMode(jsonData: jsonData, testCases: testCases)

        // RESULTS SUMMARY
        print("\n🏆 PERFORMANCE BENCHMARK RESULTS:")
        print("📊 JSON Mode:")
        print("   🎯 Startup (KEY METRIC): \(String(format: "%.0f", jsonResults.startupTime))ms")
        print("   ⚡ Evaluation Speed: \(String(format: "%.0f", jsonResults.evaluationsPerSecond)) evals/sec")
        print("   💾 Memory Usage: \(String(format: "%.0f", jsonResults.memoryUsage))MB")
        print("   📊 Total Evaluations: \(jsonResults.totalEvaluations)")

        // FUTURE: Add FlatBuffer comparison here
        // print("📊 FlatBuffer Mode:")
        // print("   🎯 Startup: \(String(format: "%.0f", flatBufferResults.startupTime))ms")
        // print("   ⚡ Evaluation Speed: \(String(format: "%.0f", flatBufferResults.evaluationsPerSecond)) evals/sec")
        // print("   💾 Memory Usage: \(String(format: "%.0f", flatBufferResults.memoryUsage))MB")
        // print("   📊 Total Evaluations: \(flatBufferResults.totalEvaluations)")

        // PERFORMANCE ASSERTIONS (focusing on startup as primary)
        XCTAssertLessThan(jsonResults.startupTime, 10000, "JSON startup should be under 10 seconds for 2000 flags")
        XCTAssertGreaterThan(jsonResults.evaluationsPerSecond, 100, "Should handle at least 100 evaluations per second")
        XCTAssertGreaterThan(jsonResults.totalEvaluations, 0, "Should perform some evaluations")

        print("\n🎯 JSON Performance Benchmark completed!")
        print("   Ready for FlatBuffer comparison when implemented")

        // Explicit cleanup for CI memory pressure relief
        autoreleasepool {
            // Force cleanup of large objects
        }
    }

    // MARK: - Benchmark Methods

    private func benchmarkJSONMode(jsonData: Data, testCases: [PerformanceTestCase]) throws -> PerformanceResults {
        print("\n🔄 Benchmarking JSON Mode...")

        // CRITICAL MEASUREMENT: Startup Performance (JSON->objects conversion)
        let memoryBefore = getCurrentMemoryUsage()
        print("   🏁 Starting JSON->objects conversion...")

        let startupStart = CFAbsoluteTimeGetCurrent()
        var configuration: Configuration? = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let startupTime = (CFAbsoluteTimeGetCurrent() - startupStart) * 1000

        let memoryAfter = getCurrentMemoryUsage()
        print("   ⚡ Startup complete: \(String(format: "%.0f", startupTime))ms, Memory: +\(String(format: "%.0f", memoryAfter - memoryBefore))MB")

        // Create client for evaluations
        var client: EppoClient? = EppoClient.initializeOffline(
            sdkKey: "json-benchmark-key",
            initialConfiguration: configuration!
        )

        // SECONDARY MEASUREMENT: Evaluation Performance across ALL 2000 flags
        print("   🏃 Running evaluation performance benchmark across all flags...")
        let evaluationStart = CFAbsoluteTimeGetCurrent()
        var totalEvaluations = 0

        // Standard test subjects for consistent evaluation
        let standardSubjects = [
            ("user_basic", [:]),
            ("user_us", ["country": EppoValue(value: "US")]),
            ("user_uk", ["country": EppoValue(value: "UK")]),
            ("user_premium", ["tier": EppoValue(value: "premium"), "country": EppoValue(value: "US")]),
            ("user_enterprise", ["tier": EppoValue(value: "enterprise"), "plan": EppoValue(value: "annual")])
        ]

        // Get all flag keys from configuration
        let flagsConfiguration = configuration!.flagsConfiguration
        let allFlagKeys = Array(flagsConfiguration.flags.keys)

        print("   📊 Testing \(allFlagKeys.count) flags with \(standardSubjects.count) subjects each...")

        // Evaluate every flag with every standard subject
        for flagKey in allFlagKeys {
            guard let flag = flagsConfiguration.flags[flagKey] else { continue }

            for (subjectKey, subjectAttributes) in standardSubjects {
                // Determine appropriate default based on flag's variation type
                switch flag.variationType {
                case .string:
                    _ = client!.getStringAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: "default"
                    )
                case .numeric:
                    _ = client!.getNumericAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: 0.0
                    )
                case .integer:
                    _ = client!.getIntegerAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: 0
                    )
                case .boolean:
                    _ = client!.getBooleanAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: false
                    )
                case .json:
                    _ = client!.getJSONStringAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: subjectAttributes,
                        defaultValue: "{}"
                    )
                }

                totalEvaluations += 1
            }
        }

        let evaluationTime = (CFAbsoluteTimeGetCurrent() - evaluationStart) * 1000
        let evaluationsPerSecond = Double(totalEvaluations) / (evaluationTime / 1000.0)

        print("   ✅ Evaluations complete: \(totalEvaluations) in \(String(format: "%.0f", evaluationTime))ms")
        print("   📈 Performance: \(String(format: "%.0f", evaluationsPerSecond)) evals/sec")

        let results = PerformanceResults(
            startupTime: startupTime,
            evaluationTime: evaluationTime,
            totalEvaluations: totalEvaluations,
            evaluationsPerSecond: evaluationsPerSecond,
            memoryUsage: memoryAfter
        )

        // Explicit cleanup for CI memory management
        configuration = nil
        client = nil

        return results
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

    private func loadAllGeneratedTestCases() throws -> [PerformanceTestCase] {
        guard let testDataURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/generated-tests",
            withExtension: ""
        ) else {
            throw TestError.fileNotFound("Could not find generated-tests directory")
        }

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: testDataURL, includingPropertiesForKeys: nil)

        var testCases: [PerformanceTestCase] = []
        for fileURL in files where fileURL.pathExtension == "json" {
            let data = try Data(contentsOf: fileURL)
            let testCase = try JSONDecoder().decode(PerformanceTestCase.self, from: data)
            testCases.append(testCase)
        }

        return testCases
    }

    private func convertSubjectAttributes(_ attributes: [String: AnyCodable]) -> [String: EppoValue] {
        return attributes.mapValues { anyValue in
            switch anyValue.value {
            case let stringValue as String:
                return EppoValue(value: stringValue)
            case let doubleValue as Double:
                return EppoValue(value: doubleValue)
            case let intValue as Int:
                return EppoValue(value: intValue)
            case let boolValue as Bool:
                return EppoValue(value: boolValue)
            default:
                return EppoValue(value: "")
            }
        }
    }

    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }

        return 0
    }
}

// MARK: - Data Models (Following EppoClientUFCTests Pattern)

struct PerformanceTestCase: Codable {
    let flag: String
    let variationType: String
    let defaultValue: AnyCodable
    let subjects: [PerformanceTestSubject]
}

struct PerformanceTestSubject: Codable {
    let subjectKey: String
    let subjectAttributes: [String: AnyCodable]
    let assignment: AnyCodable?
    let evaluationDetails: PerformanceEvaluationDetails?
}

struct PerformanceEvaluationDetails: Codable {
    let environmentName: String
    let flagEvaluationCode: String
    let flagEvaluationDescription: String
    let banditKey: String?
    let banditAction: String?
    let variationKey: String?
    let variationValue: AnyCodable?
    let matchedRule: PerformanceMatchedRule?
}

struct PerformanceMatchedRule: Codable {
    let conditions: [PerformanceConditionDetail]?
}

struct PerformanceConditionDetail: Codable {
    let attribute: String
    let `operator`: String
    let value: AnyCodable
}

enum TestError: Error {
    case fileNotFound(String)
}

// MARK: - Performance Results Tracking

struct PerformanceResults {
    let startupTime: Double          // Key metric - JSON->objects conversion time (ms)
    let evaluationTime: Double       // Secondary metric - total evaluation time (ms)
    let totalEvaluations: Int        // Number of evaluations performed
    let evaluationsPerSecond: Double // Evaluation throughput
    let memoryUsage: Double          // Memory usage (MB)
}

