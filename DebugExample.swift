import Foundation

// Example usage of the new debug callback feature with timing context

// Simple print example with timing in milliseconds
let simplePrintCallback: (String, Double, Double) -> Void = { message, elapsedTimeMs, stepDurationMs in
    print("[\(String(format: "%.1f", elapsedTimeMs))ms] \(message) (step: \(String(format: "%.1f", stepDurationMs))ms)")
}

// DataDog example with custom attributes (pseudocode)
let dataDogCallback: (String, Double, Double) -> Void = { message, elapsedTimeMs, stepDurationMs in
    // Assuming DataDog SDK is available
    // RUMMonitor.shared().addAction(
    //     type: .custom,
    //     name: "eppo_initialization_step",
    //     attributes: [
    //         "message": message,
    //         "step_duration_ms": stepDurationMs,
    //         "elapsed_time_ms": elapsedTimeMs
    //     ]
    // )
}

// Usage examples:

// With simple print debugging
func initializeWithSimplePrint() async throws {
    let eppoClient = try await EppoClient.initialize(
        sdkKey: "your-sdk-key",
        debugCallback: simplePrintCallback
    )
}

// With DataDog integration
func initializeWithDataDog() async throws {
    let eppoClient = try await EppoClient.initialize(
        sdkKey: "your-sdk-key", 
        debugCallback: dataDogCallback
    )
}

// Without debugging (production)
func initializeProduction() async throws {
    let eppoClient = try await EppoClient.initialize(
        sdkKey: "your-sdk-key"
        // No debugCallback parameter = no debugging overhead
    )
}

// Custom timing analysis example - much cleaner with automatic timing!
func initializeWithCustomTiming() async throws {
    let customCallback: (String, Double, Double) -> Void = { message, elapsedTimeMs, stepDurationMs in
        if stepDurationMs == 0.0 {
            print("🚀 Init started: \(message)")
        } else {
            print("⏱️  [\(String(format: "%.1f", elapsedTimeMs))ms total] Step took \(String(format: "%.1f", stepDurationMs))ms: \(message)")
        }
        
        if message.contains("Total SDK initialization completed") {
            print("🎉 Initialization complete in \(String(format: "%.1f", elapsedTimeMs))ms!")
        }
    }
    
    let eppoClient = try await EppoClient.initialize(
        sdkKey: "your-sdk-key",
        debugCallback: customCallback
    )
}