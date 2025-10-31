import XCTest
@testable import EppoFlagging
import Foundation

/**
 * Large Flag Performance Tests
 *
 * Compares Standard JSON Evaluator vs OptimizedJSON Evaluator performance
 * with a focus on large-scale configuration files and evaluation throughput.
 */
final class LargeFlagPerformanceTests: XCTestCase {

    func testJSONPerformanceBenchmark() throws {
        NSLog("🚀 Starting JSON Performance Benchmark")
        NSLog("🎯 Key Focus: Standard JSON vs OptimizedJSON Evaluator comparison")
        NSLog("📊 Secondary: Evaluation performance across test cases")

        // Load large test data
        let jsonData = try loadLargeJSONTestData()
        NSLog("📦 Data loaded:")
        NSLog("   📄 JSON: %.1f MB", Double(jsonData.count) / (1024 * 1024))

        let testCases = try loadTestCases()
        NSLog("   📊 Test Cases: %d", testCases.count)

        let loadStartTime = CFAbsoluteTimeGetCurrent()
        let loadTime = (CFAbsoluteTimeGetCurrent() - loadStartTime) * 1000
        NSLog("   ⏱️  Load Time: %.2fms", loadTime)

        // Benchmark Standard JSON Mode
        NSLog("")
        NSLog("🔄 Benchmarking Standard JSON Mode...")
        let standardResults = try benchmarkStandardJSONMode(jsonData: jsonData, testCases: testCases)

        // Benchmark OptimizedJSON Mode
        NSLog("")
        NSLog("🔄 Benchmarking OptimizedJSON Mode...")
        let optimizedResults = try benchmarkOptimizedJSONMode(jsonData: jsonData, testCases: testCases)

        // Performance comparison results
        NSLog("")
        NSLog("🏆 PERFORMANCE BENCHMARK RESULTS:")
        NSLog("📊 Standard JSON Mode:")
        NSLog("   🎯 Startup (KEY METRIC): %.0fms", standardResults.startupTime)
        NSLog("   ⚡ Evaluation Speed: %.0f evals/sec", standardResults.evaluationsPerSec)
        NSLog("   💾 Memory Usage: %.0fMB", standardResults.memoryUsage)
        NSLog("   📊 Total Evaluations: %d", standardResults.totalEvaluations)

        NSLog("📊 OptimizedJSON Mode:")
        NSLog("   🎯 Startup: %.0fms", optimizedResults.startupTime)
        NSLog("   ⚡ Evaluation Speed: %.0f evals/sec", optimizedResults.evaluationsPerSec)
        NSLog("   💾 Memory Usage: %.0fMB", optimizedResults.memoryUsage)
        NSLog("   📊 Total Evaluations: %d", optimizedResults.totalEvaluations)

        NSLog("")
        NSLog("🏁 PERFORMANCE COMPARISON:")
        let startupSpeedup = standardResults.startupTime / optimizedResults.startupTime
        let evaluationSlowdown = standardResults.evaluationsPerSec / optimizedResults.evaluationsPerSec
        NSLog("   ⚡ Startup Speedup: %.1fx faster", startupSpeedup)
        NSLog("   🏃 Evaluation Change: %.1fx", evaluationSlowdown >= 1 ? evaluationSlowdown : 1.0/evaluationSlowdown)

        NSLog("")
        NSLog("🎯 JSON Performance Benchmark completed!")
        NSLog("   OptimizedJSON provides %.1fx faster startup (main optimization target)",
              startupSpeedup)

        // Performance assertions - OptimizedJSON optimizes for fast startup
        XCTAssertGreaterThan(startupSpeedup, 2.0, "OptimizedJSON should provide at least 2x startup speedup")

        // Note: OptimizedJSON is optimized for fast startup, evaluation performance may be slightly different
        // The key goal is reducing initialization time for faster app startup
    }

    // MARK: - Performance Benchmarking

    private func benchmarkStandardJSONMode(jsonData: Data, testCases: [TestCase]) throws -> PerformanceResults {
        NSLog("   🏁 Starting Standard JSON->objects conversion...")
        let startupStartTime = CFAbsoluteTimeGetCurrent()

        // Create standard JSON evaluator through Configuration
        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        EppoClient.resetSharedInstance()

        let client = EppoClient.initializeOffline(
            sdkKey: "standard-performance-test",
            assignmentLogger: nil,
            initialConfiguration: configuration,
            evaluatorType: .standard
        )

        let startupTime = (CFAbsoluteTimeGetCurrent() - startupStartTime) * 1000
        let memoryUsage = getMemoryUsage()
        NSLog("   ⚡ Startup complete: %.0fms, Memory: +%.0fMB", startupTime, memoryUsage)

        // Run evaluation performance benchmark
        NSLog("   🏃 Running evaluation performance benchmark...")
        let (totalEvaluations, evaluationTime) = runEvaluationBenchmark(client: client, testCases: testCases)

        let evaluationsPerSec = Double(totalEvaluations) / (evaluationTime / 1000)
        NSLog("   ✅ Evaluations complete: %d in %.0fms", totalEvaluations, evaluationTime)
        NSLog("   📈 Performance: %.0f evals/sec", evaluationsPerSec)

        return PerformanceResults(
            startupTime: startupTime,
            evaluationTime: evaluationTime,
            evaluationsPerSec: evaluationsPerSec,
            memoryUsage: memoryUsage,
            totalEvaluations: totalEvaluations
        )
    }

    private func benchmarkOptimizedJSONMode(jsonData: Data, testCases: [TestCase]) throws -> PerformanceResults {
        NSLog("   🏁 Starting OptimizedJSON evaluator creation...")
        let startupStartTime = CFAbsoluteTimeGetCurrent()

        // Create OptimizedJSON evaluator using the new API
        EppoClient.resetSharedInstance()

        let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
        let client = EppoClient.initializeOffline(
            sdkKey: "optimized-performance-test",
            initialConfiguration: configuration,
            evaluatorType: .optimizedJSON
        )

        let startupTime = (CFAbsoluteTimeGetCurrent() - startupStartTime) * 1000
        let memoryUsage = getMemoryUsage()
        NSLog("   ⚡ Startup complete: %.0fms, Memory: +%.0fMB", startupTime, memoryUsage)

        // Run evaluation performance benchmark
        NSLog("   🏃 Running evaluation performance benchmark...")
        let (totalEvaluations, evaluationTime) = runEvaluationBenchmark(client: client, testCases: testCases)

        let evaluationsPerSec = Double(totalEvaluations) / (evaluationTime / 1000)
        NSLog("   ✅ Evaluations complete: %d in %.0fms", totalEvaluations, evaluationTime)
        NSLog("   📈 Performance: %.0f evals/sec", evaluationsPerSec)

        return PerformanceResults(
            startupTime: startupTime,
            evaluationTime: evaluationTime,
            evaluationsPerSec: evaluationsPerSec,
            memoryUsage: memoryUsage,
            totalEvaluations: totalEvaluations
        )
    }

    private func runEvaluationBenchmark(client: EppoClient, testCases: [TestCase]) -> (totalEvaluations: Int, evaluationTime: Double) {
        let subjects = ["alice", "bob", "charlie", "diana", "evan"]
        let flags = ["boolean-flag", "string-flag", "numeric-flag", "integer-flag", "json-flag"]

        var totalEvaluations = 0
        let evaluationStartTime = CFAbsoluteTimeGetCurrent()

        // Run evaluations across all combinations
        for _ in 0..<1000 { // 1000 iterations for meaningful benchmark
            for flagKey in flags {
                for subjectKey in subjects {
                    // Test boolean assignment
                    _ = client.getBooleanAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: [:],
                        defaultValue: false
                    )
                    totalEvaluations += 1

                    // Test string assignment
                    _ = client.getStringAssignment(
                        flagKey: flagKey,
                        subjectKey: subjectKey,
                        subjectAttributes: [:],
                        defaultValue: "default"
                    )
                    totalEvaluations += 1
                }
            }
        }

        let evaluationTime = (CFAbsoluteTimeGetCurrent() - evaluationStartTime) * 1000
        return (totalEvaluations, evaluationTime)
    }

    // MARK: - Helper Methods

    private func loadLargeJSONTestData() throws -> Data {
        // Try to load the 10000 flags file, fallback to smaller if needed
        if let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-10000.json", withExtension: "") {
            return try Data(contentsOf: fileURL)
        } else if let fileURL = Bundle.module.url(forResource: "Resources/test-data/ufc/flags-v1.json", withExtension: "") {
            return try Data(contentsOf: fileURL)
        } else {
            throw NSError(domain: "TestError", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Missing large JSON test data"])
        }
    }

    private func loadTestCases() throws -> [TestCase] {
        // Simplified test case loading - in real scenario would load from test files
        return Array(0..<12).map { TestCase(id: $0) }
    }

    private func getMemoryUsage() -> Double {
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
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        }
        return 0.0
    }

    // MARK: - Data Structures

    private struct PerformanceResults {
        let startupTime: Double
        let evaluationTime: Double
        let evaluationsPerSec: Double
        let memoryUsage: Double
        let totalEvaluations: Int
    }

    private struct TestCase {
        let id: Int
    }
}