import Foundation

/// Decodes SDK tokens with embedded encoded data.
public class SDKKey {
    private let decodedParams: [String: String]?
    
    /// The original token string
    public let token: String
    
    /// Possible errors when working with SDK keys
    public enum SDKKeyError: Error {
        case invalidFormat
        case invalidEncoding
        case missingParameters
    }
    
    /// Creates a new SDK key from a token string
    /// - Parameter token: The raw SDK token string
    public init(_ token: String) {
        self.token = token
        self.decodedParams = SDKKey.decodeToken(token)
    }
    
    /// Whether the token contains valid encoded data
    public var isValid: Bool {
        decodedParams != nil
    }
    
    /// The subdomain extracted from the token, if available
    public var subdomain: String? {
        decodedParams?["cs"]
    }
    
    /// Attempts to decode the token and extract parameters.
    /// - Parameter token: The raw token string to decode
    /// - Returns: Dictionary of decoded parameters or nil if invalid
    private static func decodeToken(_ token: String) -> [String: String]? {
        let components = token.split(separator: ".")
        
        guard components.count >= 2 else {
            return nil
        }
        
        let encodedPart = String(components[1])
        
        guard let decodedData = Data(base64Encoded: encodedPart) else {
            return nil
        }
        
        guard let decodedString = String(data: decodedData, encoding: .utf8) else {
            return nil
        }
        
        // Use URLComponents to parse the query string
        guard let components = URLComponents(string: "?\(decodedString)") else {
            return nil
        }
        
        // Convert URLQueryItems to dictionary
        let params = components.queryItems?.reduce(into: [String: String]()) { dict, item in
            dict[item.name] = item.value
        }
        
        return params?.isEmpty == true ? nil : params
    }
}
