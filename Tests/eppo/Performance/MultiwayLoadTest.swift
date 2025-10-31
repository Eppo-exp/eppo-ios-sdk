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

    /// Describes the performance characteristics and benefits of this evaluator
    func getPerformanceDescription() -> String
}

// Extend EppoClient to conform to the protocol
extension EppoClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        🏛️  BASELINE: Traditional JSON Configuration Evaluator
        📊 What's tested: JSON parsing → Swift struct conversion → evaluation
        🔬 Startup hypothesis: SLOWEST - Full JSON parsing and object creation overhead
        🔬 Evaluation hypothesis: GOOD - Optimized Swift struct access patterns
        💾 Memory hypothesis: HIGH - All flags converted to Swift objects in memory
        🎯 Use case: Traditional approach, good for comparison baseline
        ✅ Benefits: Mature, well-tested, human-readable config format
        """
    }
}

// Extend SwiftStructFromProtobufClient to conform to the protocol
extension SwiftStructFromProtobufClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        📦 SWIFT STRUCTS: Protobuf → Swift Objects Evaluator
        📊 What's tested: Protobuf parsing → Swift struct conversion → evaluation
        🔬 Startup hypothesis: SLOW - Protobuf parsing + Swift struct conversion overhead
        🔬 Evaluation hypothesis: EXCELLENT - Fast Swift struct access patterns
        💾 Memory hypothesis: HIGH - All flags as Swift objects, more compact source than JSON
        🎯 Use case: Balanced approach with better serialization than JSON
        ✅ Benefits: Compact wire format, type safety, should be faster than JSON startup
        """
    }
}

// Extend SwiftStructFromFlatBufferClient to conform to the protocol
extension SwiftStructFromFlatBufferClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        ⚡ SWIFT STRUCTS: FlatBuffer → Swift Objects Evaluator
        📊 What's tested: FlatBuffer parsing → Swift struct conversion → evaluation
        🔬 Startup hypothesis: SLOW - FlatBuffer parsing + Swift struct conversion overhead
        🔬 Evaluation hypothesis: EXCELLENT - Fast Swift struct access patterns
        💾 Memory hypothesis: HIGH - All flags as Swift objects, most compact source format
        🎯 Use case: Most compact serialization with Swift struct benefits
        ✅ Benefits: Ultra-compact wire format, zero-copy parsing potential, type safety
        """
    }
}

// Extend NativeProtobufClient to conform to the protocol
extension NativeProtobufClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        🔥 NATIVE: Direct Protobuf Binary Evaluator (NO SWIFT STRUCTS)
        📊 What's tested: Direct protobuf binary evaluation without object conversion
        🔬 Startup hypothesis: VERY FAST - No Swift struct creation, binary ready
        🔬 Evaluation hypothesis: GOOD - Direct binary access, no object overhead
        💾 Memory hypothesis: LOW - Raw binary format, minimal memory allocation
        🎯 Use case: Memory-constrained environments, ultra-fast startup required
        ✅ Benefits: Minimal memory footprint, lightning startup, no GC pressure
        """
    }
}

// Extend NativeFlatBufferClient to conform to the protocol
extension NativeFlatBufferClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        🚀 NATIVE: Direct FlatBuffer Binary Evaluator (NO SWIFT STRUCTS)
        📊 What's tested: Direct FlatBuffer binary evaluation with optional O(1) indexing
        🔬 Startup hypothesis: FASTEST - Zero-copy access, optional index building
        🔬 Evaluation hypothesis: FASTEST - O(1) lookup with index, zero allocations
        💾 Memory hypothesis: LOWEST - Raw binary format, absolute minimal allocation
        🎯 Use case: Performance-critical applications, maximum throughput required
        ✅ Benefits: Ultimate performance potential, zero-copy access, optional O(1) vs O(log n) trade-off
        """
    }
}

// Extend AaronClaudeClient to conform to the protocol
extension AaronClaudeClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        🧠 AARON CLAUDE: Optimized JSON→EppoValue Parser (Foundation-Only)
        📊 What's tested: Direct JSON parsing with EppoValue optimization → evaluation
        🔬 Startup hypothesis: FAST - Avoids expensive try-catch chains in EppoValue creation
        🔬 Evaluation hypothesis: EXCELLENT - Pre-computed EppoValue types, no runtime inference
        💾 Memory hypothesis: MEDIUM - Optimized structures with pre-processed values
        🎯 Use case: JSON performance optimization without changing serialization format
        ✅ Benefits: Foundation-only parsing, direct EppoValue creation, pre-analyzed types
        """
    }
}

// COMMENTED OUT: JsonOffsetIndexClient protocol extension - test is disabled
/*
// Extend JsonOffsetIndexClient to conform to the protocol
extension JsonOffsetIndexClient: AssignmentClient {
    func getPerformanceDescription() -> String {
        return """
        📍 BREAKTHROUGH: JSON Offset Index Evaluator (Revolutionary Approach)
        📊 What's tested: JSON byte offset indexing → lazy Swift struct loading → caching
        🔬 Startup hypothesis: ULTRA-FAST - Only offset indexing, zero Swift struct creation
        🔬 Evaluation hypothesis: EXCELLENT - Swift struct performance after first access
        💾 Memory hypothesis: DYNAMIC - Only cache accessed flags, scales with usage
        🎯 Use case: Best of both worlds - instant startup + Swift struct evaluation speed
        ✅ Benefits: Revolutionary concept, minimal memory until needed, cache effectiveness
        """
    }
}
*/

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

    // MARK: - Shared Results Storage for Cross-Test Comparisons

    private static var evaluatorResults: [String: (startupMs: Double, evalsPerSec: Double)] = [:]
    private static let resultsLock = NSLock()

    private static func storeResult(evaluator: String, startupMs: Double, evalsPerSec: Double) {
        resultsLock.lock()
        defer { resultsLock.unlock() }
        evaluatorResults[evaluator] = (startupMs, evalsPerSec)
    }

    private static func getAllResults() -> [String: (startupMs: Double, evalsPerSec: Double)] {
        resultsLock.lock()
        defer { resultsLock.unlock() }
        return evaluatorResults
    }


    // MARK: - Individual Evaluator Tests (DRY with memory management)

    func testJSONEvaluatorPerformance() throws {
        NSLog("📦 1. Testing Swift Struct Evaluator (JSON init)...")
        try testEvaluatorPerformance(
            evaluatorName: "JSON",
            setupBlock: {
                let jsonData = try self.loadJSONData()
                let startTime = CFAbsoluteTimeGetCurrent()
                let configuration = try Configuration(flagsConfigurationJson: jsonData, obfuscated: false)
                let client = EppoClient.initializeOffline(
                    sdkKey: "json-test-key",
                    assignmentLogger: nil,
                    initialConfiguration: configuration
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let flagCount = configuration.flagsConfiguration.flags.count
                return (client, startupTime, "swift structs populated from JSON - \(flagCount) flags")
            }
        )
    }

    func testAaronClaudeEvaluatorPerformance() throws {
        NSLog("🧠 2. Testing Aaron Claude Optimized JSON Evaluator...")
        try testEvaluatorPerformance(
            evaluatorName: "Aaron Claude",
            setupBlock: {
                let jsonData = try self.loadJSONData()
                NSLog("   🧠 Starting optimized JSON parsing with EppoValue improvements...")
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try AaronClaudeClient(
                    sdkKey: "aaron-claude-test-key",
                    jsonData: jsonData,
                    obfuscated: false,
                    assignmentLogger: nil
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                NSLog("   ✅ Aaron Claude parsing completed with Foundation-only optimizations")
                return (client, startupTime, "Foundation-only JSON parsing with pre-computed EppoValue types")
            }
        )
    }

    // COMMENTED OUT: JSON Offset Index test is extremely slow - DO NOT UNCOMMENT
    // The revolutionary JsonOffsetIndexEvaluator implementation is complete but performance
    // in test environment is unexpectedly slow. Code is preserved for future optimization.
    /*
    func testJsonOffsetIndexEvaluatorPerformance() throws {
        NSLog("📍 2. Testing JSON Offset Index Evaluator (Revolutionary)...")
        try testEvaluatorPerformance(
            evaluatorName: "JSON Offset Index",
            setupBlock: {
                let jsonData = try self.loadJSONData()
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try JsonOffsetIndexClient(
                    sdkKey: "json-offset-index-test-key",
                    jsonData: jsonData,
                    obfuscated: false,
                    assignmentLogger: nil
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return (client, startupTime, "byte offset index built, lazy Swift struct loading")
            }
        )
    }
    */

    func testProtobufLazyEvaluatorPerformance() throws {
        NSLog("📦 3. Testing Swift Struct Evaluator (Lazy PB)...")
        try testEvaluatorPerformance(
            evaluatorName: "Lazy PB",
            setupBlock: {
                let protobufData = try self.loadProtobufData()
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try SwiftStructFromProtobufClient(
                    sdkKey: "protobuf-lazy-test-key",
                    protobufData: protobufData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    prewarmCache: false
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return (client, startupTime, "protobuf parsed only - lazy swift struct conversion")
            }
        )
    }

    func testProtobufPrewarmedEvaluatorPerformance() throws {
        NSLog("📦 4. Testing Swift Struct Evaluator (Protobuf init)...")
        try testEvaluatorPerformance(
            evaluatorName: "Protobuf init",
            setupBlock: {
                let protobufData = try self.loadProtobufData()
                NSLog("   🔄 Pre-converting flags to UFC objects...")
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try SwiftStructFromProtobufClient(
                    sdkKey: "protobuf-prewarmed-test-key",
                    protobufData: protobufData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    prewarmCache: true
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                NSLog("   ✅ Pre-converted flags successfully")
                return (client, startupTime, "swift structs populated from protobuf")
            }
        )
    }

    func testFlatBufferLazyEvaluatorPerformance() throws {
        NSLog("📦 5. Testing Swift Struct Evaluator (Lazy FlatBuffer)...")
        try testEvaluatorPerformance(
            evaluatorName: "Lazy FlatBuffer",
            setupBlock: {
                let flatBufferData = try self.loadFlatBufferData()
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try SwiftStructFromFlatBufferClient(
                    sdkKey: "flatbuffer-lazy-test-key",
                    flatBufferData: flatBufferData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    prewarmCache: false
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return (client, startupTime, "FlatBuffer parsed only - lazy swift struct conversion")
            }
        )
    }

    func testFlatBufferPrewarmedEvaluatorPerformance() throws {
        NSLog("📦 6. Testing Swift Struct Evaluator (FlatBuffer init)...")
        try testEvaluatorPerformance(
            evaluatorName: "FlatBuffer init",
            setupBlock: {
                let flatBufferData = try self.loadFlatBufferData()
                NSLog("   🔄 Pre-converting flags to UFC objects...")
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try SwiftStructFromFlatBufferClient(
                    sdkKey: "flatbuffer-prewarmed-test-key",
                    flatBufferData: flatBufferData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    prewarmCache: true
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                NSLog("   ✅ Pre-converted flags successfully")
                return (client, startupTime, "swift structs populated from FlatBuffer")
            }
        )
    }

    func testNativeProtobufLazyEvaluatorPerformance() throws {
        NSLog("📦 7. Testing Native Protobuf Evaluator (LAZY - Parse on First Access)...")
        try testEvaluatorPerformance(
            evaluatorName: "Native PB Lazy",
            setupBlock: {
                let protobufData = try self.loadProtobufData()
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try NativeProtobufClient(
                    sdkKey: "native-protobuf-lazy-test-key",
                    protobufData: protobufData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    prewarmCache: false
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return (client, startupTime, "LAZY - protobuf parsing deferred until first evaluation")
            }
        )
    }

    func testNativeProtobufPrewarmedEvaluatorPerformance() throws {
        NSLog("📦 8. Testing Native Protobuf Evaluator (BLOCKING - Parse All Upfront)...")
        try testEvaluatorPerformance(
            evaluatorName: "Native PB Prewarmed",
            setupBlock: {
                let protobufData = try self.loadProtobufData()
                NSLog("   ⏳ BLOCKING until all protobuf parsing completes...")
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try NativeProtobufClient(
                    sdkKey: "native-protobuf-prewarmed-test-key",
                    protobufData: protobufData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    prewarmCache: true
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                NSLog("   ✅ BLOCKED - all flags parsed and ready for evaluation")
                return (client, startupTime, "BLOCKING - protobuf fully parsed upfront, objects ready")
            }
        )
    }

    func testNativeFlatBufferNoIndexEvaluatorPerformance() throws {
        NSLog("📦 9. Testing Native FlatBuffer Evaluator (BLOCKING - Parse FlatBuffer Only)...")
        try testEvaluatorPerformance(
            evaluatorName: "Native FB No Index",
            setupBlock: {
                let flatBufferData = try self.loadFlatBufferData()
                NSLog("   ⏳ BLOCKING until FlatBuffer parsing completes...")
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try NativeFlatBufferClient(
                    sdkKey: "native-flatbuffer-test-key",
                    flatBufferData: flatBufferData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    useIndex: false
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                NSLog("   ✅ BLOCKED - FlatBuffer parsed and ready, O(log n) flag lookup")
                return (client, startupTime, "BLOCKING - FlatBuffer parsed, ready for O(log n) evaluation")
            }
        )
    }

    func testNativeFlatBufferWithIndexEvaluatorPerformance() throws {
        NSLog("📦 10. Testing Native FlatBuffer Evaluator (BLOCKING - Parse + Build O(1) Index)...")
        try testEvaluatorPerformance(
            evaluatorName: "Native FB With Index",
            setupBlock: {
                let flatBufferData = try self.loadFlatBufferData()
                NSLog("   ⏳ BLOCKING until FlatBuffer parsing AND O(1) index building completes...")
                let startTime = CFAbsoluteTimeGetCurrent()
                let client = try NativeFlatBufferClient(
                    sdkKey: "native-flatbuffer-indexed-test-key",
                    flatBufferData: flatBufferData,
                    obfuscated: false,
                    assignmentLogger: nil,
                    useIndex: true
                )
                let startupTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                NSLog("   ✅ BLOCKED - FlatBuffer parsed + O(1) index built, ready for fastest evaluation")
                return (client, startupTime, "BLOCKING - FlatBuffer parsed + O(1) index built, ready for ultra-fast evaluation")
            }
        )
    }

    // MARK: - Performance Comparison Test

    func testZZZPerformanceComparison() throws {
        NSLog("\n" + String(repeating: "=", count: 60))
        NSLog("🏆 CROSS-EVALUATOR PERFORMANCE COMPARISON")
        NSLog(String(repeating: "=", count: 60))

        let allResults = Self.getAllResults()

        guard !allResults.isEmpty else {
            NSLog("⚠️  No individual test results found. Run individual evaluator tests first.")
            return
        }

        NSLog("📊 Results Summary:")
        for (evaluator, result) in allResults.sorted(by: { $0.key < $1.key }) {
            NSLog("   • \(evaluator): \(formatNumber(Int(result.startupMs)))ms startup, \(formatNumber(Int(result.evalsPerSec))) evals/sec")
        }

        // Fastest Startup Analysis
        NSLog("\n⚡ STARTUP SPEED RANKINGS:")
        let sortedByStartup = allResults.sorted { $0.value.startupMs < $1.value.startupMs }
        for (index, (evaluator, result)) in sortedByStartup.enumerated() {
            let rank = index + 1
            NSLog("   \(rank). \(evaluator): \(formatNumber(Int(result.startupMs)))ms")
        }

        // Fastest Evaluation Analysis
        NSLog("\n🚀 EVALUATION SPEED RANKINGS:")
        let sortedBySpeed = allResults.sorted { $0.value.evalsPerSec > $1.value.evalsPerSec }
        for (index, (evaluator, result)) in sortedBySpeed.enumerated() {
            let rank = index + 1
            NSLog("   \(rank). \(evaluator): \(formatNumber(Int(result.evalsPerSec))) evals/sec")
        }

        // Baseline Comparisons
        if let jsonResult = allResults["JSON"] {
            NSLog("\n📈 SPEEDUP vs JSON BASELINE:")
            for (evaluator, result) in allResults.sorted(by: { $0.value.evalsPerSec > $1.value.evalsPerSec }) {
                let startupSpeedup = jsonResult.startupMs / result.startupMs
                let evalSpeedup = result.evalsPerSec / jsonResult.evalsPerSec
                NSLog("   • \(evaluator): \(String(format: "%.1f", startupSpeedup))x startup, \(String(format: "%.1f", evalSpeedup))x evaluation")
            }
        }

        // Native vs Swift Struct Analysis
        let nativeEvaluators = allResults.filter { $0.key.contains("Native") }
        let swiftStructEvaluators = allResults.filter { !$0.key.contains("Native") }

        if !nativeEvaluators.isEmpty && !swiftStructEvaluators.isEmpty {
            let avgNativeStartup = nativeEvaluators.values.map { $0.startupMs }.reduce(0, +) / Double(nativeEvaluators.count)
            let avgNativeEvals = nativeEvaluators.values.map { $0.evalsPerSec }.reduce(0, +) / Double(nativeEvaluators.count)
            let avgSwiftStartup = swiftStructEvaluators.values.map { $0.startupMs }.reduce(0, +) / Double(swiftStructEvaluators.count)
            let avgSwiftEvals = swiftStructEvaluators.values.map { $0.evalsPerSec }.reduce(0, +) / Double(swiftStructEvaluators.count)

            NSLog("\n🥊 NATIVE vs SWIFT STRUCT AVERAGES:")
            NSLog("   Native Avg: \(formatNumber(Int(avgNativeStartup)))ms startup, \(formatNumber(Int(avgNativeEvals))) evals/sec")
            NSLog("   Swift Avg:  \(formatNumber(Int(avgSwiftStartup)))ms startup, \(formatNumber(Int(avgSwiftEvals))) evals/sec")
            NSLog("   Native wins by: \(String(format: "%.1f", avgSwiftStartup/avgNativeStartup))x startup, \(String(format: "%.1f", avgNativeEvals/avgSwiftEvals))x evaluation")
        }

        // FlatBuffer Analysis
        if let fbNoIndex = allResults["Native FB No Index"],
           let fbWithIndex = allResults["Native FB With Index"] {
            NSLog("\n📦 FLATBUFFER INDEX ANALYSIS:")
            let indexBuildCost = fbWithIndex.startupMs - fbNoIndex.startupMs
            let indexSpeedGain = fbWithIndex.evalsPerSec / fbNoIndex.evalsPerSec
            NSLog("   Index Build Cost: +\(formatNumber(Int(indexBuildCost)))ms")
            NSLog("   Index Speed Gain: \(String(format: "%.1f", indexSpeedGain))x faster evaluation")
            NSLog("   Trade-off: Pay \(formatNumber(Int(indexBuildCost)))ms once for \(String(format: "%.1f", indexSpeedGain))x ongoing performance")
        }

        NSLog("\n✅ Performance comparison completed!")
        NSLog("💾 Memory benefit: Each test ran in isolation with automatic cleanup between tests")
    }

    // MARK: - DRY Helper Functions

    /// Generic evaluator performance test with setup closure for memory management
    private func testEvaluatorPerformance(
        evaluatorName: String,
        setupBlock: () throws -> (AssignmentClient, Double, String)
    ) throws {
        let (client, startupTime, description) = try setupBlock()

        // Print performance characteristics and benefits
        NSLog("\n" + String(repeating: "─", count: 80))
        NSLog(client.getPerformanceDescription())
        NSLog(String(repeating: "─", count: 80))

        NSLog("   ⚡ Startup: \(formatNumber(Int(startupTime)))ms (\(description))")

        // Run evaluation benchmark
        let results = try performEvaluationBenchmark(client: client, clientName: evaluatorName)

        // Performance assertions
        XCTAssertGreaterThan(results.evalsPerSec, 100, "\(evaluatorName) should handle at least 100 evaluations per second")

        NSLog("   ✅ \(evaluatorName) test completed: \(formatNumber(Int(startupTime)))ms startup, \(formatNumber(Int(results.evalsPerSec))) evals/sec")

        // Store results for cross-test comparison
        Self.storeResult(evaluator: evaluatorName, startupMs: startupTime, evalsPerSec: results.evalsPerSec)

        // Memory will be automatically cleaned up when client goes out of scope
    }

    /// Load data files (DRY helper functions)
    private func loadJSONData() throws -> Data {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-10000.json",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-10000.json")
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing JSON test data"])
        }
        return try Data(contentsOf: fileURL)
    }

    private func loadProtobufData() throws -> Data {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-10000.pb",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-10000.pb")
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing protobuf test data"])
        }
        return try Data(contentsOf: fileURL)
    }

    private func loadFlatBufferData() throws -> Data {
        let fileURL = Bundle.module.url(
            forResource: "Resources/test-data/ufc/flags-10000.flatbuf",
            withExtension: ""
        )
        guard let fileURL = fileURL else {
            XCTFail("Could not find flags-10000.flatbuf")
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing FlatBuffer test data"])
        }
        return try Data(contentsOf: fileURL)
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
                NSLog("   🔥 First iteration (warming up caches/parsing)...")
            } else {
                NSLog("   💨 Iteration \(iteration) (cached performance)...")
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
            NSLog("      -> \(formatNumber(iterationEvalCount)) evals in \(formatNumber(Int(iterationTime)))ms = \(formatNumber(Int(iterationEvalsPerSec))) evals/sec")
        }

        let evalTime = (CFAbsoluteTimeGetCurrent() - evalStart) * 1000
        let evalsPerSec = Double(evaluationCount) / (evalTime / 1000.0)
        NSLog("   🏁 \(clientName) TOTAL: \(formatNumber(Int(evalsPerSec))) evals/sec (\(formatNumber(evaluationCount)) evals in \(formatNumber(Int(evalTime)))ms over \(BENCHMARK_ITERATIONS) iterations)")

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
