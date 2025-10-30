import Foundation
import IkigaJSON

public class IkigaJSONLazyEvaluator {
    private let jsonData: Data
    private let flagEvaluator: FlagEvaluator
    private let flagTypeCache: [String: UFC_VariationType]

    // Thread-safe cache for lazy-loaded UFC_Flag objects
    private var flagCache: [String: UFC_Flag] = [:]
    private let cacheQueue = DispatchQueue(label: "com.eppo.ikiga-json-lazy-cache", attributes: .concurrent)

    // Parsed JSON object for efficient access
    private let rootObject: JSONObject

    init(jsonData: Data) throws {
        self.jsonData = jsonData
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())

        // Parse JSON once using IkigaJSON's raw API
        self.rootObject = try JSONObject(data: jsonData)

        // Pre-cache flag variation types for fast lookup during evaluation
        var typeCache: [String: UFC_VariationType] = [:]

        if let flags = rootObject["flags"] as? JSONObject {
            for (flagKey, _) in flags {
                if let flagData = flags[flagKey] as? JSONObject,
                   let variationType = flagData["variationType"] as? String {
                    switch variationType {
                    case "BOOLEAN":
                        typeCache[flagKey] = .boolean
                    case "INTEGER":
                        typeCache[flagKey] = .integer
                    case "NUMERIC":
                        typeCache[flagKey] = .numeric
                    case "STRING":
                        typeCache[flagKey] = .string
                    case "JSON":
                        typeCache[flagKey] = .json
                    default:
                        break
                    }
                }
            }
        }

        self.flagTypeCache = typeCache
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

        // Use the existing JSON evaluation logic with the hydrated UFC_Flag
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

    // Get all flag keys for benchmark
    func getAllFlagKeys() -> [String] {
        return Array(flagTypeCache.keys)
    }

    // Get flag variation type for benchmark
    func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        return flagTypeCache[flagKey]
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

    private func getOrLoadFlag(flagKey: String) -> UFC_Flag? {
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

            // Load from JSON and convert to UFC_Flag
            guard let ufcFlag = try? parseJSONFlag(flagKey: flagKey) else {
                return nil
            }

            // Cache the converted flag
            flagCache[flagKey] = ufcFlag
            return ufcFlag
        }
    }

    private func parseJSONFlag(flagKey: String) throws -> UFC_Flag? {
        guard let flags = rootObject["flags"] as? JSONObject,
              let flagData = flags[flagKey] as? JSONObject else {
            return nil
        }

        // Extract basic properties
        let enabled = flagData["enabled"] as? Bool ?? false

        // Convert variation type
        let variationTypeString = flagData["variationType"] as? String ?? ""
        let variationType: UFC_VariationType
        switch variationTypeString {
        case "BOOLEAN":
            variationType = .boolean
        case "INTEGER":
            variationType = .integer
        case "JSON":
            variationType = .json
        case "NUMERIC":
            variationType = .numeric
        case "STRING":
            variationType = .string
        default:
            throw NSError(domain: "IkigaJSONLazyError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown variation type: \(variationTypeString)"])
        }

        // Convert variations
        var variations: [String: UFC_Variation] = [:]
        if let variationsData = flagData["variations"] as? JSONObject {
            for (variationKey, variationValue) in variationsData {
                guard let variationObject = variationValue as? JSONObject,
                      let value = variationObject["value"] else {
                    continue
                }

                // Convert value to EppoValue based on variation type
                let eppoValue: EppoValue
                switch variationType {
                case .boolean:
                    if let boolValue = value as? Bool {
                        eppoValue = EppoValue(value: boolValue)
                    } else {
                        eppoValue = EppoValue(value: false)
                    }
                case .integer:
                    if let intValue = value as? Int {
                        eppoValue = EppoValue(value: intValue)
                    } else if let doubleValue = value as? Double {
                        // Check if this is actually an integer value (no decimal part)
                        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                            eppoValue = EppoValue(value: Int(doubleValue))
                        } else {
                            // This is a type mismatch - flag expects INTEGER but got decimal
                            // The evaluator should handle this as an assignment error
                            // Store as double so the evaluator can detect the mismatch
                            eppoValue = EppoValue(value: doubleValue)
                        }
                    } else {
                        eppoValue = EppoValue(value: 0)
                    }
                case .numeric:
                    if let doubleValue = value as? Double {
                        eppoValue = EppoValue(value: doubleValue)
                    } else if let intValue = value as? Int {
                        eppoValue = EppoValue(value: Double(intValue))
                    } else {
                        eppoValue = EppoValue(value: 0.0)
                    }
                case .string:
                    if let stringValue = value as? String {
                        eppoValue = EppoValue(value: stringValue)
                    } else {
                        eppoValue = EppoValue(value: "")
                    }
                case .json:
                    if let stringValue = value as? String {
                        eppoValue = EppoValue(value: stringValue)
                    } else {
                        // Convert JSON value to string representation
                        let jsonString = String(describing: value)
                        eppoValue = EppoValue(value: jsonString)
                    }
                }

                variations[variationKey] = UFC_Variation(key: variationKey, value: eppoValue)
            }
        }

        // Convert allocations
        var allocations: [UFC_Allocation] = []
        if let allocationsArray = flagData["allocations"] as? JSONArray {
            for case let allocationData as JSONObject in allocationsArray {
                guard let allocationKey = allocationData["key"] as? String else {
                    continue
                }

                // Convert rules
                var rules: [UFC_Rule]? = nil
                if let rulesArray = allocationData["rules"] as? JSONArray {
                    var rulesList: [UFC_Rule] = []
                    for case let ruleData as JSONObject in rulesArray {
                        if let ufcRule = convertRule(ruleData) {
                            rulesList.append(ufcRule)
                        }
                    }
                    rules = rulesList.isEmpty ? nil : rulesList
                }

                // Convert splits
                var splits: [UFC_Split] = []
                if let splitsArray = allocationData["splits"] as? JSONArray {
                    for case let splitData as JSONObject in splitsArray {
                        guard let splitVariationKey = splitData["variationKey"] as? String else {
                            continue
                        }

                        // Convert shards
                        var shards: [UFC_Shard] = []
                        if let shardsArray = splitData["shards"] as? JSONArray {
                            for case let shardData as JSONObject in shardsArray {
                                guard let salt = shardData["salt"] as? String else {
                                    continue
                                }

                                // Convert ranges
                                var ranges: [UFC_Range] = []
                                if let rangesArray = shardData["ranges"] as? JSONArray {
                                    for case let rangeData as JSONObject in rangesArray {
                                        if let start = rangeData["start"] as? Int,
                                           let end = rangeData["end"] as? Int {
                                            ranges.append(UFC_Range(start: start, end: end))
                                        }
                                    }
                                }

                                shards.append(UFC_Shard(salt: salt, ranges: ranges))
                            }
                        }

                        // Convert extra logging
                        var extraLogging: [String: String]? = nil
                        if let extraLoggingData = splitData["extraLogging"] as? JSONObject {
                            var extraLoggingDict: [String: String] = [:]
                            for (key, value) in extraLoggingData {
                                if let stringValue = value as? String {
                                    extraLoggingDict[key] = stringValue
                                }
                            }
                            extraLogging = extraLoggingDict.isEmpty ? nil : extraLoggingDict
                        }

                        splits.append(UFC_Split(variationKey: splitVariationKey, shards: shards, extraLogging: extraLogging))
                    }
                }

                // Convert dates
                let startAt = parseTimestamp(allocationData["startAt"] as? String)
                let endAt = parseTimestamp(allocationData["endAt"] as? String)
                let doLog = allocationData["doLog"] as? Bool ?? true

                allocations.append(UFC_Allocation(
                    key: allocationKey,
                    rules: rules,
                    startAt: startAt,
                    endAt: endAt,
                    splits: splits,
                    doLog: doLog
                ))
            }
        }

        // Get totalShards and entityId
        let totalShards = flagData["totalShards"] as? Int ?? 10000
        let entityId = flagData["entityId"] as? Int

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

    private func convertRule(_ ruleData: JSONObject) -> UFC_Rule? {
        guard let conditionsArray = ruleData["conditions"] as? JSONArray else {
            return nil
        }

        var conditions: [UFC_TargetingRuleCondition] = []
        for case let conditionData as JSONObject in conditionsArray {
            guard let attribute = conditionData["attribute"] as? String,
                  let operatorString = conditionData["operator"] as? String,
                  let value = conditionData["value"] else {
                continue
            }

            // Convert operator from string to enum
            let operatorEnum: UFC_RuleConditionOperator
            switch operatorString {
            case "LT":
                operatorEnum = .lessThan
            case "LTE":
                operatorEnum = .lessThanEqual
            case "GT":
                operatorEnum = .greaterThan
            case "GTE":
                operatorEnum = .greaterThanEqual
            case "MATCHES":
                operatorEnum = .matches
            case "ONE_OF":
                operatorEnum = .oneOf
            case "NOT_ONE_OF":
                operatorEnum = .notOneOf
            case "IS_NULL":
                operatorEnum = .isNull
            case "NOT_MATCHES":
                operatorEnum = .notMatches
            default:
                continue
            }

            // Convert value to EppoValue based on operator type
            let conditionValue: EppoValue
            switch operatorEnum {
            case .oneOf, .notOneOf:
                if let jsonArray = value as? JSONArray {
                    let stringArray = jsonArray.compactMap { $0 as? String }
                    conditionValue = EppoValue(array: stringArray)
                } else {
                    conditionValue = EppoValue(array: [])
                }
            case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
                // For version comparison operators, treat as strings to preserve semantic versioning
                if let stringValue = value as? String {
                    conditionValue = EppoValue(value: stringValue)
                } else if let doubleValue = value as? Double {
                    conditionValue = EppoValue(value: doubleValue)
                } else if let intValue = value as? Int {
                    conditionValue = EppoValue(value: Double(intValue))
                } else {
                    conditionValue = EppoValue(value: 0.0)
                }
            case .isNull:
                if let boolValue = value as? Bool {
                    conditionValue = EppoValue(value: boolValue)
                } else {
                    conditionValue = EppoValue(value: true)
                }
            case .matches, .notMatches:
                if let stringValue = value as? String {
                    conditionValue = EppoValue(value: stringValue)
                } else {
                    conditionValue = EppoValue(value: "")
                }
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
}