enum EppoValueType {
    case Number
    case String
    case Boolean
    case Null
    case ArrayOfStrings
}

enum EppoValueErrors : Error {
    case NotImplemented;
}

class EppoValue : Decodable {
    public var value: String = "";
    public var type: EppoValueType = EppoValueType.Null;
    public var array: [String] = [];

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
        try? self.value = container.decode(String.self);
        
        if self.value.count > 0 {
            if UInt(self.value) != nil {
                self.type = EppoValueType.Number;
            } else if self.value.lowercased() == "false" || self.value.lowercased() == "true" {
                self.type = EppoValueType.Boolean;
            }
        } else if self.array.count > 0 {
            self.type = EppoValueType.ArrayOfStrings;
        }
    }

    public static func valueOf() -> EppoValue {
        return EppoValue(type: EppoValueType.Null);
    }

    public static func valueOf(value: String) -> EppoValue {
        return EppoValue(value: value, type: EppoValueType.String);
    }
}
