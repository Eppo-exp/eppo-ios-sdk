public enum EppoValueType {
    case Number
    case String
    case Boolean
    case Null
    case ArrayOfStrings
}

public class EppoValue : Decodable, Equatable {
    public var value: String?;
    public var type: EppoValueType = EppoValueType.Null;
    public var array: [String]?;

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

        try? self.array = container.decode([String].self);
        if self.array != nil {
            self.type = EppoValueType.ArrayOfStrings;
            return;
        }

        try? self.value = String(container.decode(Int.self));
        if self.value != nil {
            self.type = EppoValueType.Number;
            return;
        }

        try? self.value = String(container.decode(Bool.self));
        if self.value != nil {
            self.type = EppoValueType.Boolean;
            return;
        }

        try? self.value = container.decode(String.self);
        if self.value != nil {
            self.type = EppoValueType.String;
            return;
        }

        self.type = EppoValueType.Null;
    }

    public static func valueOf() -> EppoValue {
        return EppoValue(type: EppoValueType.Null);
    }

    public static func valueOf(_ value: String) -> EppoValue {
        return EppoValue(value: value, type: EppoValueType.String);
    }

    public static func valueOf(_ value: Int64) -> EppoValue {
        return EppoValue(value: String(value), type: EppoValueType.Number);
    }

    public static func valueOf(_ value: [String]) -> EppoValue {
        return EppoValue(array: value);
    }

    public func longValue() throws -> Int64 {
        if self.value == nil {
            throw Errors.valueNotSet;
        }

        guard let rval = Int64(self.value!) else {
            throw Errors.conversionError;
        }

        return rval;
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
}
