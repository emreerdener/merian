import Foundation
import Observation

/// The outer presentation keeps one identity while its selected media changes.
/// Child navigation never dismisses the presentation or releases the camera.
@MainActor @Observable
final class CaptureMediaReviewSession: Identifiable {
    let id = UUID()
    let draftGeneration: UUID
    let accountID: UUID?
    var selectedNodeID: String
    var historicalDescriptionID: UUID?

    init(draftGeneration: UUID, accountID: UUID?, selectedNodeID: String) {
        self.draftGeneration = draftGeneration
        self.accountID = accountID
        self.selectedNodeID = selectedNodeID
    }
}
