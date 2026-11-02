import Foundation
import SwiftData

enum SharedMediaNativeRepositoryOpenKind { case qualificationEmpty, qualificationOriginal, scopedInspection, appInitialization, appDispatch }

/// Closed descriptive queries only. Callers cannot inject a callback into the
/// repository's retained read boundary or obtain its grant/container from it.
@MainActor
enum SharedMediaNativeReceivingQuery {
    @MainActor struct Read<Value: Sendable> {
        private let resolve: (ModelContainer, SharedMediaNativeAppProfile) throws -> Value
        fileprivate init(_ resolve: @escaping (ModelContainer, SharedMediaNativeAppProfile) throws -> Value) { self.resolve = resolve }
        func read(_ container: ModelContainer, profile: SharedMediaNativeAppProfile) throws -> Value { try resolve(container, profile) }
    }
    static func intent(_ packageID: UUID) -> Read<SharedMediaNativeReceivingIntent.Prepared?> {
        .init { try SharedMediaNativeRepositoryFacts.receivingIntent($0, profile: $1, packageID: packageID) }
    }
    static func slot(_ packageID: UUID) -> Read<SharedMediaNativeReceivingIntentGraph.Row?> {
        .init { try SharedMediaNativeRepositoryFacts.receivingSlot($0, inventoryID: $1.inventoryID, packageID: packageID) }
    }
    static func submission(_ packageID: UUID) -> Read<SharedMediaNativePhotoSubmissionState?> {
        .init { try SharedMediaNativeRepositoryFacts.photoSubmission($0, inventoryID: $1.inventoryID, packageID: packageID) }
    }
    static var candidates: Read<[SharedMediaNativeReceivedCandidate]> {
        .init { try SharedMediaNativeRepositoryFacts.receivedCandidates($0, profile: $1) }
    }
    static func received(_ candidate: SharedMediaNativeReceivedCandidate) -> Read<SharedMediaNativePhotoSubmissionState> {
        .init {
            guard candidate.profile == $1 else { throw SharedMediaStorageFailure.stale }
            return try SharedMediaNativeRepositoryFacts.receivedSubmission($0, candidate: candidate)
        }
    }
}

/// Fresh persisted facts only. File fences and capability construction remain
/// private to the repository; no helper here accepts or returns an authority.
@MainActor
enum SharedMediaNativeRepositoryFacts {
    static func empty(_ container: ModelContainer, inventoryID: UUID, storeIdentity: String,
                      rootBinding: String, generation: UUID) throws -> SharedMediaStorageSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let row = try SharedMediaNativeEligibility.emptyState(context, inventoryID: inventoryID,
            storeIdentity: storeIdentity, rootBinding: rootBinding), row.generation == generation else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }
    static func scoped(_ container: ModelContainer, scope: SharedMediaNativeScopeIdentity) throws -> SharedMediaStorageSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = try SharedMediaNativeScopedEligibility.header(context: context, scope: scope)
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }
    static func app(_ container: ModelContainer, scope: SharedMediaNativeScopeIdentity?) throws -> SharedMediaNativeAppEligibility.Header {
        guard let scope else { throw SharedMediaStorageFailure.closed }
        let context = ModelContext(container); context.autosaveEnabled = false
        return try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
    }
    static func receivingIntent(_ container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                packageID: UUID) throws -> SharedMediaNativeReceivingIntent.Prepared? {
        guard let row = try receivingSlot(container, inventoryID: profile.inventoryID, packageID: packageID) else { return nil }
        guard case .prepared(let value) = try SharedMediaNativeReceivingSlot.decode(row, profile: profile) else { throw SharedMediaStorageFailure.closed }
        return value
    }
    static func receivingSlot(_ container: ModelContainer, inventoryID: UUID,
                              packageID: UUID) throws -> SharedMediaNativeReceivingIntentGraph.Row? {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        return try SharedMediaNativeReceivingPhaseGraph.pending(context, inventory: inventory)[packageID]?.row
    }

    static func photoSubmission(_ container: ModelContainer, inventoryID: UUID,
                                packageID: UUID) throws -> SharedMediaNativePhotoSubmissionState? {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard let witness = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[packageID] else { return nil }
        switch witness {
        case .allocating(let value):
            return .init(prepared: value.prepared, receipt: value.transaction.cohort, allocation: value.allocation)
        case .generic(let value):
            switch value.slot {
            case .prepared(let prepared): return .init(prepared: prepared, receipt: nil, allocation: nil)
            case .received(let prepared, _, let transaction):
                return .init(prepared: prepared, receipt: transaction.cohort, allocation: nil)
            case .abandoned: throw SharedMediaStorageFailure.closed
            }
        case .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
    }

    static func receivedCandidates(_ container: ModelContainer, profile: SharedMediaNativeAppProfile) throws -> [SharedMediaNativeReceivedCandidate] {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile else { throw SharedMediaStorageFailure.stale }
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        return try witnesses.values.compactMap { witness in
            try receivedProjection(witness, profile: profile)?.0
        }.sorted { $0.packageID.uuidString < $1.packageID.uuidString }
    }

    static func receivedSubmission(_ container: ModelContainer, candidate: SharedMediaNativeReceivedCandidate) throws -> SharedMediaNativePhotoSubmissionState {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = candidate.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == candidate.profile,
              let witness = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[candidate.packageID],
              let (saved, submission) = try receivedProjection(witness, profile: candidate.profile),
              saved == candidate else { throw SharedMediaStorageFailure.stale }
        return submission
    }

    private static func receivedProjection(_ witness: SharedMediaNativeReceivingCleanGraph.Witness,
        profile: SharedMediaNativeAppProfile) throws -> (SharedMediaNativeReceivedCandidate, SharedMediaNativePhotoSubmissionState)? {
        let row: SharedMediaNativeReceivingIntentGraph.Row, submission: SharedMediaNativePhotoSubmissionState
        switch witness {
        case .allocating(let value):
            row = value.row
            submission = .init(prepared: value.prepared, receipt: value.transaction.cohort, allocation: value.allocation)
        case .generic(let value):
            guard case .received(let prepared, _, let transaction) = value.slot else { return nil }
            row = value.row
            submission = .init(prepared: prepared, receipt: transaction.cohort, allocation: nil)
        case .staged, .releasing: return nil
        }
        guard let resultHash = row.resultSHA256 else { throw SharedMediaStorageFailure.conflict }
        return (.init(profile: profile, packageID: row.id, draftGeneration: row.draftGeneration,
            operationID: row.operationID, revision: row.revision, preparedSHA256: row.preparedSHA256,
            receivedSHA256: resultHash), submission)
    }
}

/// Descriptive recovery projection from the clean graph. No create, execution
/// or release authority; generic receiving readers still reject sidecars.
struct SharedMediaNativePhotoSubmissionState: Sendable {
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let receipt: SharedMediaNativeConsumerCohort?
    let allocation: SharedMediaNativePhotoAllocation?
}
