import Foundation
import FlatBuffers

/// FlatBuffer native evaluator that works directly with FlatBuffer objects without Swift struct conversion
/// Provides optional indexing for O(1) flag lookups vs O(log n) binary search
public class FlatBufferNativeEvaluator: FlagEvaluatorProtocol {
    private let ufcRoot: Eppo_UFC_UniversalFlagConfig
    private let flagEvaluator: FlagEvaluator
    private let useIndex: Bool

    // Optional index for O(1) flag lookups
    private let flagIndex: [String: Int]?

    public init(flatBufferData: Data, useIndex: Bool = false) throws {
        let buffer = ByteBuffer(data: flatBufferData)
        self.ufcRoot = Eppo_UFC_UniversalFlagConfig(buffer, o: Int32(buffer.read(def: UOffset.self, position: buffer.reader)) + Int32(buffer.reader))
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())
        self.useIndex = useIndex

        if useIndex {
            // Build index mapping flag keys to their positions
            var indexMap: [String: Int] = [:]
            let flagsCount = ufcRoot.flagsCount

            print("   📚 Building FlatBuffer flag index for \(flagsCount) flags...")

            for i in 0..<flagsCount {
                if let flagEntry = ufcRoot.flags(at: i),
                   let flag = flagEntry.flag,
                   let key = flag.key {
                    indexMap[key] = Int(i)
                }
            }

            self.flagIndex = indexMap
            print("   ✅ Built index for \(indexMap.count) flags")
        } else {
            self.flagIndex = nil
        }
    }

    public func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType? = nil
    ) -> FlagEvaluation {
        // Find flag using either index or binary search
        guard let fbFlag = findFlag(flagKey: flagKey) else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found"
            )
        }

        // Check if flag is enabled
        guard fbFlag.enabled else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag is disabled"
            )
        }

        // Evaluate flag directly on FlatBuffer objects
        return evaluateFlatBufferFlag(
            flag: fbFlag,
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )
    }

    // MARK: - Private Methods

    private func findFlag(flagKey: String) -> Eppo_UFC_Flag? {
        if let index = flagIndex {
            // O(1) index lookup
            guard let position = index[flagKey] else { return nil }
            return ufcRoot.flags(at: Int32(position))?.flag
        } else {
            // O(log n) binary search using FlatBuffer's native indexed lookup
            return ufcRoot.flagsBy(key: flagKey)?.flag
        }
    }

    private func evaluateFlatBufferFlag(
        flag: Eppo_UFC_Flag,
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool
    ) -> FlagEvaluation {

        // Iterate through allocations to find a matching one
        let allocationsCount = flag.allocationsCount
        for i in 0..<allocationsCount {
            guard let allocation = flag.allocations(at: i) else { continue }

            // Check allocation timing
            if !isAllocationActive(allocation: allocation) {
                continue
            }

            // Check rules if present
            let rulesCount = allocation.rulesCount
            if rulesCount > 0 {
                var allRulesMatch = true

                for j in 0..<rulesCount {
                    guard let rule = allocation.rules(at: j) else { continue }

                    if !evaluateRule(rule: rule, subjectAttributes: subjectAttributes, flagKey: flagKey) {
                        allRulesMatch = false
                        break
                    }
                }

                if !allRulesMatch {
                    continue
                }
            }

            // Find matching split
            if let evaluation = evaluateSplits(
                allocation: allocation,
                flag: flag,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagKey: flagKey
            ) {
                return evaluation
            }
        }

        // No matching allocation found
        return FlagEvaluation.noneResult(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            flagEvaluationCode: .flagUnrecognizedOrDisabled,
            flagEvaluationDescription: "No matching allocation found"
        )
    }

    private func isAllocationActive(allocation: Eppo_UFC_Allocation) -> Bool {
        let now = Date()

        // Check start time
        if allocation.startAt > 0 {
            let startDate = parseUInt64Timestamp(allocation.startAt)
            if let startDate = startDate, now < startDate {
                return false
            }
        }

        // Check end time
        if allocation.endAt > 0 {
            let endDate = parseUInt64Timestamp(allocation.endAt)
            if let endDate = endDate, now > endDate {
                return false
            }
        }

        return true
    }

    private func evaluateRule(
        rule: Eppo_UFC_Rule,
        subjectAttributes: SubjectAttributes,
        flagKey: String
    ) -> Bool {
        let conditionsCount = rule.conditionsCount

        // All conditions must be true for rule to match
        for i in 0..<conditionsCount {
            guard let condition = rule.conditions(at: i) else { continue }
            guard let attribute = condition.attribute else { continue }
            guard let value = condition.value else { continue }

            if !evaluateCondition(
                attribute: attribute,
                operator: condition.operator_,
                value: value,
                subjectAttributes: subjectAttributes,
                flagKey: flagKey
            ) {
                return false
            }
        }

        return true
    }

    private func evaluateCondition(
        attribute: String,
        operator: Eppo_UFC_OperatorType,
        value: String,
        subjectAttributes: SubjectAttributes,
        flagKey: String
    ) -> Bool {
        let subjectValue = subjectAttributes[attribute]

        switch `operator` {
        case .oneOf:
            // Parse JSON array
            guard let data = value.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                return false
            }

            if let subjectStringValue = try? subjectValue?.getStringValue() {
                return array.contains(subjectStringValue)
            }
            return false

        case .notOneOf:
            // Parse JSON array
            guard let data = value.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                return true  // If can't parse, assume not in list
            }

            if let subjectStringValue = try? subjectValue?.getStringValue() {
                return !array.contains(subjectStringValue)
            }
            return true

        case .gt:
            guard let subjectNumeric = try? subjectValue?.getDoubleValue(),
                  let conditionNumeric = Double(value) else {
                return false
            }
            return subjectNumeric > conditionNumeric

        case .gte:
            guard let subjectNumeric = try? subjectValue?.getDoubleValue(),
                  let conditionNumeric = Double(value) else {
                return false
            }
            return subjectNumeric >= conditionNumeric

        case .lt:
            guard let subjectNumeric = try? subjectValue?.getDoubleValue(),
                  let conditionNumeric = Double(value) else {
                return false
            }
            return subjectNumeric < conditionNumeric

        case .lte:
            guard let subjectNumeric = try? subjectValue?.getDoubleValue(),
                  let conditionNumeric = Double(value) else {
                return false
            }
            return subjectNumeric <= conditionNumeric

        case .matches:
            guard let subjectStringValue = try? subjectValue?.getStringValue() else {
                return false
            }
            // Use regex matching
            do {
                let regex = try NSRegularExpression(pattern: value)
                let range = NSRange(location: 0, length: subjectStringValue.utf16.count)
                return regex.firstMatch(in: subjectStringValue, options: [], range: range) != nil
            } catch {
                return false
            }

        case .notMatches:
            guard let subjectStringValue = try? subjectValue?.getStringValue() else {
                return true
            }
            // Use regex matching (inverted)
            do {
                let regex = try NSRegularExpression(pattern: value)
                let range = NSRange(location: 0, length: subjectStringValue.utf16.count)
                return regex.firstMatch(in: subjectStringValue, options: [], range: range) == nil
            } catch {
                return true
            }

        case .isNull:
            let expectNull = value.lowercased() == "true"
            return expectNull ? (subjectValue == nil) : (subjectValue != nil)
        }
    }

    private func evaluateSplits(
        allocation: Eppo_UFC_Allocation,
        flag: Eppo_UFC_Flag,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        flagKey: String
    ) -> FlagEvaluation? {

        let splitsCount = allocation.splitsCount
        for i in 0..<splitsCount {
            guard let split = allocation.splits(at: i) else { continue }
            guard let variationKey = split.variationKey else { continue }

            let shardsCount = split.shardsCount
            for j in 0..<shardsCount {
                guard let shard = split.shards(at: j) else { continue }
                guard let salt = shard.salt else { continue }

                // Calculate hash using MD5 sharder
                let hashInput = "\(salt)-\(subjectKey)"
                let hashValue = flagEvaluator.sharder.getShard(input: hashInput, totalShards: Int(flag.totalShards))

                // Check if hash falls within any range
                let rangesCount = shard.rangesCount
                for k in 0..<rangesCount {
                    guard let range = shard.ranges(at: k) else { continue }

                    if hashValue >= Int(range.start) && hashValue < Int(range.end) {
                        // Found matching shard, return evaluation with this variation
                        return createFlagEvaluation(
                            flag: flag,
                            allocation: allocation,
                            variationKey: variationKey,
                            flagKey: flagKey,
                            subjectKey: subjectKey,
                            subjectAttributes: subjectAttributes
                        )
                    }
                }
            }
        }

        return nil
    }

    private func createFlagEvaluation(
        flag: Eppo_UFC_Flag,
        allocation: Eppo_UFC_Allocation,
        variationKey: String,
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes
    ) -> FlagEvaluation {

        // Find the variation value
        let variationsCount = flag.variationsCount
        var variationValue: EppoValue = EppoValue(value: "default")

        for i in 0..<variationsCount {
            guard let variation = flag.variations(at: i) else { continue }
            guard let key = variation.key else { continue }

            if key == variationKey {
                guard let valueString = variation.value else { break }
                variationValue = convertFlatBufferValue(valueString, variationType: flag.variationType)
                break
            }
        }

        // Convert FlatBuffer variation type to UFC variation type
        let ufcVariationType: UFC_VariationType
        switch flag.variationType {
        case .boolean: ufcVariationType = .boolean
        case .integer: ufcVariationType = .integer
        case .numeric: ufcVariationType = .numeric
        case .string: ufcVariationType = .string
        case .json: ufcVariationType = .json
        }

        return FlagEvaluation.matchedResult(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: allocation.key,
            variation: UFC_Variation(key: variationKey, value: variationValue),
            variationType: ufcVariationType,
            extraLogging: [:],
            doLog: allocation.doLog,
            isConfigObfuscated: false,
            entityId: flag.entityId != 0 ? Int(flag.entityId) : nil
        )
    }

    private func convertFlatBufferValue(_ valueString: String, variationType: Eppo_UFC_VariationType) -> EppoValue {
        switch variationType {
        case .boolean:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let boolValue = cleanValue.lowercased() == "true"
            return EppoValue(value: boolValue)
        case .integer:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let intValue = Int(cleanValue) ?? 0
            return EppoValue(value: intValue)
        case .numeric:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let doubleValue = Double(cleanValue) ?? 0.0
            return EppoValue(value: doubleValue)
        case .string:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return EppoValue(value: cleanValue)
        case .json:
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let unescapedValue = cleanValue.replacingOccurrences(of: "\\\"", with: "\"")
            return EppoValue(value: unescapedValue)
        }
    }

    private func parseUInt64Timestamp(_ timestamp: UInt64) -> Date? {
        guard timestamp > 0 else { return nil }

        let timeInterval: TimeInterval
        if timestamp > 1_000_000_000_000 {
            // Likely milliseconds since Unix epoch
            timeInterval = TimeInterval(timestamp) / 1000.0
        } else {
            // Likely seconds since Unix epoch
            timeInterval = TimeInterval(timestamp)
        }

        return Date(timeIntervalSince1970: timeInterval)
    }

    // MARK: - Benchmark Support

    public func getAllFlagKeys() -> [String] {
        if let index = flagIndex {
            return Array(index.keys)
        } else {
            var allKeys: [String] = []
            let flagsCount = ufcRoot.flagsCount
            for i in 0..<flagsCount {
                if let flagEntry = ufcRoot.flags(at: i),
                   let flag = flagEntry.flag,
                   let key = flag.key {
                    allKeys.append(key)
                }
            }
            return allKeys
        }
    }

    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        guard let fbFlag = findFlag(flagKey: flagKey) else { return nil }

        switch fbFlag.variationType {
        case .boolean: return .boolean
        case .integer: return .integer
        case .numeric: return .numeric
        case .string: return .string
        case .json: return .json
        }
    }
}