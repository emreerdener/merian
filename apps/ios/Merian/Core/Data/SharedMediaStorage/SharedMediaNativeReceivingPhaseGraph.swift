import Foundation
import SwiftData

/// Phase-aware, database-only leaves. No budget, consumer-graph or whole-audit
/// recursion; decoded values never grant save or execution authority.
@MainActor
enum SharedMediaNativeReceivingPhaseGraph {
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Intent = SharedMediaNativeReceivingIntent
    struct Witness {
        let row: Row
        let slot: SharedMediaNativeReceivingSlot
        let states: [SharedMediaNativePairFileState]
        var recoveryPresentationData: Data?
        var recoveryPresentation: AnalysisRecoveryPresentation.StorageLiability? {
            get throws {
                guard case .received(let prepared, _, _) = slot else {
                    guard recoveryPresentationData == nil else { throw SharedMediaStorageFailure.conflict }
                    return nil
                }
                return try SharedMediaNativeReceivingRows.recoveryPresentation(recoveryPresentationData, prepared: prepared)
            }
        }
    }

    static func row(_ id: UUID, in context: ModelContext) throws -> SharedMediaReceivingIntentRecord? {
        var query = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2; query.includePendingChanges = true
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    /// Only pending membership roots enter transaction facts. Raw orphan/foreign
    /// rows are checked separately by the complete paged scoped audit.
    static func snapshots(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> [UUID: Row] {
        let id = profile.inventoryID
        var query = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.inventoryID == id })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1; query.includePendingChanges = true
        let members = try context.fetch(query)
        guard members.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        var result: [UUID: Row] = [:]
        for member in members {
            guard member.ownerID == profile.ownerID, member.inventoryGeneration == profile.generation else {
                throw SharedMediaStorageFailure.conflict
            }
            if let saved = try row(member.id, in: context) {
                let value = Row(saved)
                _ = try SharedMediaNativeReceivingSlot.decode(value, profile: profile)
                guard result.updateValue(value, forKey: value.id) == nil else { throw SharedMediaStorageFailure.conflict }
            }
        }
        return result
    }

    static func pending(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> [UUID: Witness] {
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        var result: [UUID: Witness] = [:], identities = Set<UUID>()
        for row in try snapshots(context, profile: profile).values {
            let witness = try validate(row, context: context, inventory: inventory)
            let ids: [UUID]
            switch witness.slot {
            case .prepared(let p), .received(let p, _, _):
                ids = [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID]
            case .abandoned(let a):
                ids = [a.operationID, a.queueID, a.observationID, a.bindingID, a.generation, a.eventID]
            }
            for id in ids { guard identities.insert(id).inserted else { throw SharedMediaStorageFailure.conflict } }
            result[row.id] = witness
        }
        return result
    }

    static func validate(_ row: Row, context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Witness {
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let slot = try SharedMediaNativeReceivingSlot.decode(row, profile: profile)
        switch slot {
        case .prepared(let p):
            try SharedMediaNativeReceivingRows.requireAbsent(.init(p), in: context)
            return .init(row: row, slot: slot, states: try SharedMediaNativeReceivingIntentGraph.currentCohort(p,
                context: context, inventory: inventory))
        case .received(_, _, let transaction):
            let rows = try receivedRows(transaction, context: context)
            let value = Witness(row: row, slot: slot, states: [], recoveryPresentationData: rows.queue.recoveryPresentationData)
            _ = try value.recoveryPresentation
            return value
        case .abandoned(let a):
            try SharedMediaNativeReceivingRows.requireAbsent(.init(a), in: context)
            let id = row.id
            let package = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
            let member = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            // Later legitimate edits may change revision, generation and bytes.
            // Terminal proof is retained unchanged; exact acknowledgement uses
            // Abandoned.requireSuccessor instead of this structural check.
            guard package.id == package.draftID, package.ownerID == profile.ownerID,
                  package.contractVersion == PhotoPreparationPolicy.contract, package.accountingTierRaw == "pending",
                  member.inventoryID == profile.inventoryID, member.inventoryGeneration == profile.generation,
                  member.ownerID == profile.ownerID, member.draftGeneration == package.draftGeneration else {
                throw SharedMediaStorageFailure.conflict
            }
            return .init(row: row, slot: slot, states: [])
        }
    }

    /// Called from every consumer validator, including legacy candidates. A
    /// missing/downgraded marker cannot hide an existing intent-bearing package.
    static func requireConsumerLink(_ consumer: SharedMediaConsumerRecord, value: SharedMediaNativeConsumerCohort,
                                    context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        let saved = try row(consumer.packageID, in: context)
        if value.format == .receiving {
            guard saved == nil else { throw SharedMediaStorageFailure.conflict }
            return
        }
        guard let saved,
              case .received(_, _, let transaction) = try SharedMediaNativeReceivingSlot.decode(Row(saved),
                profile: SharedMediaNativeAppEligibility.profile(inventory)),
              transaction.cohort == value,
              try receivedRows(transaction, context: context).consumer.persistentModelID == consumer.persistentModelID else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    static func receivedRows(_ transaction: Intent.Transaction, context: ModelContext) throws -> SharedMediaNativeReceivingRows.Set {
        let id = transaction.package.id
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard transaction.cohort.format == .intentReceiving,
              let origin = transaction.cohort.intentBinding,
              (origin.preparedRevision == 0 && origin.restagedFromSHA256 == nil) ||
                (origin.preparedRevision > 0 && origin.restagedFromSHA256 != nil),
              SharedMediaNativeAppMetadataFacts.Package(package) == (try transaction.frozenPackage()),
              SharedMediaNativeAppMetadataFacts.Member(member) == transaction.member,
              let rows = try SharedMediaNativeReceivingRows.read(transaction, in: context, absent: false) else {
            throw SharedMediaStorageFailure.conflict
        }
        return rows
    }
}
