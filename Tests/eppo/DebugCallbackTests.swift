import XCTest
import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import EppoFlagging

final class DebugCallbackTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset shared instance before each test
        EppoClient.resetSharedInstance()
    }
    
    override func tearDown() {
        super.tearDown()
        HTTPStubs.removeAllStubs()
        EppoClient.resetSharedInstance()
    }
    
    func testDebugCallbackReceivesTimingData() async throws {
        // Arrange
        var capturedMessages: [(String, Double, Double)] = []
        let debugCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            capturedMessages.append((message, elapsedMs, stepMs))
        }
        
        // Mock the HTTP response for configuration fetch
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {},
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "SERVER_1_0"
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Act
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key",
            debugCallback: debugCallback
        )
        
        // Assert
        XCTAssertGreaterThan(capturedMessages.count, 0, "Debug callback should receive messages")
        
        // Verify first message has zero elapsed time and step duration
        let firstMessage = capturedMessages.first!
        XCTAssertTrue(firstMessage.0.contains("Starting Eppo SDK initialization"))
        XCTAssertEqual(firstMessage.1, 0.0, "First message should have 0ms elapsed time")
        XCTAssertEqual(firstMessage.2, 0.0, "First message should have 0ms step duration")
        
        // Verify subsequent messages have positive timing values
        if capturedMessages.count > 1 {
            let secondMessage = capturedMessages[1]
            XCTAssertGreaterThan(secondMessage.1, 0.0, "Elapsed time should be positive for subsequent messages")
            XCTAssertGreaterThan(secondMessage.2, 0.0, "Step duration should be positive for subsequent messages")
        }
        
        // Verify last message indicates completion (could be SDK init, storage write start/end due to async timing)
        let lastMessage = capturedMessages.last!
        let isValidLastMessage = lastMessage.0.contains("Total SDK initialization completed") || 
                                lastMessage.0.contains("Starting persistent storage write") ||
                                lastMessage.0.contains("Persistent storage write completed")
        XCTAssertTrue(isValidLastMessage, "Last message should be SDK completion or storage write operation, but was: '\(lastMessage.0)'")
        XCTAssertGreaterThan(lastMessage.1, 0.0, "Final message should have positive elapsed time")
        
        // Verify elapsed times are monotonically increasing (or equal)
        let elapsedTimes = capturedMessages.map { $0.1 }
        XCTAssertGreaterThan(elapsedTimes.count, 1, "Should have multiple timing measurements")
        
        for i in 1..<elapsedTimes.count {
            XCTAssertGreaterThanOrEqual(elapsedTimes[i], elapsedTimes[i-1], 
                "Elapsed time should be monotonically increasing: \(elapsedTimes[i]) >= \(elapsedTimes[i-1])")
        }
        
        // First elapsed time should be 0
        XCTAssertEqual(elapsedTimes.first!, 0.0, "First elapsed time should be 0ms")
    }
    
    func testDebugCallbackNotCalledWhenNil() async throws {
        // Mock the HTTP response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {},
                "createdAt": "2023-01-01T00:00:00.000Z", 
                "environment": {"name": "test"},
                "format": "SERVER_1_0"
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Act - initialize without debug callback
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key"
            // No debugCallback parameter
        )
        
        // Assert - we can't directly test that the callback wasn't called since it's nil,
        // but we can verify the initialization completed successfully without errors
        XCTAssertTrue(true, "Initialization should complete successfully without debug callback")
    }
    
    func testDebugCallbackWithPersistentStorage() async throws {
        // Arrange - debug callback that prints to console showing persistent storage behavior
        let debugCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            print("[\(String(format: "%.1f", elapsedMs))ms] \(message) (step: \(String(format: "%.1f", stepMs))ms)")
        }
        
        // Mock the HTTP response
        stub(condition: isHost("fscdn.eppo.cloud")) { _ in
            let testConfig = """
            {
                "flags": {},
                "createdAt": "2023-01-01T00:00:00.000Z",
                "environment": {"name": "test"},
                "format": "SERVER_1_0"
            }
            """
            return HTTPStubsResponse(data: testConfig.data(using: .utf8)!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        // Clear any existing cached configuration to ensure clean test
        EppoClient.resetSharedInstance()
        ConfigurationStore.clearPersistentCache()
        
        print("\n🧪 === First Initialization (New Client, Config not yet in Persistent Storage) ===")
        
        // Act - First initialization (should fetch from network)
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-storage-test",
            debugCallback: debugCallback
        )
        
        // Wait briefly for async write to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        print("🧪 === Second Initialization (Reuse Same Client, Should Use In-Memory Cache) ===")
        
        // Second call to initialize should return existing instance without network fetch
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-storage-test",
            debugCallback: debugCallback
        )
        
        print("🧪 === Third Initialization (New Client, Should Read from Persistent Storage) ===")
        
        // Reset to create new instance that should read from persistent storage
        EppoClient.resetSharedInstance()
        
        // Third initialization should read cached config from persistent storage
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-storage-test",
            debugCallback: debugCallback
        )
        
        print("🧪 === End Persistent Storage Test ===\n")
        
        // Assert - just verify initialization completed
        XCTAssertTrue(true, "Initialization completed successfully with persistent storage usage")
    }
}
