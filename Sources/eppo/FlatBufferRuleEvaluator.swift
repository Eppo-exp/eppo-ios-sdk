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

        // Simplified evaluation - find first allocation and return first variation
        // This is a minimal implementation for performance testing
        let allocationsCount = fbFlag.allocationsCount
        if allocationsCount > 0, let allocation = fbFlag.allocations(at: 0) {
            let splitsCount = allocation.splitsCount
            if splitsCount > 0, let split = allocation.splits(at: 0) {
                if let variationKey = split.variationKey,
                   let variation = findVariation(in: fbFlag, variationKey: variationKey) {

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

        // No valid allocation found
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
            eppoValue = EppoValue(value: valueString.lowercased() == "true")
        case .integer:
            eppoValue = EppoValue(value: Int(valueString) ?? 0)
        case .numeric:
            eppoValue = EppoValue(value: Double(valueString) ?? 0.0)
        case .string, .json:
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
}