import Foundation
import Observation

/// Coordinates secondary capture interactions (like voice dictation toggling or opening the Table of Contents)
/// between the globally pinned `CaptureControlBar` and the workspace-owned lifecycle observer.
/// The coordinator carries user intent only; `CaptureWorkspaceView` owns presentation state and
/// `DescribeInputLifecycleObserver` owns the mode-specific side effects.
@Observable final class CaptureActionCoordinator {
    /// True when dictation has been requested; the lifecycle observer listens and handles termination,
    /// ultimately resetting this back to false once the session naturally ends.
    var isDictationRequested: Bool = false
    
    /// A single-shot trigger that asks the workspace to present the Table of Contents sheet.
    /// UUID is used so that repeated button taps (true -> true) cleanly trigger `.onChange`.
    var tocRequestID: UUID?
}
