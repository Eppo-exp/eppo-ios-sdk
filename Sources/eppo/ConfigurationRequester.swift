import Foundation;

let RAC_CONFIG_URL = "/api/randomized_assignment/v3/config"

enum ConfigurationRequesterError: Error, CustomNSError {
    case invalidJSON(String)
    case parsingError(String)

    static var errorDomain: String { return "ConfigurationRequesterError" }
    
        var errorCode: Int {
        switch self {
        case .invalidJSON:
            return 100 
        case .parsingError:
            return 101
        }
    }
}

class ConfigurationRequester {
    private let httpClient: EppoHttpClient;

    public init(httpClient: EppoHttpClient) {
        self.httpClient = httpClient
    }

    public func fetchConfigurations() async throws -> RACConfig {
        let (urlData, _) = try await httpClient.get(RAC_CONFIG_URL);
        return try ConfigurationRequester.decodeRACConfig(from: String(data: urlData, encoding: .utf8) ?? "");    
    }

    internal static func decodeRACConfig(from jsonString: String) throws -> RACConfig {
        do {
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw ConfigurationRequesterError.invalidJSON("Cannot be encoded into UTF-8")
            }

            // Attempt to validate JSON structure
            do {
                _ = try JSONSerialization.jsonObject(with: jsonData, options: [])
            } catch let error {
                throw ConfigurationRequesterError.invalidJSON("Invalid JSON: \(error.localizedDescription)")
            }

            // Attempt to decode the JSON into RACConfig
            return try JSONDecoder().decode(RACConfig.self, from: jsonData)
        } catch let error as DecodingError {
            let specificError: String
            switch error {
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context):
                specificError = "Parsing error: \(context.debugDescription)"
            case .dataCorrupted(let context):
                specificError = "Data corrupted: \(context.debugDescription)"
            default:
                specificError = "Unknown parsing error"
            }
            throw ConfigurationRequesterError.parsingError(specificError)
        } catch let error {
            throw ConfigurationRequesterError.invalidJSON("JSON cannot be parsed: \(error.localizedDescription)")
        }
    }
}
