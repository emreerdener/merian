import Foundation

/// Optional item edits are committed before navigation or whole-draft submission.
/// IDs are draft-local; neither this state nor its tokens enter saved requests.
enum CapturePhotoReviewAction: Equatable {
    case identify
    case selectMedia(String)
    case addMore
    case fieldNotes
    case historicalDescription(UUID)

}

struct CapturePhotoReviewCommit: Equatable {
    let id = UUID()
    let imageID: UUID
    let generation: UUID
    let accountID: UUID?
    let action: CapturePhotoReviewAction
}
