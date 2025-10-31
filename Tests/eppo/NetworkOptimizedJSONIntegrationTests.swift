import XCTest
@testable import EppoFlagging
import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

/**
 * Network OptimizedJSON Integration Tests
 *
 * Tests the OptimizedJSON evaluator through the full network initialization flow
 * using mock HTTP responses, verifying end-to-end functionality.
 */
final class NetworkOptimizedJSONIntegrationTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        HTTPStubs.removeAllStubs()
        EppoClient.resetSharedInstance()
    }

    func testOptimizedJSONNetworkInitializationEndToEnd() async throws {
        NSLog("🚀 Starting OptimizedJSON network initialization integration test")

        // Mock the HTTP response with a real flag configuration
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {
                    "test-flag": {
                        "key": "test-flag",
                        "enabled": true,
                        "variationType": "STRING",
                        "variations": {
                            "control": {"key": "control", "value": "control-value"},
                            "treatment": {"key": "treatment", "value": "treatment-value"}
                        },
                        "allocations": [{
                            "key": "allocation-1",
                            "rules": [],
                            "startAt": "2023-01-01T00:00:00.000Z",
                            "endAt": "2024-01-01T00:00:00.000Z",
                            "splits": [{
                                "variationKey": "control",
                                "shards": [{"salt": "test-salt", "ranges": [{"start": 0, "end": 10000}]}]
                            }]
                        }]
                    }
                },
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "ufc-v1",
                "doLog": true
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        // Act: Initialize with OptimizedJSON evaluator type (THIS SHOULD USE THE FAST PATH!)
        NSLog("🎯 Calling EppoClient.initialize() with evaluatorType: .optimizedJSON")
        let client = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-optimized",
            evaluatorType: .optimizedJSON  // <- This should trigger the fast path
        )

        NSLog("✅ EppoClient.initialize() completed successfully with OptimizedJSON")

        // Verify that the client was created and can evaluate flags
        let assignment = client.getStringAssignment(
            flagKey: "test-flag",
            subjectKey: "test-subject",
            subjectAttributes: [:],
            defaultValue: "default"
        )

        NSLog("🎯 Flag evaluation result: \(assignment)")

        // Assert that we got a valid assignment (not the default)
        XCTAssertEqual(assignment, "control", "OptimizedJSON evaluator should evaluate flag correctly")

        NSLog("🏆 OptimizedJSON network initialization integration test PASSED!")
    }

    func testCompareStandardVsOptimizedJSONNetworkInitialization() async throws {
        NSLog("🚀 Starting Standard vs OptimizedJSON network initialization comparison test")

        let testConfigData = """
        {
            "flags": {
                "comparison-flag": {
                    "key": "comparison-flag",
                    "enabled": true,
                    "variationType": "BOOLEAN",
                    "variations": {
                        "control": {"key": "control", "value": false},
                        "treatment": {"key": "treatment", "value": true}
                    },
                    "allocations": [{
                        "key": "allocation-1",
                        "rules": [],
                        "startAt": "2023-01-01T00:00:00.000Z",
                        "endAt": "2024-01-01T00:00:00.000Z",
                        "splits": [{
                            "variationKey": "control",
                            "shards": [{"salt": "test-salt", "ranges": [{"start": 0, "end": 10000}]}]
                        }]
                    }]
                }
            },
            "createdAt": "2023-01-01T00:00:00.000Z",
            "environment": {"name": "test"},
            "format": "ufc-v1",
            "doLog": true
        }
        """

        // Test Standard evaluator
        HTTPStubs.removeAllStubs()
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            return HTTPStubsResponse(data: testConfigData.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        NSLog("🔄 Testing Standard evaluator network initialization...")
        let standardStartTime = CFAbsoluteTimeGetCurrent()

        let standardClient = try await EppoClient.initialize(
            sdkKey: "standard-sdk-key",
            evaluatorType: .standard
        )

        let standardInitTime = (CFAbsoluteTimeGetCurrent() - standardStartTime) * 1000
        NSLog("⏱️  Standard network initialization took: %.2fms", standardInitTime)

        let standardAssignment = standardClient.getBooleanAssignment(
            flagKey: "comparison-flag",
            subjectKey: "test-subject",
            subjectAttributes: [:],
            defaultValue: true
        )

        // Reset for OptimizedJSON test
        EppoClient.resetSharedInstance()
        HTTPStubs.removeAllStubs()
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            return HTTPStubsResponse(data: testConfigData.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        NSLog("🚀 Testing OptimizedJSON evaluator network initialization...")
        let optimizedStartTime = CFAbsoluteTimeGetCurrent()

        let optimizedClient = try await EppoClient.initialize(
            sdkKey: "optimized-sdk-key",
            evaluatorType: .optimizedJSON  // <- Fast path
        )

        let optimizedInitTime = (CFAbsoluteTimeGetCurrent() - optimizedStartTime) * 1000
        NSLog("⚡ OptimizedJSON network initialization took: %.2fms", optimizedInitTime)

        let optimizedAssignment = optimizedClient.getBooleanAssignment(
            flagKey: "comparison-flag",
            subjectKey: "test-subject",
            subjectAttributes: [:],
            defaultValue: true
        )

        // Verify both produce the same results
        XCTAssertEqual(standardAssignment, optimizedAssignment, "Both evaluators should produce identical results")
        XCTAssertEqual(standardAssignment, false, "Both should evaluate to 'control' variation (false)")

        NSLog("🏁 NETWORK INITIALIZATION COMPARISON RESULTS:")
        NSLog("   📊 Standard: %.2fms", standardInitTime)
        NSLog("   ⚡ OptimizedJSON: %.2fms", optimizedInitTime)

        if optimizedInitTime < standardInitTime {
            let speedup = standardInitTime / optimizedInitTime
            NSLog("   🏆 OptimizedJSON is %.1fx FASTER", speedup)
        } else {
            let slowdown = optimizedInitTime / standardInitTime
            NSLog("   ⚠️  OptimizedJSON is %.1fx slower (unexpected)", slowdown)
        }

        NSLog("✅ Network initialization comparison test completed!")
    }

    func testOptimizedJSONNetworkInitializationWithDebugCallback() async throws {
        NSLog("🚀 Testing OptimizedJSON network initialization with debug logging")

        var debugMessages: [(String, Double, Double)] = []
        let debugCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            debugMessages.append((message, elapsedMs, stepMs))
            NSLog("🐛 Debug: \(message) (elapsed: %.1fms, step: %.1fms)", elapsedMs, stepMs)
        }

        // Mock HTTP response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {"debug-flag": {"key": "debug-flag", "enabled": true, "variationType": "STRING", "variations": {"default": {"key": "default", "value": "test"}}, "allocations": []}},
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "ufc-v1",
                "doLog": true
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        // Initialize with OptimizedJSON and debug callback
        let client = try await EppoClient.initialize(
            sdkKey: "debug-sdk-key",
            evaluatorType: .optimizedJSON,
            debugCallback: debugCallback
        )

        // Verify debug messages were captured
        XCTAssertGreaterThan(debugMessages.count, 0, "Debug callback should receive messages")

        // Look for OptimizedJSON-specific debug messages
        let optimizedMessages = debugMessages.filter { $0.0.contains("OptimizedJSON") || $0.0.contains("fast path") }
        NSLog("📊 Found \(optimizedMessages.count) OptimizedJSON-specific debug messages")

        for message in optimizedMessages {
            NSLog("   🎯 OptimizedJSON Debug: \(message.0)")
        }

        // Verify the client can evaluate flags
        let assignment = client.getStringAssignment(
            flagKey: "debug-flag",
            subjectKey: "debug-subject",
            subjectAttributes: [:],
            defaultValue: "default"
        )

        XCTAssertEqual(assignment, "test", "Flag evaluation should work correctly")

        NSLog("✅ OptimizedJSON debug callback test completed!")
    }
}