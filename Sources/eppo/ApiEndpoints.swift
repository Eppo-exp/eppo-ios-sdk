

/// Handles API endpoint URL construction with subdomain support.
public class ApiEndpoints {
    private let effectiveBaseURL: String
    
    public init(baseURL: String?, sdkKey: SDKKey) {
        
        if baseURL == defaultHost {
            // Custom baseURL cannot be the default host
            self.effectiveBaseURL = Self.getEffectiveBaseURL(sdkKey: sdkKey)
        } else if let baseURL = baseURL {
            self.effectiveBaseURL = baseURL
        } else {
            self.effectiveBaseURL = Self.getEffectiveBaseURL(sdkKey: sdkKey)
        }
    }
    
    /// Determines the effective base URL to use for API requests.
    /// If a valid subdomain is found in the SDK token, it will be inserted into the default host.
    /// Otherwise, falls back to the default host with no subdomain.
    private static func getEffectiveBaseURL(sdkKey: SDKKey) -> String {
        if let subdomain = sdkKey.getSubdomain(), sdkKey.isValid() {
            return defaultHost.replacingOccurrences(of: "https://", with: "https://\(subdomain).")
        }
        return defaultHost
    }
    
    /// Returns the effective base URL for API requests.
    public var baseURL: String {
        effectiveBaseURL
    }
}
