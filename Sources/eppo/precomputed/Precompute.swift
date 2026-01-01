import Foundation

/// Represents the precompute configuration for precomputed flag assignments
/// Contains subject information and attributes used for flag evaluation
public struct Precompute: Codable {
    /// The unique identifier for the subject
    public let subjectKey: String
    
    /// Additional attributes associated with the subject
    public let subjectAttributes: [String: EppoValue]
    
    // MARK: - Initialization
    
    public init(subjectKey: String, subjectAttributes: [String: EppoValue] = [:]) {
        self.subjectKey = subjectKey
        self.subjectAttributes = subjectAttributes
    }
}