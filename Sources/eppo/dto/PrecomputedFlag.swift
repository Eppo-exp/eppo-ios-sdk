import Foundation

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

enum VariationType: String, Codable {
    case boolean = "BOOLEAN"
    case numeric = "NUMERIC"
    case integer = "INTEGER"
    case string = "STRING"
    case json = "JSON"
}
