import Foundation

/// Bounded derivative values only. Originals stay with the native processor;
/// these bytes cannot be used as original crop sources or storage capabilities.
struct SharedMediaNativePhotoReadback: Sendable {
    struct Photo: Sendable {
        let pair: SharedMediaNativePairFileState
        let original: PhotoOriginalReference
        let ai: Data
        let display: Data
    }
    let metadata: SharedMediaNativeAppMetadataRequest
    let photos: [Photo]

    /// Validate the complete selection and both aggregate budgets before any
    /// payload allocation. The caller separately seals live authority and files.
    static func validate(metadata: SharedMediaNativeAppMetadataRequest, pairs: [SharedMediaNativePairFileState]) throws {
        let package = metadata.package
        guard metadata.envelope == package.envelope, package.phase == "draftOwned",
              package.tier == "pending", !package.retiring, (1...2).contains(pairs.count),
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(metadata.envelope),
              envelope.attempt == nil, envelope.frozen == nil,
              envelope.intents == pairs.map(\.plan.intent) else { throw SharedMediaStorageFailure.closed }
        let intents = try pairs.map { try $0.intent() }
        guard Set(intents.map(\.pairID)).count == pairs.count else { throw SharedMediaStorageFailure.conflict }
        for (pair, intent) in zip(pairs, intents) {
            let original = intent.preparation.original.reference
            guard pair.phase == "ready", pair.publishedRevision != nil,
                  pair.plan.inventoryID == metadata.profile.inventoryID,
                  pair.plan.inventoryGeneration == metadata.profile.generation,
                  pair.plan.packageID == package.id, pair.plan.draftGeneration == package.generation,
                  original.ownerID == metadata.profile.ownerID, original.packageID == package.id,
                  original.draftGeneration == package.generation else { throw SharedMediaStorageFailure.stale }
            for input in [intent.ai, intent.display] {
                try input.validate()
                let (work, _) = try pair.selected(input.id)
                guard work.phase == "completed", work.writerState == "closed", work.finalIdentity != nil,
                      work.retirementID == nil, work.closure == nil else { throw SharedMediaStorageFailure.closed }
            }
        }
        let ai = try PhotoPreparationPolicy.add(intents.map(\.ai.byteCount))
        let display = try PhotoPreparationPolicy.add(intents.map(\.display.byteCount))
        guard ai <= PhotoPreparationPolicy.aiCohort, display <= PhotoPreparationPolicy.displayCohort else {
            throw PhotoPreparationFailure.sizeLimit
        }
    }
}
