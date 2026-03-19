import Foundation
#if os(iOS)
import UIKit

/// A generic, thread-safe wrapper for managing UIBackgroundTaskIdentifier
/// Ensures strict Sendable conformance avoiding iOS strict concurrency crashes natively.
public final class BackgroundTaskWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: UIBackgroundTaskIdentifier = .invalid
    
    public var id: UIBackgroundTaskIdentifier {
        get { lock.withLock { _id } }
        set { lock.withLock { _id = newValue } }
    }
    
    public init() {}
    
    public func safeEnd() {
        let currentId = id
        if currentId != .invalid {
            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(currentId)
            }
            id = .invalid
        }
    }
}
#endif
