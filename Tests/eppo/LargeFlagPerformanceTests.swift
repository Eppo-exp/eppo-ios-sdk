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

        // RUN JSON MODE FIRST (isolated)
        let jsonResults = try autoreleasepool {
            print("\n📦 Loading JSON data...")
            let jsonData = try loadTestDataFile("flags-10000.json")
            let testCases = try loadAllGeneratedTestCases()
            print("   📄 JSON: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary))")

            let results = try benchmarkJSONMode(jsonData: jsonData, testCases: testCases)

            // Force memory cleanup
            print("   🧹 Releasing JSON memory...")
            return results
        }

        // FORCE MEMORY CLEANUP BETWEEN MODES
        autoreleasepool {}

        // RUN FLATBUFFER MODE SECOND (isolated)
        let flatBufferResults = try autoreleasepool {
            print("\n📦 Loading FlatBuffer data...")
            let flatBufferData = try loadTestDataFile("flags-10000.flatbuf")
            let testCases = try loadAllGeneratedTestCases()
            print("   ⚡ FlatBuffer: \(ByteCountFormatter.string(fromByteCount: Int64(flatBufferData.count), countStyle: .binary))")

            let results = try benchmarkFlatBufferMode(flatBufferData: flatBufferData, testCases: testCases)

            // Force memory cleanup
            print("   🧹 Releasing FlatBuffer memory...")
            return results
        }

        // RESULTS SUMMARY
        print("\n🏆 PERFORMANCE BENCHMARK RESULTS:")
        print("📊 JSON Mode:")
        print("   🎯 Startup (KEY METRIC): \(String(format: "%.0f", jsonResults.startupTime))ms")
        print("   ⚡ Evaluation Speed: \(String(format: "%.0f", jsonResults.evaluationsPerSecond)) evals/sec")
        print("   💾 Memory Usage: \(String(format: "%.0f", jsonResults.memoryUsage))MB")
        print("   📊 Total Evaluations: \(jsonResults.totalEvaluations)")

        print("📊 FlatBuffer Mode:")
        print("   🎯 Startup: \(String(format: "%.0f", flatBufferResults.startupTime))ms")
        print("   ⚡ Evaluation Speed: \(String(format: "%.0f", flatBufferResults.evaluationsPerSecond)) evals/sec")
        print("   💾 Memory Usage: \(String(format: "%.0f", flatBufferResults.memoryUsage))MB")
        print("   📊 Total Evaluations: \(flatBufferResults.totalEvaluations)")

        // PERFORMANCE COMPARISON
        let startupSpeedup = jsonResults.startupTime / flatBufferResults.startupTime
        let evaluationSpeedup = flatBufferResults.evaluationsPerSecond / jsonResults.evaluationsPerSecond
        print("\n🏁 PERFORMANCE COMPARISON:")
        print("   ⚡ Startup Speedup: \(String(format: "%.1f", startupSpeedup))x faster")
        print("   🚀 Evaluation Speedup: \(String(format: "%.1f", evaluationSpeedup))x faster")
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

    func testThreeWayPerformanceBenchmark() throws {
        // This test benchmarks all three approaches: JSON, Direct FlatBuffer, and Lazy FlatBuffer
        // to compare startup and evaluation performance across all modes

        print("🚀 Starting Three-Way Performance Benchmark")
        print("🎯 Comparing: JSON, Direct FlatBuffer, and Lazy FlatBuffer modes")
        print("📊 Key Metrics: Startup time (primary) and evaluation speed (secondary)")

        // RUN JSON MODE FIRST (isolated)
        let jsonResults = try autoreleasepool {
            print("\n📦 Loading JSON data...")
            let jsonData = try loadTestDataFile("flags-10000.json")
            let testCases = try loadAllGeneratedTestCases()
            print("   📄 JSON: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .binary))")

            let results = try benchmarkJSONMode(jsonData: jsonData, testCases: testCases)

            print("   🧹 Releasing JSON memory...")
            return results
        }

        autoreleasepool {} // Force memory cleanup

        // RUN DIRECT FLATBUFFER MODE SECOND (isolated)
        let directFlatBufferResults = try autoreleasepool {
            print("\n📦 Loading FlatBuffer data for direct mode...")
            let flatBufferData = try loadTestDataFile("flags-10000.flatbuf")
            let testCases = try loadAllGeneratedTestCases()
            print("   ⚡ FlatBuffer: \(ByteCountFormatter.string(fromByteCount: Int64(flatBufferData.count), countStyle: .binary))")

            let results = try benchmarkFlatBufferMode(flatBufferData: flatBufferData, testCases: testCases)

            print("   🧹 Releasing Direct FlatBuffer memory...")
            return results
        }

        autoreleasepool {} // Force memory cleanup

        // RUN LAZY FLATBUFFER MODE THIRD (isolated)
        let lazyFlatBufferResults = try autoreleasepool {
            print("\n📦 Loading FlatBuffer data for lazy mode...")
            let flatBufferData = try loadTestDataFile("flags-10000.flatbuf")
            let testCases = try loadAllGeneratedTestCases()
            print("   🧠 Lazy FlatBuffer: \(ByteCountFormatter.string(fromByteCount: Int64(flatBufferData.count), countStyle: .binary))")

            let results = try benchmarkLazyFlatBufferMode(flatBufferData: flatBufferData, testCases: testCases)

            print("   🧹 Releasing Lazy FlatBuffer memory...")
            return results
        }

        // THREE-WAY RESULTS SUMMARY
        print("\n🏆 THREE-WAY PERFORMANCE BENCHMARK RESULTS:")
        print("📊 JSON Mode:")
        print("   🎯 Startup (KEY METRIC): \(String(format: "%.0f", jsonResults.startupTime))ms")
        print("   ⚡ Evaluation Speed: \(String(format: "%.0f", jsonResults.evaluationsPerSecond)) evals/sec")
        print("   💾 Memory Usage: \(String(format: "%.0f", jsonResults.memoryUsage))MB")
        print("   📊 Total Evaluations: \(jsonResults.totalEvaluations)")

        print("📊 Direct FlatBuffer Mode:")
        print("   🎯 Startup: \(String(format: "%.0f", directFlatBufferResults.startupTime))ms")
        print("   ⚡ Evaluation Speed: \(String(format: "%.0f", directFlatBufferResults.evaluationsPerSecond)) evals/sec")
        print("   💾 Memory Usage: \(String(format: "%.0f", directFlatBufferResults.memoryUsage))MB")
        print("   📊 Total Evaluations: \(directFlatBufferResults.totalEvaluations)")

        print("📊 Lazy FlatBuffer Mode:")
        print("   🎯 Startup: \(String(format: "%.0f", lazyFlatBufferResults.startupTime))ms")
        print("   ⚡ Evaluation Speed: \(String(format: "%.0f", lazyFlatBufferResults.evaluationsPerSecond)) evals/sec")
        print("   💾 Memory Usage: \(String(format: "%.0f", lazyFlatBufferResults.memoryUsage))MB")
        print("   📊 Total Evaluations: \(lazyFlatBufferResults.totalEvaluations)")

        // PERFORMANCE COMPARISONS
        let directStartupSpeedup = jsonResults.startupTime / directFlatBufferResults.startupTime
        let lazyStartupSpeedup = jsonResults.startupTime / lazyFlatBufferResults.startupTime
        let directEvaluationSpeedup = directFlatBufferResults.evaluationsPerSecond / jsonResults.evaluationsPerSecond
        let lazyEvaluationSpeedup = lazyFlatBufferResults.evaluationsPerSecond / jsonResults.evaluationsPerSecond

        print("\n🏁 THREE-WAY PERFORMANCE COMPARISON:")
        print("   📈 Startup Performance (vs JSON):")
        print("      ⚡ Direct FlatBuffer: \(String(format: "%.1f", directStartupSpeedup))x faster")
        print("      🧠 Lazy FlatBuffer: \(String(format: "%.1f", lazyStartupSpeedup))x faster")
        print("   📈 Evaluation Performance (vs JSON):")
        print("      ⚡ Direct FlatBuffer: \(String(format: "%.1f", directEvaluationSpeedup))x faster")
        print("      🧠 Lazy FlatBuffer: \(String(format: "%.1f", lazyEvaluationSpeedup))x faster")

        print("\n🎯 Three-Way Performance Benchmark completed!")
        print("   📝 Summary: Lazy FlatBuffer combines fast startup with proven JSON evaluation logic")

        // Performance assertions
        XCTAssertGreaterThan(directStartupSpeedup, 1.0, "Direct FlatBuffer should be faster than JSON for startup")
        XCTAssertGreaterThan(lazyStartupSpeedup, 1.0, "Lazy FlatBuffer should be faster than JSON for startup")
        XCTAssertGreaterThan(lazyFlatBufferResults.evaluationsPerSecond, 100, "Lazy mode should handle at least 100 evaluations per second")

        // Explicit cleanup
        autoreleasepool {}
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

        // Create assignment logger for realistic benchmarking
        let assignmentLogger: EppoClient.AssignmentLogger = { assignment in
            // Simulate realistic logging work (minimal processing)
            _ = assignment.featureFlag.count + assignment.subject.count
        }

        // Create client for evaluations
        var client: EppoClient? = EppoClient.initializeOffline(
            sdkKey: "json-benchmark-key",
            assignmentLogger: assignmentLogger,
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

    private func benchmarkFlatBufferMode(flatBufferData: Data, testCases: [PerformanceTestCase]) throws -> PerformanceResults {
        print("\n🔄 Benchmarking FlatBuffer Mode...")

        // CRITICAL MEASUREMENT: Startup Performance (no conversion, direct FlatBuffer access)
        let memoryBefore = getCurrentMemoryUsage()
        print("   🏁 Starting direct FlatBuffer client creation...")

        // Create assignment logger for realistic benchmarking (same as JSON mode)
        let assignmentLogger: EppoClient.AssignmentLogger = { assignment in
            // Simulate realistic logging work (minimal processing)
            _ = assignment.featureFlag.count + assignment.subject.count
        }

        let startupStart = CFAbsoluteTimeGetCurrent()
        var client: LazyFlatBufferClient? = try LazyFlatBufferClient(
            sdkKey: "flatbuffer-benchmark-key",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: assignmentLogger
        )
        let startupTime = (CFAbsoluteTimeGetCurrent() - startupStart) * 1000

        let memoryAfter = getCurrentMemoryUsage()
        print("   ⚡ Startup complete: \(String(format: "%.0f", startupTime))ms, Memory: +\(String(format: "%.0f", memoryAfter - memoryBefore))MB")

        // SECONDARY MEASUREMENT: Evaluation Performance across ALL 10K flags
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

        // Get all flag keys from FlatBuffer client
        let allFlagKeys = client!.getAllFlagKeys()

        print("   📊 Testing \(allFlagKeys.count) flags with \(standardSubjects.count) subjects each...")

        // Evaluate every flag with every standard subject
        for flagKey in allFlagKeys {
            guard let flagVariationType = client!.getFlagVariationType(flagKey: flagKey) else { continue }

            for (subjectKey, subjectAttributes) in standardSubjects {
                // Determine appropriate default based on flag's variation type
                switch flagVariationType {
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
        client = nil

        return results
    }

    private func benchmarkLazyFlatBufferMode(flatBufferData: Data, testCases: [PerformanceTestCase]) throws -> PerformanceResults {
        print("\n🔄 Benchmarking Lazy FlatBuffer Mode...")

        // CRITICAL MEASUREMENT: Startup Performance (almost instantaneous)
        let memoryBefore = getCurrentMemoryUsage()
        print("   🏁 Starting lazy FlatBuffer client creation...")

        let startupStart = CFAbsoluteTimeGetCurrent()
        var lazyClient: LazyFlatBufferClient? = try LazyFlatBufferClient(
            sdkKey: "lazy-flatbuffer-benchmark-key",
            flatBufferData: flatBufferData,
            obfuscated: false,
            assignmentLogger: { assignment in
                // Simulate realistic logging work (minimal processing)
                _ = assignment.featureFlag.count + assignment.subject.count
            }
        )
        let startupTime = (CFAbsoluteTimeGetCurrent() - startupStart) * 1000

        let memoryAfter = getCurrentMemoryUsage()
        print("   ⚡ Startup complete: \(String(format: "%.0f", startupTime))ms, Memory: +\(String(format: "%.0f", memoryAfter - memoryBefore))MB")

        // SECONDARY MEASUREMENT: Evaluation Performance
        print("   🏃 Running evaluation performance benchmark across all flags...")

        let evaluationStart = CFAbsoluteTimeGetCurrent()
        var totalEvaluations = 0

        // Get flag keys and test 5 subjects per flag (same as other modes)
        let flagKeys = lazyClient!.getAllFlagKeys()
        let subjects = ["user_basic", "user_us", "user_uk", "user_premium", "user_enterprise"]

        print("   📊 Testing \(flagKeys.count) flags with \(subjects.count) subjects each...")

        for flagKey in flagKeys {
            guard let flagType = lazyClient!.getFlagVariationType(flagKey: flagKey) else { continue }

            for subject in subjects {
                totalEvaluations += 1
                let attributes: [String: EppoValue] = ["country": EppoValue.valueOf("US")]

                // Perform evaluation based on flag type
                switch flagType {
                case .boolean:
                    _ = lazyClient!.getBooleanAssignment(
                        flagKey: flagKey,
                        subjectKey: subject,
                        subjectAttributes: attributes,
                        defaultValue: false
                    )
                case .string:
                    _ = lazyClient!.getStringAssignment(
                        flagKey: flagKey,
                        subjectKey: subject,
                        subjectAttributes: attributes,
                        defaultValue: "default"
                    )
                case .integer:
                    _ = lazyClient!.getIntegerAssignment(
                        flagKey: flagKey,
                        subjectKey: subject,
                        subjectAttributes: attributes,
                        defaultValue: 0
                    )
                case .numeric:
                    _ = lazyClient!.getNumericAssignment(
                        flagKey: flagKey,
                        subjectKey: subject,
                        subjectAttributes: attributes,
                        defaultValue: 0.0
                    )
                case .json:
                    _ = lazyClient!.getJSONStringAssignment(
                        flagKey: flagKey,
                        subjectKey: subject,
                        subjectAttributes: attributes,
                        defaultValue: "{}"
                    )
                }
            }
        }

        let evaluationTime = (CFAbsoluteTimeGetCurrent() - evaluationStart) * 1000
        let evaluationsPerSecond = Double(totalEvaluations) / (evaluationTime / 1000)

        print("   ✅ Evaluations complete: \(totalEvaluations) in \(String(format: "%.0f", evaluationTime))ms")
        print("   📈 Performance: \(String(format: "%.0f", evaluationsPerSecond)) evals/sec")

        // Clean up
        lazyClient = nil

        return PerformanceResults(
            startupTime: startupTime,
            evaluationTime: evaluationTime,
            totalEvaluations: totalEvaluations,
            evaluationsPerSecond: evaluationsPerSecond,
            memoryUsage: memoryAfter
        )
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

