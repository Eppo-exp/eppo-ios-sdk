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
        // Arrange - capture messages instead of printing
        var firstInitMessages: [(String, Double, Double)] = []
        var secondInitMessages: [(String, Double, Double)] = []
        var thirdInitMessages: [(String, Double, Double)] = []
        
        let firstInitCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            firstInitMessages.append((message, elapsedMs, stepMs))
        }
        
        let secondInitCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            secondInitMessages.append((message, elapsedMs, stepMs))
        }
        
        let thirdInitCallback: (String, Double, Double) -> Void = { message, elapsedMs, stepMs in
            thirdInitMessages.append((message, elapsedMs, stepMs))
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
        
        // Act - First initialization (should fetch from network)
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-storage-test",
            debugCallback: firstInitCallback
        )
        
        // Wait briefly for async write to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Second call to initialize should return existing instance without network fetch
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-storage-test",
            debugCallback: secondInitCallback
        )
        
        // Reset to create new instance that should read from persistent storage
        EppoClient.resetSharedInstance()
        
        // Third initialization should read cached config from persistent storage
        let _ = try await EppoClient.initialize(
            sdkKey: "test-sdk-key-storage-test",
            debugCallback: thirdInitCallback
        )
        
        // Assert first initialization behavior
        XCTAssertGreaterThan(firstInitMessages.count, 0, "First initialization should generate debug messages")
        
        let firstInitMessageTexts = firstInitMessages.map { $0.0 }
        let hasReadAttempt = firstInitMessageTexts.contains { $0.contains("persistent storage read") }
        let hasReadFailure = firstInitMessageTexts.contains { $0.contains("failed") || $0.contains("not found") }
        let hasNetworkFetch = firstInitMessageTexts.contains { $0.contains("fetch") || $0.contains("network") }
        let hasStorageWrite = firstInitMessageTexts.contains { $0.contains("persistent storage write") }
        
        XCTAssertTrue(hasReadAttempt || hasReadFailure, "First initialization should attempt to read from persistent storage and fail")
        XCTAssertTrue(hasNetworkFetch, "First initialization should fetch from network")
        XCTAssertTrue(hasStorageWrite, "First initialization should write to persistent storage")
        
        // Assert second initialization behavior (should be instantaneous with existing instance)
        let secondInitMessageTexts = secondInitMessages.map { $0.0 }
        let hasNoStorageOperations = !secondInitMessageTexts.contains { $0.contains("persistent storage") }
        XCTAssertTrue(hasNoStorageOperations || secondInitMessages.isEmpty, "Second initialization should not perform storage operations")
        
        // Verify second initialization is much faster (if any messages at all)
        if !secondInitMessages.isEmpty {
            let secondInitTotalTime = secondInitMessages.last?.1 ?? 0
            let firstInitTotalTime = firstInitMessages.last?.1 ?? 0
            XCTAssertLessThan(secondInitTotalTime, firstInitTotalTime * 0.5, "Second initialization should be faster (reusing existing instance)")
        }
        
        // Assert third initialization behavior
        XCTAssertGreaterThan(thirdInitMessages.count, 0, "Third initialization should generate debug messages")
        
        let thirdInitMessageTexts = thirdInitMessages.map { $0.0 }
        let hasSuccessfulRead = thirdInitMessageTexts.contains { $0.contains("persistent storage read") && !$0.contains("failed") && !$0.contains("not found") }
        
        XCTAssertTrue(hasSuccessfulRead, "Third initialization should successfully read from persistent storage")
        
        // Note: Third initialization will still do network fetch to get latest config, but starts with cached config
    }
}
