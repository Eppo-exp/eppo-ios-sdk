import Foundation

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
    let subject: Subject
    
    init(
        flags: [String: PrecomputedFlag],
        salt: String,
        format: String,
        configFetchedAt: Date,
        subject: Subject,
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
    
    /// Initialize from precomputed configuration string (from the Node SDK's getPrecomputedConfiguration method)
    public init(precomputedConfiguration: String) throws {
        guard let data = precomputedConfiguration.data(using: .utf8) else {
            throw EncodingError.invalidValue(precomputedConfiguration, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert precomputed configuration string to UTF-8 data"
            ))
        }
        try self.init(precomputedConfigurationJson: data)
    }
    
    internal init(precomputedConfigurationJson: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wireFormat = try decoder.decode(PrecomputedConfigurationWireFormat.self, from: precomputedConfigurationJson)
        
        // Parse the inner response JSON
        let responseData = wireFormat.precomputed.response.data(using: .utf8) ?? Data()
        let responseDecoded = try decoder.decode(PrecomputedConfigurationFromJSON.self, from: responseData)
        
        self.flags = responseDecoded.flags
        self.salt = responseDecoded.salt
        self.format = responseDecoded.format
        self.configFetchedAt = wireFormat.precomputed.fetchedAt
        self.configPublishedAt = responseDecoded.configPublishedAt
        self.environment = responseDecoded.environment
        
        // Convert wire format subject to internal Subject
        self.subject = Subject(
            subjectKey: wireFormat.precomputed.subjectKey,
            subjectAttributes: wireFormat.precomputed.subjectAttributes.toDictionary()
        )
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
        subject = try container.decode(Subject.self, forKey: .subject)
        
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

// MARK: - Wire Format Structure

private struct PrecomputedConfigurationWireFormat: Decodable {
    let version: Int
    let precomputed: PrecomputedWireData
}

private struct PrecomputedWireData: Decodable {
    let subjectKey: String
    let subjectAttributes: WireSubjectAttributes
    let fetchedAt: Date
    let response: String
    
    private enum CodingKeys: String, CodingKey {
        case subjectKey, subjectAttributes, fetchedAt, response
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        subjectKey = try container.decode(String.self, forKey: .subjectKey)
        subjectAttributes = try container.decode(WireSubjectAttributes.self, forKey: .subjectAttributes)
        response = try container.decode(String.self, forKey: .response)
        
        // Parse fetchedAt with custom date handling
        let fetchedAtString = try container.decode(String.self, forKey: .fetchedAt)
        if let parsedDate = parseUtcISODateElement(fetchedAtString) {
            fetchedAt = parsedDate
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to parse fetchedAt date: \(fetchedAtString)"
            ))
        }
    }
}

private struct WireSubjectAttributes: Decodable {
    let categoricalAttributes: [String: EppoValue]?
    let numericAttributes: [String: EppoValue]?
    
    func toDictionary() -> [String: EppoValue] {
        var result: [String: EppoValue] = [:]
        
        if let categorical = categoricalAttributes {
            result.merge(categorical) { _, new in new }
        }
        
        if let numeric = numericAttributes {
            result.merge(numeric) { _, new in new }
        }
        
        return result
    }
}

// MARK: - Internal Subject Type

/// Internal subject representation specifically for precomputed flag assignments
/// Used for storing subject data (subjectKey + subjectAttributes) extracted from:
/// - Precompute objects (online initialization input)
/// - Network configuration responses (wire format and direct JSON)
struct Subject: Codable {
    let subjectKey: String
    let subjectAttributes: [String: EppoValue]
    
    init(subjectKey: String, subjectAttributes: [String: EppoValue] = [:]) {
        self.subjectKey = subjectKey
        self.subjectAttributes = subjectAttributes
    }
}
