import Foundation

public struct UniversalFlagConfig : Decodable {
    let createdAt: Date?;
    let flags: [String: UFC_Flag];
    // todo: add bandits
    
    static func decodeFromJSON(from jsonString: String) throws -> UniversalFlagConfig {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw UniversalFlagConfigError.notUTF8Encoded("Failed to encode JSON string into UTF-8 data.")
        }

        let decoder = JSONDecoder()
        
        // Set up the date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"  // Adjusted to include milliseconds
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")  // Use POSIX to avoid unexpected behaviors
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)  // Adjust if your JSON dates are not in GMT
        
        // Use the date formatter in the decoder
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        do {
            return try decoder.decode(UniversalFlagConfig.self, from: jsonData)
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(_, let context):
                throw UniversalFlagConfigError.parsingError("Type mismatch: \(context.debugDescription)")
            case .valueNotFound(_, let context):
                throw UniversalFlagConfigError.parsingError("Value not found: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                throw UniversalFlagConfigError.parsingError("Key not found: \(key.stringValue) - \(context.debugDescription)")
            case .dataCorrupted(let context):
                print(context.codingPath)
                throw UniversalFlagConfigError.parsingError("Data corrupted: \(context.debugDescription)")
            default:
                throw UniversalFlagConfigError.parsingError("JSON parsing error: \(error.localizedDescription)")
            }
        } catch {
            throw UniversalFlagConfigError.parsingError("Unexpected error: \(error.localizedDescription)")
        }
    }
}

// enums
enum UniversalFlagConfigError: Error, CustomNSError, LocalizedError {
    case notUTF8Encoded(String)
    case parsingError(String)

    static var errorDomain: String { return "UniversalFlagConfigError" }
    
    var errorCode: Int {
        switch self {
        case .notUTF8Encoded:
            return 100 
        case .parsingError:
            return 101
        }
    }

    var errorDescription: String? {
        switch self {
        case .notUTF8Encoded(let message):
            return message
        case .parsingError(let message):
            return message
        }
    }
}

enum UFC_VariationType: String, Decodable {
      case boolean = "BOOLEAN"
      case integer = "INTEGER"
      case json = "JSON"
      case numeric = "NUMERIC"
      case string = "STRING"
}

enum UFC_AlgorithmType: String, Decodable {
    case constant = "CONSTANT"
    case contextualBandit = "CONTEXTUAL_BANDIT"
}

enum UFC_RuleConditionOperator: String, Decodable {
  case lessThan = "LT"
  case lessThanEqual = "LTE"
  case greaterThan = "GT"
  case greaterThanEqual = "GTE"
  case matches = "MATCHES"
  case notMatches = "NOT_MATCHES"
  case oneOf = "ONE_OF"
  case notOneOf = "NOT_ONE_OF"
  case isNull = "IS_NULL"
}

// models

public struct UFC_Flag : Decodable {
    let key: String;
    let enabled: Bool;
    let variationType: UFC_VariationType;
    let variations: [String: UFC_Variation];
    let allocations: [UFC_Allocation];
    let totalShards: Int;
}

public struct UFC_Variation : Decodable  {
    let key: String;
    let value: EppoValue;
    let algorithmType: UFC_AlgorithmType?
}

public struct UFC_Allocation : Decodable {
    let key: String;
    let rules: [UFC_Rule]?;
    let startAt: Date?;
    let endAt: Date?;
    let splits: [UFC_Split];
    let doLog: Bool;
    
    enum CodingKeys: CodingKey {
        case key
        case rules
        case startAt
        case endAt
        case splits
        case doLog
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // the incoming value might be obfuscated or not
        let operatorString = try container.decode(String.self, forKey: .operator)
        
        if let decodedOperator = md5ToOperator[operatorString] {
            // if the incoming value matches the md5 lookup table, it is obfuscated
            self.operator = decodedOperator
        } else if let unobfuscatedOperator = UFC_RuleConditionOperator(rawValue: operatorString) {
            // not obfuscated; use directly
            self.operator = unobfuscatedOperator
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .operator,
                in: container,
                debugDescription: "Operator could not be decoded as either obfuscated or direct string"
            )
        }
        
        self.attribute = try container.decode(String.self, forKey: .attribute)
        self.value = try container.decode(EppoValue.self, forKey: .value)
    }
}

public struct UFC_Rule : Decodable {
    let conditions: [UFC_TargetingRuleCondition];
}

public struct UFC_TargetingRuleCondition : Decodable {
    let `operator`: UFC_RuleConditionOperator;
    let attribute: String;
    let value: EppoValue;
    
    enum CodingKeys: CodingKey {
        case `operator`
        case attribute
        case value
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // the incoming value might be obfuscated or not
        let operatorString = try container.decode(String.self, forKey: .operator)
        
        if let decodedOperator = md5ToOperator[operatorString] {
            // if the incoming value matches the md5 lookup table, it is obfuscated
            self.operator = decodedOperator
        } else if let unobfuscatedOperator = UFC_RuleConditionOperator(rawValue: operatorString) {
            // not obfuscated; use directly
            self.operator = unobfuscatedOperator
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .operator,
                in: container,
                debugDescription: "Operator could not be decoded as either obfuscated or direct string"
            )
        }
        
        self.attribute = try container.decode(String.self, forKey: .attribute)
        self.value = try container.decode(EppoValue.self, forKey: .value)
    }

    init(operator: UFC_RuleConditionOperator, attribute: String, value: EppoValue) {
        self.operator = `operator`
        self.attribute = attribute
        self.value = value
    }
}

public struct UFC_Split : Decodable {
    let variationKey: String;
    let shards: [UFC_Shard];
    let extraLogging: [String: String]?
}

public struct UFC_Shard : Decodable {
    let salt: String;
    let ranges: [UFC_Range];
}

public struct UFC_Range : Decodable {
    let start: Int;
    let end: Int;
}
