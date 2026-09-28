import Foundation

/// Deterministic projection of a staged capture into the bottom toolbar.
struct CaptureStagingToolbarPresentation {
    let visibleNodes: [StagedCaptureNode]
    let photoSelectionCount: Int?
    let submitTitle: String
    let isSubmitDisabled: Bool

    /// Every unused physical-media slot is visible, independently of shared text.
    var emptyMediaSlotCount: Int { photoSelectionCount ?? 0 }

    init(
        stagedCapture: StagedCapture,
        isRefining: Bool,
        stagedCaptureLimit: Int
    ) {
        visibleNodes = stagedCapture.orderedNodes.filter { node in
            if case .description(_, let description) = node {
                return isRefining && !description.isRefinementSupplement
            }
            if case .video(_, let stagedVideo) = node {
                return stagedVideo.coverImage != nil
            }
            return true
        }

        if isRefining {
            let slots = stagedCapture.availableEvidenceSlots(
                limit: stagedCaptureLimit,
                isRefining: true
            )
            photoSelectionCount = slots > 0 ? slots : nil
        } else if stagedCapture.physicalItemCount < stagedCaptureLimit {
            photoSelectionCount = max(
                1,
                stagedCapture.availableSlots(limit: stagedCaptureLimit)
            )
        } else {
            photoSelectionCount = nil
        }

        submitTitle = isRefining ? "Analyze" : "Identify"
        isSubmitDisabled = stagedCapture.isEmpty
    }
}
