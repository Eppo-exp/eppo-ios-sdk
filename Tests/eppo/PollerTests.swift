import XCTest
@testable import EppoFlagging

final class PollerTests: XCTestCase {
    @MainActor
    func testInvokesCallbackUntilStopped() async throws {
        var callCount = 0
        
        let mockCallback: () async throws -> Void = {
            callCount += 1
        }
        
        let testTimer = TestTimer()
        let poller = await Poller(
            intervalMs: 100,
            jitterMs: 10,
            callback: mockCallback,
            logger: PollerLogger(),
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
        try await Task.sleep(nanoseconds: 500_000_000) // 100ms
        
        // Counts should remain the same after stopping
        XCTAssertEqual(callCount, 1, "Call count should not change after stopping")
        XCTAssertEqual(testTimer.executeCount, 1, "Timer executions should not change after stopping")
    }
    
    @MainActor
    func testSuccessfulPolling() async throws {
        var callCount = 0
        
        let mockCallback: () async throws -> Void = {
            callCount += 1
        }
        
        let testTimer = TestTimer()
        let poller = await Poller(
            intervalMs: 100,
            jitterMs: 10,
            callback: mockCallback,
            logger: PollerLogger(),
            timer: testTimer
        )
        
        try await poller.start()
        
        // Give it some time to execute multiple polls
        try await Task.sleep(nanoseconds: 500_000_000) // 100ms
        
        // Stop the poller
        poller.stop()
        
        XCTAssertGreaterThan(callCount, 1, "Should have called multiple times")
        XCTAssertGreaterThan(testTimer.executeCount, 1, "Timer should have been scheduled multiple times")
    }
    
    @MainActor
    func testExponentialBackoffOnErrors() async throws {
        var callCount = 0
        let mockCallback: () async throws -> Void = {
            callCount += 1
            throw NSError(domain: "Test", code: 0, userInfo: [NSLocalizedDescriptionKey: "bad request"])
        }

        // Use the regular TestTimer but with very short intervals (1ms instead of seconds)
        let testTimer = TestTimer()
        let poller = await Poller(
            intervalMs: 1,  // 1ms instead of 100ms for speed
            jitterMs: 0,    // No jitter for predictable timing
            callback: mockCallback,
            logger: PollerLogger(),
            timer: testTimer
        )

        // Start the poller
        try? await poller.start()
        XCTAssertEqual(callCount, 1, "Should have made initial call")

        // Wait for all retries to complete (exponential backoff: 1ms, 2ms, 4ms, 8ms, 16ms, 32ms, 64ms)
        // Total time ~127ms + processing overhead, use 300ms to be safe
        try await Task.sleep(nanoseconds: 300_000_000)

        // After all retries are complete, verify final state
        XCTAssertEqual(callCount, 8, "Should have made 1 initial call + 7 retry attempts (max reached)")
        XCTAssertEqual(testTimer.executeCount, 7, "Timer should have been scheduled 7 times")

        // Wait a bit more to ensure no more attempts are made after max retries
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(callCount, 8, "Should have stopped at max retries and not made more attempts")
    }
    
    @MainActor
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
        let jitterMs = 10
        let testTimer = TestTimer()
        
        let poller = await Poller(
            intervalMs: intervalMs,
            jitterMs: jitterMs,
            callback: mockCallback,
            logger: PollerLogger(),
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
