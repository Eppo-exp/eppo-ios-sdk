import XCTest
@testable import EppoFlagging

class EppoPrecomputedClientPerformanceTests: XCTestCase {
    var testPrecompute: Precompute!

    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()

        testPrecompute = Precompute(
            subjectKey: "performance-test-user",
            subjectAttributes: [
                "age": EppoValue(value: 25),
                "plan": EppoValue(value: "premium"),
                "country": EppoValue(value: "US")
            ]
        )
    }

    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }

    // MARK: - Single Assignment Performance Tests

    func testSingleAssignmentPerformance() {
        // Create a realistic configuration with moderate number of flags
        let testConfig = createPerformanceConfiguration(flagCount: 100)

        // Initialize client
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            initialPrecomputedConfiguration: testConfig
        )

        // Measure single assignment performance
        measure {
            _ = try! EppoPrecomputedClient.shared().getStringAssignment(
                flagKey: "flag-50", // Pick a flag in the middle
                defaultValue: "default"
            )
        }
    }

    func testAssignmentPerformanceUnder1ms() {
        // Test with realistic flag count
        let testConfig = createPerformanceConfiguration(flagCount: 500)

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            initialPrecomputedConfiguration: testConfig
        )

        // Test multiple assignments and measure average time
        let iterations = 1000
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<iterations {
            let flagKey = "flag-\(i % 500)" // Cycle through available flags
            _ = try! EppoPrecomputedClient.shared().getStringAssignment(
                flagKey: flagKey,
                defaultValue: "default"
            )
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = (totalTime * 1000) / Double(iterations) // Convert to ms

        // Verify <1ms requirement
        XCTAssertLessThan(averageTime, 1.0, "Average assignment time should be less than 1ms, got \(averageTime)ms")
    }

    // MARK: - Concurrent Performance Tests

    func testConcurrentAssignmentPerformance() {
        let testConfig = createPerformanceConfiguration(flagCount: 200)

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            initialPrecomputedConfiguration: testConfig
        )

        let expectation = XCTestExpectation(description: "Concurrent assignments")
        expectation.expectedFulfillmentCount = 10

        let startTime = CFAbsoluteTimeGetCurrent()

        // Launch multiple concurrent assignment threads
        for _ in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<100 {
                    let flagKey = "flag-\(i % 200)"
                    _ = try! EppoPrecomputedClient.shared().getStringAssignment(
                        flagKey: flagKey,
                        defaultValue: "default"
                    )
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let totalAssignments = 10 * 100
        let averageTime = (totalTime * 1000) / Double(totalAssignments)

        // Allow slightly higher time for concurrent access due to lock contention
        XCTAssertLessThan(averageTime, 2.0, "Concurrent assignment average should be reasonable, got \(averageTime)ms")
    }

    // MARK: - Memory Usage Tests

    func testMemoryUsageWithLargeConfiguration() {
        // Test memory usage with large configuration
        let testConfig = createPerformanceConfiguration(flagCount: 1000)

        // Measure memory before initialization
        let initialMemory = getCurrentMemoryUsage()

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            initialPrecomputedConfiguration: testConfig
        )

        // Perform many assignments to stress test memory
        for i in 0..<1000 {
            let flagKey = "flag-\(i)"
            _ = try! EppoPrecomputedClient.shared().getStringAssignment(
                flagKey: flagKey,
                defaultValue: "default"
            )
        }

        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory

        // Memory usage should be reasonable (less than 50MB for 1000 flags)
        XCTAssertLessThan(memoryIncrease, 50 * 1024 * 1024, "Memory usage should be reasonable")
    }

    func testInitializationPerformance() {
        // Test how quickly we can initialize with different config sizes
        let flagCounts = [50, 100, 500, 1000]

        for flagCount in flagCounts {
            let testConfig = createPerformanceConfiguration(flagCount: flagCount)

            // Reset for clean test
            EppoPrecomputedClient.resetForTesting()

            let startTime = CFAbsoluteTimeGetCurrent()

            _ = EppoPrecomputedClient.initializeOffline(
                sdkKey: "performance-test-key-\(flagCount)",
                initialPrecomputedConfiguration: testConfig
            )

            let initTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms

            // Initialization should be fast even with many flags (<100ms)
            XCTAssertLessThan(initTime, 100, "Initialization should be fast for \(flagCount) flags")
        }
    }

    // MARK: - Different Assignment Type Performance

    func testDifferentAssignmentTypesPerformance() {
        let testConfig = createMixedTypeConfiguration(flagCount: 200)

        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            initialPrecomputedConfiguration: testConfig
        )

        let iterations = 250 // 50 of each type
        let startTime = CFAbsoluteTimeGetCurrent()

        // Test different assignment types
        for i in 0..<iterations {
            let flagIndex = i % 50

            switch i % 5 {
            case 0:
                _ = try! EppoPrecomputedClient.shared().getStringAssignment(
                    flagKey: "string-flag-\(flagIndex)",
                    defaultValue: "default"
                )
            case 1:
                _ = try! EppoPrecomputedClient.shared().getBooleanAssignment(
                    flagKey: "boolean-flag-\(flagIndex)",
                    defaultValue: false
                )
            case 2:
                _ = try! EppoPrecomputedClient.shared().getIntegerAssignment(
                    flagKey: "integer-flag-\(flagIndex)",
                    defaultValue: 0
                )
            case 3:
                _ = try! EppoPrecomputedClient.shared().getNumericAssignment(
                    flagKey: "numeric-flag-\(flagIndex)",
                    defaultValue: 0.0
                )
            case 4:
                _ = try! EppoPrecomputedClient.shared().getJSONStringAssignment(
                    flagKey: "json-flag-\(flagIndex)",
                    defaultValue: "{}"
                )
            default:
                break
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = (totalTime * 1000) / Double(iterations)

        XCTAssertLessThan(averageTime, 1.0, "Mixed type assignments should be fast")
    }

    // MARK: - Helper Methods

    private func createPerformanceConfiguration(flagCount: Int) -> PrecomputedConfiguration {
        var flagSpecs: [(String, PrecomputedFlag)] = []

        for i in 0..<flagCount {
            let flagKey = "flag-\(i)"
            flagSpecs.append((flagKey, createTestFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variant-\(i % 3)",
                variationType: .STRING,
                variationValue: "value-\(i)",
                extraLogging: [
                    "experiment-holdout-key": "holdout-\(i % 10)",
                    "holdoutVariation": i % 2 == 0 ? "status_quo" : "all_shipped"
                ],
                doLog: i % 5 == 0 // Only log 20% to be realistic
            )))
        }

        let flags = createTestFlags(flagSpecs)

        return PrecomputedConfiguration(
            flags: flags,
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(
                subjectKey: testPrecompute.subjectKey,
                subjectAttributes: testPrecompute.subjectAttributes
            ),
            configPublishedAt: nil,
            environment: nil
        )
    }

    private func createMixedTypeConfiguration(flagCount: Int) -> PrecomputedConfiguration {
        var flagSpecs: [(String, PrecomputedFlag)] = []

        let flagsPerType = flagCount / 5

        // Create flags of different types
        for i in 0..<flagsPerType {
            // String flags
            flagSpecs.append(("string-flag-\(i)", createTestFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variant-a",
                variationType: .STRING,
                variationValue: "string-value-\(i)"
            )))

            // Boolean flags
            flagSpecs.append(("boolean-flag-\(i)", createTestFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variant-b",
                variationType: .BOOLEAN,
                variationValue: i % 2 == 0
            )))

            // Integer flags
            flagSpecs.append(("integer-flag-\(i)", createTestFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variant-c",
                variationType: .INTEGER,
                variationValue: Double(i * 10)
            )))

            // Numeric flags
            flagSpecs.append(("numeric-flag-\(i)", createTestFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variant-d",
                variationType: .NUMERIC,
                variationValue: Double(i) * 1.5
            )))

            // JSON flags
            flagSpecs.append(("json-flag-\(i)", createTestFlag(
                allocationKey: "allocation-\(i)",
                variationKey: "variant-e",
                variationType: .JSON,
                variationValue: "{\"index\": \(i)}"
            )))
        }

        let flags = createTestFlags(flagSpecs)

        return PrecomputedConfiguration(
            flags: flags,
            salt: base64Encode("test-salt"),
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            subject: Subject(
                subjectKey: testPrecompute.subjectKey,
                subjectAttributes: testPrecompute.subjectAttributes
            ),
            configPublishedAt: nil,
            environment: nil
        )
    }

    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
