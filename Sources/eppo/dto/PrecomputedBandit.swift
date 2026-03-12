import Foundation

/// Represents a precomputed bandit assignment from the server.
/// String fields are Base64 encoded in the wire format.
struct PrecomputedBandit: Codable, Equatable {
    let banditKey: String
    let action: String?
    let modelVersion: String?
    let actionNumericAttributes: [String: String]?
    let actionCategoricalAttributes: [String: String]?
    let actionProbability: Double
    let optimalityGap: Double

    init(
        banditKey: String,
        action: String?,
        modelVersion: String?,
        actionNumericAttributes: [String: String]? = nil,
        actionCategoricalAttributes: [String: String]? = nil,
        actionProbability: Double,
        optimalityGap: Double
    ) {
        self.banditKey = banditKey
        self.action = action
        self.modelVersion = modelVersion
        self.actionNumericAttributes = actionNumericAttributes
        self.actionCategoricalAttributes = actionCategoricalAttributes
        self.actionProbability = actionProbability
        self.optimalityGap = optimalityGap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        banditKey = try container.decode(String.self, forKey: .banditKey)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        modelVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion)
        actionNumericAttributes = try container.decodeIfPresent([String: String].self, forKey: .actionNumericAttributes)
        actionCategoricalAttributes = try container.decodeIfPresent([String: String].self, forKey: .actionCategoricalAttributes)
        actionProbability = try container.decodeIfPresent(Double.self, forKey: .actionProbability) ?? 0.0
        optimalityGap = try container.decodeIfPresent(Double.self, forKey: .optimalityGap) ?? 0.0
    }

    private enum CodingKeys: String, CodingKey {
        case banditKey
        case action
        case modelVersion
        case actionNumericAttributes
        case actionCategoricalAttributes
        case actionProbability
        case optimalityGap
    }
}

/// Decoded version of PrecomputedBandit with Base64-decoded string fields
struct DecodedPrecomputedBandit: Codable, Equatable {
    let banditKey: String
    let action: String?
    let modelVersion: String?
    let actionNumericAttributes: [String: Double]
    let actionCategoricalAttributes: [String: String]
    let actionProbability: Double
    let optimalityGap: Double
}
