import Foundation

/// Subject information specifically for precomputed configurations
/// This is a Codable version that can be serialized/deserialized with JSON
public struct PrecomputedSubject: Codable {
    public let subjectKey: String
    public let subjectAttributes: [String: EppoValue]
    
    public init(subjectKey: String, subjectAttributes: [String: EppoValue] = [:]) {
        self.subjectKey = subjectKey
        self.subjectAttributes = subjectAttributes
    }
    
    /// Create PrecomputedSubject from regular Subject
    public init(from subject: Subject) {
        self.subjectKey = subject.subjectKey
        self.subjectAttributes = subject.subjectAttributes
    }
    
    /// Convert to regular Subject for use with assignment logging
    public func toSubject() -> Subject {
        return Subject(subjectKey: subjectKey, subjectAttributes: subjectAttributes)
    }
}

/// Represents the configuration for precomputed flag assignments
public struct PrecomputedConfiguration: Codable {
    let flags: [String: PrecomputedFlag]
    
    /// Salt used for obfuscation (always present for precomputed)
    public let salt: String
    
    /// Configuration format (should be "PRECOMPUTED")
    public let format: String
    
    public let configFetchedAt: Date
    
    /// Timestamp when the configuration was published (optional)
    public let configPublishedAt: Date?
    
    public let environment: Environment?
    
    /// Subject information that this configuration was generated for
    public let subject: PrecomputedSubject
    
    init(
        flags: [String: PrecomputedFlag],
        salt: String,
        format: String,
        configFetchedAt: Date,
        subject: PrecomputedSubject,
        configPublishedAt: Date? = nil,
        environment: Environment? = nil
    ) {
        self.flags = flags
        self.salt = salt
        self.format = format
        self.configFetchedAt = configFetchedAt
        self.configPublishedAt = configPublishedAt
        self.environment = environment
        self.subject = subject
    }
    
    public init(precomputedConfigurationJson: Data, subject: Subject) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PrecomputedConfigurationFromJSON.self, from: precomputedConfigurationJson)
        
        self.flags = decoded.flags
        self.salt = decoded.salt
        self.format = decoded.format
        self.configFetchedAt = Date() // Always use current time when parsing
        self.configPublishedAt = decoded.configPublishedAt
        self.environment = decoded.environment
        self.subject = PrecomputedSubject(from: subject) // Convert Subject to PrecomputedSubject
    }
}

/// Helper struct for parsing JSON configuration without embedded subject
private struct PrecomputedConfigurationFromJSON: Decodable {
    let flags: [String: PrecomputedFlag]
    let salt: String
    let format: String
    let configPublishedAt: Date?
    let environment: Environment?
    
    private enum CodingKeys: String, CodingKey {
        case flags
        case salt
        case format
        case createdAt
        case environment
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        flags = try container.decode([String: PrecomputedFlag].self, forKey: .flags)
        salt = try container.decode(String.self, forKey: .salt)
        format = try container.decode(String.self, forKey: .format)
        
        // Handle dates with base64 support
        if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            configPublishedAt = parseUtcISODateElement(createdAtString)
        } else {
            configPublishedAt = nil
        }
        
        environment = try container.decodeIfPresent(Environment.self, forKey: .environment)
    }
}

extension PrecomputedConfiguration {
    
    private enum CodingKeys: String, CodingKey {
        case flags
        case salt
        case format
        case createdAt
        case environment
        case subject
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        flags = try container.decode([String: PrecomputedFlag].self, forKey: .flags)
        salt = try container.decode(String.self, forKey: .salt)
        format = try container.decode(String.self, forKey: .format)
        
        // Handle dates with base64 support
        if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            configPublishedAt = parseUtcISODateElement(createdAtString)
        } else {
            configPublishedAt = nil
        }
        
        configFetchedAt = Date()
        
        environment = try container.decodeIfPresent(Environment.self, forKey: .environment)
        subject = try container.decode(PrecomputedSubject.self, forKey: .subject)
        
        // Note: obfuscated field is always true for precomputed configs, so we ignore it
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(flags, forKey: .flags)
        try container.encode(salt, forKey: .salt)
        try container.encode(format, forKey: .format)
        
        if let publishedAt = configPublishedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: publishedAt), forKey: .createdAt)
        }
        
        try container.encodeIfPresent(environment, forKey: .environment)
        try container.encode(subject, forKey: .subject)
    }
}
