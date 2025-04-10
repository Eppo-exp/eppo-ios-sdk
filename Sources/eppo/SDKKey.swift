import Foundation

/// Decodes SDK tokens with embedded encoded data.
public class SDKKey {
    private let decodedParams: [String: String]?
    private let sdkToken: String
    
    public init(_ sdkToken: String) {
        self.decodedParams = SDKKey.decodeToken(sdkToken)
        self.sdkToken = sdkToken
    }
    
    /// Checks if the token contains encoded data.
    public func isValid() -> Bool {
        decodedParams != nil
    }
    
    /// Returns the original token string.
    public func getToken() -> String {
        sdkToken
    }
    
    /// Gets the subdomain from the token if available.
    /// Returns nil if the token is invalid or doesn't contain a subdomain.
    public func getSubdomain() -> String? {
        decodedParams?["cs"]
    }

    /// Decodes the token and extracts parameters.
    /// Returns nil if the token is invalid or cannot be decoded.
    private static func decodeToken(_ tokenString: String) -> [String: String]? {
        let components = tokenString.split(separator: ".")
        
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
