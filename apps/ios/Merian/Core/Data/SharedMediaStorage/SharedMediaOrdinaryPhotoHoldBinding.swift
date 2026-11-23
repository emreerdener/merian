import Foundation

/// Binds ordinary hold descriptions to the existing native photo submission
/// bytes. It does not generalize the photo format to audio/video, create a
/// second observation DTO, prove persistence or grant file/execution authority.
struct SharedMediaOrdinaryPhotoHoldBinding: Sendable {
    /// Retain these exact bytes with admission. Digests alone cannot recover a
    /// submission after restart; mutable UI values must never reconstruct it.
    let submission: SharedMediaNativePreparationBlob
    /// Media order comes from frozen entry.position, never sorted hold UUIDs.
    let orderedRequests: [SharedMediaOrdinaryHoldRequest]

    init(holds: SharedMediaOrdinaryHoldCohort, submission: SharedMediaNativePreparationBlob) throws {
        try holds.validate(); try submission.validate()
        let frozen = try SharedMediaNativeFrozenCohort.decode(submission.bytes)
        guard frozen.entries.count == holds.requests.count else { throw SharedMediaStorageFailure.conflict }
        let byReference = Dictionary(uniqueKeysWithValues: holds.requests.map { ($0.source.referenceID, $0) })
        var ordered: [SharedMediaOrdinaryHoldRequest] = []
        for entry in frozen.entries {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let original = intent.preparation.original
            guard let request = byReference[original.reference.referenceID], request.source == original.reference,
                  request.profile.ownerID == frozen.ownerID, request.source.packageID == frozen.packageID,
                  request.source.draftGeneration == frozen.draftGeneration,
                  intent.preparation.inventoryID == request.profile.inventoryID,
                  intent.preparation.inventoryGeneration == request.profile.generation,
                  intent.preparation.inventoryRevision <= request.inventoryRevision,
                  intent.preparation.packageRevision <= request.sourcePackageRevision,
                  intent.preparation.membershipRevision <= request.sourceMembershipRevision,
                  request.recipient.observationSHA256 == submission.sha256,
                  request.recipient.preparationSHA256 == entry.intent.sha256,
                  original.token == request.acquisition.finalToken,
                  original.byteCount == request.completion.byteCount, original.sha256 == request.completion.sha256,
                  original.contentType == request.completion.contentType,
                  original.descriptor == request.completion.descriptor else { throw SharedMediaStorageFailure.conflict }
            ordered.append(request)
        }
        guard Set(ordered.map(\.id)) == Set(holds.requests.map(\.id)) else { throw SharedMediaStorageFailure.conflict }
        self.submission = submission; orderedRequests = ordered
    }
}
