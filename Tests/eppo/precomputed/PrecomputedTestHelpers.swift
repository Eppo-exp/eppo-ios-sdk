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

    let encodedVariationValue: EppoValue
    switch variationType {
    case .STRING, .JSON:
        if let stringValue = variationValue as? String {
            encodedVariationValue = EppoValue(value: base64Encode(stringValue))
        } else {
            fatalError("STRING and JSON variation values must be String type")
        }
    case .BOOLEAN:
        if let boolValue = variationValue as? Bool {
            encodedVariationValue = EppoValue(value: boolValue)
        } else if let stringValue = variationValue as? String {
            encodedVariationValue = EppoValue(value: base64Encode(stringValue))
        } else {
            fatalError("BOOLEAN variation values must be Bool or String type")
        }
    case .INTEGER:
        if let doubleValue = variationValue as? Double {
            encodedVariationValue = EppoValue(value: doubleValue)
        } else if let intValue = variationValue as? Int {
            encodedVariationValue = EppoValue(value: intValue)
        } else {
            fatalError("INTEGER variation values must be Double or Int type")
        }
    case .NUMERIC:
        if let doubleValue = variationValue as? Double {
            encodedVariationValue = EppoValue(value: doubleValue)
        } else if let intValue = variationValue as? Int {
            encodedVariationValue = EppoValue(value: intValue)
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
