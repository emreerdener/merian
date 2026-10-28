import Foundation
import SwiftData
@testable import Merian

/// Synthetic probe evidence only. Reuses the production clean readers; it
/// neither grants a writer nor changes persisted model/codec conformances.
@MainActor
enum SharedMediaStageExitProbeState {
    struct Record: Codable, Equatable {
        let fields: [String?]
        let payloads: [Data?]
    }

    struct Snapshot: Codable, Equatable {
        let header: SharedMediaNativeAppEligibility.Header
        let slot: Record
        let packages: [SharedMediaNativeAppMetadataFacts.Package]
        let members: [SharedMediaNativeAppMetadataFacts.Member]
        let consumers: [Record]
        let receipts: [Record]
        let pairs: [SharedMediaNativePairFileState]
        let releaseRequest: Data
    }

    static func capture(container: ModelContainer, inventoryID: UUID, packageID: UUID,
                        releaseID: UUID) throws -> Snapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let snapshot = try SharedMediaNativeReceivedReleaseSnapshot.read(packageID: packageID,
            inventoryID: inventoryID, releaseID: releaseID, context: context)
        try snapshot.slot.requireNoReleaseStart()
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        guard case .received(let prepared, let received, let transaction) =
                try SharedMediaNativeReceivingSlot.decode(snapshot.slot, profile: profile),
              try SharedMediaNativeReceivingRows.read(transaction, in: context, absent: false) != nil else {
            throw SharedMediaStorageFailure.conflict
        }
        // read(...) verifies the complete receiving quartet against its frozen
        // transaction, including all queue/job/event defaults and metadata.
        _ = try SharedMediaNativeAppMetadataFacts.capture(context, profile: profile)
        // The seed includes an ordinary draft with no pending membership.
        // Pending-only metadata facts cannot detect changes to that survivor.
        var packagesQuery = FetchDescriptor<PhotoPreparationRecord>()
        packagesQuery.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        let packageRows = try context.fetch(packagesQuery)
        var membersQuery = FetchDescriptor<SharedMediaPendingMembershipRecord>()
        membersQuery.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        let memberRows = try context.fetch(membersQuery)
        var consumersQuery = FetchDescriptor<SharedMediaConsumerRecord>()
        consumersQuery.fetchLimit = 2
        let consumerRows = try context.fetch(consumersQuery)
        guard packageRows.count == 2, memberRows.count == 1,
              consumerRows.count == 1 else { throw SharedMediaStorageFailure.conflict }
        // Exactly one P2 slot and quartet, with no unrelated V1 fixture graph.
        guard try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1,
              try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 1 else {
            throw SharedMediaStorageFailure.conflict
        }
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let pairs = try cohort.entries.map { entry in
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            // Read actual current pair state, not the release projection's
            // intentionally predicted post-start inventory revision.
            return try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                package: package, member: member, pairID: intent.pairID)
        }
        var receiptQuery = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()
        receiptQuery.fetchLimit = 2 // Exactly one original, no historical graph.
        let receiptRows = try context.fetch(receiptQuery)
        guard receiptRows.count == 1 else { throw SharedMediaStorageFailure.conflict }
        let receipts = try receiptRows.sorted { $0.id.uuidString < $1.id.uuidString }.map { row in
            _ = try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory,
                context: context, format: .appV2)
            return Record(fields: [row.id.uuidString, String(row.schemaVersion), row.inventoryID.uuidString,
                row.inventoryGeneration.uuidString, row.ownerID.uuidString, row.requestFingerprint,
                row.phaseRaw, row.terminalOutcomeRaw, String(row.revision), row.packageID?.uuidString,
                row.assetID?.uuidString], payloads: [row.requestData, row.resultData])
        }
        let release = try SharedMediaNativeReleaseStartRequest(prepared: prepared, received: received,
            stagePreHeader: snapshot.header, releaseID: releaseID)
        let result = Snapshot(header: snapshot.header, slot: record(snapshot.slot),
            packages: packageRows.sorted { $0.id.uuidString < $1.id.uuidString }.map(SharedMediaNativeAppMetadataFacts.Package.init),
            members: memberRows.sorted { $0.id.uuidString < $1.id.uuidString }.map(SharedMediaNativeAppMetadataFacts.Member.init),
            consumers: consumerRows.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                let value = SharedMediaNativeAppMetadataFacts.Consumer($0)
                return Record(fields: value.fields.map(Optional.some), payloads: [value.cohort])
            }, receipts: receipts, pairs: pairs, releaseRequest: try release.encoded())
        guard !context.hasChanges,
              try SharedMediaNativeDraftEnvelope.bytes(result).count <= 1_048_576 else {
            throw SharedMediaStorageFailure.conflict
        }
        return result
    }

    private static func record(_ row: SharedMediaNativeReceivingIntentGraph.Row) -> Record {
        Record(fields: [row.id.uuidString, row.inventoryID.uuidString, row.inventoryGeneration.uuidString,
            row.ownerID.uuidString, row.draftGeneration.uuidString, row.operationID.uuidString,
            row.cursor, row.phase, row.preparedSHA256, String(row.version), String(row.revision),
            row.resultSHA256, row.releaseStartSHA256, row.allocationSHA256],
            payloads: [row.preparedData, row.resultData, row.releaseStartData, row.allocationData])
    }
}
