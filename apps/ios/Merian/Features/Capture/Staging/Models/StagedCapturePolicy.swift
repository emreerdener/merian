/// Normal evidence capacity across images, audio clips, videos, and descriptions.
/// Refinement permits one explicitly marked supplementary description beyond this budget.
let stagedCaptureCapacity = 2

/// Visual captures still top out at the same total staged capacity today.
let stagedImageCapacity = stagedCaptureCapacity

extension StagedCapture {
    var refinementSupplementIndex: Int? {
        observationContexts.firstIndex(where: \.isRefinementSupplement)
    }

    /// Refinement permits one description in addition to the normal evidence budget.
    /// Historical descriptions remain evidence; only the current supplement is exempt.
    func availableEvidenceSlots(limit: Int, isRefining: Bool) -> Int {
        let supplementCount = isRefining && refinementSupplementIndex != nil ? 1 : 0
        return max(0, limit - (totalItemCount - supplementCount))
    }

    var canStageRefinementDescription: Bool {
        let supplements = observationContexts.filter(\.isRefinementSupplement).count
        return supplements <= 1
            && totalItemCount - supplements <= stagedCaptureCapacity
    }

    mutating func clearRefinementDescriptionAssociation() {
        for index in observationContexts.indices {
            observationContexts[index].isRefinementSupplement = false
        }
    }
}
