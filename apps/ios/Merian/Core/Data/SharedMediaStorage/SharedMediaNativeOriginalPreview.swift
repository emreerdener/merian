import Foundation

/// One bounded raster and a fresh read-only scope check. No original path or bytes escape.
@MainActor
struct SharedMediaNativeOriginalPreview {
    let image: ImageDownsampler.SendableImage
    let index: Int
    let count: Int
    let validate: @MainActor () async throws -> Void
}

/// Internal physical seals remain owned by the native receiving boundary.
struct SharedMediaNativeOriginalPreviewRead: Sendable {
    let image: ImageDownsampler.SendableImage
    let index: Int
    let cohort: SharedMediaNativeConsumerCohort
    let proofs: [SharedMediaPhotoRetirementInspection]
}

extension SharedMediaNativeAppReceivingIO {
    static func readOriginal(_ prepared: SharedMediaNativeReceivingIntent.Prepared, index: Int,
                             io: SharedMediaNativeOriginalIO,
                             verify: (SharedMediaPhotoRetirementInspection) throws -> Void,
                             current: () throws -> SharedMediaNativeConsumerCohort) async throws -> SharedMediaNativeOriginalPreviewRead {
        let cohort = try current()
        guard prepared.version == 2, cohort.format == .intentReceiving else { throw SharedMediaStorageFailure.closed }
        let commit = try SharedMediaNativeFreezeCommit.decode(cohort.freeze.bytes)
        guard commit.cohort == prepared.cohort else { throw SharedMediaStorageFailure.stale }
        let frozen = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
        let originals = try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).preparation.original }
        guard originals.indices.contains(index) else { throw SharedMediaStorageFailure.closed }
        func check() throws {
            try Task.checkCancellation()
            guard try current() == cohort else { throw SharedMediaStorageFailure.stale }
        }
        var proofs: [SharedMediaPhotoRetirementInspection] = []
        for original in originals {
            try check()
            let proof = try await io.inspect(original.file)
            try check()
            guard proof.identity == original.descriptor else { throw SharedMediaStorageFailure.stale }
            try verify(proof); proofs.append(proof)
        }
        let image = try await io.previewOriginal(originals[index])
        try check()
        // Earlier siblings remain sealed after the selected image was decoded.
        for proof in proofs { try verify(proof) }
        return .init(image: image, index: index, cohort: cohort, proofs: proofs)
    }
}

@MainActor
struct SharedMediaNativeOriginalPreviewAccess {
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let io: SharedMediaNativeOriginalIO
    let verify: (SharedMediaPhotoRetirementInspection) throws -> Void
    let current: () throws -> SharedMediaNativeConsumerCohort

    func read(index: Int) async throws -> SharedMediaNativeOriginalPreviewRead {
        try await SharedMediaNativeAppReceivingIO.readOriginal(prepared, index: index, io: io, verify: verify, current: current)
    }
    func validate(_ read: SharedMediaNativeOriginalPreviewRead) throws {
        try Task.checkCancellation()
        guard try current() == read.cohort else { throw SharedMediaStorageFailure.stale }
        for proof in read.proofs { try verify(proof) }
    }
}

extension SharedMediaNativeOriginalOwner {
    /// Preview stays inside receiving locks and the original accounting owner.
    func previewReceivedAppOriginal(_ prepared: SharedMediaNativeReceivingIntent.Prepared, index: Int) async throws -> SharedMediaNativeOriginalPreview {
        let read = try await withReceivingLocks(queueID: prepared.queueID.uuidString, observationID: prepared.observationID.uuidString) { lock in
            try await self.appReceivingWorkflow(lock: lock) { try await $0.originalPreviewAccess(prepared).read(index: index) }
        }
        return .init(image: read.image, index: read.index, count: read.proofs.count, validate: {
            try await self.withReceivingLocks(queueID: prepared.queueID.uuidString, observationID: prepared.observationID.uuidString) { lock in
                try await self.appReceivingWorkflow(lock: lock) { try $0.originalPreviewAccess(prepared).validate(read) }
            }
        })
    }
}
