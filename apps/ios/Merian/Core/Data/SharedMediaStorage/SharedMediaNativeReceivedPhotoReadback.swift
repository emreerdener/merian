import Foundation
import SwiftData

/// Immutable local input, not provider dispatch, funding or file authority.
/// The existing execution owner must separately admit this same identity.
struct SharedMediaNativeReceivedPhotoReadback: Sendable {
    struct Photo: Sendable {
        let pairID: UUID
        let ai: Data
    }
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let cohort: SharedMediaNativeConsumerCohort
    let supportingBytes: Data
    let photos: [Photo]
}

/// Bounded I/O inside the existing receiving operation and its retained locks.
@MainActor
enum SharedMediaNativeAppReceivingIO {
    static func inspect(_ states: [SharedMediaNativePairFileState], io: SharedMediaNativeOriginalIO,
                        check: () throws -> Void,
                        verify: (SharedMediaPhotoRetirementInspection) throws -> Void) async throws -> [SharedMediaPhotoRetirementInspection] {
        var proofs: [SharedMediaPhotoRetirementInspection] = []
        for state in states {
            let intent = try state.intent()
            for file in [intent.preparation.original.file, try state.file(intent.ai.id), try state.file(intent.display.id)] {
                try check()
                let proof = try await io.inspect(file)
                try check(); try verify(proof); proofs.append(proof)
            }
        }
        return proofs
    }

    static func read(_ prepared: SharedMediaNativeReceivingIntent.Prepared, container: ModelContainer,
                     io: SharedMediaNativeOriginalIO,
                     verify: (SharedMediaNativePairCompletion) throws -> Void,
                     current: () throws -> SharedMediaNativeConsumerCohort) async throws -> SharedMediaNativeReceivedPhotoReadback {
        let cohort = try current()
        guard prepared.version == 2, cohort.format == .intentReceiving else { throw SharedMediaStorageFailure.closed }
        let commit = try SharedMediaNativeFreezeCommit.decode(cohort.freeze.bytes)
        let frozen = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
        guard commit.cohort == prepared.cohort else { throw SharedMediaStorageFailure.stale }
        let intents = try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes) }
        guard try PhotoPreparationPolicy.add(intents.map(\.ai.byteCount)) <= PhotoPreparationPolicy.aiCohort else {
            throw PhotoPreparationFailure.sizeLimit
        }
        func states() throws -> [SharedMediaNativePairFileState] {
            try Task.checkCancellation()
            guard try current() == cohort else { throw SharedMediaStorageFailure.stale }
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventoryID = prepared.profile.inventoryID, packageID = prepared.package.id
            let inventory = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let package = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
            let member = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
            return try intents.map { intent in
                let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                    package: package, member: member, pairID: intent.pairID)
                guard state.phase == "ready", state.publishedRevision != nil,
                      try state.intent() == intent else { throw SharedMediaStorageFailure.stale }
                return state
            }
        }
        let selected = try states()
        var photos: [SharedMediaNativeReceivedPhotoReadback.Photo] = []
        var proofs: [SharedMediaNativePairCompletion] = []
        for (state, intent) in zip(selected, intents) {
            guard try states() == selected else { throw SharedMediaStorageFailure.stale }
            let (bytes, proof) = try await io.readCompletedPair(state, workID: intent.ai.id)
            guard try states() == selected, Int64(bytes.count) == intent.ai.byteCount,
                  SharedMediaAcquisitionEncoding.digest(bytes) == intent.ai.sha256 else { throw SharedMediaStorageFailure.stale }
            proofs.append(proof)
            photos.append(.init(pairID: intent.pairID, ai: bytes))
        }
        // Earlier files must still match after reading a later photo. No await
        // separates these physical seals, the final authority check and return.
        guard try states() == selected else { throw SharedMediaStorageFailure.stale }
        for proof in proofs { try verify(proof) }
        try Task.checkCancellation()
        return .init(prepared: prepared, cohort: cohort, supportingBytes: frozen.supportingBytes, photos: photos)
    }
}

/// Bounded retained derivative bytes, never paths, fresh inference or export authority.
struct SharedMediaNativeRetainedPhotoReadback: Sendable {
    enum Role: Sendable { case ai, display }
    struct Photo: Sendable { let pairID: UUID; let bytes: Data }
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let cohort: SharedMediaNativeConsumerCohort.AppliedInitial
    let role: Role
    let supportingBytes: Data
    let photos: [Photo]
}

extension SharedMediaNativeAppReceivingIO {
    static func originalFacts(_ cohort: SharedMediaNativeFrozenCohort, context: ModelContext,
                              inventoryID: UUID) throws -> [SharedMediaNativeOriginalAccounting.Snapshot] {
        try cohort.entries.map { entry in
            let original = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original
            return try SharedMediaNativeOriginalAccounting.audit(assetID: original.reference.assetID,
                inventoryID: inventoryID, context: context)
        }
    }

    static func readRetained(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                             role: SharedMediaNativeRetainedPhotoReadback.Role, container: ModelContainer,
                             io: SharedMediaNativeOriginalIO, verify: (SharedMediaNativePairCompletion) throws -> Void,
                             check: () throws -> Void) async throws -> SharedMediaNativeRetainedPhotoReadback {
        typealias Applied = SharedMediaNativePhotoAllocationSnapshot.Applied
        func current() throws -> Applied {
            try Task.checkCancellation(); try check()
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventoryID = prepared.profile.inventoryID
            let inventory = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else {
                throw SharedMediaStorageFailure.closed
            }
            let applied = try Applied.read(row, inventory: inventory, context: context, checkpoint: check)
            guard try applied.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            return applied
        }
        let applied = try current()
        let commit = try SharedMediaNativeFreezeCommit.decode(applied.cohort.original.freeze.bytes)
        let frozen = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
        let intents = try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes) }
        let inputs = intents.map { role == .ai ? $0.ai : $0.display }
        guard try PhotoPreparationPolicy.add(inputs.map(\.byteCount)) <= (role == .ai ? PhotoPreparationPolicy.aiCohort : PhotoPreparationPolicy.displayCohort) else {
            throw PhotoPreparationFailure.sizeLimit
        }
        func states() throws -> [SharedMediaNativePairFileState] {
            let fresh = try current()
            guard fresh.row == applied.row, fresh.cohort == applied.cohort, fresh.header == applied.header else {
                throw SharedMediaStorageFailure.stale
            }
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventoryID = prepared.profile.inventoryID, packageID = prepared.package.id
            let inventory = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let package = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
            return try intents.map { intent in
                let state = try SharedMediaNativePairFileGraph.retainedState(fresh, pairID: intent.pairID,
                    context: context, inventory: inventory, package: package)
                guard state.phase == "ready", state.publishedRevision != nil,
                      try state.intent() == intent else { throw SharedMediaStorageFailure.stale }
                return state
            }
        }
        let selected = try states()
        var photos: [SharedMediaNativeRetainedPhotoReadback.Photo] = []
        var proofs: [SharedMediaNativePairCompletion] = []
        for (index, input) in inputs.enumerated() {
            guard try states() == selected else { throw SharedMediaStorageFailure.stale }
            let (bytes, proof) = try await io.readCompletedPair(selected[index], workID: input.id)
            guard try states() == selected, Int64(bytes.count) == input.byteCount,
                  SharedMediaAcquisitionEncoding.digest(bytes) == input.sha256 else { throw SharedMediaStorageFailure.stale }
            proofs.append(proof); photos.append(.init(pairID: intents[index].pairID, bytes: bytes))
        }
        // Seal earlier files again after the final awaited read. No capabilities escape.
        guard try states() == selected else { throw SharedMediaStorageFailure.stale }
        for proof in proofs { try verify(proof) }
        try Task.checkCancellation(); try check()
        return .init(prepared: prepared, cohort: applied.cohort, role: role, supportingBytes: frozen.supportingBytes, photos: photos)
    }
}
