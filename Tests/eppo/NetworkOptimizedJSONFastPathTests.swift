import XCTest
@testable import EppoFlagging
import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

/**
 * Network OptimizedJSON Fast Path Tests
 *
 * Focused tests that validate the OptimizedJSON network fast path is working correctly.
 * Primary goal: Verify Configuration parsing is bypassed for maximum startup performance.
 */
final class NetworkOptimizedJSONFastPathTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        HTTPStubs.removeAllStubs()
        EppoClient.resetSharedInstance()
    }

    func testOptimizedJSONNetworkFastPathExecuted() async throws {
        NSLog("🚀 Testing OptimizedJSON network fast path execution")

        var debugMessages: [String] = []
        let debugCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            debugMessages.append(message)
        }

        // Mock HTTP response with minimal valid JSON
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {},
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "ufc-v1",
                "doLog": true
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        // Initialize with OptimizedJSON evaluator type
        let client = try await EppoClient.initialize(
            sdkKey: "test-fast-path-sdk-key",
            evaluatorType: .optimizedJSON,
            debugCallback: debugCallback
        )

        // Verify the fast path debug messages are present
        let fastPathMessages = debugMessages.filter { message in
            message.contains("raw JSON") ||
            message.contains("fast path") ||
            message.contains("skipping Configuration parsing")
        }

        NSLog("📊 Found \(fastPathMessages.count) fast path debug messages:")
        for message in fastPathMessages {
            NSLog("   🎯 \(message)")
        }

        // Assert fast path messages exist
        XCTAssertGreaterThan(fastPathMessages.count, 0, "Should have fast path debug messages")

        // Verify specific fast path messages
        let hasRawJSONMessage = debugMessages.contains { $0.contains("fetch raw JSON") }
        let hasSkipConfigMessage = debugMessages.contains { $0.contains("skipping Configuration parsing") }
        let hasFastPathCompleteMessage = debugMessages.contains { $0.contains("OptimizedJSON fast startup path completed") }

        XCTAssertTrue(hasRawJSONMessage, "Should have raw JSON fetch message")
        XCTAssertTrue(hasSkipConfigMessage, "Should have skip Configuration parsing message")
        XCTAssertTrue(hasFastPathCompleteMessage, "Should have fast path completion message")

        // Verify client was created successfully
        XCTAssertNotNil(client, "Client should be created successfully")

        NSLog("✅ OptimizedJSON network fast path test PASSED!")
    }

    func testOptimizedJSONNetworkFastPathTiming() async throws {
        NSLog("🚀 Testing OptimizedJSON network fast path timing performance")

        var initializationTime: Double = 0.0
        var optimizedJSONMessages: [(String, Double)] = []

        let debugCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            if message.contains("Total SDK initialization completed") {
                initializationTime = elapsedMs
            }
            if message.contains("OptimizedJSON") || message.contains("fast path") {
                optimizedJSONMessages.append((message, elapsedMs))
            }
        }

        // Mock HTTP response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {"test": {"key": "test", "enabled": true, "variationType": "STRING", "variations": {}, "allocations": []}},
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "ufc-v1",
                "doLog": true
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Initialize with OptimizedJSON
        let client = try await EppoClient.initialize(
            sdkKey: "timing-test-sdk-key",
            evaluatorType: .optimizedJSON,
            debugCallback: debugCallback
        )

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        NSLog("⏱️  Measured initialization times:")
        NSLog("   📊 Manual timing: %.2fms", totalTime)
        NSLog("   📊 Debug callback timing: %.2fms", initializationTime)

        NSLog("🔍 OptimizedJSON timing messages:")
        for (message, timing) in optimizedJSONMessages {
            NSLog("   ⚡ %.1fms: \(message)", timing)
        }

        // Verify timing is reasonable for fast path (should be very quick)
        XCTAssertLessThan(totalTime, 100.0, "OptimizedJSON initialization should be under 100ms")
        XCTAssertGreaterThan(optimizedJSONMessages.count, 0, "Should have OptimizedJSON timing messages")

        XCTAssertNotNil(client, "Client should be created")

        NSLog("✅ OptimizedJSON network fast path timing test PASSED!")
    }

    func testOptimizedJSONBypassesConfigurationParsingCompletely() async throws {
        NSLog("🚀 Testing that OptimizedJSON completely bypasses Configuration parsing")

        var allDebugMessages: [String] = []
        let debugCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            allDebugMessages.append(message)
        }

        // Mock HTTP response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {},
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "ufc-v1",
                "doLog": true
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        // Initialize with OptimizedJSON
        let _ = try await EppoClient.initialize(
            sdkKey: "bypass-config-test",
            evaluatorType: .optimizedJSON,
            debugCallback: debugCallback
        )

        // Check for messages that would indicate Configuration parsing
        let configurationParsingMessages = allDebugMessages.filter { message in
            message.contains("Configuration: Standard upfront parsing") ||
            message.contains("JSON parsing and configuration creation") ||
            message.contains("Starting JSON parsing")
        }

        NSLog("🔍 Looking for Configuration parsing messages...")
        NSLog("   📊 Total debug messages: \(allDebugMessages.count)")
        NSLog("   ❌ Configuration parsing messages: \(configurationParsingMessages.count)")

        for message in configurationParsingMessages {
            NSLog("   ⚠️  Found Configuration parsing: \(message)")
        }

        // Verify Configuration parsing was completely bypassed
        XCTAssertEqual(configurationParsingMessages.count, 0, "OptimizedJSON should completely bypass Configuration parsing")

        // Verify fast path messages exist
        let fastPathMessages = allDebugMessages.filter { $0.contains("fast path") || $0.contains("raw JSON") }
        XCTAssertGreaterThan(fastPathMessages.count, 0, "Should have fast path messages")

        NSLog("✅ Configuration parsing bypass test PASSED!")
    }
}