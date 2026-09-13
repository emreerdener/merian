import Foundation

/// Deterministic projection of a staged capture into the bottom toolbar.
struct CaptureStagingToolbarPresentation {
    let visibleNodes: [StagedCaptureNode]
    let photoSelectionCount: Int?
    let submitTitle: String
    let isSubmitDisabled: Bool

    init(
        stagedCapture: StagedCapture,
        isRefining: Bool,
        stagedCaptureLimit: Int
    ) {
        visibleNodes = stagedCapture.orderedNodes.filter { node in
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
        } else if visibleNodes.count < stagedCaptureLimit {
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
