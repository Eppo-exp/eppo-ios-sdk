import Foundation
import CryptoKit

public enum EppoValueType {
    case Number
    case String
    case Boolean
    case Null
    case ArrayOfStrings
}

public class EppoValue : Decodable, Equatable {
    private var value: String?;
    private var type: EppoValueType = EppoValueType.Null;
    private var array: [String]?;

    enum Errors : Error {
        case NotImplemented
        case conversionError
        case valueNotSet;
    }

    public static func == (lhs: EppoValue, rhs: EppoValue) -> Bool {
        if lhs.value != rhs.value { return false; }
        if lhs.type != rhs.type { return false; }

        if lhs.array == nil && rhs.array != nil { return false }
        if rhs.array == nil && lhs.array != nil { return false; }

        for lhItem in lhs.array! {
            if !rhs.array!.contains(where: { (rhItem) in return rhItem == lhItem }) {
                return false;
            }
        }

        return true;
    }

    public init(value: String, type: EppoValueType) {
        self.value = value;
        self.type = type;
        self.array = [];
    }

    public init(array: [String]) {
        self.type = EppoValueType.ArrayOfStrings;
        self.array = array;
        self.value = "";
    }

    public init(type: EppoValueType) {
        self.type = type;
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer();

        if let array = try? container.decode([String].self) {
            self.type = .ArrayOfStrings
            self.array = array
            self.value = nil
        } else if let numericValue = try? container.decode(Double.self) {
            // decode double handles both integers and floating-point numbers.
            //
            // todo: this class is clunky with storing ints and doubles as strings.
            // add support for storing them natively to avoid repeated conversions.
            self.type = .Number
            self.value = String(numericValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self.type = .Boolean
            self.value = String(boolValue)
        } else if let stringValue = try? container.decode(String.self) {
                self.type = .String
                self.value = stringValue
            } else {
            self.type = .Null
            self.value = nil
        }
    }

    public static func valueOf() -> EppoValue {
        return EppoValue(type: EppoValueType.Null);
    }

    public static func valueOf(_ value: Bool) -> EppoValue {
        return EppoValue(value: String(value), type: EppoValueType.Boolean);
    }
    
    public static func valueOf(_ value: Double) -> EppoValue {
        return EppoValue(value: String(value), type: EppoValueType.Number);
    }
    
    public static func valueOf(_ value: String) -> EppoValue {
        return EppoValue(value: value, type: EppoValueType.String);
    }

    public static func valueOf(_ value: [String]) -> EppoValue {
        return EppoValue(array: value);
    }

    public func boolValue() throws -> Bool {
        if self.value == nil {
            throw Errors.valueNotSet;
        }

        guard let rval = Bool(self.value!) else {
            throw Errors.conversionError;
        }

        return rval;
    }
    
    public func doubleValue() throws -> Double {
        if self.value == nil {
            throw Errors.valueNotSet;
        }

        guard let rval = Double(self.value!) else {
            throw Errors.conversionError;
        }

        return rval;
    }

    public func arrayValue() throws -> [String] {
        if self.array == nil {
            throw Errors.valueNotSet;
        }

        return self.array!;
    }

    public func stringValue() throws -> String {
        if self.value == nil {
            throw Errors.valueNotSet;
        }

        return self.value!;
    }

    public func toHashedString() -> String {
        var str = ""
        if let value = self.value {
            str = value
        } else if let array = self.array {
            str = array.joined(separator: ",")
        }

        // generate a sha256 hash of the string. this is a 32-byte signature which 
        // will likely save space when using json values but will almost certainly be
        // longer than typical string variation values such as "control" or "variant".
        let sha256Data = SHA256.hash(data: str.data(using: .utf8) ?? Data())
        return sha256Data.map { String(format: "%02x", $0) }.joined()
    }
}
