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
        XCTAssertEqual(
            testTimer.executeCount,
            1,
            "Timer should have been scheduled once"
        )

        // Stop the poller
        poller.stop()

        // Give it some time to execute multiple polls
        try await Task.sleep(nanoseconds: 500_000_000)  // 100ms

        // Counts should remain the same after stopping
        XCTAssertEqual(
            callCount,
            1,
            "Call count should not change after stopping"
        )
        XCTAssertEqual(
            testTimer.executeCount,
            1,
            "Timer executions should not change after stopping"
        )
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
        try await Task.sleep(nanoseconds: 500_000_000)  // 100ms

        // Stop the poller
        poller.stop()

        XCTAssertGreaterThan(callCount, 1, "Should have called multiple times")
        XCTAssertGreaterThan(
            testTimer.executeCount,
            1,
            "Timer should have been scheduled multiple times"
        )
    }

    @MainActor
    func testExponentialBackoffOnErrors() async throws {
        var callCount = 0
        let mockCallback: () async throws -> Void = {
            callCount += 1
            throw NSError(
                domain: "Test",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "bad request"]
            )
        }

        let mockTimer = MockTimer()
        let poller = await Poller(
            intervalMs: 100,
            jitterMs: 0,
            callback: mockCallback,
            logger: PollerLogger(),
            timer: mockTimer
        )

        // Start the poller - this will make the initial call and schedule the first retry
        try? await poller.start()
        XCTAssertEqual(callCount, 1, "Should have made initial call")
        XCTAssertEqual(
            mockTimer.executeCount,
            1,
            "Timer should have been scheduled once"
        )

        // Execute retries one by one and verify exponential backoff behavior
        for attempt in 1...7 {
            XCTAssertTrue(
                mockTimer.hasPendingCallbacks,
                "Should have a pending callback for attempt \(attempt)"
            )

            // Execute the next scheduled retry
            await mockTimer.executeNext()

            let expectedCallCount = attempt + 1  // +1 for initial call
            XCTAssertEqual(
                callCount,
                expectedCallCount,
                "Should have attempted \(attempt) retries + 1 initial call"
            )

            if attempt < 7 {
                // Should schedule another retry unless we've reached max retries
                let expectedExecuteCount = attempt + 1
                XCTAssertEqual(
                    mockTimer.executeCount,
                    expectedExecuteCount,
                    "Timer should have been scheduled \(expectedExecuteCount) times"
                )
            }
        }

        // After max retries (7), polling should stop - no more callbacks should be scheduled
        XCTAssertFalse(
            mockTimer.hasPendingCallbacks,
            "Should not have any more pending callbacks after max retries"
        )
        XCTAssertEqual(
            callCount,
            8,
            "Should have made 1 initial call + 7 retry attempts"
        )
        XCTAssertEqual(
            mockTimer.executeCount,
            7,
            "Timer should have been scheduled exactly 7 times (max retries)"
        )
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
        try await Task.sleep(nanoseconds: 300_000_000)  // 300ms

        poller.stop()

        // Verify that multiple executions occurred
        XCTAssertTrue(
            testTimer.executeCount > 1,
            "Should have executed multiple times"
        )

        // Verify jitter
        for interval in intervals {
            // Convert to milliseconds for comparison
            let intervalInMs = interval * 1000

            // Should be between intervalMs and intervalMs + jitterMs
            XCTAssertGreaterThanOrEqual(
                intervalInMs,
                Double(intervalMs),
                "Interval should not be less than base interval"
            )
            XCTAssertLessThanOrEqual(
                intervalInMs,
                Double(intervalMs + jitterMs),
                "Interval should not exceed base interval plus max jitter"
            )
        }

        // Verify that not all intervals are the same (jitter is actually being applied)
        if intervals.count > 1 {
            let allSame = intervals.dropFirst().allSatisfy {
                $0 == intervals[0]
            }
            XCTAssertFalse(allSame, "Intervals should vary due to jitter")
        }
    }
}
