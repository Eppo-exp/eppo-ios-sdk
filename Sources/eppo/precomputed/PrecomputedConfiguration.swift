import Foundation

/// Represents the configuration for precomputed flag assignments
public struct PrecomputedConfiguration: Codable {
    let flags: [String: PrecomputedFlag]
    internal let salt: String
    internal let format: String
    internal let fetchedAt: Date
    internal let publishedAt: Date
    internal let environment: Environment?
    let subject: Subject

    init(
        flags: [String: PrecomputedFlag],
        salt: String,
        format: String,
        fetchedAt: Date,
        subject: Subject,
        publishedAt: Date,
        environment: Environment? = nil
    ) {
        self.flags = flags
        self.salt = salt
        self.format = format
        self.fetchedAt = fetchedAt
        self.publishedAt = publishedAt
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
        self.fetchedAt = wireFormat.precomputed.fetchedAt
        self.publishedAt = responseDecoded.publishedAt
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
    let publishedAt: Date
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

        publishedAt = try decodeRequiredDate(from: container, forKey: .createdAt, fieldName: "createdAt", decoder: decoder)

        environment = try container.decodeIfPresent(Environment.self, forKey: .environment)
    }
}

extension PrecomputedConfiguration {

    private enum CodingKeys: String, CodingKey {
        case flags
        case salt
        case format
        case createdAt
        case fetchedAt
        case environment
        case subject
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        flags = try container.decode([String: PrecomputedFlag].self, forKey: .flags)
        salt = try container.decode(String.self, forKey: .salt)
        format = try container.decode(String.self, forKey: .format)

        publishedAt = try decodeRequiredDate(from: container, forKey: .createdAt, fieldName: "createdAt", decoder: decoder)
        fetchedAt = try decodeRequiredDate(from: container, forKey: .fetchedAt, fieldName: "fetchedAt", decoder: decoder)

        environment = try container.decodeIfPresent(Environment.self, forKey: .environment)
        subject = try container.decode(Subject.self, forKey: .subject)

        // Note: obfuscated field is always true for precomputed configs, so we ignore it
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(flags, forKey: .flags)
        try container.encode(salt, forKey: .salt)
        try container.encode(format, forKey: .format)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try container.encode(formatter.string(from: publishedAt), forKey: .createdAt)
        try container.encode(formatter.string(from: fetchedAt), forKey: .fetchedAt)

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

        fetchedAt = try decodeRequiredDate(from: container, forKey: .fetchedAt, fieldName: "fetchedAt", decoder: decoder)
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

// MARK: - Helper Functions

/// Decodes and parses a required date timestamp from a container
private func decodeRequiredDate<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K, fieldName: String, decoder: Decoder) throws -> Date {
    let dateString = try container.decode(String.self, forKey: key)
    if let parsedDate = parseUtcISODateElement(dateString) {
        return parsedDate
    } else {
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unable to parse \(fieldName) date: \(dateString)"
        ))
    }
}

// MARK: - Decoded Configuration Types

struct DecodedPrecomputedFlag: Codable {
    let allocationKey: String?
    let variationKey: String?
    let variationType: VariationType
    let variationValue: EppoValue
    let extraLogging: [String: String]
    let doLog: Bool
}

struct DecodedPrecomputedConfiguration: Codable {
    let flags: [String: DecodedPrecomputedFlag]
    let decodedSalt: String
    let format: String
    let fetchedAt: Date
    let publishedAt: Date
    let environment: Environment?
    let subject: Subject
}

// MARK: - Decoding Logic

extension PrecomputedConfiguration {
    func decode() -> DecodedPrecomputedConfiguration? {
        var decodedFlags: [String: DecodedPrecomputedFlag] = [:]
        for (key, flag) in self.flags {
            guard let decodedFlag = decodeFlag(flag) else {
                continue
            }
            decodedFlags[key] = decodedFlag
        }

        return DecodedPrecomputedConfiguration(
            flags: decodedFlags,
            decodedSalt: self.salt,
            format: self.format,
            fetchedAt: self.fetchedAt,
            publishedAt: self.publishedAt,
            environment: self.environment,
            subject: self.subject
        )
    }

    private func decodeFlag(_ flag: PrecomputedFlag) -> DecodedPrecomputedFlag? {
        let decodedAllocationKey: String?
        if let allocationKey = flag.allocationKey {
            if let decoded = base64Decode(allocationKey) {
                decodedAllocationKey = decoded
            } else {
                print("Warning: Failed to decode allocationKey: \(allocationKey)")
                decodedAllocationKey = nil
            }
        } else {
            decodedAllocationKey = nil
        }

        let decodedVariationKey: String?
        if let variationKey = flag.variationKey {
            if let decoded = base64Decode(variationKey) {
                decodedVariationKey = decoded
            } else {
                print("Warning: Failed to decode variationKey: \(variationKey)")
                decodedVariationKey = nil
            }
        } else {
            decodedVariationKey = nil
        }

        let decodedVariationValue: EppoValue
        if flag.variationType == .string || flag.variationType == .json {
            do {
                let encodedString = try flag.variationValue.getStringValue()
                let decodedString = try base64DecodeOrThrow(encodedString)
                decodedVariationValue = EppoValue(value: decodedString)
            } catch {
                print("Warning: Failed to decode variationValue, skipping flag - error: \(error.localizedDescription)")
                return nil
            }
        } else {
            decodedVariationValue = flag.variationValue
        }

        var decodedExtraLogging: [String: String] = [:]
        for (key, value) in flag.extraLogging {
            do {
                let decodedKey = try base64DecodeOrThrow(key)
                let decodedValue = try base64DecodeOrThrow(value)
                decodedExtraLogging[decodedKey] = decodedValue
            } catch {
                print("Warning: Failed to decode extraLogging entry - key: \(key), value: \(value), error: \(error.localizedDescription)")
                continue
            }
        }

        return DecodedPrecomputedFlag(
            allocationKey: decodedAllocationKey,
            variationKey: decodedVariationKey,
            variationType: flag.variationType,
            variationValue: decodedVariationValue,
            extraLogging: decodedExtraLogging,
            doLog: flag.doLog
        )
    }
}
