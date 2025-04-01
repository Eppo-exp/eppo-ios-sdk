import Foundation
import os

public class ApiEndpoints {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ApiEndpoints.self)
    )
    
    private let baseURL: String
    
    public init(baseURL: String?, sdkToken: String) {

        let tokenDecoder: SdkTokenDecoder = SdkTokenDecoder(sdkToken)
        if (baseURL == defaultHost) {
            Self.logger.warning("[Eppo SDK] custom baseURL cannot be the default host")
            self.baseURL = Self.getEffectiveBaseURL(tokenDecoder: tokenDecoder);
        } else if (baseURL != nil) {
            self.baseURL = baseURL!;
        } else {
            self.baseURL = Self.getEffectiveBaseURL(tokenDecoder: tokenDecoder);
        }
    }
    
    /**
     * Determines the effective base URL to use for API requests.
     * If a valid subdomain is found in the SDK token, it will be inserted into the default host.
     * Otherwise, falls back to the default host with no subdomain.
     */
    private static func getEffectiveBaseURL(tokenDecoder: SdkTokenDecoder  ) -> String {
        if let subdomain = tokenDecoder.getSubdomain(), tokenDecoder.isValid() {
            return defaultHost.replacingOccurrences(of: "https://", with: "https://\(subdomain).")
        }
        return defaultHost
    }

    public func getBaseURL() -> String {
        return baseURL
    }
}
