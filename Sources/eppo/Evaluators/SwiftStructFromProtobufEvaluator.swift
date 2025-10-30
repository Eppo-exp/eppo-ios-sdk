import Foundation
import SwiftProtobuf

public class SwiftStructFromProtobufEvaluator: SwiftStructEvaluatorProtocol {
    private let flagEvaluator: FlagEvaluator
    private let sharedCache: SwiftStructFlagCache<Eppo_Ufc_Flag>

    public var isPrewarmed: Bool { sharedCache.isPrewarmed }

    // Legacy protocol compliance properties (delegated to shared cache)
    public var flagCache: [String: UFC_Flag] {
        get { sharedCache.flagCache }
        set { sharedCache.flagCache = newValue }
    }
    public var flagTypeCache: [String: UFC_VariationType] {
        get { sharedCache.flagTypeCache }
        set { sharedCache.flagTypeCache = newValue }
    }

    // Raw protobuf data for lazy parsing
    private let protobufData: Data
    private var universalFlagConfig: Eppo_Ufc_UniversalFlagConfig?
    private let configQueue = DispatchQueue(label: "com.eppo.swift-struct-protobuf-config", attributes: .concurrent)

    init(protobufData: Data, prewarmCache: Bool = false) throws {
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())
        self.protobufData = protobufData

        // Parse protobuf config to get flag keys for shared cache initialization
        let universalFlagConfig = try Eppo_Ufc_UniversalFlagConfig(serializedBytes: protobufData)
        self.universalFlagConfig = universalFlagConfig

        let allFlagKeys = Array(universalFlagConfig.flags.keys)

        // Initialize shared cache with function-based converter
        self.sharedCache = SwiftStructFlagCache(
            flagKeys: allFlagKeys,
            prewarmCache: prewarmCache,
            findSourceFlag: { [universalFlagConfig] flagKey in
                return universalFlagConfig.flags[flagKey]
            },
            convertToUFCFlag: { sourceFlag in
                let variationType = Self.convertProtobufVariationType(sourceFlag.variationType)
                guard let ufcFlag = Self.convertProtobufFlag(sourceFlag, variationType: variationType) else {
                    throw NSError(domain: "SwiftStructFromProtobufEvaluator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert protobuf flag"])
                }
                return ufcFlag
            },
            getVariationType: { sourceFlag in
                return Self.convertProtobufVariationType(sourceFlag.variationType)
            }
        )
    }

    public func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType? = nil
    ) -> FlagEvaluation {
        // Get flag using shared cache (handles prewarmed vs lazy automatically)
        guard let flag = sharedCache.getFlag(flagKey: flagKey) else {
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .flagUnrecognizedOrDisabled,
                flagEvaluationDescription: "Flag not found"
            )
        }

        // Use the existing flag evaluation logic with the UFC_Flag
        return flagEvaluator.evaluateFlag(
            flag: flag,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            isConfigObfuscated: isConfigObfuscated
        )
    }

    // MARK: - Benchmark Support

    public func getAllFlagKeys() -> [String] {
        if isPrewarmed {
            return sharedCache.getAllFlagKeys()
        } else {
            // For lazy mode, scan all flags (only for benchmark purposes)
            guard let config = getUniversalFlagConfig() else {
                return []
            }
            return Array(config.flags.keys)
        }
    }

    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return sharedCache.getFlagVariationType(flagKey: flagKey)
    }

    // MARK: - Private Methods (Lazy Loading)

    private func getUniversalFlagConfig() -> Eppo_Ufc_UniversalFlagConfig? {
        // Concurrent read - check if already parsed
        let existingConfig = configQueue.sync {
            return universalFlagConfig
        }

        if let config = existingConfig {
            return config
        }

        // Barrier write - parse protobuf data for the first time
        return configQueue.sync(flags: .barrier) {
            // Double-check after acquiring write lock
            if let config = universalFlagConfig {
                return config
            }

            // Parse protobuf data
            do {
                let config = try Eppo_Ufc_UniversalFlagConfig(serializedBytes: protobufData)
                self.universalFlagConfig = config
                return config
            } catch {
                print("❌ Failed to parse protobuf data: \(error)")
                return nil
            }
        }
    }

    public func getOrLoadFlag(flagKey: String) -> UFC_Flag? {
        // Delegate to shared cache (handles all synchronization and caching logic)
        return sharedCache.getFlag(flagKey: flagKey)
    }

    private func findProtobufFlag(flagKey: String) -> Eppo_Ufc_Flag? {
        guard let config = getUniversalFlagConfig() else {
            return nil
        }

        return config.flags[flagKey]
    }

    // MARK: - Static Conversion Methods

    static func convertProtobufVariationType(_ protobufType: Eppo_Ufc_VariationType) -> UFC_VariationType {
        switch protobufType {
        case .boolean:
            return .boolean
        case .string:
            return .string
        case .numeric:
            return .numeric
        case .integer:
            return .integer
        case .json:
            return .json
        case .UNRECOGNIZED:
            return .string // fallback
        }
    }

    static func convertProtobufFlag(_ protobufFlag: Eppo_Ufc_Flag, variationType: UFC_VariationType) -> UFC_Flag? {
        let flagKey = protobufFlag.key
        let enabled = protobufFlag.enabled

        // Convert variations
        var variations: [String: UFC_Variation] = [:]
        for protobufVariation in protobufFlag.variations {
            let variationKey = protobufVariation.key
            let variationValue = convertProtobufValue(protobufVariation.value, variationType: variationType)
            variations[variationKey] = UFC_Variation(key: variationKey, value: variationValue)
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

                splits.append(UFC_Split(variationKey: splitVariationKey, shards: shards, extraLogging: nil))
            }

            // Convert dates
            let startAt = parseUInt64Timestamp(protobufAllocation.startAt)
            let endAt = parseUInt64Timestamp(protobufAllocation.endAt)

            allocations.append(UFC_Allocation(
                key: allocationKey,
                rules: rules,
                startAt: startAt,
                endAt: endAt,
                splits: splits,
                doLog: protobufAllocation.doLog
            ))
        }

        return UFC_Flag(
            key: flagKey,
            enabled: enabled,
            variationType: variationType,
            variations: variations,
            allocations: allocations,
            totalShards: Int(protobufFlag.totalShards),
            entityId: protobufFlag.entityID != 0 ? Int(protobufFlag.entityID) : nil
        )
    }

    static func convertProtobufValue(_ valueString: String, variationType: UFC_VariationType) -> EppoValue {
        switch variationType {
        case .boolean:
            // Handle JSON-encoded boolean values
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let boolValue = cleanValue.lowercased() == "true"
            return EppoValue(value: boolValue)
        case .integer:
            // Handle JSON-encoded integer values - preserve as integer for proper type validation
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let intValue = Int(cleanValue) ?? 0
            return EppoValue(value: intValue)
        case .numeric:
            // Handle JSON-encoded numeric values
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let doubleValue = Double(cleanValue) ?? 0.0
            return EppoValue(value: doubleValue)
        case .string:
            // Handle JSON-encoded string values - remove surrounding quotes
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return EppoValue(value: cleanValue)
        case .json:
            // JSON values are stored as quoted strings with escaped inner quotes
            let cleanValue = valueString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            // Unescape the JSON string
            let unescapedValue = cleanValue.replacingOccurrences(of: "\\\"", with: "\"")
            return EppoValue(value: unescapedValue)
        }
    }

    static func convertProtobufRule(_ protobufRule: Eppo_Ufc_Rule) -> UFC_Rule? {
        var conditions: [UFC_TargetingRuleCondition] = []

        for protobufCondition in protobufRule.conditions {
            let attribute = protobufCondition.attribute
            let operatorType = protobufCondition.operator
            let value = protobufCondition.value

            // Convert operator from protobuf enum to UFC enum
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
            case .UNRECOGNIZED:
                continue // skip unrecognized operators
            }

            // Convert value to EppoValue based on operator type
            let conditionValue: EppoValue
            switch operatorType {
            case .oneOf, .notOneOf:
                // Parse JSON array of strings
                if let data = value.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    conditionValue = EppoValue(array: array)
                } else {
                    conditionValue = EppoValue(array: [])
                }
            case .gte, .gt, .lte, .lt:
                // Numeric operators
                let doubleValue = Double(value) ?? 0.0
                conditionValue = EppoValue(value: doubleValue)
            case .isNull:
                // Parse boolean value to determine if checking for null (true) or not-null (false)
                let expectNull = value.lowercased() == "true"
                conditionValue = EppoValue(value: expectNull)
            case .matches, .notMatches:
                // String operators
                conditionValue = EppoValue(value: value)
            case .UNRECOGNIZED:
                continue
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

    static func parseTimestamp(_ timestamp: String) -> Date? {
        guard !timestamp.isEmpty else { return nil }
        // Parse ISO 8601 date string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timestamp)
        }()
    }

    static func parseUInt64Timestamp(_ timestamp: UInt64) -> Date? {
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

        guard let config = getUniversalFlagConfig() else {
            throw NSError(domain: "SwiftStructFromProtobufEvaluator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load protobuf configuration"])
        }

        // Get all flag keys
        let allFlagKeys = Array(config.flags.keys)

        // Delegate to shared cache (handles all synchronization and conversion logic)
        sharedCache.prewarmAllFlags(allFlagKeys: allFlagKeys)
    }
}