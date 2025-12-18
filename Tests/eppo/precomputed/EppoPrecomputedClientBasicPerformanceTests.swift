import XCTest
@testable import EppoFlagging

class EppoPrecomputedClientBasicPerformanceTests: XCTestCase {
    var testSubject: Subject!
    
    override func setUp() {
        super.setUp()
        EppoPrecomputedClient.resetForTesting()
        
        testSubject = Subject(
            subjectKey: "performance-test-user",
            subjectAttributes: ["age": EppoValue(value: 25)]
        )
    }
    
    override func tearDown() {
        EppoPrecomputedClient.resetForTesting()
        super.tearDown()
    }
    
    func testBasicAssignmentPerformance() {
        // Start with a small, safe configuration
        let testConfig = createSmallConfiguration(flagCount: 10)
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Test single assignment performance
        let iterations = 1000
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let flagKey = "flag-\(i % 10)" // Cycle through available flags
            _ = EppoPrecomputedClient.shared.getStringAssignment(
                flagKey: flagKey,
                defaultValue: "default"
            )
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = (totalTime * 1000) / Double(iterations) // Convert to ms
        
        print("Average assignment time: \(String(format: "%.6f", averageTime))ms over \(iterations) calls")
        print("Total time: \(String(format: "%.3f", totalTime * 1000))ms")
        
        // Verify <1ms requirement
        XCTAssertLessThan(averageTime, 1.0, "Average assignment time should be less than 1ms, got \(averageTime)ms")
    }
    
    func testMediumConfigurationPerformance() {
        // Test with medium sized configuration (50 flags)
        let testConfig = createSmallConfiguration(flagCount: 50)
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Test assignment performance
        let iterations = 500
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let flagKey = "flag-\(i % 50)"
            _ = EppoPrecomputedClient.shared.getStringAssignment(
                flagKey: flagKey,
                defaultValue: "default"
            )
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = (totalTime * 1000) / Double(iterations)
        
        print("Medium config average time: \(String(format: "%.6f", averageTime))ms over \(iterations) calls")
        
        XCTAssertLessThan(averageTime, 1.0, "Average assignment time should be less than 1ms with 50 flags")
    }
    
    func testDifferentAssignmentTypes() {
        let testConfig = createMixedTypeSmallConfiguration()
        
        _ = EppoPrecomputedClient.initializeOffline(
            sdkKey: "performance-test-key",
            subject: testSubject,
            initialPrecomputedConfiguration: testConfig
        )
        
        // Test each assignment type separately
        let iterations = 100
        
        // String assignments
        var startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = EppoPrecomputedClient.shared.getStringAssignment(
                flagKey: "string-flag",
                defaultValue: "default"
            )
        }
        let stringTime = ((CFAbsoluteTimeGetCurrent() - startTime) * 1000) / Double(iterations)
        
        // Boolean assignments
        startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = EppoPrecomputedClient.shared.getBooleanAssignment(
                flagKey: "boolean-flag",
                defaultValue: false
            )
        }
        let boolTime = ((CFAbsoluteTimeGetCurrent() - startTime) * 1000) / Double(iterations)
        
        // Integer assignments
        startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = EppoPrecomputedClient.shared.getIntegerAssignment(
                flagKey: "integer-flag",
                defaultValue: 0
            )
        }
        let intTime = ((CFAbsoluteTimeGetCurrent() - startTime) * 1000) / Double(iterations)
        
        // Numeric assignments
        startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = EppoPrecomputedClient.shared.getNumericAssignment(
                flagKey: "numeric-flag",
                defaultValue: 0.0
            )
        }
        let numericTime = ((CFAbsoluteTimeGetCurrent() - startTime) * 1000) / Double(iterations)
        
        // JSON assignments
        startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = EppoPrecomputedClient.shared.getJSONStringAssignment(
                flagKey: "json-flag",
                defaultValue: "{}"
            )
        }
        let jsonTime = ((CFAbsoluteTimeGetCurrent() - startTime) * 1000) / Double(iterations)
        
        print("String assignment time: \(String(format: "%.6f", stringTime))ms")
        print("Boolean assignment time: \(String(format: "%.6f", boolTime))ms")
        print("Integer assignment time: \(String(format: "%.6f", intTime))ms")
        print("Numeric assignment time: \(String(format: "%.6f", numericTime))ms")
        print("JSON assignment time: \(String(format: "%.6f", jsonTime))ms")
        
        // All should be under 1ms
        XCTAssertLessThan(stringTime, 1.0, "String assignments should be fast")
        XCTAssertLessThan(boolTime, 1.0, "Boolean assignments should be fast")
        XCTAssertLessThan(intTime, 1.0, "Integer assignments should be fast")
        XCTAssertLessThan(numericTime, 1.0, "Numeric assignments should be fast")
        XCTAssertLessThan(jsonTime, 1.0, "JSON assignments should be fast")
    }
    
    func testInitializationPerformance() {
        // Test initialization time with different sizes
        let flagCounts = [5, 10, 25, 50]
        
        for flagCount in flagCounts {
            EppoPrecomputedClient.resetForTesting()
            
            let testConfig = createSmallConfiguration(flagCount: flagCount)
            let startTime = CFAbsoluteTimeGetCurrent()
            
            _ = EppoPrecomputedClient.initializeOffline(
                sdkKey: "performance-test-key-\(flagCount)",
                subject: testSubject,
                initialPrecomputedConfiguration: testConfig
            )
            
            let initTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("Initialization time for \(flagCount) flags: \(String(format: "%.3f", initTime))ms")
            
            // Initialization should be very fast for small configs
            XCTAssertLessThan(initTime, 50, "Initialization should be fast for \(flagCount) flags")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createSmallConfiguration(flagCount: Int) -> PrecomputedConfiguration {
        var flags: [String: PrecomputedFlag] = [:]
        
        for i in 0..<flagCount {
            let flagKey = "flag-\(i)"
            flags[getMD5Hex(flagKey, salt: "test-salt")] = PrecomputedFlag(
                allocationKey: base64Encode("allocation-\(i)"),
                variationKey: base64Encode("variant-a"),
                variationType: .STRING,
                variationValue: EppoValue(value: base64Encode("value-\(i)")),
                extraLogging: [:], // Keep extra logging simple
                doLog: true
            )
        }
        
        return PrecomputedConfiguration(
            flags: flags,
            salt: "dGVzdC1zYWx0",  // base64("test-salt")
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
    }
    
    private func createMixedTypeSmallConfiguration() -> PrecomputedConfiguration {
        var flags: [String: PrecomputedFlag] = [:]
        
        // String flag
        flags[getMD5Hex("string-flag", salt: "test-salt")] = PrecomputedFlag(
            allocationKey: base64Encode("allocation-1"),
            variationKey: base64Encode("variant-a"),
            variationType: .STRING,
            variationValue: EppoValue(value: base64Encode("string-value")),
            extraLogging: [:],
            doLog: true
        )
        
        // Boolean flag
        flags[getMD5Hex("boolean-flag", salt: "test-salt")] = PrecomputedFlag(
            allocationKey: base64Encode("allocation-2"),
            variationKey: base64Encode("variant-b"),
            variationType: .BOOLEAN,
            variationValue: EppoValue(value: true),
            extraLogging: [:],
            doLog: true
        )
        
        // Integer flag
        flags[getMD5Hex("integer-flag", salt: "test-salt")] = PrecomputedFlag(
            allocationKey: base64Encode("allocation-3"),
            variationKey: base64Encode("variant-c"),
            variationType: .INTEGER,
            variationValue: EppoValue(value: 42.0),
            extraLogging: [:],
            doLog: true
        )
        
        // Numeric flag
        flags[getMD5Hex("numeric-flag", salt: "test-salt")] = PrecomputedFlag(
            allocationKey: base64Encode("allocation-4"),
            variationKey: base64Encode("variant-d"),
            variationType: .NUMERIC,
            variationValue: EppoValue(value: 3.14),
            extraLogging: [:],
            doLog: true
        )
        
        // JSON flag
        flags[getMD5Hex("json-flag", salt: "test-salt")] = PrecomputedFlag(
            allocationKey: base64Encode("allocation-5"),
            variationKey: base64Encode("variant-e"),
            variationType: .JSON,
            variationValue: EppoValue(value: base64Encode("{\"test\": true}")),
            extraLogging: [:],
            doLog: true
        )
        
        return PrecomputedConfiguration(
            flags: flags,
            salt: "dGVzdC1zYWx0",  // base64("test-salt")
            format: "PRECOMPUTED",
            configFetchedAt: Date(),
            configPublishedAt: nil,
            environment: nil
        )
    }
}