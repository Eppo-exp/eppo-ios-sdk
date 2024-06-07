import Foundation
import CryptoKit

public enum EppoValueType {
    case Numeric
    case String
    case Boolean
    case Null
    case ArrayOfStrings
}

public class EppoValue : Decodable, Equatable {
    private var type: EppoValueType = EppoValueType.Null;
    private var boolValue: Bool?;
    private var doubleValue: Double?
    private var stringValue: String?
    private var stringArrayValue: [String]?;

    enum Errors : Error {
        case valueNotSet;
    }

    public static func == (lhs: EppoValue, rhs: EppoValue) -> Bool {
        if lhs.type != rhs.type { return false; }

        switch lhs.type {
            case .Boolean:
                return lhs.boolValue == rhs.boolValue
            case .Numeric:
                return lhs.doubleValue == rhs.doubleValue
            case .String:
                return lhs.stringValue == rhs.stringValue
            case .ArrayOfStrings:
                // Convert arrays to sets and compare, ignoring order and duplicates
                let lhsSet = Set(lhs.stringArrayValue ?? [])
                let rhsSet = Set(rhs.stringArrayValue ?? [])
                return lhsSet == rhsSet
            case .Null:
                return true // Both are null
        }
    }

    public init(value: Bool) {
        self.type = EppoValueType.Boolean;
        self.boolValue = value;
    }
    
    public init(value: Double) {
        self.type = EppoValueType.Numeric;
        self.doubleValue = value;
    }
    
    public init(value: Int) {
        self.type = EppoValueType.Numeric;
        self.doubleValue = Double(value);
    }
    
    public init(value: String) {
        self.type = EppoValueType.String;
        self.stringValue = value;
    }

    public init(array: [String]) {
        self.type = EppoValueType.ArrayOfStrings;
        self.stringArrayValue = array;
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer();

        if let array = try? container.decode([String].self) {
            self.type = .ArrayOfStrings
            self.stringArrayValue = array
        } else if let doubleValue = try? container.decode(Double.self) {
            // decode double handles both integers and floating-point numbers.
            self.type = .Numeric
            self.doubleValue = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            self.type = .Boolean
            self.boolValue = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            self.type = .String
            self.stringValue = stringValue
        } else {
            self.type = .Null
        }
    }

    public static func valueOf(_ value: Bool) -> EppoValue {
        return EppoValue(value: value);
    }

    public static func valueOf(_ value: Double) -> EppoValue {
        return EppoValue(value: value);
    }
    
    public static func valueOf(_ value: Int) -> EppoValue {
        return EppoValue(value: value);
    }

    public static func valueOf(_ value: String) -> EppoValue {
        return EppoValue(value: value);
    }

    public static func valueOf(_ value: [String]) -> EppoValue {
        return EppoValue(array: value);
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
    
    public func getBoolValue() throws -> Bool {
        guard let value = self.boolValue else {
            throw Errors.valueNotSet
        }
        return value
    }

    public func getDoubleValue() throws -> Double {
        guard let value = self.doubleValue else {
            throw Errors.valueNotSet
        }
        return value
    }

    public func getStringArrayValue() throws -> [String] {
        guard let value = self.stringArrayValue else {
            throw Errors.valueNotSet
        }

        return value;
    }

    public func getStringValue() throws -> String {
        guard let value = self.stringValue else {
            throw Errors.valueNotSet
        }

        return value;
    }

    public func toHashedString() -> String {
        // todo: this is a bit of a hack. we should probably just use a switch
        // to handle the different types.
        var str = ""
        if let value = self.stringValue {
            str = value
        } else if let array = self.stringArrayValue {
            str = array.joined(separator: " ,")
        }

        // generate a sha256 hash of the string. this is a 32-byte signature which
        // will likely save space when using json values but will almost certainly be
        // longer than typical string variation values such as "control" or "variant".
        let sha256Data = SHA256.hash(data: str.data(using: .utf8) ?? Data())
        return sha256Data.map { String(format: "%02x", $0) }.joined()
    }
}

