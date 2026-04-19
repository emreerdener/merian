import Foundation
import Observation

/// Coordinates secondary capture interactions (like voice dictation toggling or opening the Table of Contents)
/// between the globally pinned `CaptureControlBar` and the isolated active capture mode view
/// (e.g., `DescribeInputView`) without requiring the `CaptureWorkspaceView` to own mode-specific state.
@Observable final class CaptureActionCoordinator {
    /// True when dictation has been requested; the active mode view must listen and handle termination,
    /// ultimately resetting this back to false once the session naturally ends.
    var isDictationRequested: Bool = false
    
    /// A single-shot trigger that signals the active mode view to present the Table of Contents sheet.
    /// UUID is used so that repeated button taps (true -> true) cleanly trigger `.onChange`.
    var tocRequestID: UUID?
}
