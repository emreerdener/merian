import Foundation

@MainActor
extension SharedMediaNativeOriginalOwner {
    func describeAppOrdinaryPhotoHolds(submission: SharedMediaNativePreparationBlob, holdIDs: [UUID],
                                       scanID: UUID, submissionGeneration: UUID, eventID: UUID) async throws -> SharedMediaOrdinaryPhotoHoldBinding {
        try await appOriginalLifecycle {
            try $0.describeOrdinaryPhotoHolds(submission: submission, holdIDs: holdIDs,
                scanID: scanID, submissionGeneration: submissionGeneration, eventID: eventID)
        }
    }
    func describeAppOrdinaryHold(_ source: PhotoOriginalReference, id: UUID,
                                 recipient: SharedMediaOrdinaryHoldRequest.Recipient) async throws -> SharedMediaOrdinaryHoldRequest {
        try await appOriginalLifecycle { try $0.describeOrdinaryHold(source, id: id, recipient: recipient) }
    }
    func prepareAppOriginalShare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) async throws -> SharedMediaNativeAppOriginalRequest {
        try await appOriginalLifecycle { try $0.prepareShare(source, packageID: packageID, generation: draftGeneration) }
    }
    func shareAppOriginal(_ request: SharedMediaNativeAppOriginalRequest) async throws -> PhotoOriginalReference {
        try await appOriginalLifecycle { try await $0.share(request) }
    }
    func prepareAppOriginalRemoval(_ source: PhotoOriginalReference) async throws -> SharedMediaNativeAppOriginalRequest {
        try await appOriginalLifecycle { try $0.prepareRemoval(source) }
    }
    func removeAppOriginal(_ request: SharedMediaNativeAppOriginalRequest) async throws {
        try await appOriginalLifecycle { try await $0.remove(request) }
    }
    func recoverAppOriginalRetirements() async throws {
        while try await appOriginalLifecycle({ try await $0.recoverOne() }) { try Task.checkCancellation() }
    }
    #if DEBUG
    func setAppOriginalReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try await appOriginalLifecycle { try await $0.setReleaseFault(fault) }
    }
    #endif
}
