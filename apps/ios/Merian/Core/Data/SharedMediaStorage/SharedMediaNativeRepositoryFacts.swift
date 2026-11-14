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
    static func initialContinuation(_ candidate: SharedMediaNativeReceivedCandidate) -> Read<SharedMediaNativeInitialContinuation?> {
        .init { try SharedMediaNativeRepositoryFacts.initialContinuation($0, profile: $1, candidate: candidate) }
    }
    static func retainedInitial(observationID: UUID, bindingID: UUID) -> Read<SharedMediaNativeReceivingIntent.Prepared> {
        .init { try SharedMediaNativeRepositoryFacts.retainedInitial($0, profile: $1, observationID: observationID, bindingID: bindingID) }
    }
    static func initialHandoffPage(_ cursor: SharedMediaNativeInitialPage.Cursor?) -> Read<SharedMediaNativeInitialPage> {
        .init { try SharedMediaNativeRepositoryFacts.initialHandoffPage($0, profile: $1, cursor: cursor) }
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
        case .initial, .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
    }

    /// One selected package only. Retained library size is not the pending-package cap.
    static func initialContinuation(_ container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                    candidate: SharedMediaNativeReceivedCandidate) throws -> SharedMediaNativeInitialContinuation? {
        guard candidate.profile == profile else { throw SharedMediaStorageFailure.stale }
        let packageID = candidate.packageID
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventoryID = profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile else { throw SharedMediaStorageFailure.stale }
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context) else { return nil }
        let saved = SharedMediaNativeReceivingIntentGraph.Row(row)
        guard saved.draftGeneration == candidate.draftGeneration, saved.operationID == candidate.operationID,
              saved.revision == candidate.revision, saved.preparedSHA256 == candidate.preparedSHA256,
              saved.resultSHA256 == candidate.receivedSHA256 else { throw SharedMediaStorageFailure.stale }
        if let consumer = try SharedMediaConsumerLookup.one(context, packageID: packageID),
           SharedMediaNativeConsumerCohort.AppliedInitialFormat(rawValue: consumer.contractVersion) != nil {
            let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(row, inventory: inventory, context: context)
            let baseline = try NativeInitialHistoryBaseline.read(applied.prepared, context: context)?.association
            return .init(prepared: applied.prepared, phase: applied.cohort.format == .history ? .acknowledged : .applied,
                baseline: baseline)
        }
        guard let pending = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[packageID] else {
            throw SharedMediaStorageFailure.closed
        }
        switch pending {
        case .initial(let value), .allocating(let value):
            return .init(prepared: value.prepared, phase: .pending, baseline: nil)
        case .generic, .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
    }

    /// Exact scan/binding lookup; the existing Applied witness owns the complete
    /// reverse graph and receipt checks. No page traversal or media authority escapes.
    static func retainedInitial(_ container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                observationID: UUID, bindingID: UUID) throws -> SharedMediaNativeReceivingIntent.Prepared {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventoryID = profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              let consumer = try SharedMediaConsumerLookup.one(context, id: bindingID),
              let row = try SharedMediaNativeReceivingPhaseGraph.row(consumer.packageID, in: context) else {
            throw SharedMediaStorageFailure.stale
        }
        let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(row, inventory: inventory, context: context)
        guard applied.prepared.profile == profile, applied.prepared.observationID == observationID,
              applied.prepared.bindingID == bindingID else { throw SharedMediaStorageFailure.stale }
        return applied.prepared
    }

    static func initialHandoffPage(_ container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                   cursor: SharedMediaNativeInitialPage.Cursor?) throws -> SharedMediaNativeInitialPage {
        let context = ModelContext(container); context.autosaveEnabled = false
        let header = try SharedMediaNativeInitialPage.header(context, profile: profile)
        let after = try SharedMediaNativeInitialPage.lower(cursor, kind: .retained, profile: profile, header: header)
        var query = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.cursorKey > after },
            sortBy: [SortDescriptor(\.cursorKey, comparator: .lexical)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        let rows = try context.fetch(query), inventoryID = profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        var candidates: [SharedMediaNativeReceivedCandidate] = []
        for row in rows {
            try Task.checkCancellation()
            guard row.inventoryID == inventoryID, row.inventoryGeneration == profile.generation,
                  row.ownerID == profile.ownerID, row.cursorKey == row.id.uuidString.lowercased() else {
                throw SharedMediaStorageFailure.conflict
            }
            guard let consumer = try SharedMediaConsumerLookup.one(context, packageID: row.id),
                  SharedMediaNativeConsumerCohort.AppliedInitialFormat(rawValue: consumer.contractVersion) != nil else { continue }
            let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(row, inventory: inventory, context: context)
            guard applied.cohort.format == .initial else { continue }
            candidates.append(try SharedMediaNativeInitialPage.candidate(.init(row), profile: profile))
        }
        guard try SharedMediaNativeInitialPage.header(ModelContext(container), profile: profile) == header else {
            throw SharedMediaStorageFailure.stale
        }
        return .init(candidates: candidates, next: rows.count == SharedMediaStoragePolicy.pageSize
            ? rows.last.map { .init(kind: .retained, profile: profile, header: header, after: $0.cursorKey) } : nil)
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
        case .initial(let value):
            guard value.initialPin != nil else { throw SharedMediaStorageFailure.closed }
            row = value.row
            submission = .init(prepared: value.prepared, receipt: value.transaction.cohort, allocation: value.allocation)
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

/// A restart description, not permission to enroll, select, save or execute AI.
struct SharedMediaNativeInitialContinuation: Sendable {
    enum Phase: Sendable { case pending, applied, enrollmentHeld, acknowledged }
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let phase: Phase
    let baseline: NativeHistoryAssociation?
}

/// One bounded descriptive page. Selection must revalidate the full candidate.
struct SharedMediaNativeInitialPage: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case retained, enrollment }
    struct Cursor: Equatable, Sendable {
        let kind: Kind
        let profile: SharedMediaNativeAppProfile
        let header: SharedMediaNativeAppEligibility.Header
        let after: String
    }
    let candidates: [SharedMediaNativeReceivedCandidate]
    let next: Cursor?

    @MainActor static func header(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> SharedMediaNativeAppEligibility.Header {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        return try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
    }

    @MainActor static func lower(_ cursor: Cursor?, kind: Kind, profile: SharedMediaNativeAppProfile,
                                 header: SharedMediaNativeAppEligibility.Header) throws -> String {
        guard let cursor else { return "" }
        guard cursor.kind == kind, cursor.profile == profile, cursor.header == header else { throw SharedMediaStorageFailure.stale }
        let prefix = kind == .enrollment ? ObservationHistoryEnrollmentIntent.prefix : ""
        guard cursor.after.hasPrefix(prefix), let id = UUID(uuidString: String(cursor.after.dropFirst(prefix.count))),
              cursor.after == prefix + id.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
        return cursor.after
    }

    @MainActor static func candidate(_ row: SharedMediaNativeReceivingIntentGraph.Row,
                                     profile: SharedMediaNativeAppProfile) throws -> SharedMediaNativeReceivedCandidate {
        guard row.inventoryID == profile.inventoryID, row.inventoryGeneration == profile.generation,
              row.ownerID == profile.ownerID, row.cursor == row.id.uuidString.lowercased(),
              let result = row.resultSHA256, SharedMediaAcquisitionEncoding.isHash(result),
              SharedMediaAcquisitionEncoding.isHash(row.preparedSHA256) else { throw SharedMediaStorageFailure.conflict }
        return .init(profile: profile, packageID: row.id, draftGeneration: row.draftGeneration,
            operationID: row.operationID, revision: row.revision, preparedSHA256: row.preparedSHA256, receivedSHA256: result)
    }
}
