import XCTest
@testable import EppoFlagging

final class PollerTests: XCTestCase {
    
    func testInvokesCallbackUntilStopped() async throws {
        var callCount = 0
        
        let mockCallback: () async throws -> Void = {
            callCount += 1
        }
        
        let testTimer = TestTimer()
        let poller = Poller(
            intervalMs: 10,
            jitterMs: 1,
            callback: mockCallback,
            logger: Logger(),
            timer: testTimer
        )
        
        // Start the poller
        try await poller.start()
        
        // Initial call should succeed
        XCTAssertEqual(callCount, 1, "Should have made initial call")
        XCTAssertEqual(testTimer.executeCount, 1, "Timer should have been scheduled once")
        
        // Stop the poller
        poller.stop()
        
        // Give it some time to execute multiple polls
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Counts should remain the same after stopping
        XCTAssertEqual(callCount, 1, "Call count should not change after stopping")
        XCTAssertEqual(testTimer.executeCount, 1, "Timer executions should not change after stopping")
    }
    
    func testSuccessfulPolling() async throws {
        var callCount = 0
        
        let mockCallback: () async throws -> Void = {
            callCount += 1
        }
        
        let testTimer = TestTimer()
        let poller = Poller(
            intervalMs: 10,
            jitterMs: 1,
            callback: mockCallback,
            logger: Logger(),
            timer: testTimer
        )
        
        try await poller.start()
        
        // Give it some time to execute multiple polls
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Stop the poller
        poller.stop()
        
        XCTAssertGreaterThan(callCount, 1, "Should have called multiple times")
        XCTAssertGreaterThan(testTimer.executeCount, 1, "Timer should have been scheduled multiple times")
    }
    
    func testExponentialBackoffOnErrors() async throws {
        var callCount = 0
        let mockCallback: () async throws -> Void = {
            callCount += 1
            throw NSError(domain: "Test", code: 0, userInfo: [NSLocalizedDescriptionKey: "bad request"])
        }

        let testTimer = TestTimer()
        let poller = Poller(
            intervalMs: 100,
            jitterMs: 0,
            callback: mockCallback,
            logger: Logger(),
            timer: testTimer
        )

        // Start the poller
        try? await poller.start()

        // Wait for two intervals to pass
        try await Task.sleep(nanoseconds: 200_000_000 + 100_000_000) // 200ms
        XCTAssertGreaterThan(callCount, 1, "Should have attempted at least 1 retry")
        XCTAssertLessThan(callCount, 8, "Should have not yet reached the max retries")
        
        
        try await Task.sleep(nanoseconds: 12_800_000_000 + 6_400_000_000 + 3_200_000_000 + 1_600_000_000 + 800_000_000 + 400_000_000) // Last retry interval is 6_400_000_000
        XCTAssertEqual(callCount, 8, "Should have attempted up to max retries") // Cannot go beyond max
        XCTAssertEqual(testTimer.executeCount, 7, "Timer should have been scheduled 7 times")
    }
    
    func testJitterIsApplied() async throws {
        var intervals: [TimeInterval] = []
        var lastCallTime: TimeInterval = Date().timeIntervalSince1970
        
        let mockCallback: () async throws -> Void = {
            let now = Date().timeIntervalSince1970
            let interval = now - lastCallTime
            if intervals.count > 0 {  // Skip first interval
                intervals.append(interval)
            }
            lastCallTime = now
        }
        
        let intervalMs = 100
        let jitterMs = 50
        let testTimer = TestTimer()
        
        let poller = Poller(
            intervalMs: intervalMs,
            jitterMs: jitterMs,
            callback: mockCallback,
            logger: Logger(),
            timer: testTimer
        )
        
        // Start the poller
        try await poller.start()
        
        // Give some time for multiple callbacks
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        poller.stop()
        
        // Verify that multiple executions occurred
        XCTAssertTrue(testTimer.executeCount > 1, "Should have executed multiple times")
        
        // Verify jitter
        for interval in intervals {
            // Convert to milliseconds for comparison
            let intervalInMs = interval * 1000
            
            // Should be between intervalMs and intervalMs + jitterMs
            XCTAssertGreaterThanOrEqual(intervalInMs, Double(intervalMs), "Interval should not be less than base interval")
            XCTAssertLessThanOrEqual(intervalInMs, Double(intervalMs + jitterMs), "Interval should not exceed base interval plus max jitter")
        }
        
        // Verify that not all intervals are the same (jitter is actually being applied)
        if intervals.count > 1 {
            let allSame = intervals.dropFirst().allSatisfy { $0 == intervals[0] }
            XCTAssertFalse(allSame, "Intervals should vary due to jitter")
        }
    }
}
