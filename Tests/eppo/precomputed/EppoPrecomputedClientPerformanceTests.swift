import XCTest
@testable import EppoFlagging

class EppoPrecomputedClientPerformanceTests: XCTestCase {
    var testSubject: Subject!
    
    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        
        testSubject = Subject(
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
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Measure single assignment performance
        measure {
            _ = EppoPrecomputedClient.shared.getStringAssignment(
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
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Test multiple assignments and measure average time
        let iterations = 1000
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let flagKey = "flag-\(i % 500)" // Cycle through available flags
            _ = EppoPrecomputedClient.shared.getStringAssignment(
                flagKey: flagKey,
                defaultValue: "default"
            )
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = (totalTime * 1000) / Double(iterations) // Convert to ms
        
        print("Average assignment time: \(String(format: "%.3f", averageTime))ms over \(iterations) calls")
        
        // Verify <1ms requirement
        XCTAssertLessThan(averageTime, 1.0, "Average assignment time should be less than 1ms, got \(averageTime)ms")
    }
    
    // MARK: - Concurrent Performance Tests
    
    func testConcurrentAssignmentPerformance() {
        let testConfig = createPerformanceConfiguration(flagCount: 200)
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        let expectation = XCTestExpectation(description: "Concurrent assignments")
        expectation.expectedFulfillmentCount = 10
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Launch multiple concurrent assignment threads
        for threadIndex in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<100 {
                    let flagKey = "flag-\(i % 200)"
                    _ = EppoPrecomputedClient.shared.getStringAssignment(
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
        
        print("Concurrent average assignment time: \(String(format: "%.3f", averageTime))ms over \(totalAssignments) calls")
        
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
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Perform many assignments to stress test memory
        for i in 0..<1000 {
            let flagKey = "flag-\(i)"
            _ = EppoPrecomputedClient.shared.getStringAssignment(
                flagKey: flagKey,
                defaultValue: "default"
            )
        }
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        print("Memory increase: \(memoryIncrease / 1024 / 1024) MB for 1000 flags")
        
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
                subject: testSubject,
                initialPrecomputedConfiguration: testConfig
            )
            
            let initTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
            
            print("Initialization time for \(flagCount) flags: \(String(format: "%.2f", initTime))ms")
            
            // Initialization should be fast even with many flags (<100ms)
            XCTAssertLessThan(initTime, 100, "Initialization should be fast for \(flagCount) flags")
        }
    }
    
    // MARK: - Different Assignment Type Performance
    
    func testDifferentAssignmentTypesPerformance() {
        let testConfig = createMixedTypeConfiguration(flagCount: 200)
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        let iterations = 250 // 50 of each type
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Test different assignment types
        for i in 0..<iterations {
            let flagIndex = i % 50
            
            switch i % 5 {
            case 0:
                _ = EppoPrecomputedClient.shared.getStringAssignment(
                    flagKey: "string-flag-\(flagIndex)",
                    defaultValue: "default"
                )
            case 1:
                _ = EppoPrecomputedClient.shared.getBooleanAssignment(
                    flagKey: "boolean-flag-\(flagIndex)",
                    defaultValue: false
                )
            case 2:
                _ = EppoPrecomputedClient.shared.getIntegerAssignment(
                    flagKey: "integer-flag-\(flagIndex)",
                    defaultValue: 0
                )
            case 3:
                _ = EppoPrecomputedClient.shared.getNumericAssignment(
                    flagKey: "numeric-flag-\(flagIndex)",
                    defaultValue: 0.0
                )
            case 4:
                _ = EppoPrecomputedClient.shared.getJSONStringAssignment(
                    flagKey: "json-flag-\(flagIndex)",
                    defaultValue: "{}"
                )
            default:
                break
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = (totalTime * 1000) / Double(iterations)
        
        print("Mixed type assignment average time: \(String(format: "%.3f", averageTime))ms")
        
        XCTAssertLessThan(averageTime, 1.0, "Mixed type assignments should be fast")
    }
    
    // MARK: - Helper Methods
    
    private func createPerformanceConfiguration(flagCount: Int) -> PrecomputedConfiguration {
        var flags: [String: PrecomputedFlag] = [:]
        
        for i in 0..<flagCount {
            let flagKey = "flag-\(i)"
            flags[getMD5Hex(flagKey, salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-\(i % 3)"),
                variationType: .STRING,
                variationValue: EppoValue(value: base64Encode("value-\(i)")),
                extraLogging: [
                    base64Encode("experiment-holdout-key"): base64Encode("holdout-\(i % 10)"),
                    base64Encode("holdoutVariation"): base64Encode(i % 2 == 0 ? "status_quo" : "all_shipped")
                ],
                doLog: i % 5 == 0 // Only log 20% to be realistic
            )
        }
        
        return PrecomputedConfiguration(
            flags: flags,
            salt: "test-salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
    }
    
    private func createMixedTypeConfiguration(flagCount: Int) -> PrecomputedConfiguration {
        var flags: [String: PrecomputedFlag] = [:]
        
        let flagsPerType = flagCount / 5
        
        // Create flags of different types
        for i in 0..<flagsPerType {
            // String flags
            flags[getMD5Hex("string-flag-\(i)", salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-a"),
                variationType: .STRING,
                variationValue: EppoValue(value: base64Encode("string-value-\(i)")),
                extraLogging: [:],
                doLog: true
            )
            
            // Boolean flags
            flags[getMD5Hex("boolean-flag-\(i)", salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-b"),
                variationType: .BOOLEAN,
                variationValue: EppoValue(value: i % 2 == 0),
                extraLogging: [:],
                doLog: true
            )
            
            // Integer flags
            flags[getMD5Hex("integer-flag-\(i)", salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-c"),
                variationType: .INTEGER,
                variationValue: EppoValue(value: Double(i * 10)),
                extraLogging: [:],
                doLog: true
            )
            
            // Numeric flags
            flags[getMD5Hex("numeric-flag-\(i)", salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-d"),
                variationType: .NUMERIC,
                variationValue: EppoValue(value: Double(i) * 1.5),
                extraLogging: [:],
                doLog: true
            )
            
            // JSON flags
            flags[getMD5Hex("json-flag-\(i)", salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-e"),
                variationType: .JSON,
                variationValue: EppoValue(value: base64Encode("{\"index\": \(i)}")),
                extraLogging: [:],
                doLog: true
            )
        }
        
        return PrecomputedConfiguration(
            flags: flags,
            salt: "test-salt",
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
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