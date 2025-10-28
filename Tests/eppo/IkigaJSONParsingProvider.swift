import Foundation
import IkigaJSON
@testable import EppoFlagging

/// IkigaJSON implementation of JSONParsingProvider for testing performance and compatibility
public class IkigaJSONParsingProvider: JSONParsingProvider {

    public init() {}

    public func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        // IkigaJSON doesn't have dateDecodingStrategy, so we need to use the standard approach
        // but rely on the custom date handling in the Codable implementations themselves
        let decoder = IkigaJSONDecoder()

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
        let decoder = IkigaJSONDecoder()
        return try decoder.decode(Configuration.self, from: data)
    }

    /// Create an IkigaJSONEncoder with basic configuration
    /// Note: IkigaJSON doesn't have the same dateEncodingStrategy API as JSONEncoder
    /// so we rely on the custom encoding in the Codable implementations
    private func createEncoder() -> IkigaJSONEncoder {
        return IkigaJSONEncoder()
    }
}

/// Performance monitoring wrapper that can compare parsing times between different providers
public class MetricsJSONParsingProvider: JSONParsingProvider {
    private let wrapped: JSONParsingProvider
    private let label: String

    public init(wrapping provider: JSONParsingProvider, label: String) {
        self.wrapped = provider
        self.label = label
    }

    public func decodeUniversalFlagConfig(from data: Data) throws -> UniversalFlagConfig {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("[\(label)] decodeUniversalFlagConfig: \(String(format: "%.4f", duration * 1000))ms for \(data.count) bytes")
        }
        return try wrapped.decodeUniversalFlagConfig(from: data)
    }

    public func encodeUniversalFlagConfig(_ config: UniversalFlagConfig) throws -> Data {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("[\(label)] encodeUniversalFlagConfig: \(String(format: "%.4f", duration * 1000))ms")
        }
        return try wrapped.encodeUniversalFlagConfig(config)
    }

    public func encodeUniversalFlagConfigToString(_ config: UniversalFlagConfig) throws -> String {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("[\(label)] encodeUniversalFlagConfigToString: \(String(format: "%.4f", duration * 1000))ms")
        }
        return try wrapped.encodeUniversalFlagConfigToString(config)
    }

    public func decodeConfiguration(from data: Data, obfuscated: Bool) throws -> Configuration {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("[\(label)] decodeConfiguration: \(String(format: "%.4f", duration * 1000))ms for \(data.count) bytes")
        }
        return try wrapped.decodeConfiguration(from: data, obfuscated: obfuscated)
    }

    public func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("[\(label)] encodeConfiguration: \(String(format: "%.4f", duration * 1000))ms")
        }
        return try wrapped.encodeConfiguration(configuration)
    }

    public func decodeEncodedConfiguration(from data: Data) throws -> Configuration {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("[\(label)] decodeEncodedConfiguration: \(String(format: "%.4f", duration * 1000))ms for \(data.count) bytes")
        }
        return try wrapped.decodeEncodedConfiguration(from: data)
    }
}