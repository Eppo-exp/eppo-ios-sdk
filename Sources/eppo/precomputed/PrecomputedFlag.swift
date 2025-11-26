import Foundation

/// Represents a precomputed flag assignment from the server
struct PrecomputedFlag: Codable, Equatable {
    /// The allocation key for this assignment (nil if not allocated)
    let allocationKey: String?
    
    /// The variation key for this assignment (nil if not allocated)
    let variationKey: String?
    
    /// The type of the variation value
    let variationType: VariationType
    
    /// The actual variation value
    let variationValue: EppoValue
    
    /// Additional logging data (obfuscated if configuration is obfuscated)
    let extraLogging: [String: String]
    
    /// Whether this assignment should be logged
    let doLog: Bool
    
    // MARK: - Initialization
    
    init(
        allocationKey: String?,
        variationKey: String?,
        variationType: VariationType,
        variationValue: EppoValue,
        extraLogging: [String: String] = [:],
        doLog: Bool = false
    ) {
        self.allocationKey = allocationKey
        self.variationKey = variationKey
        self.variationType = variationType
        self.variationValue = variationValue
        self.extraLogging = extraLogging
        self.doLog = doLog
    }
}

/// Represents the type of a variation value
enum VariationType: String, Codable {
    case BOOLEAN = "BOOLEAN"
    case NUMERIC = "NUMERIC"
    case INTEGER = "INTEGER"
    case STRING = "STRING"
    case JSON = "JSON"
}