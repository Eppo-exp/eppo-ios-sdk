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
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
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
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
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

        // Wait for one interval to pass
        try await Task.sleep(nanoseconds: 110_000_000) // 100ms
        XCTAssertGreaterThanOrEqual(callCount, 2, "Should have attempted at least 1 retry")
        XCTAssertLessThan(callCount, 8, "Should have not yet reached the max retries")
//        // Wait for one interval to pass
//        try await Task.sleep(nanoseconds: 110_000_000) // 100ms
//        XCTAssertEqual(callCount, 2, "Should have attempted 1 retry + 1 initial call")
//
//        try await Task.sleep(nanoseconds: 210_000_000) // 200ms
//        XCTAssertEqual(callCount, 3, "Should have attempted 2 retries + 1 initial call")
//
//        try await Task.sleep(nanoseconds: 410_000_000) // 400ms
//        XCTAssertEqual(callCount, 4, "Should have attempted 3 retries + 1 initial call")
//
//        try await Task.sleep(nanoseconds: 810_000_000) // 800ms
//        XCTAssertEqual(callCount, 5, "Should have attempted 4 retries + 1 initial call")
//        
//        try await Task.sleep(nanoseconds: 1_610_000_000) // 1600ms
//        XCTAssertEqual(callCount, 6, "Should have attempted 5 retries + 1 initial call")
//        
//        try await Task.sleep(nanoseconds: 3_210_000_000) // 3200ms
//        XCTAssertEqual(callCount, 7, "Should have attempted 6 retries + 1 initial call")
//        
//        try await Task.sleep(nanoseconds: 6_410_000_000) // 6400ms
//        XCTAssertEqual(callCount, 8, "Should have attempted 7 retries + 1 initial call")
//
//        try await Task.sleep(nanoseconds: 12_810_000_000) // 12800ms
//        XCTAssertEqual(callCount, 8, "Should have attempted up to max retries") // Cannot go beyond max
//        XCTAssertEqual(testTimer.executeCount, 7, "Timer should have been scheduled 7 times")
        
        
        try await Task.sleep(nanoseconds: 12_810_000_000) // 12800ms
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
