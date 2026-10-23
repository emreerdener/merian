import Foundation

/// Inert lifecycle values only. The registered owner keeps its state properties
/// private; constructing these values cannot install state or mint any grant.
enum SharedMediaNativeOriginalOpenKind { case qualification, scopedInspection, appInitialization, appDispatch }
enum SharedMediaNativeOriginalPhase { case unopened, opening, ready, failed, suspended }
struct SharedMediaNativeOriginalPendingSettlement {
    let id = UUID()
    let request: SharedMediaAcquisitionIntent
    let loaderStarted: Bool
    let writerReturned: Bool
    var appTicket: SharedMediaNativeAppAcquisitionSettlement? = nil
}
