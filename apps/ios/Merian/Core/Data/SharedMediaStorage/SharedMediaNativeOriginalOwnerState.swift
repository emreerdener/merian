import Foundation

/// Inert lifecycle values only. The registered owner keeps its state properties
/// private; constructing these values cannot install state or mint any grant.
enum SharedMediaNativeOriginalOpenKind { case qualification, scopedInspection, appInitialization, appDispatch }
enum SharedMediaNativeOriginalPhase { case unopened, opening, ready, failed, suspended }
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
struct SharedMediaNativeOriginalPendingSettlement {
    let id = UUID()
    let request: SharedMediaAcquisitionIntent
    let loaderStarted: Bool
    let writerReturned: Bool
    var appTicket: SharedMediaNativeAppAcquisitionSettlement?
}

/// Value-only opening result; neither branch carries an operation capability.
enum SharedMediaNativeAppOpenResult: Sendable {
    #if DEBUG
    case qualification(SharedMediaNativeOriginalSnapshot)
    #endif
    case initialization(SharedMediaStorageSnapshot)
    case dispatch(SharedMediaNativeScopedSnapshot)
}
