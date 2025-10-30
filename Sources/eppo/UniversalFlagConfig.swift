import Foundation
import FlatBuffers

public struct UniversalFlagConfig: Codable {
    let createdAt: Date
    let format: String
    let environment: Environment
    let flags: [String: UFC_Flag]

    static func decodeFromJSON(from json: Data) throws -> UniversalFlagConfig {
        let decoder = JSONDecoder()

        // Dates could be in base64 encoded format or not
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            guard let date = parseUtcISODateElement(dateStr) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format for: <\(dateStr)>")
            }
            return date
        }

        do {
            return try decoder.decode(UniversalFlagConfig.self, from: json)
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(_, let context):
                throw UniversalFlagConfigError.parsingError("Type mismatch: \(context.debugDescription)")
            case .valueNotFound(_, let context):
                throw UniversalFlagConfigError.parsingError("Value not found: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                throw UniversalFlagConfigError.parsingError("Key not found: \(key.stringValue) - \(context.debugDescription)")
            case .dataCorrupted(let context):
                throw UniversalFlagConfigError.parsingError("Data corrupted: \(context.debugDescription)")
            default:
                throw UniversalFlagConfigError.parsingError("JSON parsing error: \(error.localizedDescription)")
            }
        } catch {
            throw UniversalFlagConfigError.parsingError("Unexpected error: \(error.localizedDescription)")
        }
    }

    static func decodeFromFlatBuffer(from data: Data) throws -> UniversalFlagConfig {
        do {
            let buffer = ByteBuffer(data: data)
            let ufcRoot = Eppo_UFC_UniversalFlagConfig(buffer, o: Int32(buffer.read(def: UOffset.self, position: buffer.reader)) + Int32(buffer.reader))

            // Parse creation date (now UInt64 timestamp instead of string)
            let createdAt: Date
            let createdAtTimestamp = ufcRoot.createdAt
            if createdAtTimestamp > 0 {
                createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtTimestamp) / 1000.0) // Assuming milliseconds
            } else {
                throw UniversalFlagConfigError.parsingError("Missing or invalid creation date in FlatBuffer")
            }

            // Parse environment
            guard let fbEnvironment = ufcRoot.environment else {
                throw UniversalFlagConfigError.parsingError("Missing environment in FlatBuffer")
            }
            guard let environmentName = fbEnvironment.name else {
                throw UniversalFlagConfigError.parsingError("Missing environment name in FlatBuffer")
            }
            let environment = Environment(name: environmentName)

            // Convert format enum to string
            let format: String
            switch ufcRoot.format {
            case .server:
                format = "server"
            case .client:
                format = "client"
            }

            // Parse flags
            var flags: [String: UFC_Flag] = [:]
            let flagsCount = ufcRoot.flagsCount
            for i in 0..<flagsCount {
                guard let flagEntry = ufcRoot.flags(at: i) else { continue }
                guard let flagKey = flagEntry.key else { continue }
                guard let fbFlag = flagEntry.flag else { continue }

                if let ufcFlag = try? convertFlatBufferFlag(fbFlag) {
                    flags[flagKey] = ufcFlag
                }
            }

            return UniversalFlagConfig(
                createdAt: createdAt,
                format: format,
                environment: environment,
                flags: flags
            )
        } catch {
            throw UniversalFlagConfigError.parsingError("FlatBuffer parsing error: \(error.localizedDescription)")
        }
    }

    static func convertFlatBufferFlag(_ fbFlag: Eppo_UFC_Flag) throws -> UFC_Flag {
        // Extract basic properties
        guard let key = fbFlag.key else {
            throw UniversalFlagConfigError.parsingError("Missing flag key in FlatBuffer")
        }

        let enabled = fbFlag.enabled

        // Convert variation type
        let variationType: UFC_VariationType
        switch fbFlag.variationType {
        case .boolean:
            variationType = .boolean
        case .integer:
            variationType = .integer
        case .json:
            variationType = .json
        case .numeric:
            variationType = .numeric
        case .string:
            variationType = .string
        }

        // Convert variations
        var variations: [String: UFC_Variation] = [:]
        let variationsCount = fbFlag.variationsCount
        for i in 0..<variationsCount {
            guard let fbVariation = fbFlag.variations(at: i) else { continue }
            guard let variationKey = fbVariation.key else { continue }
            guard let valueString = fbVariation.value else { continue }

            let variationValue: EppoValue
            switch variationType {
            case .boolean:
                variationValue = EppoValue(value: valueString.lowercased() == "true")
            case .integer:
                if let intVal = Int(valueString) {
                    variationValue = EppoValue(value: intVal)
                } else {
                    variationValue = EppoValue(value: 0)
                }
            case .numeric:
                if let doubleVal = Double(valueString) {
                    variationValue = EppoValue(value: doubleVal)
                } else {
                    variationValue = EppoValue(value: 0.0)
                }
            case .string, .json:
                variationValue = EppoValue(value: valueString)
            }

            variations[variationKey] = UFC_Variation(key: variationKey, value: variationValue)
        }

        // Convert allocations (simplified for now)
        var allocations: [UFC_Allocation] = []
        let allocationsCount = fbFlag.allocationsCount
        for i in 0..<allocationsCount {
            guard let fbAllocation = fbFlag.allocations(at: i) else { continue }
            guard let allocationKey = fbAllocation.key else { continue }

            // Convert splits
            var splits: [UFC_Split] = []
            let splitsCount = fbAllocation.splitsCount
            for j in 0..<splitsCount {
                guard let fbSplit = fbAllocation.splits(at: j) else { continue }
                guard let splitVariationKey = fbSplit.variationKey else { continue }

                // Convert shards
                var shards: [UFC_Shard] = []
                let shardsCount = fbSplit.shardsCount
                for k in 0..<shardsCount {
                    guard let fbShard = fbSplit.shards(at: k) else { continue }
                    guard let salt = fbShard.salt else { continue }

                    // Convert ranges
                    var ranges: [UFC_Range] = []
                    let rangesCount = fbShard.rangesCount
                    for l in 0..<rangesCount {
                        guard let fbRange = fbShard.ranges(at: l) else { continue }
                        ranges.append(UFC_Range(start: Int(fbRange.start), end: Int(fbRange.end)))
                    }

                    shards.append(UFC_Shard(salt: salt, ranges: ranges))
                }

                splits.append(UFC_Split(variationKey: splitVariationKey, shards: shards, extraLogging: nil))
            }

            allocations.append(UFC_Allocation(
                key: allocationKey,
                rules: nil, // TODO: Implement rules conversion if needed
                startAt: nil, // TODO: Implement date conversion if needed
                endAt: nil,
                splits: splits,
                doLog: fbAllocation.doLog
            ))
        }

        return UFC_Flag(
            key: key,
            enabled: enabled,
            variationType: variationType,
            variations: variations,
            allocations: allocations,
            totalShards: Int(fbFlag.totalShards),
            entityId: fbFlag.entityId != 0 ? Int(fbFlag.entityId) : nil
        )
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

public enum UFC_VariationType: String, Codable {
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
