import Foundation

/**
 * Decodes SDK tokens with embedded encoded data.
 */
public class SdkTokenDecoder {
    private let decodedParams: [String: String]?
    
    public init(_ sdkToken: String) {
        self.decodedParams = SdkTokenDecoder.decodeToken(sdkToken)
    }
    
    /**
     * Checks if the token is valid and contains encoded data.
     */
    public func isValid() -> Bool {
        return decodedParams != nil
    }
    
    /**
     * Returns the original token string.
     */
    public func getToken() -> String {
        return sdkToken
    }
    
    /**
     * Gets the subdomain from the token if available.
     * Returns nil if the token is invalid or doesn't contain a subdomain.
     */
    public func getSubdomain() -> String? {
        return decodedParams?["cs"]
    }
    
    /**
     * Gets the event ingestion hostname from the token if available.
     * Returns nil if the token is invalid or doesn't contain an event hostname.
     */
    public func getEventIngestionHostname() -> String? {
        return decodedParams?["eh"]
    }
    
    private let sdkToken: String
    
    /**
     * Decodes the token and extracts parameters.
     * Returns nil if the token is invalid or cannot be decoded.
     */
    private static func decodeToken(_ token: String) -> [String: String]? {
        let components = token.split(separator: ".")
        
        guard components.count >= 2 else {
            return nil
        }
        
        let encodedPart = String(components[1])
        
        guard let decodedData = Data(base64Encoded: encodedPart, options: .ignoreUnknownCharacters) else {
            return nil
        }
        
        guard let decodedString = String(data: decodedData, encoding: .utf8) else {
            return nil
        }
        
        var params = [String: String]()
        let queryItems = decodedString.split(separator: "&")
        
        for item in queryItems {
            let keyValue = item.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                let key = String(keyValue[0])
                let value = String(keyValue[1])
                
                if let decodedValue = value.removingPercentEncoding {
                    params[key] = decodedValue
                } else {
                    params[key] = value
                }
            }
        }
        
        return params.isEmpty ? nil : params
    }
}
