/// Physical media capacity. Ordinary notes and historical/current refinement text
/// have separate budgets and do not consume physical media slots.
let stagedCaptureCapacity = 2

/// Visual captures still top out at the same total staged capacity today.
let stagedImageCapacity = stagedCaptureCapacity

extension StagedCapture {
    var refinementSupplementIndex: Int? {
        observationContexts.firstIndex(where: \.isRefinementSupplement)
    }

    /// Historical text remains evidence without reducing physical capacity.
    func availableEvidenceSlots(limit: Int, isRefining _: Bool) -> Int {
        availableSlots(limit: limit)
    }

    var canStageRefinementDescription: Bool {
        let supplements = observationContexts.filter(\.isRefinementSupplement).count
        return physicalItemCount <= stagedCaptureCapacity && supplements <= 1
    }

    mutating func clearRefinementDescriptionAssociation() {
        for index in observationContexts.indices {
            observationContexts[index].isRefinementSupplement = false
        }
    }
}
