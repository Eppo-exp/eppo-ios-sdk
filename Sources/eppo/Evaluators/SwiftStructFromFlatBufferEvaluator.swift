import Foundation
import FlatBuffers

public class SwiftStructFromFlatBufferEvaluator: SwiftStructEvaluatorProtocol {
    private let ufcRoot: Eppo_UFC_UniversalFlagConfig
    private let flagEvaluator: FlagEvaluator
    public let isPrewarmed: Bool

    // For prewarmed mode - all flags and types pre-cached
    private let prewarmedFlagTypeCache: [String: UFC_VariationType]

    // For lazy mode - flags and types loaded on-demand
    public var flagCache: [String: UFC_Flag] = [:]
    public var flagTypeCache: [String: UFC_VariationType] = [:]
    public let cacheLock = NSLock()
    private let cacheQueue = DispatchQueue(label: "com.eppo.swift-struct-flatbuffer-cache", attributes: .concurrent)

    init(flatBufferData: Data, prewarmCache: Bool = false) throws {
        let buffer = ByteBuffer(data: flatBufferData)
        self.ufcRoot = Eppo_UFC_UniversalFlagConfig(buffer, o: Int32(buffer.read(def: UOffset.self, position: buffer.reader)) + Int32(buffer.reader))
        self.isPrewarmed = prewarmCache

        // Create evaluator with MD5 sharder (same as JSON mode)
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())

        if prewarmCache {
            // Prewarm mode - pre-cache flag variation types for fast lookup during evaluation
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
            self.prewarmedFlagTypeCache = typeCache
        } else {
            // Lazy mode - no upfront scanning
            self.prewarmedFlagTypeCache = [:]
        }
    }

    public func evaluateFlag(
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

        // Use the existing JSON evaluation logic with the hydrated UFC_Flag
        let result = flagEvaluator.evaluateFlag(
            flag: ufcFlag,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )

        if flagKey == "kill-switch" && subjectKey == "alice" {
            print("DEBUG: kill-switch evaluation result for alice:")
            print("  - flagEvaluationCode: \(result.flagEvaluationCode)")
            print("  - flagEvaluationDescription: \(result.flagEvaluationDescription)")
            print("  - variation: \(result.variation?.key ?? "nil")")
            print("  - allocationKey: \(result.allocationKey ?? "nil")")
            print("  - subject attributes: \(subjectAttributes)")
        }

        return result
    }

    // Get all flag keys for benchmark
    public func getAllFlagKeys() -> [String] {
        if isPrewarmed {
            return Array(prewarmedFlagTypeCache.keys)
        } else {
            // For lazy mode, scan all flags (only for benchmark purposes)
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

    // Get flag variation type for benchmark
    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        if isPrewarmed {
            return prewarmedFlagTypeCache[flagKey]
        } else {
            // Lazy lookup with caching
            return cacheQueue.sync {
                if let cachedType = flagTypeCache[flagKey] {
                    return cachedType
                }

                // Find and cache the type
                let flagsCount = ufcRoot.flagsCount
                for i in 0..<flagsCount {
                    if let flagEntry = ufcRoot.flags(at: i),
                       let flag = flagEntry.flag,
                       let key = flag.key, key == flagKey {
                        let variationType: UFC_VariationType
                        switch flag.variationType {
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
                        flagTypeCache[flagKey] = variationType
                        return variationType
                    }
                }
                return nil
            }
        }
    }


    // MARK: - Private Methods

    public func getOrLoadFlag(flagKey: String) -> UFC_Flag? {
        // Try to get from cache first (concurrent read)
        let cachedFlag = cacheQueue.sync {
            return flagCache[flagKey]
        }

        if let flag = cachedFlag {
            return flag
        }

        // Not in cache, load it with a barrier write
        return cacheQueue.sync(flags: .barrier) {
            // Double-check after acquiring write lock
            if let cachedFlag = flagCache[flagKey] {
                return cachedFlag
            }

            // Load from FlatBuffer and convert to UFC_Flag
            guard let fbFlag = findFlatBufferFlag(flagKey: flagKey) else {
                return nil
            }

            guard let ufcFlag = try? convertFlatBufferFlagToUFC(fbFlag) else {
                return nil
            }

            // Cache the converted flag
            flagCache[flagKey] = ufcFlag
            return ufcFlag
        }
    }

    private func findFlatBufferFlag(flagKey: String) -> Eppo_UFC_Flag? {
        // O(log n) binary search using FlatBuffer's native indexed lookup
        guard let flagEntry = ufcRoot.flagsBy(key: flagKey) else {
            return nil
        }
        return flagEntry.flag
    }

    private func convertFlatBufferFlagToUFC(_ fbFlag: Eppo_UFC_Flag) throws -> UFC_Flag {
        // Extract basic properties
        guard let key = fbFlag.key else {
            throw NSError(domain: "SwiftStructFromFlatBufferEvaluatorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing flag key"])
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

            // Parse variation value - use proper JSON decoding
            let eppoValue: EppoValue
            switch variationType {
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
                // JSON values are stored as quoted strings with escaped inner quotes
                // Need to trim outer quotes and unescape the inner JSON
                let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                // Unescape the JSON string
                let unescapedValue = cleanValue.replacingOccurrences(of: "\\\"", with: "\"")
                eppoValue = EppoValue(value: unescapedValue)
            }

            variations[variationKey] = UFC_Variation(key: variationKey, value: eppoValue)
        }

        // Convert allocations
        var allocations: [UFC_Allocation] = []
        let allocationsCount = fbFlag.allocationsCount
        for i in 0..<allocationsCount {
            guard let fbAllocation = fbFlag.allocations(at: i) else { continue }
            guard let allocationKey = fbAllocation.key else { continue }

            // Convert rules
            var rules: [UFC_Rule]? = nil
            let rulesCount = fbAllocation.rulesCount
            if rulesCount > 0 {
                var rulesList: [UFC_Rule] = []
                for j in 0..<rulesCount {
                    if let fbRule = fbAllocation.rules(at: j) {
                        if let ufcRule = convertRule(fbRule, flagKey: key) {
                            rulesList.append(ufcRule)
                        }
                    }
                }
                rules = rulesList.isEmpty ? nil : rulesList
            }

            // Convert splits
            var splits: [UFC_Split] = []
            let splitsCount = fbAllocation.splitsCount
            for k in 0..<splitsCount {
                guard let fbSplit = fbAllocation.splits(at: k) else { continue }
                guard let splitVariationKey = fbSplit.variationKey else { continue }

                // Convert shards
                var shards: [UFC_Shard] = []
                let shardsCount = fbSplit.shardsCount
                for l in 0..<shardsCount {
                    guard let fbShard = fbSplit.shards(at: l) else { continue }
                    guard let salt = fbShard.salt else { continue }

                    // Convert ranges
                    var ranges: [UFC_Range] = []
                    let rangesCount = fbShard.rangesCount
                    for m in 0..<rangesCount {
                        guard let fbRange = fbShard.ranges(at: m) else { continue }
                        ranges.append(UFC_Range(start: Int(fbRange.start), end: Int(fbRange.end)))
                    }

                    shards.append(UFC_Shard(salt: salt, ranges: ranges))
                }

                splits.append(UFC_Split(variationKey: splitVariationKey, shards: shards, extraLogging: nil))
            }

            // Convert dates from UInt64 timestamps
            let startAt = parseUInt64Timestamp(fbAllocation.startAt)
            let endAt = parseUInt64Timestamp(fbAllocation.endAt)

            allocations.append(UFC_Allocation(
                key: allocationKey,
                rules: rules,
                startAt: startAt,
                endAt: endAt,
                splits: splits,
                doLog: fbAllocation.doLog
            ))
        }

        let flag = UFC_Flag(
            key: key,
            enabled: enabled,
            variationType: variationType,
            variations: variations,
            allocations: allocations,
            totalShards: Int(fbFlag.totalShards),
            entityId: fbFlag.entityId != 0 ? Int(fbFlag.entityId) : nil
        )

        if key == "kill-switch" {
            print("DEBUG: kill-switch flag structure:")
            print("  - enabled: \(enabled)")
            print("  - allocations count: \(allocations.count)")
            for (i, allocation) in allocations.enumerated() {
                print("  - allocation[\(i)]: key='\(allocation.key)', rules=\(allocation.rules?.count ?? 0), splits=\(allocation.splits.count)")
                if let rules = allocation.rules {
                    for (j, rule) in rules.enumerated() {
                        print("    - rule[\(j)]: conditions=\(rule.conditions.count)")
                        for (k, condition) in rule.conditions.enumerated() {
                            print("      - condition[\(k)]: attr='\(condition.attribute)', op=\(condition.operator)")
                        }
                    }
                }
            }
        }

        return flag
    }

    private func convertRule(_ fbRule: Eppo_UFC_Rule, flagKey: String) -> UFC_Rule? {
        // Convert conditions
        var conditions: [UFC_TargetingRuleCondition] = []
        let conditionsCount = fbRule.conditionsCount
        for i in 0..<conditionsCount {
            guard let fbCondition = fbRule.conditions(at: i) else { continue }
            guard let attribute = fbCondition.attribute else { continue }
            let operatorType = fbCondition.operator_
            guard let value = fbCondition.value else { continue }

            // Convert operator from FlatBuffer enum to UFC enum
            let operatorEnum: UFC_RuleConditionOperator
            switch operatorType {
            case .lt:
                operatorEnum = .lessThan
            case .lte:
                operatorEnum = .lessThanEqual
            case .gt:
                operatorEnum = .greaterThan
            case .gte:
                operatorEnum = .greaterThanEqual
            case .matches:
                operatorEnum = .matches
            case .oneOf:
                operatorEnum = .oneOf
            case .notOneOf:
                operatorEnum = .notOneOf
            case .isNull:
                operatorEnum = .isNull
            case .notMatches:
                operatorEnum = .notMatches
            }

            // Convert value to EppoValue based on operator type
            let conditionValue: EppoValue
            switch operatorType {
            case .oneOf, .notOneOf:
                // Parse JSON array of strings
                if let data = value.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    if flagKey == "kill-switch" || flagKey == "empty_string_flag" || flagKey == "new-user-onboarding" {
                        print("DEBUG: \(flagKey) ONE_OF operator \(operatorType) - attribute: '\(attribute)', raw value: '\(value)', parsed: \(array)")
                    }
                    conditionValue = EppoValue(array: array)
                } else {
                    if flagKey == "kill-switch" || flagKey == "empty_string_flag" || flagKey == "new-user-onboarding" {
                        print("DEBUG: \(flagKey) FAILED to parse ONE_OF - raw value: '\(value)'")
                    }
                    conditionValue = EppoValue(array: [])
                }
            case .gte, .gt, .lte, .lt:
                // Numeric operators
                let doubleValue = Double(value) ?? 0.0
                if flagKey == "kill-switch" || flagKey == "empty_string_flag" || flagKey == "new-user-onboarding" {
                    print("DEBUG: \(flagKey) comparison operator \(operatorType) - attribute: '\(attribute)', raw value: '\(value)', parsed: \(doubleValue)")
                }
                conditionValue = EppoValue(value: doubleValue)
            case .isNull:
                // Parse boolean value to determine if checking for null (true) or not-null (false)
                let expectNull = value.lowercased() == "true"
                conditionValue = EppoValue(value: expectNull)
            case .matches, .notMatches:
                // String operators (MATCHES, NOT_MATCHES, etc.)
                conditionValue = EppoValue(value: value)
            }

            conditions.append(UFC_TargetingRuleCondition(
                operator: operatorEnum,
                attribute: attribute,
                value: conditionValue
            ))
        }

        if conditions.isEmpty {
            return nil
        }

        return UFC_Rule(conditions: conditions)
    }

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

    private func parseUInt64Timestamp(_ timestamp: UInt64) -> Date? {
        guard timestamp > 0 else { return nil }

        // Convert UInt64 timestamp to Date
        // Check if it's milliseconds (13 digits) or seconds (10 digits)
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

    // MARK: - SwiftStructEvaluatorProtocol Methods

    public func prewarmAllFlags() throws {
        guard !isPrewarmed else { return } // Already prewarmed during init

        cacheQueue.async(flags: .barrier) {
            let flagsCount = self.ufcRoot.flagsCount
            print("   🔄 Pre-converting \(flagsCount) FlatBuffer flags to UFC objects...")

            for i in 0..<flagsCount {
                guard let flagEntry = self.ufcRoot.flags(at: i),
                      let flag = flagEntry.flag,
                      let key = flag.key else {
                    continue
                }

                // Convert FlatBuffer flag to UFC_Flag
                if let ufcFlag = try? self.convertFlatBufferFlagToUFC(flag) {
                    self.flagCache[key] = ufcFlag
                    // Also cache the type
                    switch flag.variationType {
                    case .boolean:
                        self.flagTypeCache[key] = .boolean
                    case .integer:
                        self.flagTypeCache[key] = .integer
                    case .numeric:
                        self.flagTypeCache[key] = .numeric
                    case .string:
                        self.flagTypeCache[key] = .string
                    case .json:
                        self.flagTypeCache[key] = .json
                    }
                }
            }

            print("   ✅ Pre-converted \(self.flagCache.count) flags successfully")
        }
    }
}