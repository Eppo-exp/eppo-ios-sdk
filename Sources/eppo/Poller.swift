import Foundation

public enum PollerConstants {
    public static let DEFAULT_POLL_INTERVAL_MS = 300_000 // 5 minutes in milliseconds
    public static let DEFAULT_JITTER_INTERVAL_RATIO = 10 // 10% of poll interval
    public static let DEFAULT_MAX_POLL_RETRIES = 7
}

class PollerLogger {
    func info(_ message: String) {
        print("INFO: \(message)")
    }
    
    func warn(_ message: String) {
        print("WARN: \(message)")
    }
    
    func error(_ message: String) {
        print("ERROR: \(message)")
    }
}

// Protocol for timing mechanism
protocol TimerType {
    var executeCount: Int { get }
    func schedule(deadline: TimeInterval, callback: @escaping () async -> Void)
    func cancel()
}

// Real timer implementation
class RealTimer: TimerType {
    var executeCount: Int = 0
    private var timer: Timer?
    
    func schedule(deadline: TimeInterval, callback: @escaping () async -> Void) {
        executeCount += 1
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: deadline, repeats: false) { _ in
            Task { await callback() }
        }
    }
    
    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

// Test timer implementation that respects scheduling
class TestTimer: TimerType {
    private(set) var executeCount: Int = 0
    private var isRunning = true
    private var startTime: TimeInterval
    
    init() {
        self.startTime = Date().timeIntervalSince1970
    }
    
    func schedule(deadline: TimeInterval, callback: @escaping () async -> Void) {
        executeCount += 1
        
        if isRunning {
            Task {
                // Convert deadline to nanoseconds and wait
                let delayNanos = UInt64(deadline * 1_000_000_000) // Convert seconds to nanoseconds
                try? await Task.sleep(nanoseconds: delayNanos)
                
                if self.isRunning {
                    await callback()
                }
            }
        }
    }
    
    func cancel() {
        isRunning = false
    }
}

public class Poller {
    private let intervalMs: Int
    private let jitterMs: Int
    private let callback: () async throws -> Void
    
    private var stopped = true
    private var failedAttempts = 0
    private var nextPollMs: Int
    private var logger: PollerLogger
    private let timer: TimerType
    
    public init(
        intervalMs: Int,
        jitterMs: Int,
        callback: @escaping () async throws -> Void
    ) {
        self.intervalMs = intervalMs
        self.jitterMs = jitterMs
        self.callback = callback
        self.nextPollMs = intervalMs
        self.logger = PollerLogger()
        self.timer = RealTimer()
    }
    
    // Internal initializer for testing
    init(
        intervalMs: Int,
        jitterMs: Int,
        callback: @escaping () async throws -> Void,
        logger: PollerLogger,
        timer: TimerType
    ) {
        self.intervalMs = intervalMs
        self.jitterMs = jitterMs
        self.callback = callback
        self.nextPollMs = intervalMs
        self.logger = logger
        self.timer = timer
    }
    
    public func start() async throws {
        stopped = false
        
        do {
            try await callback()
            logger.info("Eppo SDK successfully requested initial configuration")
        } catch {
            // Still schedule the first poll even if initial call fails
        }
        
        schedulePoll()
    }
    
    public func stop() {
        if !stopped {
            stopped = true
            timer.cancel()
            logger.info("Eppo SDK polling stopped")
        }
    }
    
    private func schedulePoll() {
        let nextInterval = nextPollMs + randomJitterMs()
        timer.schedule(deadline: TimeInterval(nextInterval) / 1000.0) { [self] in
            Task {
                await poll()
            }
        }
    }
    
    private func poll() async {
        if stopped {
            return
        }
        
        do {
            try await callback()
            failedAttempts = 0
            nextPollMs = intervalMs
        } catch {
            failedAttempts += 1
            if failedAttempts < PollerConstants.DEFAULT_MAX_POLL_RETRIES {
                let failureWaitMultiplier = pow(2.0, Double(failedAttempts))
                nextPollMs = Int(failureWaitMultiplier) * intervalMs
            } else {
                stop()
                return
            }
        }
        
        schedulePoll()
    }
    
    private func randomJitterMs() -> Int {
        guard jitterMs > 0 else { return 0 }
        return Int.random(in: 0...jitterMs)
    }
}
