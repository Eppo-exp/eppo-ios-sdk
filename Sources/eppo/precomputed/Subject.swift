import Foundation

/// Represents a subject (user/entity) for precomputed flag assignments
struct Subject: Codable, Hashable {
    /// The unique identifier for the subject
    let subjectKey: String
    
    /// Additional attributes associated with the subject
    let subjectAttributes: [String: EppoValue]
    
    // MARK: - Initialization
    
    init(subjectKey: String, subjectAttributes: [String: EppoValue] = [:]) {
        self.subjectKey = subjectKey
        self.subjectAttributes = subjectAttributes
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(subjectKey)
        // Note: We can't hash subjectAttributes directly because EppoValue isn't Hashable
        // For now, we'll just hash the subject key which should be unique
    }
    
    // MARK: - Equatable
    
    static func == (lhs: Subject, rhs: Subject) -> Bool {
        if lhs.subjectKey != rhs.subjectKey {
            return false
        }
        
        // Compare attributes by key and value
        if lhs.subjectAttributes.count != rhs.subjectAttributes.count {
            return false
        }
        
        for (key, lhsValue) in lhs.subjectAttributes {
            guard let rhsValue = rhs.subjectAttributes[key] else {
                return false
            }
            if lhsValue != rhsValue {
                return false
            }
        }
        
        return true
    }
}