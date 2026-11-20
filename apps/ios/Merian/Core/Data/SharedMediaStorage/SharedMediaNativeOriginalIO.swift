import Foundation

/// Uses the repository's already-held files. Never acquires a second namespace
/// owner. Verified URLs stay scoped to the sealed native photo processor and
/// never escape to Capture or callers; contexts/models and raw descriptors stay private.
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
    func verifyReleasePrefix(_ prefix: SharedMediaNativeReleasePrefix) throws {
        try Task.checkCancellation()
        try prefix.verify(files: files, binding: binding)
    }
    func inspect(_ file: PhotoPreparationFile) throws -> SharedMediaPhotoRetirementInspection { try files.inspectSharedRetirement(file) }
    func inspectHeldOriginal(_ state: SharedMediaNativeRetirementState) async throws -> SharedMediaNativeHeldOriginalInspection {
        try Task.checkCancellation()
        let proof = try files.inspectHeldOriginal(state, binding: binding)
        #if DEBUG
        await acquisitionEntryPause?(.inspectOriginal)
        #endif
        // Deliver the observation even if authority was revoked during the hop.
        // The caller records it before checking authority; this grants no I/O.
        return proof
    }
    func release(_ retirement: SharedMediaNativeRetirement) async throws -> SharedMediaNativeReleaseProof {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.releaseOriginal)
        #endif
        try Task.checkCancellation()
        return try files.releaseNative(retirement, binding: binding)
    }
    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) { files.sharedReleaseFault = fault }
    #endif
    #if DEBUG
    private var acquisitionEntryPause: (@Sendable (SharedMediaNativeOriginalIOEntry) async -> Void)?
    private var transferReadFault: (@Sendable (Int64) throws -> Void)?
    func setAcquisitionEntryPause(_ pause: (@Sendable (SharedMediaNativeOriginalIOEntry) async -> Void)?, transferReadFault: (@Sendable (Int64) throws -> Void)?) { acquisitionEntryPause = pause; self.transferReadFault = transferReadFault }
    #endif
    func load(_ provider: @Sendable () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.load)
        #endif
        try Task.checkCancellation()
        return try await provider()
    }

    func preparePhoto(_ attempt: SharedMediaNativePreparationAttempt, focusFactory: ImageFocusWorkFactory) async throws -> SharedMediaNativePreparedOutputs {
        try Task.checkCancellation()
        let file = attempt.original.file
        let before = try files.inspectSharedRetirement(file)
        guard before.identity == attempt.original.descriptor, before.binding == binding.bytes,
              before.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        let result = try await SharedMediaNativePhotoProcessor.prepare(url: files.preparationURL(file), attempt: attempt, focusFactory: focusFactory)
        try Task.checkCancellation()
        let after = try files.inspectSharedRetirement(file)
        guard after.identity == before.identity, after.binding == before.binding, after.epoch == before.epoch else {
            throw SharedMediaStorageFailure.conflict
        }
        return result
    }

    func previewOriginal(_ original: SharedMediaNativeOriginalIdentity) async throws -> ImageDownsampler.SendableImage {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.previewOriginal)
        #endif
        try Task.checkCancellation()
        let before = try files.inspectSharedRetirement(original.file)
        guard before.identity == original.descriptor, before.binding == binding.bytes,
              before.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        guard let image = ImageDownsampler.downsampledSendableImage(url: try files.preparationURL(original.file),
            maxSize: ImagePreparationPolicy.displayMaxDimension) else { throw SharedMediaStorageFailure.closed }
        try Task.checkCancellation()
        try files.requireCurrentSharedInspection(before)
        return image
    }

    func verifyPair(_ state: SharedMediaNativePairFileState) throws {
        if case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(state.plan.envelope), let frozen = envelope.frozen {
            let commit = try SharedMediaNativeFreezeCommit.decode(frozen.bytes)
            let cohort = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
            guard let entry = cohort.entries.first(where: { $0.intent == state.plan.intent }) else { throw SharedMediaStorageFailure.conflict }
            let intent = try state.intent()
            for (id, expected) in [(intent.ai.id, entry.aiDescriptor), (intent.display.id, entry.displayDescriptor)] {
                let proof = try files.inspectSharedRetirement(state.file(id))
                guard proof.identity == expected, proof.binding == binding.bytes, proof.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
            }
        }
        for work in state.work {
            try files.withNativePairDestination(state, workID: work.id, binding: binding, create: false) { try $0.verify() }
        }
    }
    #if DEBUG
    private var pairFault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?
    func setPairFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) { pairFault = fault }
    #endif
    private func withPair<T>(_ state: SharedMediaNativePairFileState, workID: UUID, create: Bool,
                             _ body: (SharedMediaNativePairFiles) throws -> T) throws -> T {
        try files.withNativePairDestination(state, workID: workID, binding: binding, create: create) { value in
            var value = value
            #if DEBUG
            value.fault = pairFault
            #endif
            return try body(value)
        }
    }
    func releasePair(_ disposal: SharedMediaNativePairDisposal, workID: UUID) async throws -> SharedMediaNativePairAbsence {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.releasePair)
        #endif
        try Task.checkCancellation()
        // A held disposal carries its own opaque permit, so ordinary entry
        // cannot bypass revocation. No actor hop/re-entrant fault inside body.
        return try disposal.withCurrent(workID: workID) {
            try withPair(disposal.state, workID: workID, create: false) { try $0.release(disposal) }
        }
    }
    func beginPair(_ state: SharedMediaNativePairFileState, workID: UUID) async throws -> SharedMediaNativePairPartial {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.beginPair)
        #endif
        try Task.checkCancellation()
        return try withPair(state, workID: workID, create: true) { try $0.begin() }
    }
    func writePair(_ data: Data, state: SharedMediaNativePairFileState, workID: UUID) throws -> SharedMediaNativePairCompletion {
        try withPair(state, workID: workID, create: false) { try $0.write(data) }
    }
    func inspectCompletedPair(_ state: SharedMediaNativePairFileState, workID: UUID) throws -> SharedMediaNativePairCompletion {
        try withPair(state, workID: workID, create: false) { try $0.inspectCompleted() }
    }
    /// The same completion proof seals inspection, actual-byte read and final
    /// physical identity. No path or file capability is returned to Capture.
    func readCompletedPair(_ state: SharedMediaNativePairFileState, workID: UUID) async throws -> (Data, SharedMediaNativePairCompletion) {
        try Task.checkCancellation()
        guard state.phase == "ready" else { throw SharedMediaStorageFailure.closed }
        let (_, input) = try state.selected(workID)
        try input.validate()
        let proof = try inspectCompletedPair(state, workID: workID)
        #if DEBUG
        await acquisitionEntryPause?(.readPair)
        #endif
        try Task.checkCancellation()
        let bytes = try files.read(proof.file)
        try files.requireCurrentPairCompletion(proof, binding: binding)
        return (bytes, proof)
    }
    /// Reuses the sealed 64 KiB hash/count reader. No whole-file Data, staging
    /// copy, path, descriptor or caller-controlled chunk consumer can escape.
    func verifyTransfer(_ state: SharedMediaNativePairFileState,
                        reservation: SharedMediaNativePhotoTransferReservation) async throws -> (SharedMediaPhotoRetirementInspection, SharedMediaNativePairCompletion?) {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.readTransfer)
        #endif
        try Task.checkCancellation()
        let intent = try state.intent()
        let file: PhotoPreparationFile
        let workID: UUID?
        if reservation.selection.role == .source {
            file = intent.preparation.original.file; workID = nil
        } else {
            let selected = reservation.selection.role == .ai ? intent.ai.id : intent.display.id
            file = try state.file(selected); workID = selected
        }
        guard state.phase == "ready", intent.pairID == reservation.pairID,
              file.assetID == reservation.assetID, file.generation == reservation.assetGeneration,
              file.byteCount == reservation.byteCount, file.sha256 == reservation.sha256,
              file.contentType == reservation.contentType else { throw SharedMediaStorageFailure.stale }
        // Reject a different named inode/generation before reading its bytes.
        // The hash reader also compares its opened and named descriptors after I/O.
        try files.requireSharedIdentity(file, identity: reservation.descriptor, binding: binding)
        let completion = try workID.map { try inspectCompletedPair(state, workID: $0) }
        #if DEBUG
        // Install only around this role read, never an earlier MainActor audit.
        files.sharedReadFault = transferReadFault
        defer { files.sharedReadFault = nil }
        #endif
        let proof = try files.inspectSharedRetirement(file)
        guard proof.identity == reservation.descriptor, proof.binding == binding.bytes,
              proof.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        if let completion { try files.requireCurrentPairCompletion(completion, binding: binding) }
        try Task.checkCancellation()
        return (proof, completion)
    }
    /// The receiving owner holds queue/observation exclusion and its account
    /// lease across this entire call. Ready files cannot be rewritten, and
    /// received cleanup uses those same locks. Actor isolation alone is not the
    /// exclusion guarantee while the concrete upload awaits its callback.
    func uploadTransfer(_ state: SharedMediaNativePairFileState,
                        reservation: SharedMediaNativePhotoTransferReservation,
                        upload: SharedMediaNativePhotoUpload,
                        validate: @MainActor @Sendable () throws -> Void) async throws -> SharedMediaNativePhotoUpload.Readback {
        _ = try await verifyTransfer(state, reservation: reservation)
        try await validate()
        try Task.checkCancellation()
        let intent = try state.intent()
        let file = try reservation.selection.role == .source ? intent.preparation.original.file
            : state.file(reservation.selection.role == .ai ? intent.ai.id : intent.display.id)
        try files.requireSharedIdentity(file, identity: reservation.descriptor, binding: binding)
        // consume joins actual termination on success AND failure before this
        // owner can unwind. No staging copy or whole-original Data is created.
        let status = try await upload.consume(file: files.preparationURL(file))
        let (proof, completion) = try await verifyTransfer(state, reservation: reservation)
        return .init(statusCode: status, inspection: proof, completion: completion)
    }
    func recoverPair(_ state: SharedMediaNativePairFileState, workID: UUID) async throws -> SharedMediaNativePairCompletion? {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.recoverPair)
        #endif
        try Task.checkCancellation()
        return try withPair(state, workID: workID, create: false) { try $0.recover() }
    }
    func inspectPlannedPairAbsent(_ state: SharedMediaNativePairFileState) throws -> [SharedMediaNativePlannedAbsence] {
        try Task.checkCancellation()
        return try state.work.map { work in
            try withPair(state, workID: work.id, create: false) { try $0.inspectPlannedAbsent() }
        }
    }
    func inspectRetiringPair(_ state: SharedMediaNativePairFileState, workID: UUID) throws -> SharedMediaNativeRetiringPairInspection {
        try withPair(state, workID: workID, create: false) { try $0.inspectRetiring() }
    }
    func inspectPair(_ state: SharedMediaNativePairFileState, workID: UUID) throws -> SharedMediaNativePairInspection {
        try withPair(state, workID: workID, create: false) { try $0.inspect() }
    }

    func write(_ data: Data, request: SharedMediaAcquisitionIntent) async throws -> SharedMediaPhotoRetirementInspection {
        try Task.checkCancellation()
        #if DEBUG
        await acquisitionEntryPause?(.write)
        #endif
        try Task.checkCancellation()
        let intent = PhotoPreparationIntent(leaseID: request.operationID, ownerID: request.ownerID, packageID: request.packageID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, referenceID: request.referenceID,
            draftGeneration: request.draftGeneration, processEpoch: request.writerEpoch, role: .original,
            ordinal: request.ordinal, acquisitionKind: request.kind.rawValue, maximumBytes: request.maximumBytes)
        return try files.inspectSharedRetirement(files.write(data, intent: intent))
    }

}

#if DEBUG
enum SharedMediaNativeOriginalIOEntry: Sendable { case previewOriginal, readPair, readTransfer, load, write, beginPair, recoverPair, releasePair, releaseOriginal, inspectOriginal }
#endif
