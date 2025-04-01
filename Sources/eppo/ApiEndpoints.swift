import Foundation
import os

/// Handles API endpoint URL construction with subdomain support.
public class ApiEndpoints {
    private static let logger: Logger = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.eppo.sdk"
        return Logger(subsystem: bundleID, category: String(describing: ApiEndpoints.self))
    }()
    
    private let effectiveBaseURL: String
    
    public init(baseURL: String?, sdkToken: String) {
        let tokenDecoder = SdkTokenDecoder(sdkToken)
        if baseURL == defaultHost {
            Self.logger.warning("[Eppo SDK] custom baseURL cannot be the default host")
            self.effectiveBaseURL = Self.getEffectiveBaseURL(tokenDecoder: tokenDecoder)
        } else if let baseURL = baseURL {
            self.effectiveBaseURL = baseURL
        } else {
            self.effectiveBaseURL = Self.getEffectiveBaseURL(tokenDecoder: tokenDecoder)
        }
    }
    
    /// Determines the effective base URL to use for API requests.
    /// If a valid subdomain is found in the SDK token, it will be inserted into the default host.
    /// Otherwise, falls back to the default host with no subdomain.
    private static func getEffectiveBaseURL(tokenDecoder: SdkTokenDecoder) -> String {
        if let subdomain = tokenDecoder.getSubdomain(), tokenDecoder.isValid() {
            return defaultHost.replacingOccurrences(of: "https://", with: "https://\(subdomain).")
        }
        return defaultHost
    }
    
    /// Returns the effective base URL for API requests.
    public var baseURL: String {
        effectiveBaseURL
    }
}
