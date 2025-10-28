import Foundation

/// Protocol for pluggable JSON parsing implementations
/// This allows customers to provide their own JSON parser for performance optimization
public protocol JSONParsingProvider {
    /// Decode UniversalFlagConfig from raw JSON data
    /// - Parameters:
    ///   - data: Raw JSON data
    /// - Returns: Decoded UniversalFlagConfig
    /// - Throws: Parsing errors
    func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig

    /// Encode UniversalFlagConfig to JSON data
    /// - Parameter config: UniversalFlagConfig to encode
    /// - Returns: JSON data
    /// - Throws: Encoding errors
    func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data

    /// Encode UniversalFlagConfig to JSON string
    /// - Parameter config: UniversalFlagConfig to encode
    /// - Returns: JSON string
    /// - Throws: Encoding errors
    func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String

    /// Decode Configuration from raw JSON data
    /// - Parameters:
    ///   - data: Raw JSON data
    ///   - obfuscated: Whether the data is obfuscated
    /// - Returns: Decoded Configuration
    /// - Throws: Parsing errors
    func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration

    /// Encode Configuration to JSON data
    /// - Parameter configuration: Configuration to encode
    /// - Returns: JSON data
    /// - Throws: Encoding errors
    func encodeConfiguration(_ configuration: Configuration) throws -> Data

    /// Decode Configuration from previously encoded data (for persistence)
    /// - Parameter data: Previously encoded Configuration data
    /// - Returns: Decoded Configuration
    /// - Throws: Decoding errors
    func decodeEncodedConfiguration(from data: Data) throws -> Configuration
}

/// Factory for managing the current JSON parsing provider
public class JSONParsingFactory {
    /// The current JSON parsing provider used throughout the SDK
    public static var currentProvider: JSONParsingProvider = StandardJSONParsingProvider()

    /// Configure a custom JSON parsing provider
    /// - Parameter provider: The custom JSON parsing provider
    public static func configure(provider: JSONParsingProvider) {
        currentProvider = provider
    }

    /// Reset to the default JSON parsing provider
    public static func useDefault() {
        currentProvider = StandardJSONParsingProvider()
    }
}

/// Default JSON parsing provider that uses Swift's standard Codable implementation
/// This wraps the existing parsing logic to maintain compatibility
public class StandardJSONParsingProvider: JSONParsingProvider {

    public init() {}

    public func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        let decoder = JSONDecoder()

        // Configure the same custom date decoding strategy as the original implementation
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            guard let date = parseUtcISODateElement(dateStr) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format for: <\(dateStr)>")
            }
            return date
        }

        // Decode with the same error translation as original implementation
        do {
            return try decoder.decode(UniversalFlagConfig.self, from: data)
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, let context):
                throw UniversalFlagConfigError.parsingError("Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                throw UniversalFlagConfigError.parsingError("Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                throw UniversalFlagConfigError.parsingError("Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                throw UniversalFlagConfigError.parsingError("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)")
            @unknown default:
                throw UniversalFlagConfigError.parsingError("Unknown parsing error: \(error)")
            }
        } catch {
            throw UniversalFlagConfigError.parsingError("Unexpected parsing error: \(error)")
        }
    }

    public func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data {
        let encoder = createEncoder()
        return try encoder.encode(config)
    }

    public func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String {
        let data = try encodeUniversalFlagConfig(config)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(config, EncodingError.Context(codingPath: [], debugDescription: "Could not convert encoded data to UTF-8 string"))
        }
        return string
    }

    public func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration {
        // Parse the UniversalFlagConfig first
        let flagsConfiguration = try decodeUniversalFlagConfig(from: data)

        // Create Configuration wrapper with current timestamp
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)

        return Configuration(
            flagsConfiguration: flagsConfiguration,
            obfuscated: obfuscated,
            fetchedAt: timestamp,
            publishedAt: timestamp
        )
    }

    public func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        let encoder = createEncoder()
        return try encoder.encode(configuration)
    }

    public func decodeEncodedConfiguration(from data: Data) throws -> Configuration {
        let decoder = JSONDecoder()

        // Use the same custom date decoding strategy as for UniversalFlagConfig
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            guard let date = parseUtcISODateElement(dateStr) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format for: <\(dateStr)>")
            }
            return date
        }

        return try decoder.decode(Configuration.self, from: data)
    }

    /// Create a JSONEncoder with the same configuration as the original implementation
    private func createEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let string = formatter.string(from: date)
            var container = encoder.singleValueContainer()
            try container.encode(string)
        }
        return encoder
    }
}