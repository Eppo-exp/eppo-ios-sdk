import Foundation

public struct Precompute: Codable {
    /// The unique identifier for the subject
    public let subjectKey: String

    /// Additional attributes associated with the subject
    public let subjectAttributes: [String: EppoValue]

    /// Bandit actions available for each flag
    /// Structure: flagKey -> actionKey -> attributes
    public let banditActions: [String: [String: [String: EppoValue]]]?

    public init(
        subjectKey: String,
        subjectAttributes: [String: EppoValue] = [:],
        banditActions: [String: [String: [String: EppoValue]]]? = nil
    ) {
        self.subjectKey = subjectKey
        self.subjectAttributes = subjectAttributes
        self.banditActions = banditActions
    }
}
