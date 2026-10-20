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
    func inspect(_ file: PhotoPreparationFile) throws -> SharedMediaPhotoRetirementInspection { try files.inspectSharedRetirement(file) }
    func release(_ retirement: SharedMediaNativeRetirement) throws -> SharedMediaNativeReleaseProof { try files.releaseNative(retirement) }
    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) { files.sharedReleaseFault = fault }
    #endif
    #if DEBUG
    private var acquisitionEntryPause: (@Sendable (SharedMediaNativeOriginalIOEntry) async -> Void)?
    func setAcquisitionEntryPause(_ pause: (@Sendable (SharedMediaNativeOriginalIOEntry) async -> Void)?) { acquisitionEntryPause = pause }
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
        return try withPair(disposal.state, workID: workID, create: false) { try $0.release(disposal) }
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
enum SharedMediaNativeOriginalIOEntry: Sendable { case load, write, beginPair, recoverPair, releasePair }
#endif
