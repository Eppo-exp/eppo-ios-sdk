import Foundation

/// Result of a bandit action assignment.
/// Contains the variation from the feature flag and the selected action (if any).
public struct BanditResult {
    /// The variation value from the feature flag assignment
    public let variation: String

    /// The selected bandit action, or nil if no bandit was assigned
    public let action: String?

    public init(variation: String, action: String?) {
        self.variation = variation
        self.action = action
    }
}
