import Foundation

/// Represents a precomputed flag assignment from the server
struct PrecomputedFlag: Codable, Equatable {
    let allocationKey: String?
    let variationKey: String?
    let variationType: VariationType
    let variationValue: EppoValue
    let extraLogging: [String: String]
    let doLog: Bool
    
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