import Foundation

/// Eppo client for precomputed flag assignments
public class EppoPrecomputedClient {
    public typealias AssignmentLogger = (Assignment) -> Void
    // MARK: - Singleton Pattern (matches regular EppoClient)
    public static let shared = EppoPrecomputedClient()
    private static var initialized = false
    
    // MARK: - Thread Safety (matches regular EppoClient approach)
    private let accessQueue = DispatchQueue(label: "cloud.eppo.precomputed.access", qos: .userInitiated)
    
    // MARK: - Core Components
    private var configurationStore: PrecomputedConfigurationStore?
    private var subject: Subject?
    private var assignmentLogger: AssignmentLogger?
    private var assignmentCache: AssignmentCache?
    private var poller: Poller?
    
    // MARK: - Network Components
    private var requestor: PrecomputedRequestor?
    
    // MARK: - Event Queuing (before logger is set)
    private var queuedAssignments: [Assignment] = []
    private let maxEventQueueSize = 100  // Match JS MAX_EVENT_QUEUE_SIZE
    
    // MARK: - Client State
    private var sdkKey: String?
    private var isInitialized: Bool {
        return Self.initialized
    }
    
    // MARK: - Initialization
    
    private init() {} // Singleton
    
    // MARK: - Lifecycle Management
    
    /// Stops the configuration polling
    @MainActor
    public func stopPolling() {
        poller?.stop()
    }
    
    /// Resets the client state (useful for testing)
    internal static func resetForTesting() {
        initialized = false
        shared.accessQueue.sync(flags: .barrier) {
            shared.configurationStore = nil
            shared.subject = nil
            shared.assignmentLogger = nil
            shared.assignmentCache = nil
            // Note: We can't call stop() here as it's MainActor-isolated
            // The poller will be replaced/cleaned up when set to nil
            shared.poller = nil
            shared.requestor = nil
            shared.queuedAssignments.removeAll()
            shared.sdkKey = nil
        }
    }
    
    // MARK: - Queue Management
    
    /// Adds an assignment to the queue (called before logger is set)
    private func queueAssignment(_ assignment: Assignment) {
        accessQueue.sync(flags: .barrier) {
            // Limit queue size to prevent memory issues
            if queuedAssignments.count < maxEventQueueSize {
                queuedAssignments.append(assignment)
            }
        }
    }
    
    /// Flushes queued assignments to the logger
    private func flushQueuedAssignments() {
        guard let logger = assignmentLogger else { return }
        
        accessQueue.sync(flags: .barrier) {
            for assignment in queuedAssignments {
                logger(assignment)
            }
            queuedAssignments.removeAll()
        }
    }
}