import Foundation

/// Represents the configuration for precomputed flag assignments
public struct PrecomputedConfiguration: Codable {
    /// Map of flag keys to precomputed flag assignments
    let flags: [String: PrecomputedFlag]
    
    /// Salt used for obfuscation (always present for precomputed)
    public let salt: String
    
    /// Configuration format (should be "PRECOMPUTED")
    public let format: String
    
    /// Timestamp when the configuration was fetched
    public let configFetchedAt: Date
    
    /// Timestamp when the configuration was published (optional)
    public let configPublishedAt: Date?
    
    /// Environment information
    public let environment: Environment?
    
    // MARK: - Initialization
    
    init(
        flags: [String: PrecomputedFlag],
        salt: String,
        format: String,
        configFetchedAt: Date,
        configPublishedAt: Date? = nil,
        environment: Environment? = nil
    ) {
        self.flags = flags
        self.salt = salt
        self.format = format
        self.configFetchedAt = configFetchedAt
        self.configPublishedAt = configPublishedAt
        self.environment = environment
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case flags
        case salt
        case format
        case createdAt
        case environment
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
    }
}

