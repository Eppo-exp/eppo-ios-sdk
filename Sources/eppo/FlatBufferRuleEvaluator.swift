import Foundation
import FlatBuffers

public struct FlatBufferRuleEvaluator {
    private let ufcRoot: Eppo_UFC_UniversalFlagConfig
    private let flagTypeCache: [String: UFC_VariationType]

    init(flatBufferData: Data) throws {
        let buffer = ByteBuffer(data: flatBufferData)
        self.ufcRoot = Eppo_UFC_UniversalFlagConfig(buffer, o: Int32(buffer.read(def: UOffset.self, position: buffer.reader)) + Int32(buffer.reader))

        // Pre-cache flag variation types for fast lookup during evaluation
        var typeCache: [String: UFC_VariationType] = [:]
        let flagsCount = ufcRoot.flagsCount
        for i in 0..<flagsCount {
            if let flagEntry = ufcRoot.flags(at: i),
               let flag = flagEntry.flag,
               let key = flag.key {
                switch flag.variationType {
                case .boolean:
                    typeCache[key] = .boolean
                case .integer:
                    typeCache[key] = .integer
                case .numeric:
                    typeCache[key] = .numeric
                case .string:
                    typeCache[key] = .string
                case .json:
                    typeCache[key] = .json
                }
            }
        }
        self.flagTypeCache = typeCache
    }

    func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation {

        // Find the flag directly in FlatBuffer
        guard let fbFlag = findFlag(flagKey: flagKey) else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found"
            )
        }

        if !fbFlag.enabled {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag is disabled"
            )
        }

        // Convert FlatBuffer variation type
        let variationType: UFC_VariationType
        switch fbFlag.variationType {
        case .boolean:
            variationType = .boolean
        case .integer:
            variationType = .integer
        case .numeric:
            variationType = .numeric
        case .string:
            variationType = .string
        case .json:
            variationType = .json
        }

        // Check if flag has allocations
        let allocationsCount = fbFlag.allocationsCount
        if allocationsCount == 0 {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Unrecognized or disabled flag: \(flagKey)"
            )
        }

        // Evaluate allocations in order
        for i in 0..<allocationsCount {
            guard let allocation = fbFlag.allocations(at: i) else { continue }


            // Check start time (if specified)
            if let startAt = parseTimestamp(allocation.startAt) {
                if Date() < startAt {
                    continue // Skip this allocation - too early
                }
            }

            // Check end time (if specified)
            if let endAt = parseTimestamp(allocation.endAt) {
                if Date() > endAt {
                    continue // Skip this allocation - too late
                }
            }

            // Check rules (if any)
            let rulesCount = allocation.rulesCount
            if rulesCount > 0 {
                var rulesMatch = false
                for j in 0..<rulesCount {
                    if let rule = allocation.rules(at: j) {
                        if matchesRule(rule: rule, subjectAttributes: subjectAttributes, subjectKey: subjectKey, isConfigObfuscated: isConfigObfuscated) {
                            rulesMatch = true
                            break
                        }
                    }
                }
                if !rulesMatch {
                    continue // Skip this allocation - rules don't match
                }
            }

            // Check traffic sharding
            let splitsCount = allocation.splitsCount
            for k in 0..<splitsCount {
                guard let split = allocation.splits(at: k) else { continue }

                if matchesSharding(split: split, subjectKey: subjectKey, totalShards: fbFlag.totalShards, isConfigObfuscated: isConfigObfuscated) {
                    // Found matching split - get variation
                    if let variationKey = split.variationKey {
                        if let variation = findVariation(in: fbFlag, variationKey: variationKey) {
                            return FlagEvaluation.matchedResult(
                                flagKey: flagKey,
                                subjectKey: subjectKey,
                                subjectAttributes: subjectAttributes,
                                allocationKey: allocation.key,
                                variation: variation,
                                variationType: variationType,
                                extraLogging: [:],
                                doLog: allocation.doLog,
                                isConfigObfuscated: isConfigObfuscated
                            )
                        }
                    }
                }
            }
        }

        // No allocations matched
        return FlagEvaluation.noneResult(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            flagEvaluationCode: .flagUnrecognizedOrDisabled,
            flagEvaluationDescription: "No allocations matched"
        )
    }

    private func findFlag(flagKey: String) -> Eppo_UFC_Flag? {
        // O(log n) binary search using FlatBuffer's native indexed lookup
        guard let flagEntry = ufcRoot.flagsBy(key: flagKey) else {
            return nil
        }
        return flagEntry.flag
    }

    private func findVariation(in flag: Eppo_UFC_Flag, variationKey: String) -> UFC_Variation? {
        // O(log n) binary search using FlatBuffer's native indexed lookup
        guard let fbVariation = flag.variationsBy(key: variationKey) else {
            return nil
        }

        // Convert FlatBuffer variation to EppoValue based on flag's variation type
        guard let valueString = fbVariation.value else { return nil }

        let eppoValue: EppoValue
        switch flag.variationType {
        case .boolean:
            // Handle JSON-encoded boolean values
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let boolValue = cleanValue.lowercased() == "true"
            eppoValue = EppoValue(value: boolValue)
        case .integer:
            // Handle JSON-encoded integer values
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let intValue = Int(cleanValue) ?? 0
            eppoValue = EppoValue(value: intValue)
        case .numeric:
            // Handle JSON-encoded numeric values
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let doubleValue = Double(cleanValue) ?? 0.0
            eppoValue = EppoValue(value: doubleValue)
        case .string:
            // Handle JSON-encoded string values - remove surrounding quotes
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            eppoValue = EppoValue(value: cleanValue)
        case .json:
            // JSON values should remain as-is (the string contains the JSON structure)
            eppoValue = EppoValue(value: valueString)
        }

        return UFC_Variation(key: variationKey, value: eppoValue)
    }

    // Get all flag keys for benchmark
    func getAllFlagKeys() -> [String] {
        return Array(flagTypeCache.keys)
    }

    // Get flag variation type for benchmark
    func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return flagTypeCache[flagKey]
    }

    // MARK: - Helper Methods

    private func parseTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp = timestamp, !timestamp.isEmpty else { return nil }
        // Parse ISO 8601 date string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timestamp)
        }()
    }

    private func matchesRule(rule: Eppo_UFC_Rule, subjectAttributes: SubjectAttributes, subjectKey: String, isConfigObfuscated: Bool) -> Bool {
        let conditionsCount = rule.conditionsCount
        guard conditionsCount > 0 else { return true }

        // All conditions must match for rule to match
        for i in 0..<conditionsCount {
            guard let condition = rule.conditions(at: i) else { continue }
            if !matchesCondition(condition: condition, subjectAttributes: subjectAttributes, subjectKey: subjectKey, isConfigObfuscated: isConfigObfuscated) {
                return false
            }
        }
        return true
    }

    private func matchesCondition(condition: Eppo_UFC_TargetingRuleCondition, subjectAttributes: SubjectAttributes, subjectKey: String, isConfigObfuscated: Bool) -> Bool {
        guard let attribute = condition.attribute,
              let operatorStr = condition.operator_,
              let valueStr = condition.value else { return false }

        // Get the attribute value from subject
        let attributeValue: EppoValue
        if attribute == "id" {
            attributeValue = EppoValue(value: subjectKey)
        } else {
            attributeValue = subjectAttributes[attribute] ?? EppoValue.nullValue()
        }

        // Parse condition value based on operator
        let conditionValue = parseConditionValueFromString(valueStr, operator: operatorStr)

        // Apply operator
        return applyOperator(operatorStr, attributeValue: attributeValue, conditionValue: conditionValue)
    }

    private func parseConditionValueFromString(_ value: String, operator operatorStr: String) -> EppoValue {
        // Parse value based on operator type
        switch operatorStr {
        case "ONE_OF", "NOT_ONE_OF":
            // Parse JSON array of strings
            if let data = value.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return EppoValue(array: array)
            }
            return EppoValue(array: [])

        case "GTE", "GT", "LTE", "LT":
            // Numeric operators
            return EppoValue(value: Double(value) ?? 0.0)

        case "MATCHES":
            // Regex - treat as string
            return EppoValue(value: value)

        case "IS_NULL", "NOT_NULL":
            // These operators don't use values
            return EppoValue(value: value)

        default:
            // Default to string
            return EppoValue(value: value)
        }
    }

    private func applyOperator(_ operatorStr: String, attributeValue: EppoValue, conditionValue: EppoValue) -> Bool {
        switch operatorStr {
        case "MATCHES":
            do {
                let attrString = try attributeValue.getStringValue()
                let condString = try conditionValue.getStringValue()
                return matchesRegex(attrString, condString)
            } catch {
                return false
            }

        case "ONE_OF":
            do {
                let attrString = try attributeValue.getStringValue()
                let condArray = try conditionValue.getStringArrayValue()
                return condArray.contains(attrString)
            } catch {
                return false
            }

        case "NOT_ONE_OF":
            do {
                let attrString = try attributeValue.getStringValue()
                let condArray = try conditionValue.getStringArrayValue()
                return !condArray.contains(attrString)
            } catch {
                return false
            }

        case "GTE":
            do {
                let attrDouble = try attributeValue.getDoubleValue()
                let condDouble = try conditionValue.getDoubleValue()
                return attrDouble >= condDouble
            } catch {
                return false
            }

        case "GT":
            do {
                let attrDouble = try attributeValue.getDoubleValue()
                let condDouble = try conditionValue.getDoubleValue()
                return attrDouble > condDouble
            } catch {
                return false
            }

        case "LTE":
            do {
                let attrDouble = try attributeValue.getDoubleValue()
                let condDouble = try conditionValue.getDoubleValue()
                return attrDouble <= condDouble
            } catch {
                return false
            }

        case "LT":
            do {
                let attrDouble = try attributeValue.getDoubleValue()
                let condDouble = try conditionValue.getDoubleValue()
                return attrDouble < condDouble
            } catch {
                return false
            }

        case "IS_NULL":
            return attributeValue.isNull()

        case "NOT_NULL":
            return !attributeValue.isNull()

        default:
            return false
        }
    }

    private func matchesRegex(_ string: String, _ pattern: String) -> Bool {
        return string.range(of: pattern, options: .regularExpression) != nil
    }

    private func matchesSharding(split: Eppo_UFC_Split, subjectKey: String, totalShards: Int32, isConfigObfuscated: Bool) -> Bool {
        let shardsCount = split.shardsCount
        guard shardsCount > 0 else { return false }

        // JSON version uses allSatisfy - ALL shards must match, not ANY
        // Create sharder for this evaluation
        let sharder = MD5Sharder()

        // Check that ALL shards match (like JSON allSatisfy logic)
        for i in 0..<shardsCount {
            guard let shard = split.shards(at: i) else { return false }
            guard let salt = shard.salt else { return false }

            // Handle obfuscated salt (same logic as JSON version)
            let actualSalt: String?
            if isConfigObfuscated {
                actualSalt = base64Decode(salt)
            } else {
                actualSalt = salt
            }

            guard let finalSalt = actualSalt else { return false }

            // Create hash key like JSON version: salt + "-" + subjectKey
            let hashKey = finalSalt + "-" + subjectKey

            let shardValue = sharder.getShard(
                input: hashKey, // Use hash key instead of just subjectKey
                totalShards: Int(totalShards)
            )

            // Check if shardValue falls within ANY range for this shard
            let rangesCount = shard.rangesCount
            var shardMatches = false
            for j in 0..<rangesCount {
                if let range = shard.ranges(at: j) {
                    if shardValue >= range.start && shardValue < range.end {
                        shardMatches = true
                        break
                    }
                }
            }

            // If this shard doesn't match, the whole split fails (allSatisfy logic)
            if !shardMatches {
                return false
            }
        }

        // All shards matched
        return true
    }
}