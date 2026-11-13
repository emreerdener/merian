import Foundation
import SwiftData

/// A copied AI-role input from the exact enrolled native baseline. This is not
/// a protected server reference or a file capability, and never owns execution.
struct ObservationReanalysisRetainedInput: Sendable {
    struct Origin: Equatable, Sendable {
        let source: ObservationReanalysisSource
        fileprivate let preparedBytes: Data
        fileprivate let cohort: SharedMediaNativeConsumerCohort.AppliedInitial
        fileprivate let association: NativeHistoryAssociation

        @MainActor func validate(context: ModelContext) throws {
            try source.validate(context: context)
            let prepared = try SharedMediaNativeReceivingIntent.Prepared.decode(preparedBytes)
            let inventoryID = prepared.profile.inventoryID
            let inventory = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else {
                throw SharedMediaStorageFailure.stale
            }
            let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(row, inventory: inventory, context: context)
            guard try applied.prepared.encoded() == preparedBytes, applied.cohort == cohort,
                  try NativeInitialHistoryBaseline.read(prepared, context: context)?.association == association else {
                throw SharedMediaStorageFailure.stale
            }
        }
    }

    struct Photo: Equatable, Sendable {
        let origin: Origin
        let pairID: UUID
        let roleID: UUID
        let byteCount: Int
        let sha256: String
        fileprivate let originalBytes: Data

        func validate(source: ObservationReanalysisSource, bytes: Data, edited: Bool) throws {
            guard origin.source == source, !bytes.isEmpty, bytes.count <= ObservationEvidenceUpload.maximumBytes,
                  edited || bytes == originalBytes else {
                throw ObservationHistoryError.invalidSnapshot
            }
        }
    }

    let origin: Origin
    let photos: [(photo: Photo, bytes: Data)]
    let descriptions: [String]

    private init(source: ObservationReanalysisSource, readback: SharedMediaNativeRetainedPhotoReadback,
                 association: NativeHistoryAssociation) throws {
        let prepared = readback.prepared
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        guard readback.role == .ai, source.ownerID == prepared.profile.ownerID,
              source.observationID == prepared.observationID, source.analysisID == association.baselineAnalysisID,
              association.snapshotSHA256 == ObservationHistoryEnrollmentIntent.baselineDigest(source.snapshot),
              readback.supportingBytes == frozen.supportingBytes, readback.photos.count == frozen.entries.count else {
            throw SharedMediaStorageFailure.stale
        }
        let origin = try Origin(source: source, preparedBytes: prepared.encoded(), cohort: readback.cohort, association: association)
        self.origin = origin
        photos = try zip(frozen.entries, readback.photos).map { entry, loaded in
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            guard loaded.pairID == intent.pairID, loaded.bytes.count == intent.ai.byteCount,
                  SharedMediaAcquisitionEncoding.digest(loaded.bytes) == intent.ai.sha256 else { throw SharedMediaStorageFailure.stale }
            return (.init(origin: origin, pairID: intent.pairID, roleID: intent.ai.id,
                byteCount: loaded.bytes.count, sha256: intent.ai.sha256, originalBytes: loaded.bytes), loaded.bytes)
        }
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            frozen.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        // Native submission orders its photos first, then the frozen contexts.
        descriptions = supporting.contexts.map(\.freeText)
    }

    func selection(_ ids: Set<UUID>) throws -> [(photo: Photo, bytes: Data)] {
        guard ids.isSubset(of: Set(photos.map { $0.photo.pairID })), ids.count <= 5 else { throw MerianError.invalidResponse }
        let selected = photos.filter { ids.contains($0.photo.pairID) }
        var count = 0
        for value in selected {
            guard value.bytes.count <= ObservationEvidenceUpload.maximumBytes - count else { throw MerianError.invalidResponse }
            count += value.bytes.count
        }
        return selected
    }

    @MainActor func validate(container: ModelContainer) throws {
        try ConfirmedSpeciesReviewPersistence.transaction { try origin.validate(context: ModelContext(container)) }
    }

    /// Only the original associated baseline offers native input. Other historical
    /// sources remain eligible for explicitly added photos, without parent fallback.
    @MainActor static func read(source: ObservationReanalysisSource, container: ModelContainer,
                                owner: @MainActor () async throws -> SharedMediaNativeOriginalOwner,
                                isCurrent: @MainActor () -> Bool) async throws -> Self? {
        func check() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            try source.validate(container: container)
        }
        try check()
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let baseline = try ObservationHistoryEnrollmentIntent.baseline(observationID: source.observationID,
            ownerID: source.ownerID, context: context), baseline.baselineAnalysisID == source.analysisID else { return nil }
        let id = source.observationID.uuidString.lowercased()
        let scan = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id }))
        guard case .nativeInitial(let binding) = try SharedMediaConsumerAuthority.classify(
            raw: scan.mediaAuthorityRaw, consumerID: scan.sharedMediaConsumerID, record: .scan) else { return nil }
        let native = try await owner(); try check()
        let prepared = try await native.appReceivingQuery(
            SharedMediaNativeReceivingQuery.retainedInitial(observationID: source.observationID, bindingID: binding))
        try check()
        let readback = try await native.readRetainedAppPhotos(prepared, role: .ai)
        try check()
        let association = try NativeHistoryAssociation(baseline)
        let value = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try Self(source: source, readback: readback, association: association)
        }
        try check()
        try value.validate(container: container)
        return value
    }
}
