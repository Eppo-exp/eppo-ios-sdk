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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allocationKey = try container.decodeIfPresent(String.self, forKey: .allocationKey)
        variationKey = try container.decodeIfPresent(String.self, forKey: .variationKey)
        variationType = try container.decode(VariationType.self, forKey: .variationType)
        variationValue = try container.decode(EppoValue.self, forKey: .variationValue)
        extraLogging = try container.decodeIfPresent([String: String].self, forKey: .extraLogging) ?? [:]
        doLog = try container.decode(Bool.self, forKey: .doLog)
    }

    private enum CodingKeys: String, CodingKey {
        case allocationKey
        case variationKey
        case variationType
        case variationValue
        case extraLogging
        case doLog
    }
}

enum VariationType: String, Codable {
    case boolean = "BOOLEAN"
    case numeric = "NUMERIC"
    case integer = "INTEGER"
    case string = "STRING"
    case json = "JSON"
}
