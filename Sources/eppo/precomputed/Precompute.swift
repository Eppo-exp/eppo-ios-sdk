import Foundation

public struct Precompute: Codable {
    /// The unique identifier for the subject
    public let subjectKey: String
    
    /// Additional attributes associated with the subject
    public let subjectAttributes: [String: EppoValue]
    
    public init(subjectKey: String, subjectAttributes: [String: EppoValue] = [:]) {
        self.subjectKey = subjectKey
        self.subjectAttributes = subjectAttributes
    }
}
