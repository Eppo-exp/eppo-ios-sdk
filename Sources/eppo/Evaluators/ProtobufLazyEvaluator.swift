import Foundation
import SwiftProtobuf

public class ProtobufLazyEvaluator {
    private let protobufData: Data
    private let flagEvaluator: FlagEvaluator

    // Truly lazy: No upfront caching, everything on-demand
    private var flagCache: [String: UFC_Flag] = [:]
    private var flagTypeCache: [String: UFC_VariationType] = [:]
    private let cacheLock = NSLock()

    // Parsed protobuf config for efficient access
    private let universalFlagConfig: Eppo_Ufc_UniversalFlagConfig

    init(protobufData: Data) throws {
        self.protobufData = protobufData
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())

        // ONLY parse protobuf structure - don't iterate through flags!
        self.universalFlagConfig = try Eppo_Ufc_UniversalFlagConfig(serializedBytes: protobufData)

        // That's it! No upfront scanning, no type cache building
        // Everything is done on-demand when flags are accessed
    }

    func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType? = nil
    ) -> FlagEvaluation {
        // Get or load the flag from cache using lazy hydration
        guard let ufcFlag = getOrLoadFlag(flagKey: flagKey) else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found"
            )
        }

        // Use the existing flag evaluation logic with the hydrated UFC_Flag
        let result = flagEvaluator.evaluateFlag(
            flag: ufcFlag,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )

        // Type validation: Check if variation value matches expected type
        if let expectedType = expectedVariationType,
           let variation = result.variation,
           result.flagEvaluationCode == .match {

            // Validate type compatibility
            let isTypeCompatible = validateTypeCompatibility(
                variation: variation,
                expectedType: expectedType,
                flagType: ufcFlag.variationType
            )

            if !isTypeCompatible {
                // Return assignment error with correct constructor parameters
                return FlagEvaluation(
                    flagKey: flagKey,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    allocationKey: result.allocationKey,
                    variation: variation, // Keep variation info for debugging
                    variationType: ufcFlag.variationType,
                    extraLogging: result.extraLogging,
                    doLog: result.doLog,
                    matchedRule: result.matchedRule,
                    matchedAllocation: result.matchedAllocation,
                    unmatchedAllocations: result.unmatchedAllocations,
                    unevaluatedAllocations: result.unevaluatedAllocations,
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription: "Variation (\(variation.key)) is configured for type \(ufcFlag.variationType.rawValue.uppercased()), but is set to incompatible value (\(variation.value))",
                    entityId: result.entityId
                )
            }
        }

        return result
    }

    // Get all flag keys - this is the ONLY time we scan all flags
    func getAllFlagKeys() -> [String] {
        return universalFlagConfig.flags.map { $0.key }
    }

    // Get flag variation type - truly on-demand
    func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        // Check type cache first
        if let cachedType = flagTypeCache[flagKey] {
            return cachedType
        }

        // Find and cache the type on-demand
        guard let protobufFlag = universalFlagConfig.flags.first(where: { $0.key == flagKey }) else {
            return nil
        }

        let variationType = Self.convertProtobufVariationType(protobufFlag.variationType)

        cacheLock.lock()
        flagTypeCache[flagKey] = variationType
        cacheLock.unlock()

        return variationType
    }

    // MARK: - Private Methods

    private func validateTypeCompatibility(variation: UFC_Variation, expectedType: UFC_VariationType, flagType: UFC_VariationType) -> Bool {
        // First check: Expected type must match the flag's declared type
        guard expectedType == flagType else {
            return false
        }

        // Second check: Variation value must be compatible with the type
        switch expectedType {
        case .integer:
            // For integer type, check if the value is actually an integer (no decimal part)
            do {
                let doubleValue = try variation.value.getDoubleValue()
                return doubleValue.truncatingRemainder(dividingBy: 1) == 0
            } catch {
                return false
            }
        case .boolean:
            do {
                _ = try variation.value.getBoolValue()
                return true
            } catch {
                return false
            }
        case .numeric:
            do {
                _ = try variation.value.getDoubleValue()
                return true
            } catch {
                return false
            }
        case .string, .json:
            do {
                _ = try variation.value.getStringValue()
                return true
            } catch {
                return false
            }
        }
    }

    // TRULY LAZY: No queue overhead, minimal locking
    private func getOrLoadFlag(flagKey: String) -> UFC_Flag? {
        // Fast path: Try to read from cache without locking
        if let cachedFlag = flagCache[flagKey] {
            return cachedFlag
        }

        // Slow path: Load flag on-demand with minimal locking
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Double-check: flag might have been loaded by another thread
        if let cachedFlag = flagCache[flagKey] {
            return cachedFlag
        }

        // Find and convert flag on-demand
        guard let protobufFlag = universalFlagConfig.flags.first(where: { $0.key == flagKey }) else {
            return nil
        }

        guard let ufcFlag = convertProtobufFlag(protobufFlag) else {
            return nil
        }

        // Cache both the flag and its type
        flagCache[flagKey] = ufcFlag
        flagTypeCache[flagKey] = ufcFlag.variationType

        return ufcFlag
    }

    private func convertProtobufFlag(_ protobufFlag: Eppo_Ufc_Flag) -> UFC_Flag? {
        // Convert basic properties
        let flagKey = protobufFlag.key
        let enabled = protobufFlag.enabled
        let variationType = Self.convertProtobufVariationType(protobufFlag.variationType)

        // Convert variations
        var variations: [String: UFC_Variation] = [:]
        for protobufVariation in protobufFlag.variations {
            let variationKey = protobufVariation.key
            let eppoValue = convertProtobufValue(protobufVariation.value, variationType: variationType)


            variations[variationKey] = UFC_Variation(key: variationKey, value: eppoValue)
        }


        // Convert allocations
        var allocations: [UFC_Allocation] = []
        for protobufAllocation in protobufFlag.allocations {
            let allocationKey = protobufAllocation.key


            // Convert rules
            var rules: [UFC_Rule]? = nil
            if !protobufAllocation.rules.isEmpty {
                var rulesList: [UFC_Rule] = []
                for protobufRule in protobufAllocation.rules {
                    if let ufcRule = convertProtobufRule(protobufRule) {
                        rulesList.append(ufcRule)
                    }
                }
                rules = rulesList.isEmpty ? nil : rulesList
            }

            // Convert splits
            var splits: [UFC_Split] = []
            for protobufSplit in protobufAllocation.splits {
                let splitVariationKey = protobufSplit.variationKey


                // Convert shards
                var shards: [UFC_Shard] = []
                for protobufShard in protobufSplit.shards {
                    let salt = protobufShard.salt

                    // Convert ranges
                    var ranges: [UFC_Range] = []
                    for protobufRange in protobufShard.ranges {
                        ranges.append(UFC_Range(start: Int(protobufRange.start), end: Int(protobufRange.end)))
                    }


                    shards.append(UFC_Shard(salt: salt, ranges: ranges))
                }

                // Convert extra logging
                var extraLogging: [String: String]? = nil
                if !protobufSplit.extraLogging.isEmpty {
                    extraLogging = protobufSplit.extraLogging
                }

                splits.append(UFC_Split(variationKey: splitVariationKey, shards: shards, extraLogging: extraLogging))
            }

            // Convert dates (protobuf timestamps are in milliseconds)
            let startAt = protobufAllocation.startAt > 0 ? Date(timeIntervalSince1970: TimeInterval(protobufAllocation.startAt) / 1000.0) : nil
            let endAt = protobufAllocation.endAt > 0 ? Date(timeIntervalSince1970: TimeInterval(protobufAllocation.endAt) / 1000.0) : nil
            let doLog = protobufAllocation.doLog

            allocations.append(UFC_Allocation(
                key: allocationKey,
                rules: rules,
                startAt: startAt,
                endAt: endAt,
                splits: splits,
                doLog: doLog
            ))
        }

        let totalShards = Int(protobufFlag.totalShards)
        let entityId = protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil

        return UFC_Flag(
            key: flagKey,
            enabled: enabled,
            variationType: variationType,
            variations: variations,
            allocations: allocations,
            totalShards: totalShards,
            entityId: entityId
        )
    }

    private func convertProtobufRule(_ protobufRule: Eppo_Ufc_Rule) -> UFC_Rule? {
        var conditions: [UFC_TargetingRuleCondition] = []

        for protobufCondition in protobufRule.conditions {
            let attribute = protobufCondition.attribute
            let operatorEnum = convertProtobufOperatorType(protobufCondition.operator)


            // Convert value to EppoValue based on operator type
            let conditionValue: EppoValue
            switch operatorEnum {
            case .oneOf, .notOneOf:
                // For array values
                conditionValue = convertProtobufValue(protobufCondition.value, isArray: true)
            case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
                // For comparison operators, preserve string or numeric values
                conditionValue = convertProtobufValue(protobufCondition.value, isArray: false)
            case .isNull:
                // For null checks, expect boolean value
                conditionValue = convertProtobufValue(protobufCondition.value, isArray: false)
            case .matches, .notMatches:
                // For regex, expect string value
                conditionValue = convertProtobufValue(protobufCondition.value, isArray: false)
            }

            conditions.append(UFC_TargetingRuleCondition(
                operator: operatorEnum,
                attribute: attribute,
                value: conditionValue
            ))
        }

        return conditions.isEmpty ? nil : UFC_Rule(conditions: conditions)
    }

    private static func convertProtobufVariationType(_ protobufType: Eppo_Ufc_VariationType) -> UFC_VariationType {
        switch protobufType {
        case .boolean: return .boolean
        case .integer: return .integer
        case .json: return .json
        case .numeric: return .numeric
        case .string: return .string
        case .UNRECOGNIZED(_): return .string // Default fallback
        }
    }

    private func convertProtobufOperatorType(_ protobufOperator: Eppo_Ufc_OperatorType) -> UFC_RuleConditionOperator {
        switch protobufOperator {
        case .matches: return .matches
        case .notMatches: return .notMatches
        case .gte: return .greaterThanEqual
        case .gt: return .greaterThan
        case .lte: return .lessThanEqual
        case .lt: return .lessThan
        case .oneOf: return .oneOf
        case .notOneOf: return .notOneOf
        case .isNull: return .isNull
        case .UNRECOGNIZED(_): return .matches // Default fallback
        }
    }

    private func convertProtobufValue(_ protobufValue: String, variationType: UFC_VariationType? = nil, isArray: Bool = false) -> EppoValue {
        if isArray {
            // Parse as JSON array for oneOf/notOneOf operators
            if let data = protobufValue.data(using: .utf8),
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return EppoValue(array: jsonArray)
            }
            return EppoValue(array: [])
        }

        // First, try to decode as JSON string if it starts and ends with quotes
        var cleanValue = protobufValue
        if protobufValue.hasPrefix("\"") && protobufValue.hasSuffix("\"") {
            // Try to parse as JSON string first (handles escaping properly)
            if let data = protobufValue.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? String {
                cleanValue = decoded
            } else {
                // Fallback: just remove quotes and basic unescape
                cleanValue = String(protobufValue.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
        }

        // Parse based on variation type or infer from string content
        if let variationType = variationType {
            switch variationType {
            case .boolean:
                return EppoValue(value: cleanValue.lowercased() == "true")
            case .integer:
                if let intValue = Int(cleanValue) {
                    return EppoValue(value: intValue)
                } else if let doubleValue = Double(cleanValue) {
                    // Preserve the actual numeric value so type validation can detect incompatibility
                    return EppoValue(value: doubleValue)
                }
                return EppoValue(value: 0)
            case .numeric:
                if let doubleValue = Double(cleanValue) {
                    return EppoValue(value: doubleValue)
                }
                return EppoValue(value: 0.0)
            case .string, .json:
                return EppoValue(value: cleanValue)
            }
        }

        // Auto-detect type from string content
        if cleanValue.lowercased() == "true" || cleanValue.lowercased() == "false" {
            return EppoValue(value: cleanValue.lowercased() == "true")
        } else if let intValue = Int(cleanValue) {
            return EppoValue(value: intValue)
        } else if let doubleValue = Double(cleanValue) {
            return EppoValue(value: doubleValue)
        } else {
            return EppoValue(value: cleanValue)
        }
    }
}