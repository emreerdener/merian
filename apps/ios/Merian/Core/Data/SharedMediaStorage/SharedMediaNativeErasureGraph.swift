import CryptoKit
import Foundation
import SwiftData

/// Complete raw-row change detector for the dedicated native erasure owner.
/// This reads every native table without filtering by phase or account. It is
/// not an ownership audit, deletion capability, or substitute for physical proof.
/// The erasure owner must hold the store/no-writer fence for the entire read;
/// checkpoint must revalidate its accepted scope and durable inventory revision.
/// Context-local hasChanges checks cannot detect saves in another context.
@MainActor
enum SharedMediaNativeErasureGraph {
    #if DEBUG
    private static var snapshotObserver: (container: ObjectIdentifier, visit: () -> Void)?

    /// Synchronous MainActor scope: no other task can enter between installation
    /// and removal. Counts nested graph passes as well as the outer pass.
    static func countSnapshotsForTesting(container: ModelContainer, body: () throws -> Void) throws -> Int {
        guard TestExecutionCoordinator.isRunningTests, snapshotObserver == nil else { throw SharedMediaStorageFailure.closed }
        var count = 0
        snapshotObserver = (ObjectIdentifier(container), { count += 1 })
        defer { snapshotObserver = nil }
        try body()
        return count
    }
    #endif

    struct Table: Codable, Equatable, Sendable {
        let name: String
        let rows: Int64
        let sha256: String
    }

    static var carrierModelTypes: [any PersistentModel.Type] { [SharedMediaNativeErasurePageRecord.self] }

    static var modelTypes: [any PersistentModel.Type] { [
        PhotoPreparationAsset.self,
        PhotoPreparationLease.self,
        PhotoPreparationRecord.self,
        PhotoPreparationReference.self,
        SharedMediaAcquisitionReceiptRecord.self,
        SharedMediaAllocationRecord.self,
        SharedMediaAssetReferenceCountRecord.self,
        SharedMediaCaptureDraftJournalRecord.self,
        SharedMediaConsumerRecord.self,
        SharedMediaDerivativePairRecord.self,
        SharedMediaDerivativeWorkRecord.self,
        SharedMediaInboxHandoffRecord.self,
        SharedMediaInboxSourceRecord.self,
        SharedMediaLeaseRecord.self,
        SharedMediaMembershipBootstrapRecord.self,
        SharedMediaOrdinaryArtifactRecord.self,
        SharedMediaOrdinarySubmissionRecord.self,
        SharedMediaOrdinaryTransferRecord.self,
        SharedMediaPendingMembershipRecord.self,
        SharedMediaReceivingIntentRecord.self,
        SharedMediaReferenceRecord.self
    ] }

    static func snapshot(_ context: ModelContext, checkpoint: () throws -> Void) throws -> [Table] {
        #if DEBUG
        if let observer = snapshotObserver, observer.container == ObjectIdentifier(context.container) { observer.visit() }
        #endif
        guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let expected = SharedMediaStorageLookup.photoTypes.union(SharedMediaStorageLookup.inboxTypes)
            .union(SharedMediaStorageLookup.ledgerTypes).subtracting([ObjectIdentifier(SharedMediaInventoryRecord.self)] + carrierModelTypes.map(ObjectIdentifier.init))
        let nativeSchema = CurrentSchema.models.filter {
            let name = String(describing: $0)
            return name.hasPrefix("SharedMedia") || name.hasPrefix("PhotoPreparation")
        }
        guard Set(modelTypes.map(ObjectIdentifier.init)) == expected,
              Set(nativeSchema.map(ObjectIdentifier.init)) == expected.union([ObjectIdentifier(SharedMediaInventoryRecord.self)] + carrierModelTypes.map(ObjectIdentifier.init)) else { throw SharedMediaStorageFailure.conflict }
        var result: [Table] = []
        result.append(try table(PhotoPreparationAsset.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("ownerID", \.ownerID),
            column("generation", \.generation),
            column("fileToken", \.fileToken),
            column("contentType", \.contentType),
            column("byteCount", \.byteCount),
            column("sha256", \.sha256),
            column("acquisitionKindRaw", \.acquisitionKindRaw),
            column("cleanupStateRaw", \.cleanupStateRaw)
        ]))
        result.append(try table(PhotoPreparationLease.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("packageID", \.packageID),
            column("assetID", \.assetID),
            column("ownerID", \.ownerID),
            column("processEpoch", \.processEpoch),
            column("purposeRaw", \.purposeRaw),
            column("partialFileToken", \.partialFileToken),
            column("finalFileToken", \.finalFileToken),
            column("reservedByteCount", \.reservedByteCount),
            column("allocatedByteCount", \.allocatedByteCount),
            column("writerStateRaw", \.writerStateRaw),
            column("sourceIdentity", \.sourceIdentity),
            column("terminalProof", \.terminalProof)
        ]))
        result.append(try table(PhotoPreparationRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("accountingTierRaw", \.accountingTierRaw),
            column("id", \.id),
            column("ownerID", \.ownerID),
            column("contractVersion", \.contractVersion),
            column("draftID", \.draftID),
            column("draftGeneration", \.draftGeneration),
            column("revision", \.revision),
            column("phaseRaw", \.phaseRaw),
            column("supportingContextData", \.supportingContextData),
            column("allocatedByteCount", \.allocatedByteCount),
            column("retirementRequested", \.retirementRequested)
        ]))
        result.append(try table(PhotoPreparationReference.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("packageID", \.packageID),
            column("assetID", \.assetID),
            column("ownerID", \.ownerID),
            column("roleRaw", \.roleRaw),
            column("ordinal", \.ordinal),
            column("revision", \.revision),
            column("isLive", \.isLive)
        ]))
        result.append(try table(SharedMediaAcquisitionReceiptRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("schemaVersion", \.schemaVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("requestFingerprint", \.requestFingerprint),
            column("phaseRaw", \.phaseRaw),
            column("terminalOutcomeRaw", \.terminalOutcomeRaw),
            column("revision", \.revision),
            column("packageID", \.packageID),
            column("assetID", \.assetID),
            column("requestData", \.requestData),
            column("resultData", \.resultData)
        ]))
        result.append(try table(SharedMediaAllocationRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("inventoryID", \.inventoryID),
            column("accountID", \.accountID),
            column("packageID", \.packageID),
            column("namespaceRaw", \.namespaceRaw),
            column("fileToken", \.fileToken),
            column("poolRaw", \.poolRaw),
            column("stateRaw", \.stateRaw),
            column("materializedBytes", \.materializedBytes),
            column("reservedBytes", \.reservedBytes),
            column("physicalIdentity", \.physicalIdentity)
        ]))
        result.append(try table(SharedMediaAssetReferenceCountRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("assetGeneration", \.assetGeneration),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("liveCount", \.liveCount),
            column("revision", \.revision),
            column("retirementID", \.retirementID)
        ]))
        result.append(try table(SharedMediaCaptureDraftJournalRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("cursorKey", \.cursorKey),
            column("scanKey", \.scanKey),
            column("schemaVersion", \.schemaVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("scanID", \.scanID),
            column("rootBindingSHA256", \.rootBindingSHA256),
            column("revision", \.revision),
            column("bodyData", \.bodyData),
            column("bodySHA256", \.bodySHA256)
        ]))
        result.append(try table(SharedMediaConsumerRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("cursorKey", \.cursorKey),
            column("kindRaw", \.kindRaw),
            column("consumerID", \.consumerID),
            column("originQueueID", \.originQueueID),
            column("observationID", \.observationID),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("packageID", \.packageID),
            column("draftGeneration", \.draftGeneration),
            column("frozenPackageRevision", \.frozenPackageRevision),
            column("contractVersion", \.contractVersion),
            column("digestVersion", \.digestVersion),
            column("cohortData", \.cohortData),
            column("cohortSHA256", \.cohortSHA256),
            column("executionKindRaw", \.executionKindRaw),
            column("inferenceGeneration", \.inferenceGeneration),
            column("retirementID", \.retirementID),
            column("lifecycleRaw", \.lifecycleRaw),
            column("revision", \.revision)
        ]))
        result.append(try table(SharedMediaDerivativePairRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("nonce", \.nonce),
            column("contractVersion", \.contractVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("expectedInventoryRevision", \.expectedInventoryRevision),
            column("ownerID", \.ownerID),
            column("packageID", \.packageID),
            column("draftGeneration", \.draftGeneration),
            column("originalReferenceID", \.originalReferenceID),
            column("originalReferenceRevision", \.originalReferenceRevision),
            column("originalAssetID", \.originalAssetID),
            column("originalAssetGeneration", \.originalAssetGeneration),
            column("ordinal", \.ordinal),
            column("expectedPackageRevision", \.expectedPackageRevision),
            column("aiWorkID", \.aiWorkID),
            column("displayWorkID", \.displayWorkID),
            column("previousPairID", \.previousPairID),
            column("phaseRaw", \.phaseRaw),
            column("publishedRevision", \.publishedRevision)
        ]))
        result.append(try table(SharedMediaDerivativeWorkRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("pairID", \.pairID),
            column("roleRaw", \.roleRaw),
            column("assetID", \.assetID),
            column("assetGeneration", \.assetGeneration),
            column("referenceID", \.referenceID),
            column("leaseID", \.leaseID),
            column("writerEpoch", \.writerEpoch),
            column("byteCount", \.byteCount),
            column("sha256", \.sha256),
            column("contentType", \.contentType),
            column("phaseRaw", \.phaseRaw),
            column("writerStateRaw", \.writerStateRaw),
            column("partialDevice", \.partialDevice),
            column("partialInode", \.partialInode),
            column("finalIdentity", \.finalIdentity),
            column("retirementID", \.retirementID),
            column("retirementPartialIdentity", \.retirementPartialIdentity),
            column("retirementFinalIdentity", \.retirementFinalIdentity),
            column("retirementParentIdentity", \.retirementParentIdentity),
            column("retirementNamespaceIdentity", \.retirementNamespaceIdentity)
        ]))
        result.append(try table(SharedMediaInboxHandoffRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("nonce", \.nonce),
            column("sourceID", \.sourceID),
            column("sourceGeneration", \.sourceGeneration),
            column("sourceRevision", \.sourceRevision),
            column("inventoryGeneration", \.inventoryGeneration),
            column("expectedInventoryRevision", \.expectedInventoryRevision),
            column("ownerID", \.ownerID),
            column("packageID", \.packageID),
            column("draftGeneration", \.draftGeneration),
            column("assetID", \.assetID),
            column("assetGeneration", \.assetGeneration),
            column("referenceID", \.referenceID),
            column("leaseID", \.leaseID),
            column("sourceHoldID", \.sourceHoldID),
            column("ordinal", \.ordinal),
            column("byteCount", \.byteCount),
            column("sha256", \.sha256),
            column("phaseRaw", \.phaseRaw),
            column("writerEpoch", \.writerEpoch),
            column("writerStateRaw", \.writerStateRaw),
            column("partialDevice", \.partialDevice),
            column("partialInode", \.partialInode),
            column("finalIdentity", \.finalIdentity)
        ]))
        result.append(try table(SharedMediaInboxSourceRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("inventoryID", \.inventoryID),
            column("generation", \.generation),
            column("revision", \.revision),
            column("receivedAt", \.receivedAt),
            column("partialToken", \.partialToken),
            column("finalToken", \.finalToken),
            column("rootIdentity", \.rootIdentity),
            column("maximumBytes", \.maximumBytes),
            column("byteCount", \.byteCount),
            column("sha256", \.sha256),
            column("contentType", \.contentType),
            column("partialDevice", \.partialDevice),
            column("partialInode", \.partialInode),
            column("finalIdentity", \.finalIdentity),
            column("workID", \.workID),
            column("writerEpoch", \.writerEpoch),
            column("writerStateRaw", \.writerStateRaw),
            column("phaseRaw", \.phaseRaw),
            column("retirementID", \.retirementID),
            column("retirementPartialIdentity", \.retirementPartialIdentity),
            column("retirementFinalIdentity", \.retirementFinalIdentity)
        ]))
        result.append(try table(SharedMediaLeaseRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("allocationID", \.allocationID),
            column("processEpoch", \.processEpoch),
            column("purposeRaw", \.purposeRaw),
            column("stateRaw", \.stateRaw)
        ]))
        result.append(try table(SharedMediaMembershipBootstrapRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("inventoryGeneration", \.inventoryGeneration),
            column("contractVersion", \.contractVersion),
            column("revision", \.revision)
        ]))
        result.append(try table(SharedMediaOrdinaryArtifactRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("cursorKey", \.cursorKey),
            column("membershipKey", \.membershipKey),
            column("schemaVersion", \.schemaVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("recipientScanID", \.recipientScanID),
            column("submissionGeneration", \.submissionGeneration),
            column("mediaID", \.mediaID),
            column("itemIndex", \.itemIndex),
            column("roleRaw", \.roleRaw),
            column("frameIndex", \.frameIndex),
            column("allocationID", \.allocationID),
            column("referenceID", \.referenceID),
            column("leaseID", \.leaseID),
            column("writerEpoch", \.writerEpoch),
            column("phaseRaw", \.phaseRaw),
            column("revision", \.revision),
            column("requestData", \.requestData),
            column("requestSHA256", \.requestSHA256),
            column("stageReceiptData", \.stageReceiptData),
            column("stageReceiptSHA256", \.stageReceiptSHA256),
            column("acceptanceData", \.acceptanceData),
            column("acceptanceSHA256", \.acceptanceSHA256),
            column("retirementData", \.retirementData),
            column("retirementSHA256", \.retirementSHA256)
        ]))
        result.append(try table(SharedMediaOrdinarySubmissionRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("cursorKey", \.cursorKey),
            column("identityKey", \.identityKey),
            column("scanKey", \.scanKey),
            column("schemaVersion", \.schemaVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("recipientScanID", \.recipientScanID),
            column("submissionGeneration", \.submissionGeneration),
            column("jobID", \.jobID),
            column("eventID", \.eventID),
            column("writerEpoch", \.writerEpoch),
            column("phaseRaw", \.phaseRaw),
            column("revision", \.revision),
            column("formatRaw", \.formatRaw),
            column("requestData", \.requestData),
            column("requestSHA256", \.requestSHA256),
            column("observationSHA256", \.observationSHA256),
            column("acceptanceData", \.acceptanceData),
            column("acceptanceSHA256", \.acceptanceSHA256),
            column("retirementData", \.retirementData),
            column("retirementSHA256", \.retirementSHA256)
        ]))
        result.append(try table(SharedMediaOrdinaryTransferRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("cursorKey", \.cursorKey),
            column("schemaVersion", \.schemaVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("sourceAssetID", \.sourceAssetID),
            column("sourceReferenceID", \.sourceReferenceID),
            column("recipientScanID", \.recipientScanID),
            column("submissionGeneration", \.submissionGeneration),
            column("writerEpoch", \.writerEpoch),
            column("phaseRaw", \.phaseRaw),
            column("revision", \.revision),
            column("requestData", \.requestData),
            column("requestSHA256", \.requestSHA256),
            column("completionData", \.completionData),
            column("completionSHA256", \.completionSHA256),
            column("acceptanceData", \.acceptanceData),
            column("acceptanceSHA256", \.acceptanceSHA256),
            column("retirementData", \.retirementData),
            column("retirementSHA256", \.retirementSHA256)
        ]))
        result.append(try table(SharedMediaPendingMembershipRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("draftGeneration", \.draftGeneration),
            column("revision", \.revision),
            column("membersData", \.membersData)
        ]))
        result.append(try table(SharedMediaReceivingIntentRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("cursorKey", \.cursorKey),
            column("schemaVersion", \.schemaVersion),
            column("inventoryID", \.inventoryID),
            column("inventoryGeneration", \.inventoryGeneration),
            column("ownerID", \.ownerID),
            column("draftGeneration", \.draftGeneration),
            column("operationID", \.operationID),
            column("phaseRaw", \.phaseRaw),
            column("revision", \.revision),
            column("preparedData", \.preparedData),
            column("preparedSHA256", \.preparedSHA256),
            column("resultData", \.resultData),
            column("resultSHA256", \.resultSHA256),
            column("releaseStartData", \.releaseStartData),
            column("releaseStartSHA256", \.releaseStartSHA256),
            column("allocationData", \.allocationData),
            column("allocationSHA256", \.allocationSHA256),
            column("initialAdmissionData", \.initialAdmissionData),
            column("initialAdmissionSHA256", \.initialAdmissionSHA256),
            column("initialCompletionData", \.initialCompletionData),
            column("initialCompletionSHA256", \.initialCompletionSHA256)
        ]))
        result.append(try table(SharedMediaReferenceRecord.self, id: \.id, in: context, checkpoint: checkpoint, columns: [
            column("id", \.id),
            column("allocationID", \.allocationID),
            column("accountID", \.accountID),
            column("ownerID", \.ownerID),
            column("roleRaw", \.roleRaw),
            column("stateRaw", \.stateRaw),
            column("revision", \.revision)
        ]))
        try checkpoint()
        guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    private struct Column<T> {
        let name: String
        let read: (T) throws -> Field
    }
    private static func column<T, V: Encodable>(_ name: String, _ key: KeyPath<T, V>) -> Column<T> {
        .init(name: name, read: { try field(name, $0[keyPath: key]) })
    }
    private static func column<T>(_ name: String, _ key: KeyPath<T, Data>) -> Column<T> {
        .init(name: name, read: { field(name, $0[keyPath: key]) })
    }
    private static func column<T>(_ name: String, _ key: KeyPath<T, Data?>) -> Column<T> {
        .init(name: name, read: { try field(name, $0[keyPath: key]) })
    }

    private struct Field: Encodable {
        let name: String
        let encoding: String
        let bytes: Int
        let sha256: String
    }

    private static func field<T: Encodable>(_ name: String, _ value: T) throws -> Field {
        let bytes = try SharedMediaAcquisitionEncoding.encode(value, maximum: Int(PhotoPreparationPolicy.metadata))
        return .init(name: name, encoding: "json", bytes: bytes.count, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
    }

    // Hash binary columns directly rather than allocating a base64 copy of an
    // entire observation. Optional nil remains distinct from an empty body.
    private static func field(_ name: String, _ value: Data) -> Field {
        .init(name: name, encoding: "data", bytes: value.count, sha256: SharedMediaAcquisitionEncoding.digest(value))
    }
    private static func field(_ name: String, _ value: Data?) throws -> Field {
        if let value { return field(name, value) }
        return try field(name, Optional<String>.none)
    }

    private static func table<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>, in context: ModelContext,
                                                  checkpoint: () throws -> Void,
                                                  columns readers: [Column<T>]) throws -> Table {
        var offset = 0, digest = SHA256()
        let name = String(describing: type)
        let entities = context.container.schema.entities.filter { $0.name == name }
        guard entities.count == 1, let entity = entities.first else { throw SharedMediaStorageFailure.conflict }
        let columns = entity.properties.filter { !$0.isTransient }.map(\.name).sorted()
        guard readers.map(\.name).sorted() == columns else { throw SharedMediaStorageFailure.conflict }
        // Include schema identity even for an empty table. A newly persisted
        // field cannot disappear from the checkpoint merely because it is nil.
        digest.update(data: try SharedMediaAcquisitionEncoding.encode([name] + columns,
            maximum: Int(PhotoPreparationPolicy.metadata)))
        try checkpoint()
        let expectedCount = try context.fetchCount(FetchDescriptor<T>())
        var lastID: String?
        while true {
            try Task.checkCancellation(); try checkpoint()
            var query = FetchDescriptor<T>(sortBy: [SortDescriptor(id)])
            query.fetchLimit = SharedMediaStoragePolicy.pageSize
            query.fetchOffset = offset
            let page = try context.fetch(query)
            for row in page {
                let key = row[keyPath: id].uuidString
                guard lastID.map({ $0 < key }) ?? true else { throw SharedMediaStorageFailure.conflict }
                lastID = key
                let values = try readers.map { try $0.read(row) }
                guard values.map(\.name).sorted() == columns else { throw SharedMediaStorageFailure.conflict }
                let bytes = try SharedMediaAcquisitionEncoding.encode(values, maximum: Int(PhotoPreparationPolicy.metadata))
                var length = UInt64(bytes.count).bigEndian
                withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
                digest.update(data: bytes)
            }
            let (next, overflow) = offset.addingReportingOverflow(page.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
            if page.count < SharedMediaStoragePolicy.pageSize { break }
        }
        try checkpoint()
        guard offset == expectedCount, try context.fetchCount(FetchDescriptor<T>()) == expectedCount else {
            throw SharedMediaStorageFailure.stale
        }
        return .init(name: name, rows: Int64(offset), sha256: digest.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
