import Foundation

public struct UniversalFlagConfig : Decodable {
    let createdAt: Date?;
    let flags: [String: UFC_Flag];
    
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

enum UFC_RuleConditionOperator: String, Decodable {
  case lessThan = "LT"
  case lessThanEqual = "LTE"
  case greaterThan = "GT"
  case greaterThanEqual = "GTE"
  case matches = "MATCHES"
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
}

public struct UFC_Allocation : Decodable {
    let key: String;
    let rules: [UFC_Rule]?;
    let startAt: Date?;
    let endAt: Date?;
    let splits: [UFC_Split];
    let doLog: Bool;
}

public struct UFC_Rule : Decodable {
    let conditions: [UFC_TargetingRuleCondition];
}

public struct UFC_TargetingRuleCondition : Decodable {
    let `operator`: UFC_RuleConditionOperator;
    let attribute: String;
    let value: EppoValue;
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
