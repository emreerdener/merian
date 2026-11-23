import CryptoKit
import Foundation
import SwiftData

/// Exact bounded lookups shared by the fenced repository modes.
@MainActor
enum SharedMediaStorageLookup {
    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaAllocationRecord? {
        var query = FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaReferenceRecord? {
        var query = FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaLeaseRecord? {
        var query = FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }
    static func binding(authority: String, sources: [String: URL]) throws -> String {
        var parts = [authority]
        for namespace in sources.keys.sorted() {
            try SharedMediaStoragePolicy.token(namespace)
            let root = sources[namespace]!
            parts += [namespace, root.standardizedFileURL.path, try SharedMediaStorageFileOwner.directoryIdentity(root)]
        }
        return SHA256.hash(data: Data(try JSONEncoder().encode(parts))).map { String(format: "%02x", $0) }.joined()
    }

    static let inboxTypes = Set([ObjectIdentifier(SharedMediaInboxSourceRecord.self), ObjectIdentifier(SharedMediaInboxHandoffRecord.self),
        ObjectIdentifier(SharedMediaDerivativePairRecord.self), ObjectIdentifier(SharedMediaDerivativeWorkRecord.self)])

    static let photoTypes = Set([ObjectIdentifier(PhotoPreparationRecord.self),
        ObjectIdentifier(PhotoPreparationAsset.self), ObjectIdentifier(PhotoPreparationReference.self),
        ObjectIdentifier(PhotoPreparationLease.self)])

    static let ledgerTypes = Set([ObjectIdentifier(SharedMediaInventoryRecord.self),
        ObjectIdentifier(SharedMediaAllocationRecord.self), ObjectIdentifier(SharedMediaReferenceRecord.self),
        ObjectIdentifier(SharedMediaLeaseRecord.self), ObjectIdentifier(SharedMediaConsumerRecord.self),
        ObjectIdentifier(SharedMediaAssetReferenceCountRecord.self), ObjectIdentifier(SharedMediaMembershipBootstrapRecord.self), ObjectIdentifier(SharedMediaPendingMembershipRecord.self), ObjectIdentifier(SharedMediaAcquisitionReceiptRecord.self), ObjectIdentifier(SharedMediaReceivingIntentRecord.self), ObjectIdentifier(SharedMediaOrdinaryTransferRecord.self), ObjectIdentifier(SharedMediaOrdinarySubmissionRecord.self), ObjectIdentifier(SharedMediaOrdinaryArtifactRecord.self), ObjectIdentifier(SharedMediaCaptureDraftJournalRecord.self), ObjectIdentifier(SharedMediaNativeErasurePageRecord.self)])

    static func count<T: PersistentModel>(_ context: ModelContext, _ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    static func requireNoNativeOwnership(_ context: ModelContext) throws {
        // Schema foundations do not grant intent/consumer-aware qualification or cleanup.
        try requireNoUnqualifiedOrdinaryTransfers(context)
        guard try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 0 else {
            throw SharedMediaStorageFailure.closed
        }
    }

    static func hasLiabilities(in context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>()) > 0
    }

    /// Storage support alone cannot grant transfer interpretation or deletion.
    /// Includes foreign/unanchored rows: absence of a known inventory is not
    /// evidence that a destination copy or its source hold is unowned.
    static func requireNoUnqualifiedOrdinaryTransfers(_ context: ModelContext) throws {
        try requireNoUnqualifiedCaptureArtifacts(context)
        guard try context.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == 0 else {
            throw SharedMediaStorageFailure.closed
        }
    }
    /// Photo-only readers cannot infer completion or safe cleanup from an
    /// unfamiliar artifact phase, including a seemingly terminal raw row.
    static func requireNoUnqualifiedCaptureArtifacts(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) == 0 else {
            throw SharedMediaStorageFailure.closed
        }
    }
    static func visit<T: SharedMediaStorageRow>(_ context: ModelContext, _ type: T.Type, body: (T) throws -> Void) throws {
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(\.id)])
            descriptor.fetchLimit = SharedMediaStoragePolicy.pageSize
            descriptor.fetchOffset = offset
            let page = try context.fetch(descriptor)
            for row in page { try body(row) }
            if page.count < SharedMediaStoragePolicy.pageSize { break }
            offset += page.count
        }
    }

}

protocol SharedMediaStorageRow: PersistentModel { var id: UUID { get } }
extension SharedMediaAllocationRecord: SharedMediaStorageRow {}
extension SharedMediaReferenceRecord: SharedMediaStorageRow {}
extension SharedMediaLeaseRecord: SharedMediaStorageRow {}

extension SharedMediaConsumerRecord: SharedMediaStorageRow {}

extension SharedMediaAssetReferenceCountRecord: SharedMediaStorageRow {}
extension SharedMediaMembershipBootstrapRecord: SharedMediaStorageRow {}
extension SharedMediaPendingMembershipRecord: SharedMediaStorageRow {}

extension SharedMediaAcquisitionReceiptRecord: SharedMediaStorageRow {}
extension SharedMediaReceivingIntentRecord: SharedMediaStorageRow {}
extension SharedMediaOrdinaryTransferRecord: SharedMediaStorageRow {}
extension SharedMediaOrdinarySubmissionRecord: SharedMediaStorageRow {}
extension SharedMediaOrdinaryArtifactRecord: SharedMediaStorageRow {}

extension SharedMediaCaptureDraftJournalRecord: SharedMediaStorageRow {}

extension SharedMediaNativeErasurePageRecord: SharedMediaStorageRow {}
