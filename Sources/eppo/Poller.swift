import Foundation

public class Poller {
    private static let POLL_JITTER_PCT: Double = 0.1
    private static let DEFAULT_INITIAL_CONFIG_REQUEST_RETRIES = 1
    private static let DEFAULT_POLL_CONFIG_REQUEST_RETRIES = 7
    
    private let intervalMs: Int
    private let callback: () async throws -> Void
    private let options: PollerOptions
    
    private var stopped = true
    private var failedAttempts = 0
    private var nextPollMs: Int
    private var previousPollFailed = false
    private var pollTimer: Timer?
    private var logger: Logger
    
    public struct PollerOptions {
        let maxPollRetries: Int
        let maxStartRetries: Int
        let pollAfterSuccessfulStart: Bool
        let errorOnFailedStart: Bool
        let pollAfterFailedStart: Bool
        let skipInitialPoll: Bool
        
        public init(
            maxPollRetries: Int = DEFAULT_POLL_CONFIG_REQUEST_RETRIES,
            maxStartRetries: Int = DEFAULT_INITIAL_CONFIG_REQUEST_RETRIES,
            pollAfterSuccessfulStart: Bool = true,
            errorOnFailedStart: Bool = false,
            pollAfterFailedStart: Bool = false,
            skipInitialPoll: Bool = false
        ) {
            self.maxPollRetries = maxPollRetries
            self.maxStartRetries = maxStartRetries
            self.pollAfterSuccessfulStart = pollAfterSuccessfulStart
            self.errorOnFailedStart = errorOnFailedStart
            self.pollAfterFailedStart = pollAfterFailedStart
            self.skipInitialPoll = skipInitialPoll
        }
    }
    
    public init(
        intervalMs: Int,
        callback: @escaping () async throws -> Void,
        options: PollerOptions = PollerOptions(),
        logger: Logger = Logger()
    ) {
        self.intervalMs = intervalMs
        self.callback = callback
        self.options = options
        self.nextPollMs = intervalMs
        self.logger = logger
    }
    
    public func start() async throws {
        stopped = false
        var startRequestSuccess = false
        var startAttemptsRemaining = options.skipInitialPoll ? 0 : 1 + options.maxStartRetries
        
        var startErrorToThrow: Error?
        
        while !startRequestSuccess && startAttemptsRemaining > 0 {
            do {
                try await callback()
                startRequestSuccess = true
                previousPollFailed = false
                logger.info("Eppo SDK successfully requested initial configuration")
            } catch {
                previousPollFailed = true
                logger.warn("Eppo SDK encountered an error with initial poll of configurations: \(error.localizedDescription)")
                
                if startAttemptsRemaining > 1 {
                    let jitterMs = randomJitterMs(intervalMs)
                    startAttemptsRemaining -= 1
                    logger.warn("Eppo SDK will retry the initial poll again in \(jitterMs) ms (\(startAttemptsRemaining) attempts remaining)")
                    try await Task.sleep(nanoseconds: UInt64(jitterMs) * 1_000_000)
                } else {
                    if options.pollAfterFailedStart {
                        logger.warn("Eppo SDK initial poll failed; will attempt regular polling")
                    } else {
                        logger.error("Eppo SDK initial poll failed. Aborting polling")
                        stop()
                    }
                    
                    if options.errorOnFailedStart {
                        startErrorToThrow = error
                    }
                    break
                }
            }
        }
        
        let startRegularPolling = !stopped && (
            (startRequestSuccess && options.pollAfterSuccessfulStart) ||
            (!startRequestSuccess && options.pollAfterFailedStart)
        )
        
        if startRegularPolling {
            logger.info("Eppo SDK starting regularly polling every \(intervalMs) ms")
            schedulePoll()
        } else {
            logger.info("Eppo SDK will not poll for configuration updates")
        }
        
        if let error = startErrorToThrow {
            logger.info("Eppo SDK rethrowing start error")
            throw error
        }
    }
    
    public func stop() {
        if !stopped {
            stopped = true
            pollTimer?.invalidate()
            pollTimer = nil
            logger.info("Eppo SDK polling stopped")
        }
    }
    
    private func schedulePoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(nextPollMs) / 1000.0, repeats: false) { [weak self] _ in
            Task {
                await self?.poll()
            }
        }
    }
    
    private func poll() async {
        if stopped {
            return
        }
        
        do {
            try await callback()
            // If no error, reset any retrying
            failedAttempts = 0
            nextPollMs = intervalMs
            if previousPollFailed {
                previousPollFailed = false
                logger.info("Eppo SDK poll successful; resuming normal polling")
            }
        } catch {
            previousPollFailed = true
            logger.warn("Eppo SDK encountered an error polling configurations: \(error.localizedDescription)")
            
            let maxTries = 1 + options.maxPollRetries
            failedAttempts += 1
            
            if failedAttempts < maxTries {
                let failureWaitMultiplier = pow(2.0, Double(failedAttempts))
                let jitterMs = randomJitterMs(intervalMs)
                nextPollMs = Int(failureWaitMultiplier) * intervalMs + jitterMs
                logger.warn("Eppo SDK will try polling again in \(nextPollMs) ms (\(maxTries - failedAttempts) attempts remaining)")
            } else {
                logger.error("Eppo SDK reached maximum of \(failedAttempts) failed polling attempts. Stopping polling")
                stop()
                return
            }
        }
        
        schedulePoll()
    }
    
    private func randomJitterMs(_ intervalMs: Int) -> Int {
        let halfPossibleJitter = Double(intervalMs) * Self.POLL_JITTER_PCT / 2.0
        // We want the randomly chosen jitter to be at least 1ms
        let randomOtherHalfJitter = max(
            floor(Double.random(in: 0...1) * Double(intervalMs) * Self.POLL_JITTER_PCT / 2.0),
            1.0
        )
        return Int(halfPossibleJitter + randomOtherHalfJitter)
    }
}

// Simple Logger class - you might want to replace this with your preferred logging system
class Logger {
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
