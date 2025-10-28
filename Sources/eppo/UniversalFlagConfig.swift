import Foundation

public struct UniversalFlagConfig: Codable {
    let createdAt: Date
    let format: String
    let environment: Environment
    let flags: [String: UFC_Flag]

    static func decodeFromJSON(from json: Data) throws -> UniversalFlagConfig {
        return try JSONParsingFactory.currentProvider.decodeUniversalFlagConfig(from: json)
    }
}

public struct Environment: Codable {
    let name: String
}

// enums
enum UniversalFlagConfigError: Error, CustomNSError, LocalizedError {
    case notUTF8Encoded(String)
    case parsingError(String)

    static var errorDomain: String { return "UniversalFlagConfigError" }

    var errorCode: Int {
        switch self {
        case .notUTF8Encoded:
            return 100
        case .parsingError:
            return 101
        }
    }

    var errorDescription: String? {
        switch self {
        case .notUTF8Encoded(let message):
            return message
        case .parsingError(let message):
            return message
        }
    }
}

enum UFC_VariationType: String, Codable {
    case boolean = "BOOLEAN"
    case integer = "INTEGER"
    case json = "JSON"
    case numeric = "NUMERIC"
    case string = "STRING"
}

enum UFC_RuleConditionOperator: String, Codable, CaseIterable {
    case lessThan = "LT"
    case lessThanEqual = "LTE"
    case greaterThan = "GT"
    case greaterThanEqual = "GTE"
    case matches = "MATCHES"
    case notMatches = "NOT_MATCHES"
    case oneOf = "ONE_OF"
    case notOneOf = "NOT_ONE_OF"
    case isNull = "IS_NULL"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        for type in UFC_RuleConditionOperator.allCases {
            if type.rawValue == rawValue || getMD5Hex(type.rawValue) == rawValue {
                self = type
                return
            }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot initialize UFC_RuleConditionOperator from invalid raw value \(rawValue)"
        )
    }
}

// models

public struct UFC_Flag: Codable {
    let key: String
    let enabled: Bool
    let variationType: UFC_VariationType
    let variations: [String: UFC_Variation]
    let allocations: [UFC_Allocation]
    let totalShards: Int
    let entityId: Int?
}

public struct UFC_Variation: Codable {
    let key: String
    let value: EppoValue
}

public struct UFC_Allocation: Codable {
    let key: String
    let rules: [UFC_Rule]?
    let startAt: Date?
    let endAt: Date?
    let splits: [UFC_Split]
    let doLog: Bool
}

public struct UFC_Rule: Codable {
    let conditions: [UFC_TargetingRuleCondition]
}

public struct UFC_TargetingRuleCondition: Codable {
    let `operator`: UFC_RuleConditionOperator
    let attribute: String
    let value: EppoValue
}

public struct UFC_Split: Codable {
    let variationKey: String
    let shards: [UFC_Shard]
    let extraLogging: [String: String]?
}

public struct UFC_Shard: Codable {
    let salt: String
    let ranges: [UFC_Range]
}

public struct UFC_Range: Codable {
    let start: Int
    let end: Int
}
