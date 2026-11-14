import Foundation
import SwiftData

/// Bounded pending intent facts. No filesystem inspection, mutation or execution
/// authority. Received and abandoned phases remain closed until their owners land.
@MainActor
enum SharedMediaNativeReceivingIntentGraph {
    struct Row: Equatable, Sendable {
        let id: UUID, inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID
        let draftGeneration: UUID, operationID: UUID
        let cursor: String, phase: String, preparedSHA256: String
        let version: Int, revision: Int64
        let preparedData: Data?, resultData: Data?
        let resultSHA256: String?
        let releaseStartData: Data?
        let releaseStartSHA256: String?
        let allocationData: Data?
        let allocationSHA256: String?
        let initialAdmissionData: Data?, initialCompletionData: Data?
        let initialAdmissionSHA256: String?, initialCompletionSHA256: String?

        /// Future original facts cannot enter any pre-V69 receiving owner.
        func requireNoInitialAnalysis() throws {
            guard initialAdmissionData == nil, initialAdmissionSHA256 == nil,
                  initialCompletionData == nil, initialCompletionSHA256 == nil else {
                throw SharedMediaStorageFailure.closed
            }
        }

        /// A remote allocation liability cannot enter local release or receiving.
        func requireNoAllocation() throws {
            try requireNoInitialAnalysis()
            guard allocationData == nil, allocationSHA256 == nil else {
                throw SharedMediaStorageFailure.closed
            }
        }

        /// The V66 storage foundation grants no sidecar-aware mutation or read.
        /// Keep raw projection/equality complete for a future dedicated owner.
        func requireNoReleaseStart() throws {
            try requireNoInitialAnalysis()
            guard releaseStartData == nil, releaseStartSHA256 == nil else {
                throw SharedMediaStorageFailure.closed
            }
        }

        /// Exact admission-only successor. Explicit assignment makes additions
        /// to this raw projection require a deliberate copy decision.
        init(admitting admission: InitialCompletionDocuments.CpmAdmission, from row: Self) {
            id = row.id; inventoryID = row.inventoryID; inventoryGeneration = row.inventoryGeneration
            ownerID = row.ownerID; draftGeneration = row.draftGeneration; operationID = row.operationID
            cursor = row.cursor; phase = row.phase; preparedSHA256 = row.preparedSHA256
            version = row.version; revision = row.revision; preparedData = row.preparedData
            resultData = row.resultData; resultSHA256 = row.resultSHA256
            releaseStartData = row.releaseStartData; releaseStartSHA256 = row.releaseStartSHA256
            allocationData = row.allocationData; allocationSHA256 = row.allocationSHA256
            initialAdmissionData = admission.acknowledgement
            initialAdmissionSHA256 = SharedMediaAcquisitionEncoding.digest(admission.acknowledgement)
            initialCompletionData = row.initialCompletionData; initialCompletionSHA256 = row.initialCompletionSHA256
        }

        /// Completion consumes only its reserved sidecar; all original fields stay exact.
        init(completing completion: InitialCompletionDocuments.CpmRecoveryRecord, from row: Self) {
            id = row.id; inventoryID = row.inventoryID; inventoryGeneration = row.inventoryGeneration
            ownerID = row.ownerID; draftGeneration = row.draftGeneration; operationID = row.operationID
            cursor = row.cursor; phase = row.phase; preparedSHA256 = row.preparedSHA256
            version = row.version; revision = row.revision; preparedData = row.preparedData
            resultData = row.resultData; resultSHA256 = row.resultSHA256
            releaseStartData = row.releaseStartData; releaseStartSHA256 = row.releaseStartSHA256
            allocationData = row.allocationData; allocationSHA256 = row.allocationSHA256
            initialAdmissionData = row.initialAdmissionData
            initialAdmissionSHA256 = row.initialAdmissionSHA256
            initialCompletionData = completion.bytes; initialCompletionSHA256 = SharedMediaAcquisitionEncoding.digest(completion.bytes)
        }

        init(_ row: SharedMediaReceivingIntentRecord) {
            id = row.id; inventoryID = row.inventoryID; inventoryGeneration = row.inventoryGeneration
            ownerID = row.ownerID; draftGeneration = row.draftGeneration; operationID = row.operationID
            cursor = row.cursorKey; phase = row.phaseRaw; preparedSHA256 = row.preparedSHA256
            version = row.schemaVersion; revision = row.revision; preparedData = row.preparedData
            resultData = row.resultData; resultSHA256 = row.resultSHA256
            releaseStartData = row.releaseStartData; releaseStartSHA256 = row.releaseStartSHA256
            allocationData = row.allocationData; allocationSHA256 = row.allocationSHA256
            initialAdmissionData = row.initialAdmissionData; initialAdmissionSHA256 = row.initialAdmissionSHA256
            initialCompletionData = row.initialCompletionData; initialCompletionSHA256 = row.initialCompletionSHA256
        }
    }
    struct Witness: Sendable {
        let row: Row
        let prepared: SharedMediaNativeReceivingIntent.Prepared
        let states: [SharedMediaNativePairFileState]
    }

    /// Include every raw row: a foreign or orphan row must not vanish behind a
    /// membership predicate. This bound applies only while all supported rows
    /// are pending; received lifecycle integration must use paged ownership.
    static func snapshots(_ context: ModelContext) throws -> [UUID: Row] {
        var query = FetchDescriptor<SharedMediaReceivingIntentRecord>()
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        query.includePendingChanges = true
        let rows = try context.fetch(query)
        guard rows.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        var result: [UUID: Row] = [:]
        for row in rows {
            try Row(row).requireNoReleaseStart()
            try Row(row).requireNoAllocation()
            guard result.updateValue(Row(row), forKey: row.id) == nil else { throw SharedMediaStorageFailure.conflict }
        }
        return result
    }

    /// Safe for a typed dirty poststate as well as a clean audit. This reads
    /// persisted joins only and never calls metadata facts, budget or scope audit.
    static func read(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> [UUID: Witness] {
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        var result: [UUID: Witness] = [:], identities = Set<UUID>()
        for row in try snapshots(context).values {
            try row.requireNoReleaseStart()
            try row.requireNoAllocation()
            guard row.version == 1, row.phase == "prepared", row.revision == 0,
                  row.cursor == row.id.uuidString.lowercased(), row.resultData == nil, row.resultSHA256 == nil,
                  row.inventoryID == profile.inventoryID, row.inventoryGeneration == profile.generation,
                  row.ownerID == profile.ownerID, let bytes = row.preparedData,
                  row.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else { throw SharedMediaStorageFailure.closed }
            let prepared = try SharedMediaNativeReceivingIntent.Prepared.decode(bytes)
            try requireLegacyPrepared(prepared)
            guard prepared.profile == profile, prepared.package.id == row.id,
                  prepared.package.generation == row.draftGeneration, prepared.operationID == row.operationID else {
                throw SharedMediaStorageFailure.conflict
            }
            for id in [prepared.operationID, prepared.queueID, prepared.observationID,
                       prepared.bindingID, prepared.generation, prepared.eventID] {
                guard identities.insert(id).inserted else { throw SharedMediaStorageFailure.conflict }
            }
            try SharedMediaNativeReceivingRows.requireAbsent(.init(prepared), in: context)
            result[row.id] = .init(row: row, prepared: prepared,
                states: try cohort(prepared, context: context, inventory: inventory))
        }
        return result
    }

    static func cohort(_ prepared: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext,
                       inventory: SharedMediaInventoryRecord) throws -> [SharedMediaNativePairFileState] {
        try requireLegacyPrepared(prepared)
        return try currentCohort(prepared, context: context, inventory: inventory)
    }

    /// Intent-aware owner leaf. Legacy callers retain their strict wrapper.
    static func currentCohort(_ prepared: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext,
                              inventory: SharedMediaInventoryRecord) throws -> [SharedMediaNativePairFileState] {
        _ = try prepared.encoded()
        let id = prepared.package.id
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard prepared.profile == (try SharedMediaNativeAppEligibility.profile(inventory)),
              SharedMediaNativeAppMetadataFacts.Package(package) == prepared.package,
              SharedMediaNativeAppMetadataFacts.Member(member) == prepared.member,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        var originals = Set<UUID>(), states: [SharedMediaNativePairFileState] = []
        for entry in frozen.entries {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            guard originals.insert(intent.preparation.original.reference.referenceID).inserted else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaNativePairPlanGraph.validateReadyForMembership(envelope, pairID: intent.pairID,
                package: package, inventory: inventory, context: context)
            let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                package: package, member: member, pairID: intent.pairID)
            guard state.phase == "ready", state.plan.intent == entry.intent else { throw SharedMediaStorageFailure.conflict }
            for (input, revision, identity) in [(intent.ai, entry.aiReferenceRevision, entry.aiDescriptor),
                                               (intent.display, entry.displayReferenceRevision, entry.displayDescriptor)] {
                let refID = input.referenceID
                let ref = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
                let work = try state.selected(input.id).0
                guard ref.revision == revision, work.phase == "completed", work.writerState == "closed",
                      work.finalIdentity == identity.file else { throw SharedMediaStorageFailure.conflict }
            }
            states.append(state)
        }
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id && $0.roleRaw == "original" })
        query.fetchLimit = 3; query.includePendingChanges = true
        let refs = try context.fetch(query)
        guard refs.count == states.count, Set(refs.map(\.id)) == originals, refs.allSatisfy(\.isLive) else {
            throw SharedMediaStorageFailure.conflict
        }
        return states
    }

    /// Codec support does not admit a new format into the existing owner graph.
    private static func requireLegacyPrepared(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        guard prepared.format == .prepared, prepared.version == 1, prepared.intentRevision == nil else {
            throw SharedMediaStorageFailure.closed
        }
    }
}
