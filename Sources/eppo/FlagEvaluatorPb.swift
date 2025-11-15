import Foundation
import Semver

public class FlagEvaluatorPb: FlagEvaluatorProtocol {
  let sharder: Sharder

  init(sharder: Sharder) {
    self.sharder = sharder
  }

  enum Errors: Error {
    case UnexpectedValue
  }

  func evaluateFlag(
    flag: Ufc_FlagDto,
    subjectKey: String,
    subjectAttributes: SubjectAttributes,
    isConfigObfuscated: Bool
  ) -> FlagEvaluation {
    if !flag.enabled {
      return FlagEvaluation.noneResult(
        flagKey: flag.key,
        subjectKey: subjectKey,
        subjectAttributes: subjectAttributes,
        entityId: flag.hasEntityID ? Int(flag.entityID) : nil
      )
    }

    // Check if flag is unrecognized
    if flag.key.isEmpty {
      return FlagEvaluation.noneResult(
        flagKey: flag.key,
        subjectKey: subjectKey,
        subjectAttributes: subjectAttributes,
        entityId: flag.hasEntityID ? Int(flag.entityID) : nil
      )
    }

    // Handle case where flag has no allocations
    if flag.allocations.isEmpty {
      let result = FlagEvaluation.noneResult(
        flagKey: flag.key,
        subjectKey: subjectKey,
        subjectAttributes: subjectAttributes,
        flagEvaluationCode: .flagUnrecognizedOrDisabled,
        flagEvaluationDescription: "Unrecognized or disabled flag: \(flag.key)",
        entityId: flag.hasEntityID ? Int(flag.entityID) : nil
      )
      return result
    }

    var unmatchedAllocations: [AllocationEvaluation] = []
    var unevaluatedAllocations: [AllocationEvaluation] = []
    var matchedRule: UFC_Rule? = nil
    var matchedAllocation: AllocationEvaluation? = nil

    // Get current time once for all allocations
    let currentTimeMs = Int64(Date().timeIntervalSince1970 * 1000)

    for (index, allocation) in flag.allocations.enumerated() {
      let orderPosition = index + 1

      // Check if allocation is within time range

      if allocation.hasStartAtMs {
        if currentTimeMs < allocation.startAtMs {
          unmatchedAllocations.append(
            AllocationEvaluation(
              key: allocation.key,
              allocationEvaluationCode: .beforeStartTime,
              orderPosition: orderPosition
            ))
          continue
        }
      }

      if allocation.hasEndAtMs {
        if currentTimeMs > allocation.endAtMs {
          unmatchedAllocations.append(
            AllocationEvaluation(
              key: allocation.key,
              allocationEvaluationCode: .afterEndTime,
              orderPosition: orderPosition
            ))
          continue
        }
      }

      // Check if allocation has rules
      if !allocation.rules.isEmpty {
        var rulesMatch = false
        for rule in allocation.rules {
          if matchesRule(
            subjectAttributes: subjectAttributes,
            rule: rule,
            isConfigObfuscated: isConfigObfuscated,
            subjectKey: subjectKey
          ) {
            rulesMatch = true
            matchedRule = convertRuleToUFC(rule)
            break
          }
        }

        if !rulesMatch {
          unmatchedAllocations.append(
            AllocationEvaluation(
              key: allocation.key,
              allocationEvaluationCode: .failingRule,
              orderPosition: orderPosition
            ))
          continue
        }
      }

      // Check if subject is in any traffic range
      for split in allocation.splits {
        let allShardsMatch = split.shards.allSatisfy { shard in
          matchesShard(
            shard: shard,
            subjectKey: subjectKey,
            totalShards: Int(flag.totalShards),
            isConfigObfuscated: isConfigObfuscated
          )
        }

        if allShardsMatch {
          // Mark remaining allocations as unevaluated
          for remainingIndex in (index + 1)..<flag.allocations.count {
            unevaluatedAllocations.append(
              AllocationEvaluation(
                key: flag.allocations[remainingIndex].key,
                allocationEvaluationCode: .unevaluated,
                orderPosition: remainingIndex + 1
              ))
          }

          matchedAllocation = AllocationEvaluation(
            key: allocation.key,
            allocationEvaluationCode: .match,
            orderPosition: orderPosition
          )

          let variation = flag.variations[split.variationKey]
          let variationType = convertVariationTypeToUFC(flag.variationType)

          // Convert protobuf allocation to UFC_Allocation for compatibility
          let ufcAllocation = convertAllocationToUFC(allocation)

          // Check for assignment errors
          if variationType == .integer {
            if let variation = variation {
              let ufcVariation = convertVariationToUFC(variation)

              // First try to get double value directly
              if let doubleValue = try? ufcVariation.value.getDoubleValue() {
                if !doubleValue.isInteger {
                  // Create a new variation with the original double value
                  let errorVariation = UFC_Variation(
                    key: ufcVariation.key,
                    value: EppoValue.valueOf(doubleValue)
                  )
                  let evaluation = FlagEvaluation(
                    flagKey: flag.key,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    allocationKey: allocation.key,
                    variation: errorVariation,
                    variationType: variationType,
                    extraLogging: split.extraLogging,
                    doLog: allocation.doLog,
                    matchedRule: matchedRule,
                    matchedAllocation: matchedAllocation,
                    unmatchedAllocations: unmatchedAllocations,
                    unevaluatedAllocations: unevaluatedAllocations,
                    flagEvaluationCode: .assignmentError,
                    flagEvaluationDescription:
                      "Variation (\(ufcVariation.key)) is configured for type INTEGER, but is set to incompatible value (\(doubleValue))",
                    entityId: flag.hasEntityID ? Int(flag.entityID) : nil
                  )
                  return evaluation
                }
                // Create a new variation with the double value
                let decodedVariation = UFC_Variation(
                  key: ufcVariation.key,
                  value: EppoValue.valueOf(doubleValue)
                )
                return FlagEvaluation.matchedResult(
                  flagKey: flag.key,
                  subjectKey: subjectKey,
                  subjectAttributes: subjectAttributes,
                  allocationKey: allocation.key,
                  variation: decodedVariation,
                  variationType: variationType,
                  extraLogging: split.extraLogging,
                  doLog: allocation.doLog,
                  isConfigObfuscated: isConfigObfuscated,
                  matchedRule: matchedRule,
                  matchedAllocation: matchedAllocation,
                  allocation: ufcAllocation,
                  unmatchedAllocations: unmatchedAllocations,
                  unevaluatedAllocations: unevaluatedAllocations,
                  entityId: flag.hasEntityID ? Int(flag.entityID) : nil
                )
              }

              // If not a double, try string value
              if let stringValue = try? ufcVariation.value.getStringValue() {
                var decodedValue: String? = stringValue
                if isConfigObfuscated {
                  decodedValue = base64Decode(stringValue)
                }
                if let finalValue = decodedValue, let doubleValue = Double(finalValue) {
                  if !doubleValue.isInteger {
                    // Create a new variation with the original double value
                    let errorVariation = UFC_Variation(
                      key: ufcVariation.key,
                      value: EppoValue.valueOf(doubleValue)
                    )
                    return FlagEvaluation(
                      flagKey: flag.key,
                      subjectKey: subjectKey,
                      subjectAttributes: subjectAttributes,
                      allocationKey: allocation.key,
                      variation: errorVariation,
                      variationType: variationType,
                      extraLogging: split.extraLogging,
                      doLog: allocation.doLog,
                      matchedRule: matchedRule,
                      matchedAllocation: matchedAllocation,
                      unmatchedAllocations: unmatchedAllocations,
                      unevaluatedAllocations: unevaluatedAllocations,
                      flagEvaluationCode: .assignmentError,
                      flagEvaluationDescription:
                        "Variation (\(ufcVariation.key)) is configured for type INTEGER, but is set to incompatible value (\(doubleValue))",
                      entityId: flag.hasEntityID ? Int(flag.entityID) : nil
                    )
                  }
                  // Create a new variation with the decoded value
                  let decodedVariation = UFC_Variation(
                    key: ufcVariation.key,
                    value: EppoValue.valueOf(doubleValue)
                  )
                  return FlagEvaluation.matchedResult(
                    flagKey: flag.key,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    allocationKey: allocation.key,
                    variation: decodedVariation,
                    variationType: variationType,
                    extraLogging: split.extraLogging,
                    doLog: allocation.doLog,
                    isConfigObfuscated: isConfigObfuscated,
                    matchedRule: matchedRule,
                    matchedAllocation: matchedAllocation,
                    allocation: ufcAllocation,
                    unmatchedAllocations: unmatchedAllocations,
                    unevaluatedAllocations: unevaluatedAllocations,
                    entityId: flag.hasEntityID ? Int(flag.entityID) : nil
                  )
                }
              }
              return FlagEvaluation(
                flagKey: flag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                allocationKey: allocation.key,
                variation: ufcVariation,
                variationType: variationType,
                extraLogging: split.extraLogging,
                doLog: allocation.doLog,
                matchedRule: matchedRule,
                matchedAllocation: matchedAllocation,
                unmatchedAllocations: unmatchedAllocations,
                unevaluatedAllocations: unevaluatedAllocations,
                flagEvaluationCode: .assignmentError,
                flagEvaluationDescription:
                  "Variation (\(ufcVariation.key)) is configured for type INTEGER, but is set to incompatible value",
                entityId: flag.hasEntityID ? Int(flag.entityID) : nil
              )
            } else {
              return FlagEvaluation.noneResult(
                flagKey: flag.key,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                unmatchedAllocations: unmatchedAllocations,
                unevaluatedAllocations: unevaluatedAllocations
              )
            }
          }

          let ufcVariation = variation != nil ? convertVariationToUFC(variation!) : nil

          return FlagEvaluation.matchedResult(
            flagKey: flag.key,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: allocation.key,
            variation: ufcVariation,
            variationType: variationType,
            extraLogging: split.extraLogging,
            doLog: allocation.doLog,
            isConfigObfuscated: isConfigObfuscated,
            matchedRule: matchedRule,
            matchedAllocation: matchedAllocation,
            allocation: ufcAllocation,
            unmatchedAllocations: unmatchedAllocations,
            unevaluatedAllocations: unevaluatedAllocations,
            entityId: flag.hasEntityID ? Int(flag.entityID) : nil
          )
        }
      }

      // If we get here, the subject is not in any traffic range
      unmatchedAllocations.append(
        AllocationEvaluation(
          key: allocation.key,
          allocationEvaluationCode: .trafficExposureMiss,
          orderPosition: orderPosition
        ))
    }

    // If we get here, no allocation matched
    return FlagEvaluation.noneResult(
      flagKey: flag.key,
      subjectKey: subjectKey,
      subjectAttributes: subjectAttributes,
      unmatchedAllocations: unmatchedAllocations,
      unevaluatedAllocations: unevaluatedAllocations,
      entityId: flag.hasEntityID ? Int(flag.entityID) : nil
    )
  }

  // MARK: - FlagEvaluatorProtocol Implementation

  /// Protocol method that extracts the protobuf flag from configuration and delegates to the existing evaluateFlag method
  func evaluateFlag(
    configuration: Configuration,
    flagKey: String,
    subjectKey: String,
    subjectAttributes: SubjectAttributes,
    isConfigObfuscated: Bool
  ) -> FlagEvaluation {
    let flagKeyForLookup = isConfigObfuscated ? getMD5Hex(flagKey) : flagKey

    guard let flagConfigPb = configuration.getProtobufFlag(flagKey: flagKeyForLookup) else {
      return FlagEvaluation.noneResult(
        flagKey: flagKey,
        subjectKey: subjectKey,
        subjectAttributes: subjectAttributes,
        flagEvaluationCode: .flagUnrecognizedOrDisabled,
        flagEvaluationDescription: "Unrecognized or disabled flag: \(flagKey)",
        entityId: nil
      )
    }

    return evaluateFlag(
      flag: flagConfigPb,
      subjectKey: subjectKey,
      subjectAttributes: subjectAttributes,
      isConfigObfuscated: isConfigObfuscated
    )
  }

  private func matchesShard(
    shard: Ufc_ShardDto,
    subjectKey: String,
    totalShards: Int,
    isConfigObfuscated: Bool
  ) -> Bool {
    assert(totalShards > 0, "Expect totalShards to be strictly positive")

    let salt = isConfigObfuscated ? base64Decode(shard.salt) : shard.salt

    if let salt = salt {
      let h = self.sharder.getShard(
        input: hashKey(salt: salt, subjectKey: subjectKey), totalShards: totalShards)
      return shard.ranges.contains { range in
        isInShardRange(shard: h, range: range)
      }
    }

    // If the salt is not valid, return false
    return false
  }

  private func matchesRule(
    subjectAttributes: SubjectAttributes,
    rule: Ufc_RuleDto,
    isConfigObfuscated: Bool,
    subjectKey: String
  ) -> Bool {
    // Check that all conditions within the rule are met
    return rule.conditions.allSatisfy { condition in
      // If the condition throws an error, consider this not matching.
      return evaluateCondition(
        subjectAttributes: subjectAttributes,
        condition: condition,
        isConfigObfuscated: isConfigObfuscated,
        subjectKey: subjectKey
      )
    }
  }

  private func isInShardRange(shard: Int, range: Ufc_RangeDto) -> Bool {
    return Int(range.start) <= shard && shard < Int(range.end)
  }

  private func hashKey(salt: String, subjectKey: String) -> String {
    return salt + "-" + subjectKey
  }

  private func evaluateCondition(
    subjectAttributes: SubjectAttributes,
    condition: Ufc_TargetingRuleCondition,
    isConfigObfuscated: Bool,
    subjectKey: String
  ) -> Bool {
    // attribute names are hashed if obfuscated
    let attributeKey = condition.attribute
    var attributeValue: EppoValue?

    // First check if the attribute exists in subject attributes
    if isConfigObfuscated {
      for (key, value) in subjectAttributes {
        if getMD5Hex(key) == attributeKey {
          attributeValue = value
          break
        }
      }
    } else {
      attributeValue = subjectAttributes[condition.attribute]
    }

    // If not found in attributes and the attribute is "id", use the subject key
    if attributeValue == nil {
      let idKey = isConfigObfuscated ? getMD5Hex("id") : "id"
      if attributeKey == idKey {
        attributeValue = EppoValue.valueOf(subjectKey)
      }
    }

    // First we do any NULL check
    let attributeValueIsNull = attributeValue?.isNull() ?? true

    // Convert protobuf operator string to UFC_RuleConditionOperator
    let operatorEnum = UFC_RuleConditionOperator.fromString(condition.operator)

    if operatorEnum == .isNull {
      if isConfigObfuscated, let stringValue = getStringFromProtobufValue(condition.value) {
        let expectNull: Bool = getMD5Hex("true") == stringValue
        return expectNull == attributeValueIsNull
      } else if let boolValue = getBoolFromProtobufValue(condition.value) {
        let expectNull: Bool = boolValue
        return expectNull == attributeValueIsNull
      }
    } else if attributeValueIsNull {
      // Any check other than IS NULL should fail if the attribute value is null
      return false
    }

    // Safely unwrap attributeValue for further use
    guard let value = attributeValue else {
      return false
    }

    switch operatorEnum {
    case .greaterThanEqual, .greaterThan, .lessThanEqual, .lessThan:
      let valueStr = try? value.getStringValue()

      // If the config is obfuscated, we need to unobfuscate the condition value
      var conditionValueStr = getStringFromProtobufValue(condition.value)
      if isConfigObfuscated,
        let cvs = conditionValueStr,
        let decoded = base64Decode(cvs)
      {
        conditionValueStr = decoded
      }

      if let valueVersion = valueStr.flatMap(Semver.init),
        let conditionVersion = conditionValueStr.flatMap(Semver.init)
      {
        // If both strings are valid Semver strings, perform a Semver comparison
        switch operatorEnum {
        case .greaterThanEqual:
          return valueVersion >= conditionVersion
        case .greaterThan:
          return valueVersion > conditionVersion
        case .lessThanEqual:
          return valueVersion <= conditionVersion
        case .lessThan:
          return valueVersion < conditionVersion
        default:
          return false
        }
      } else {
        // If either string is not a valid Semver, fall back to double comparison
        guard let valueDouble = try? value.getDoubleValue() else {
          return false
        }

        // If the config is obfuscated, we need to unobfuscate the condition value
        var conditionDouble: Double
        if isConfigObfuscated,
          let cvs = conditionValueStr,
          let doubleValue = Double(cvs)
        {
          conditionDouble = doubleValue
        } else if let doubleValue = getDoubleFromProtobufValue(condition.value) {
          conditionDouble = doubleValue
        } else {
          return false
        }

        switch operatorEnum {
        case .greaterThanEqual:
          return valueDouble >= conditionDouble
        case .greaterThan:
          return valueDouble > conditionDouble
        case .lessThanEqual:
          return valueDouble <= conditionDouble
        case .lessThan:
          return valueDouble < conditionDouble
        default:
          return false
        }
      }
    case .matches, .notMatches:
      if let conditionString = getStringFromProtobufValue(condition.value),
        let valueString = try? value.toEppoString()
      {
        if isConfigObfuscated,
          let decoded = base64Decode(conditionString)
        {
          return operatorEnum == .matches
            ? Compare.matchesRegex(valueString, decoded)
            : !Compare.matchesRegex(valueString, decoded)
        } else {
          return operatorEnum == .matches
            ? Compare.matchesRegex(valueString, conditionString)
            : !Compare.matchesRegex(valueString, conditionString)
        }
      }
      return false
    case .oneOf, .notOneOf:
      if let valueString = try? value.toEppoString(),
        let conditionArray = getStringArrayFromProtobufValue(condition.value)
      {
        if isConfigObfuscated {
          let valueStringHash = getMD5Hex(valueString)
          return operatorEnum == .oneOf
            ? Compare.isOneOf(valueStringHash, conditionArray)
            : !Compare.isOneOf(valueStringHash, conditionArray)
        } else {
          return operatorEnum == .oneOf
            ? Compare.isOneOf(valueString, conditionArray)
            : !Compare.isOneOf(valueString, conditionArray)
        }
      }
      return false
    default:
      return false
    }
  }

  // MARK: - Conversion Utilities

  private func convertVariationTypeToUFC(_ pbType: Ufc_ExperimentVariationValueType)
    -> UFC_VariationType
  {
    switch pbType {
    case .boolean:
      return .boolean
    case .integer:
      return .integer
    case .numeric:
      return .numeric
    case .string:
      return .string
    case .json:
      return .json
    default:
      return .string
    }
  }

  private func convertVariationToUFC(_ pbVariation: Ufc_VariationDto) -> UFC_Variation {
    let eppoValue: EppoValue

    switch pbVariation.value {
    case .boolValue(let boolVal):
      eppoValue = EppoValue.valueOf(boolVal)
    case .numberValue(let doubleVal):
      eppoValue = EppoValue.valueOf(doubleVal)
    case .stringValue(let stringVal):
      eppoValue = EppoValue.valueOf(stringVal)
    case .none:
      eppoValue = EppoValue.nullValue()
    }

    return UFC_Variation(key: pbVariation.key, value: eppoValue)
  }

    
  private func convertAllocationToUFC(_ pbAllocation: Ufc_AllocationDto) -> UFC_Allocation {
    // Only convert to Date objects when needed for UFC_Allocation compatibility
    let startAt =
      pbAllocation.hasStartAtMs
      ? Date(timeIntervalSince1970: Double(pbAllocation.startAtMs) / 1000.0) : nil
    let endAt =
      pbAllocation.hasEndAtMs
      ? Date(timeIntervalSince1970: Double(pbAllocation.endAtMs) / 1000.0) : nil

    let rules = pbAllocation.rules.map { convertRuleToUFC($0) }
    let splits = pbAllocation.splits.map { convertSplitToUFC($0) }

    return UFC_Allocation(
      key: pbAllocation.key,
      rules: rules.isEmpty ? nil : rules,
      startAt: startAt,
      endAt: endAt,
      splits: splits,
      doLog: pbAllocation.doLog
    )
  }

  private func convertRuleToUFC(_ pbRule: Ufc_RuleDto) -> UFC_Rule {
    let conditions = pbRule.conditions.map { convertConditionToUFC($0) }
    return UFC_Rule(conditions: conditions)
  }

  private func convertConditionToUFC(_ pbCondition: Ufc_TargetingRuleCondition)
    -> UFC_TargetingRuleCondition
  {
    let operatorEnum = UFC_RuleConditionOperator.fromString(pbCondition.operator)

    let eppoValue: EppoValue
    switch pbCondition.value {
    case .numberValue(let doubleVal):
      eppoValue = EppoValue.valueOf(doubleVal)
    case .boolValue(let boolVal):
      eppoValue = EppoValue.valueOf(boolVal)
    case .stringValue(let stringVal):
      eppoValue = EppoValue.valueOf(stringVal)
    case .stringArrayValue(let arrayVal):
      eppoValue = EppoValue.valueOf(arrayVal.values)
    case .none:
      eppoValue = EppoValue.nullValue()
    }

    return UFC_TargetingRuleCondition(
      operator: operatorEnum,
      attribute: pbCondition.attribute,
      value: eppoValue
    )
  }

  private func convertSplitToUFC(_ pbSplit: Ufc_SplitDto) -> UFC_Split {
    let shards = pbSplit.shards.map { convertShardToUFC($0) }
    return UFC_Split(
      variationKey: pbSplit.variationKey,
      shards: shards,
      extraLogging: pbSplit.extraLogging.isEmpty ? nil : pbSplit.extraLogging
    )
  }

  private func convertShardToUFC(_ pbShard: Ufc_ShardDto) -> UFC_Shard {
    let ranges = pbShard.ranges.map { convertRangeToUFC($0) }
    return UFC_Shard(salt: pbShard.salt, ranges: ranges)
  }

  private func convertRangeToUFC(_ pbRange: Ufc_RangeDto) -> UFC_Range {
    return UFC_Range(start: Int(pbRange.start), end: Int(pbRange.end))
  }

  // MARK: - Protobuf Value Extraction Utilities

  private func getStringFromProtobufValue(_ value: Ufc_TargetingRuleCondition.OneOf_Value?)
    -> String?
  {
    switch value {
    case .stringValue(let stringVal):
      return stringVal
    default:
      return nil
    }
  }

  private func getBoolFromProtobufValue(_ value: Ufc_TargetingRuleCondition.OneOf_Value?) -> Bool? {
    switch value {
    case .boolValue(let boolVal):
      return boolVal
    default:
      return nil
    }
  }

  private func getDoubleFromProtobufValue(_ value: Ufc_TargetingRuleCondition.OneOf_Value?)
    -> Double?
  {
    switch value {
    case .numberValue(let doubleVal):
      return doubleVal
    default:
      return nil
    }
  }

  private func getStringArrayFromProtobufValue(_ value: Ufc_TargetingRuleCondition.OneOf_Value?)
    -> [String]?
  {
    switch value {
    case .stringArrayValue(let arrayVal):
      return arrayVal.values
    default:
      return nil
    }
  }
}

// MARK: - Extensions

extension UFC_RuleConditionOperator {
  static func fromString(_ operatorString: String) -> UFC_RuleConditionOperator {
    switch operatorString {
    case "LT":
      return .lessThan
    case "LTE":
      return .lessThanEqual
    case "GT":
      return .greaterThan
    case "GTE":
      return .greaterThanEqual
    case "MATCHES":
      return .matches
    case "NOT_MATCHES":
      return .notMatches
    case "ONE_OF":
      return .oneOf
    case "NOT_ONE_OF":
      return .notOneOf
    case "IS_NULL":
      return .isNull
    default:
      return .isNull  // Default fallback
    }
  }
}
