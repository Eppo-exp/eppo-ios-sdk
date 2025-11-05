import Foundation
import CryptoKit

// Copy-on-Write wrapper for string arrays to improve memory efficiency
@usableFromInline
internal final class StringArrayStorage {
    @usableFromInline var array: [String]

    @usableFromInline
    init(_ array: [String]) {
        self.array = array
    }
}

public enum EppoValueType: Codable {
    case Numeric
    case String
    case Boolean
    case Null
    case ArrayOfStrings
}

@frozen public struct EppoValue: Codable, Equatable {
    @usableFromInline internal let type: EppoValueType
    @usableFromInline internal let _boolValue: Bool?
    @usableFromInline internal let _doubleValue: Double?
    @usableFromInline internal let _stringValue: String?
    @usableFromInline internal let _stringArrayStorage: StringArrayStorage?

    // Computed property to access the array through COW wrapper
    @usableFromInline internal var _stringArrayValue: [String]? {
        return _stringArrayStorage?.array
    }

    // MARK: - Fast Non-Throwing Value Access
    /// Fast access to boolean value without throwing - returns nil if not a boolean type
    @inlinable public var boolValue: Bool? {
        guard type == .Boolean else { return nil }
        return _boolValue
    }

    /// Fast access to double value without throwing - returns nil if not a numeric type
    @inlinable public var doubleValue: Double? {
        guard type == .Numeric else { return nil }
        return _doubleValue
    }

    /// Fast access to string value without throwing - returns nil if not a string type
    @inlinable public var stringValue: String? {
        guard type == .String else { return nil }
        return _stringValue
    }

    /// Fast access to string array value without throwing - returns nil if not an array type
    @inlinable public var stringArrayValue: [String]? {
        guard type == .ArrayOfStrings else { return nil }
        return _stringArrayValue
    }

    enum Errors: Error {
        case valueNotSet
    }

    public static func == (lhs: EppoValue, rhs: EppoValue) -> Bool {
        if lhs.type != rhs.type { return false }

        switch lhs.type {
        case .Boolean:
            return lhs._boolValue == rhs._boolValue
        case .Numeric:
            return lhs._doubleValue == rhs._doubleValue
        case .String:
            return lhs._stringValue == rhs._stringValue
        case .ArrayOfStrings:
            // Convert arrays to sets and compare, ignoring order and duplicates
            let lhsSet = Set(lhs._stringArrayValue ?? [])
            let rhsSet = Set(rhs._stringArrayValue ?? [])
            return lhsSet == rhsSet
        case .Null:
            return true // Both are null
        }
    }

    public init() {
        self.type = .Null
        self._boolValue = nil
        self._doubleValue = nil
        self._stringValue = nil
        self._stringArrayStorage = nil
    }

    public init(value: Bool) {
        self.type = .Boolean
        self._boolValue = value
        self._doubleValue = nil
        self._stringValue = nil
        self._stringArrayStorage = nil
    }

    public init(value: Double) {
        self.type = .Numeric
        self._boolValue = nil
        self._doubleValue = value
        self._stringValue = nil
        self._stringArrayStorage = nil
    }

    public init(value: Int) {
        self.type = .Numeric
        self._boolValue = nil
        self._doubleValue = Double(value)
        self._stringValue = nil
        self._stringArrayStorage = nil
    }

    public init(value: String) {
        self.type = .String
        self._boolValue = nil
        self._doubleValue = nil
        self._stringValue = value
        self._stringArrayStorage = nil
    }

    public init(array: [String]) {
        self.type = .ArrayOfStrings
        self._boolValue = nil
        self._doubleValue = nil
        self._stringValue = nil
        self._stringArrayStorage = StringArrayStorage(array)
    }

    // Standard Decodable conformance
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Check String first; most common case, especially with obfuscated values
        if let stringValue = try? container.decode(String.self) {
            self.type = .String
            self._boolValue = nil
            self._doubleValue = nil
            self._stringValue = stringValue
            self._stringArrayStorage = nil
        } else if let doubleValue = try? container.decode(Double.self) {
            self.type = .Numeric
            self._boolValue = nil
            self._doubleValue = doubleValue
            self._stringValue = nil
            self._stringArrayStorage = nil
        } else if let boolValue = try? container.decode(Bool.self) {
            self.type = .Boolean
            self._boolValue = boolValue
            self._doubleValue = nil
            self._stringValue = nil
            self._stringArrayStorage = nil
        } else if let array = try? container.decode([String].self) {
            self.type = .ArrayOfStrings
            self._boolValue = nil
            self._doubleValue = nil
            self._stringValue = nil
            self._stringArrayStorage = StringArrayStorage(array)
        } else {
            self.type = .Null
            self._boolValue = nil
            self._doubleValue = nil
            self._stringValue = nil
            self._stringArrayStorage = nil
        }
    }

    // Custom initializer with variationType support for obfuscation - optimized for strings
    internal init(from decoder: Decoder, variationType: UFC_VariationType) throws {
        let container = try decoder.singleValueContainer()

        // Check String FIRST - obfuscated values are always base64-encoded strings
        if let stringValue = try? container.decode(String.self) {
            self.type = .String
            self._boolValue = nil
            self._doubleValue = nil
            self._stringValue = stringValue
            self._stringArrayStorage = nil
        } else if let doubleValue = try? container.decode(Double.self) {
            self.type = .Numeric
            self._boolValue = nil
            self._doubleValue = doubleValue
            self._stringValue = nil
            self._stringArrayStorage = nil
        } else if let boolValue = try? container.decode(Bool.self) {
            self.type = .Boolean
            self._boolValue = boolValue
            self._doubleValue = nil
            self._stringValue = nil
            self._stringArrayStorage = nil
        } else if let array = try? container.decode([String].self) {
            self.type = .ArrayOfStrings
            self._boolValue = nil
            self._doubleValue = nil
            self._stringValue = nil
            self._stringArrayStorage = StringArrayStorage(array)
        } else {
            self.type = .Null
            self._boolValue = nil
            self._doubleValue = nil
            self._stringValue = nil
            self._stringArrayStorage = nil
        }
    }

    public static func valueOf(_ value: Bool) -> EppoValue {
        return EppoValue(value: value)
    }

    public static func valueOf(_ value: Double) -> EppoValue {
        return EppoValue(value: value)
    }

    public static func valueOf(_ value: Int) -> EppoValue {
        return EppoValue(value: value)
    }

    public static func valueOf(_ value: String) -> EppoValue {
        return EppoValue(value: value)
    }

    public static func valueOf(_ value: [String]) -> EppoValue {
        return EppoValue(array: value)
    }

    public static func nullValue() -> EppoValue {
        return EppoValue()
    }


    internal static func valueOf(_ value: Any, variationType: UFC_VariationType) -> EppoValue {
        switch variationType {
        case .boolean:
            if let boolVal = value as? Bool {
                return EppoValue(value: boolVal)
            }
            if let stringVal = value as? String {
                return EppoValue(value: stringVal.lowercased() == "true")
            }
            if let intVal = value as? Int {
                return EppoValue(value: intVal != 0)
            }
            if let doubleVal = value as? Double {
                return EppoValue(value: doubleVal != 0.0)
            }
        case .integer, .numeric:
            if let doubleVal = value as? Double {
                return EppoValue(value: doubleVal)
            }
            if let intVal = value as? Int {
                return EppoValue(value: intVal)
            }
            if let stringVal = value as? String, let doubleVal = Double(stringVal) {
                return EppoValue(value: doubleVal)
            }
        case .string, .json:
            if let stringVal = value as? String {
                return EppoValue(value: stringVal)
            }
            if let arrayVal = value as? [String] {
                return EppoValue(array: arrayVal)
            }
            // Convert other types to string representation
            return EppoValue(value: String(describing: value))
        }
        // Fallback to null if conversion fails
        return EppoValue.nullValue()
    }

    public func isNull() -> Bool {
        return self.type == EppoValueType.Null
    }

    public func isBool() -> Bool {
        return self.type == EppoValueType.Boolean
    }

    public func isNumeric() -> Bool {
        return self.type == EppoValueType.Numeric
    }

    public func isString() -> Bool {
        return self.type == EppoValueType.String
    }


    public func toEppoString() throws -> String {
        switch self.type {
        case .Boolean:
            guard let value = self.boolValue else { throw Errors.valueNotSet }
            return value ? "true" : "false"

        case .Numeric:
            guard let doubleValue = self.doubleValue else { throw Errors.valueNotSet }
            if floor(doubleValue) == doubleValue {
                return String(format: "%.0f", doubleValue)
            } else {
                return String(doubleValue)
            }

        case .String:
            guard let value = self.stringValue else { throw Errors.valueNotSet }
            return value

        case .ArrayOfStrings:
            guard let arrayValue = self.stringArrayValue else { throw Errors.valueNotSet }
            return arrayValue.joined(separator: ", ")

        default:
            throw Errors.valueNotSet
        }
    }

    /// Returns MD5 hashed string representation of the value - useful for privacy-preserving logging
    public func toHashedString() -> String {
        do {
            let stringRepresentation = try self.toEppoString()
            return getMD5Hex(stringRepresentation)
        } catch {
            return getMD5Hex("null")
        }
    }
}
extension EppoValue {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self.type {
        case .Boolean:
            try container.encode(_boolValue!)
        case .Numeric:
            try container.encode(_doubleValue!)
        case .String:
            try container.encode(_stringValue!)
        case .ArrayOfStrings:
            try container.encode(_stringArrayStorage!.array)
        case .Null:
            try container.encodeNil()
        }
    }
}
