import Foundation
@testable import EppoFlagging

/// Creates a PrecomputedFlag with base64-encoded values from unhashed and unencoded inputs
func createTestFlag(
    allocationKey: String? = nil,
    variationKey: String? = nil,
    variationType: VariationType,
    variationValue: Any,
    extraLogging: [String: String] = [:],
    doLog: Bool = true
) -> PrecomputedFlag {
    let encodedAllocationKey = allocationKey.map { base64Encode($0) }
    let encodedVariationKey = variationKey.map { base64Encode($0) }

    // All variation values are base64-encoded strings in the wire format
    let encodedVariationValue: EppoValue
    switch variationType {
    case .string, .json:
        if let stringValue = variationValue as? String {
            encodedVariationValue = EppoValue(value: base64Encode(stringValue))
        } else {
            fatalError("STRING and JSON variation values must be String type")
        }
    case .boolean:
        if let boolValue = variationValue as? Bool {
            encodedVariationValue = EppoValue(value: base64Encode(boolValue ? "true" : "false"))
        } else if let stringValue = variationValue as? String {
            // Allow passing raw string for edge case testing (e.g., "not a boolean")
            encodedVariationValue = EppoValue(value: base64Encode(stringValue))
        } else {
            fatalError("BOOLEAN variation values must be Bool or String type")
        }
    case .integer:
        if let doubleValue = variationValue as? Double {
            let intValue = Int(doubleValue)
            encodedVariationValue = EppoValue(value: base64Encode(String(intValue)))
        } else if let intValue = variationValue as? Int {
            encodedVariationValue = EppoValue(value: base64Encode(String(intValue)))
        } else {
            fatalError("INTEGER variation values must be Double or Int type")
        }
    case .numeric:
        if let doubleValue = variationValue as? Double {
            encodedVariationValue = EppoValue(value: base64Encode(String(doubleValue)))
        } else if let intValue = variationValue as? Int {
            encodedVariationValue = EppoValue(value: base64Encode(String(intValue)))
        } else {
            fatalError("NUMERIC variation values must be Double or Int type")
        }
    }

    var encodedExtraLogging: [String: String] = [:]
    for (key, value) in extraLogging {
        encodedExtraLogging[base64Encode(key)] = base64Encode(value)
    }

    return PrecomputedFlag(
        allocationKey: encodedAllocationKey,
        variationKey: encodedVariationKey,
        variationType: variationType,
        variationValue: encodedVariationValue,
        extraLogging: encodedExtraLogging,
        doLog: doLog
    )
}

func createTestFlags(_ flags: [(key: String, flag: PrecomputedFlag)], salt: String = "test-salt") -> [String: PrecomputedFlag] {
    var result: [String: PrecomputedFlag] = [:]
    for (key, flag) in flags {
        let hashedKey = getMD5Hex(key, salt: salt)
        result[hashedKey] = flag
    }
    return result
}

/// Creates a PrecomputedBandit with base64-encoded values from unencoded inputs
func createTestBandit(
    banditKey: String,
    action: String? = nil,
    modelVersion: String? = nil,
    actionNumericAttributes: [String: Double] = [:],
    actionCategoricalAttributes: [String: String] = [:],
    actionProbability: Double,
    optimalityGap: Double
) -> PrecomputedBandit {
    let encodedBanditKey = base64Encode(banditKey)
    let encodedAction = action.map { base64Encode($0) }
    let encodedModelVersion = modelVersion.map { base64Encode($0) }

    // Encode numeric attributes: both keys and values are base64 encoded
    var encodedNumericAttributes: [String: String] = [:]
    for (key, value) in actionNumericAttributes {
        encodedNumericAttributes[base64Encode(key)] = base64Encode(String(value))
    }

    // Encode categorical attributes: both keys and values are base64 encoded
    var encodedCategoricalAttributes: [String: String] = [:]
    for (key, value) in actionCategoricalAttributes {
        encodedCategoricalAttributes[base64Encode(key)] = base64Encode(value)
    }

    return PrecomputedBandit(
        banditKey: encodedBanditKey,
        action: encodedAction,
        modelVersion: encodedModelVersion,
        actionNumericAttributes: encodedNumericAttributes.isEmpty ? nil : encodedNumericAttributes,
        actionCategoricalAttributes: encodedCategoricalAttributes.isEmpty ? nil : encodedCategoricalAttributes,
        actionProbability: actionProbability,
        optimalityGap: optimalityGap
    )
}

func createTestBandits(_ bandits: [(key: String, bandit: PrecomputedBandit)], salt: String = "test-salt") -> [String: PrecomputedBandit] {
    var result: [String: PrecomputedBandit] = [:]
    for (key, bandit) in bandits {
        let hashedKey = getMD5Hex(key, salt: salt)
        result[hashedKey] = bandit
    }
    return result
}
