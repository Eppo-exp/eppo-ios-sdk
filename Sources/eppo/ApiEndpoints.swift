/// Handles API endpoint URL construction with subdomain support.
public class ApiEndpoints {
    /// The effective base URL used for API requests
    private(set) public var baseURL: String
    
    /// Creates an API endpoints helper to construct URLs for API requests.
    /// - Parameters:
    ///   - baseURL: Optional custom base URL. If nil or default host, subdomain logic will be applied.
    ///   - sdkKey: The SDK key that may contain subdomain information
    public init(baseURL: String?, sdkKey: SDKKey) {
        if baseURL == defaultHost {
            /// Using default host as custom URL is redundant, so we'll apply subdomain logic
            self.baseURL = Self.getEffectiveBaseURL(sdkKey: sdkKey)
        } else if let baseURL = baseURL {
            self.baseURL = baseURL
        } else {
            self.baseURL = Self.getEffectiveBaseURL(sdkKey: sdkKey)
        }
    }
    
    /// Determines the effective base URL to use for API requests.
    /// If a valid subdomain is found in the SDK token, it will be inserted into the default host.
    /// Otherwise, falls back to the default host with no subdomain.
    /// - Parameter sdkKey: The SDK key that may contain subdomain information
    /// - Returns: A base URL with subdomain if available
    private static func getEffectiveBaseURL(sdkKey: SDKKey) -> String {
        if let subdomain = sdkKey.subdomain, sdkKey.isValid {
            return defaultHost.replacingOccurrences(of: "https://", with: "https://\(subdomain).")
        }
        return defaultHost
    }
}
