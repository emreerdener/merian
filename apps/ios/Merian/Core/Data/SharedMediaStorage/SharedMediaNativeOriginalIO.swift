import Foundation

/// Uses the repository's already-held files. Never acquires a second namespace
/// owner; no context, model, descriptor or file URL crosses this actor boundary.
actor SharedMediaNativeOriginalIO {
    private let files: PhotoPreparationLockedFiles
    private let binding: SharedMediaNativeBinding
    private let pause: (@Sendable () async -> Void)?

    init(files: PhotoPreparationLockedFiles, binding: SharedMediaNativeBinding,
         pause: (@Sendable () async -> Void)?) {
        self.files = files; self.binding = binding; self.pause = pause
    }

    func visit(_ observe: @Sendable (PhotoPreparationNativeLeaf) async throws -> Void) async throws {
        await pause?()
        try Task.checkCancellation()
        try await files.visitNativeNamespace(observe)
    }

    func verify(request: SharedMediaAcquisitionIntent, result: SharedMediaAcquisitionResult,
                retirement: SharedMediaNativeRetirementIdentity?) async throws {
        await pause?()
        try Task.checkCancellation()
        let file = PhotoPreparationFile(assetID: request.assetID, generation: request.assetGeneration,
            token: request.finalToken, byteCount: result.byteCount, sha256: result.sha256, contentType: result.contentType)
        do {
            let observed = try files.inspectSharedRetirement(file)
            guard observed.identity == result.descriptor, observed.binding == binding.bytes,
                  observed.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        } catch PhotoPreparationFailure.missingMedia {
            guard let retirement else { throw PhotoPreparationFailure.missingMedia }
            try files.requireNativeAbsence(file, retirement: retirement, binding: binding)
        }
    }
    func inspectPending(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativePendingInspection {
        try files.inspectNativePending(request, binding: binding)
    }
    func verifyPending(_ request: SharedMediaAcquisitionIntent, closure: SharedMediaNativePendingClosure) throws {
        try files.verifyNativePending(request, closure: closure, binding: binding)
    }
    func releasePending(_ disposal: SharedMediaNativePendingDisposal) throws -> SharedMediaNativePendingAbsence { try files.releaseNativePending(disposal) }
    func inspect(_ file: PhotoPreparationFile) throws -> SharedMediaPhotoRetirementInspection { try files.inspectSharedRetirement(file) }
    func release(_ retirement: SharedMediaNativeRetirement) throws -> SharedMediaNativeReleaseProof { try files.releaseNative(retirement) }
    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) { files.sharedReleaseFault = fault }
    #endif
    func load(_ provider: @Sendable () async throws -> Data) async throws -> Data { try await provider() }

    func write(_ data: Data, request: SharedMediaAcquisitionIntent) throws -> SharedMediaPhotoRetirementInspection {
        let intent = PhotoPreparationIntent(leaseID: request.operationID, ownerID: request.ownerID, packageID: request.packageID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, referenceID: request.referenceID,
            draftGeneration: request.draftGeneration, processEpoch: request.writerEpoch, role: .original,
            ordinal: request.ordinal, acquisitionKind: request.kind.rawValue, maximumBytes: request.maximumBytes)
        return try files.inspectSharedRetirement(files.write(data, intent: intent))
    }

}
