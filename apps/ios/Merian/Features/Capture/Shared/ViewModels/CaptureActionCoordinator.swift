import Foundation
import Observation

/// Coordinates secondary capture interactions, such as dictation toggling or
/// opening the table of contents, between the pinned capture bar and workspace.
/// The coordinator carries user intent only. `CaptureWorkspaceView` owns
/// presentation state, while `DescribeInputViewModel` owns mode-specific tasks
/// behind the workspace lifecycle observer.
@Observable final class CaptureActionCoordinator {
    /// True while dictation is requested. The lifecycle owner resets it after
    /// startup failure, explicit stop, or automatic recognition termination.
    var isDictationRequested: Bool = false

    /// A single-shot trigger that asks the workspace to present the Table of Contents sheet.
    /// UUID is used so that repeated button taps (true -> true) cleanly trigger `.onChange`.
    var tocRequestID: UUID?
}
