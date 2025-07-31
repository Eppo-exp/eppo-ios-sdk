import Foundation

public struct FlagEvaluation {
    let flagKey: String
    let subjectKey: String
    let subjectAttributes: SubjectAttributes
    let allocationKey: String?
    let variation: UFC_Variation?
    let variationType: UFC_VariationType?
    let extraLogging: [String: String]
    let doLog: Bool
    let matchedRule: UFC_Rule?
    let matchedAllocation: AllocationEvaluation?
    let unmatchedAllocations: [AllocationEvaluation]
    let unevaluatedAllocations: [AllocationEvaluation]
    let flagEvaluationCode: EppoClient.FlagEvaluationCode
    let flagEvaluationDescription: String
    let entityId: Int?

    static func matchedResult(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        allocationKey: String?,
        variation: UFC_Variation?,
        variationType: UFC_VariationType?,
        extraLogging: [String: String],
        doLog: Bool,
        isConfigObfuscated: Bool,
        matchedRule: UFC_Rule? = nil,
        matchedAllocation: AllocationEvaluation? = nil,
        allocation: UFC_Allocation? = nil,
        unmatchedAllocations: [AllocationEvaluation] = [],
        unevaluatedAllocations: [AllocationEvaluation] = [],
        entityId: Int? = nil
    ) -> FlagEvaluation {
        // If the config is obfuscated, we need to unobfuscate the allocation key.
        var decodedAllocationKey: String = allocationKey ?? ""
        if isConfigObfuscated,
           let allocationKey = allocationKey,
           let decoded = base64Decode(allocationKey) {
            decodedAllocationKey = decoded
        }

        var decodedVariation: UFC_Variation? = variation
        if isConfigObfuscated,
           let variation = variation,
           let variationType = variationType,
           let decodedVariationKey = base64Decode(variation.key),
           let variationValue = try? variation.value.getStringValue(),
           let decodedVariationValue = base64Decode(variationValue) {

            var decodedValue: EppoValue = EppoValue.nullValue()

            switch variationType {
            case .boolean:
                decodedValue = EppoValue(value: "true" == decodedVariationValue)
            case .integer, .numeric:
                if let doubleValue = Double(decodedVariationValue) {
                    decodedValue = EppoValue(value: doubleValue)
                }
            case .string, .json:
                decodedValue = EppoValue(value: decodedVariationValue)
            }

            decodedVariation = UFC_Variation(key: decodedVariationKey, value: decodedValue)
        }

        // If the config is obfuscated, we need to unobfuscate the extraLogging values
        var decodedExtraLogging: [String: String] = extraLogging
        if isConfigObfuscated {
            decodedExtraLogging = [:]
            for (key, value) in extraLogging {
                // Decode both key and value if they are base64 encoded
                let decodedKey = base64Decode(key) ?? key
                let decodedValue = base64Decode(value) ?? value
                decodedExtraLogging[decodedKey] = decodedValue
            }
        }

        // Generate the detailed match description
        let flagEvaluationDescription: String
        if let allocation = allocation {
            let hasDefinedRules = !(allocation.rules?.isEmpty ?? true)
            let isExperiment = allocation.splits.count > 1
            let isPartialRollout = allocation.splits.first?.shards.count ?? 0 > 1
            let isExperimentOrPartialRollout = isExperiment || isPartialRollout

            flagEvaluationDescription = EvaluationDescription.getDescription(
                hasDefinedRules: hasDefinedRules,
                isExperimentOrPartialRollout: isExperimentOrPartialRollout,
                allocationKey: allocation.key,
                subjectKey: subjectKey,
                variationKey: decodedVariation?.key ?? ""
            )
        } else {
            flagEvaluationDescription = "Flag matched"
        }

        return FlagEvaluation(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: decodedAllocationKey,
            variation: decodedVariation,
            variationType: variationType,
            extraLogging: decodedExtraLogging,
            doLog: doLog,
            matchedRule: matchedRule,
            matchedAllocation: matchedAllocation,
            unmatchedAllocations: unmatchedAllocations,
            unevaluatedAllocations: unevaluatedAllocations,
            flagEvaluationCode: .match,
            flagEvaluationDescription: flagEvaluationDescription,
            entityId: entityId
        )
    }

    static func noneResult(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        flagEvaluationCode: EppoClient.FlagEvaluationCode = .flagUnrecognizedOrDisabled,
        flagEvaluationDescription: String? = nil,
        unmatchedAllocations: [AllocationEvaluation] = [],
        unevaluatedAllocations: [AllocationEvaluation] = [],
        entityId: Int? = nil
    ) -> FlagEvaluation {
        return FlagEvaluation(
            flagKey: flagKey,
            subjectKey: subjectKey,
            subjectAttributes: subjectAttributes,
            allocationKey: Optional<String>.none,
            variation: Optional<UFC_Variation>.none,
            variationType: Optional<UFC_VariationType>.none,
            extraLogging: [:],
            doLog: false,
            matchedRule: nil,
            matchedAllocation: nil,
            unmatchedAllocations: unmatchedAllocations,
            unevaluatedAllocations: unevaluatedAllocations,
            flagEvaluationCode: flagEvaluationCode,
            flagEvaluationDescription: flagEvaluationDescription ?? "Unrecognized or disabled flag: \(flagKey)",
            entityId: entityId
        )
    }
}

public struct AllocationEvaluation {
    public let key: String
    public let allocationEvaluationCode: EppoClient.AllocationEvaluationCode
    public let orderPosition: Int
}
