import Foundation
import SwiftData

/// Every method is called while the file owner holds the namespace lock.
/// Fresh contexts prevent an older owner from saving a stale projection.
@MainActor
final class PhotoPreparationRepository {
    let container: ModelContainer
    init(container: ModelContainer) { self.container = container }

    private struct State {
        let context: ModelContext
        let records: [PhotoPreparationRecord]
        let assets: [PhotoPreparationAsset]
        let references: [PhotoPreparationReference]
        let leases: [PhotoPreparationLease]
    }

    private func state() throws -> State {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) <= 4,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) <= 96,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>()) <= 128,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) <= 96 else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        let result = try State(context: context,
            records: context.fetch(FetchDescriptor<PhotoPreparationRecord>()),
            assets: context.fetch(FetchDescriptor<PhotoPreparationAsset>()),
            references: context.fetch(FetchDescriptor<PhotoPreparationReference>()),
            leases: context.fetch(FetchDescriptor<PhotoPreparationLease>()))
        guard result.records.allSatisfy({ $0.contractVersion == PhotoPreparationPolicy.contract
            && $0.revision >= 0 && ["acquiring", "draftOwned", "preparedHeld", "needsAttention", "retiring"].contains($0.phaseRaw) }),
              result.references.allSatisfy({ PhotoPreparationRole(rawValue: $0.roleRaw) != nil && $0.revision >= 0 && $0.ordinal >= 0 }),
              result.assets.allSatisfy({ $0.byteCount > 0 && $0.byteCount <= PhotoPreparationPolicy.original
                  && ["ready", "missing", "retiring"].contains($0.cleanupStateRaw) }),
              result.leases.allSatisfy({ $0.reservedByteCount >= 0 && $0.allocatedByteCount >= 0 }) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        for edge in result.references {
            guard let record = result.records.first(where: { $0.id == edge.packageID }),
                  let asset = result.assets.first(where: { $0.id == edge.assetID }),
                  record.ownerID == edge.ownerID, asset.ownerID == edge.ownerID else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        }
        for lease in result.leases {
            guard result.records.contains(where: { $0.id == lease.packageID && $0.ownerID == lease.ownerID }) else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        }
        guard Set(result.records.map(\.id)).count == result.records.count,
              Set(result.assets.map(\.id)).count == result.assets.count,
              Set(result.references.map(\.id)).count == result.references.count,
              Set(result.leases.map(\.id)).count == result.leases.count,
              Set(result.assets.map(\.fileToken)).count == result.assets.count,
              try PhotoPreparationPolicy.add(result.assets.map(\.byteCount)
                + result.leases.map(\.reservedByteCount)) <= PhotoPreparationPolicy.durable else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        guard try PhotoPreparationPolicy.add(result.leases.flatMap { [$0.reservedByteCount, $0.allocatedByteCount] }) <= 96 * PhotoPreparationPolicy.mib else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        for record in result.records {
            let edges = result.references.filter { $0.packageID == record.id }
            let ids = Set(edges.map(\.assetID))
            let bytes = try PhotoPreparationPolicy.add(result.assets.filter { ids.contains($0.id) }.map(\.byteCount))
            guard bytes == record.allocatedByteCount, ids.count <= 24, edges.count <= 32,
                  record.supportingContextData.count <= PhotoPreparationPolicy.metadata,
                  try PhotoPreparationPolicy.add([bytes, Int64(record.supportingContextData.count)]
                    + result.leases.filter { $0.packageID == record.id }.map(\.reservedByteCount)) <= PhotoPreparationPolicy.package else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            _ = try PhotoPreparationPolicy.decodeDraft(record.supportingContextData)
            for role in [PhotoPreparationRole.original, .aiInput, .display] {
                let subset = edges.filter { $0.roleRaw == role.rawValue && $0.isLive }
                let ceiling = role == .original ? PhotoPreparationPolicy.originalCohort
                    : (role == .aiInput ? PhotoPreparationPolicy.aiCohort : PhotoPreparationPolicy.displayCohort)
                guard subset.count <= 2, Set(subset.map(\.ordinal)).count == subset.count,
                      try PhotoPreparationPolicy.add(subset.compactMap { edge in
                        result.assets.first { $0.id == edge.assetID }?.byteCount
                      }) <= ceiling else { throw PhotoPreparationFailure.inconsistentOwnership }
            }
        }
        for asset in result.assets {
            guard asset.fileToken.hasPrefix(asset.ownerID.uuidString.lowercased() + "/"),
                  result.references.contains(where: { $0.assetID == asset.id }) || asset.cleanupStateRaw == "retiring" else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        }
        return result
    }

    func reserve(_ intent: PhotoPreparationIntent) throws {
        let s = try state()
        guard s.leases.allSatisfy({ $0.writerStateRaw == "closedSourceRetained" }) else { throw PhotoPreparationFailure.cleanupPending }
        guard (intent.sourceByteLiability == 0 && intent.sourceIdentity == nil)
            || (intent.sourceByteLiability > 0 && intent.sourceIdentity != nil
                && (intent.sourceIdentity?.utf8.count ?? 0) <= 128) else { throw PhotoPreparationFailure.inconsistentOwnership }
        guard intent.ordinal >= 0, intent.ordinal < 2 else { throw PhotoPreparationFailure.invalidMedia }
        guard !s.assets.contains(where: { $0.id == intent.assetID }),
              !s.references.contains(where: { $0.id == intent.referenceID }) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        let record: PhotoPreparationRecord
        if let saved = s.records.first(where: { $0.id == intent.packageID }) {
            guard saved.ownerID == intent.ownerID, saved.draftGeneration == intent.draftGeneration,
                  ["acquiring", "draftOwned"].contains(saved.phaseRaw), !saved.retirementRequested else {
                throw PhotoPreparationFailure.staleGeneration
            }
            record = saved
        } else {
            guard s.records.count < PhotoPreparationPolicy.maximumPackages else { throw PhotoPreparationFailure.storageLimit }
            record = PhotoPreparationRecord(id: intent.packageID, ownerID: intent.ownerID,
                contractVersion: PhotoPreparationPolicy.contract, draftID: intent.packageID,
                draftGeneration: intent.draftGeneration, revision: 0, phaseRaw: "acquiring",
                supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: 0, retirementRequested: false)
            s.context.insert(record)
        }
        let edges = s.references.filter { $0.packageID == record.id && $0.isLive }
        let roleEdges = edges.filter { $0.roleRaw == intent.role.rawValue }
        guard !roleEdges.contains(where: { $0.ordinal == intent.ordinal }), roleEdges.count < 2 else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        let roleBytes = roleEdges.compactMap { edge in s.assets.first { $0.id == edge.assetID }?.byteCount }
        let roleMaximum: Int64
        switch intent.role {
        case .original:
            guard roleEdges.count < 2 else { throw PhotoPreparationFailure.sizeLimit }
            roleMaximum = PhotoPreparationPolicy.originalCohort
        case .aiInput: roleMaximum = PhotoPreparationPolicy.aiCohort
        case .display: roleMaximum = PhotoPreparationPolicy.displayCohort
        }
        guard try PhotoPreparationPolicy.add(roleBytes + [intent.maximumBytes]) <= roleMaximum,
              intent.maximumBytes > 0, intent.maximumBytes <= PhotoPreparationPolicy.limit(for: intent.role),
              edges.count < 32 else { throw PhotoPreparationFailure.sizeLimit }
        let packageIDs = Set(edges.map(\.assetID))
        let packageBytes = try PhotoPreparationPolicy.add(s.assets.filter { packageIDs.contains($0.id) }.map(\.byteCount))
        guard record.allocatedByteCount == packageBytes,
              try PhotoPreparationPolicy.add([packageBytes, Int64(record.supportingContextData.count), intent.maximumBytes]) <= PhotoPreparationPolicy.package,
              try PhotoPreparationPolicy.add(s.assets.map(\.byteCount) + [intent.maximumBytes]) <= PhotoPreparationPolicy.durable,
              intent.maximumBytes <= PhotoPreparationPolicy.temporary else { throw PhotoPreparationFailure.storageLimit }
        // Acquisition pool includes every app-owned incoming source plus the
        // sole partial/final destination. Rename does not create a second copy.
        guard intent.sourceByteLiability >= 0, intent.sourceByteLiability <= PhotoPreparationPolicy.original,
              try PhotoPreparationPolicy.add([intent.maximumBytes, intent.sourceByteLiability]
                + s.leases.flatMap { [$0.reservedByteCount, $0.allocatedByteCount] }) <= 96 * PhotoPreparationPolicy.mib else {
            throw PhotoPreparationFailure.storageLimit
        }
        let lease = PhotoPreparationLease(id: intent.leaseID, packageID: intent.packageID,
            assetID: intent.assetID, ownerID: intent.ownerID, processEpoch: intent.processEpoch,
            purposeRaw: "acquire", partialFileToken: intent.fileToken + ".partial", finalFileToken: intent.fileToken,
            reservedByteCount: intent.maximumBytes, allocatedByteCount: intent.sourceByteLiability, writerStateRaw: "open", terminalProof: nil, sourceIdentity: intent.sourceIdentity)
        s.context.insert(lease)
        try s.context.save()
    }

    func commit(_ intent: PhotoPreparationIntent, file: PhotoPreparationFile) throws -> PhotoOriginalReference {
        let s = try state()
        guard let record = s.records.first(where: { $0.id == intent.packageID }),
              let lease = s.leases.first(where: { $0.id == intent.leaseID }),
              lease.ownerID == intent.ownerID, lease.assetID == file.assetID,
              record.ownerID == intent.ownerID, record.draftGeneration == intent.draftGeneration,
              !record.retirementRequested, ["acquiring", "draftOwned"].contains(record.phaseRaw),
              file.byteCount > 0, file.byteCount <= lease.reservedByteCount,
              file.token == intent.fileToken, file.generation == intent.assetGeneration,
              !s.assets.contains(where: { $0.id == file.assetID }) else { throw PhotoPreparationFailure.inconsistentOwnership }
        s.context.insert(PhotoPreparationAsset(id: file.assetID, ownerID: intent.ownerID,
            generation: file.generation, fileToken: file.token, contentType: file.contentType,
            byteCount: file.byteCount, sha256: file.sha256, acquisitionKindRaw: intent.acquisitionKind,
            cleanupStateRaw: "ready"))
        s.context.insert(PhotoPreparationReference(id: intent.referenceID, packageID: intent.packageID,
            assetID: file.assetID, ownerID: intent.ownerID, roleRaw: intent.role.rawValue,
            ordinal: intent.ordinal, revision: 0, isLive: true))
        record.allocatedByteCount = try PhotoPreparationPolicy.add([record.allocatedByteCount, file.byteCount])
        record.revision = try PhotoPreparationPolicy.add([record.revision, 1])
        record.phaseRaw = "draftOwned"
        if lease.allocatedByteCount > 0 {
            lease.reservedByteCount = 0
            lease.writerStateRaw = "closedSourceRetained"
            lease.terminalProof = "destinationCommittedSourceStillOwned"
        } else { s.context.delete(lease) }
        try s.context.save()
        return PhotoOriginalReference(ownerID: intent.ownerID, packageID: intent.packageID,
            referenceID: intent.referenceID, assetID: file.assetID, assetGeneration: file.generation,
            draftGeneration: intent.draftGeneration, referenceRevision: 0)
    }

    func resolve(_ handle: PhotoOriginalReference) throws -> PhotoPreparationFile {
        try handle.validate()
        let s = try state()
        guard let record = s.records.first(where: { $0.id == handle.packageID && $0.ownerID == handle.ownerID }),
              record.draftGeneration == handle.draftGeneration, !record.retirementRequested,
              ["draftOwned", "preparedHeld", "needsAttention"].contains(record.phaseRaw),
              let edge = s.references.first(where: { $0.id == handle.referenceID && $0.isLive }),
              edge.ownerID == handle.ownerID, edge.packageID == handle.packageID,
              edge.assetID == handle.assetID, edge.revision == handle.referenceRevision,
              edge.roleRaw == "original",
              let asset = s.assets.first(where: { $0.id == handle.assetID }),
              asset.ownerID == handle.ownerID, asset.generation == handle.assetGeneration,
              asset.cleanupStateRaw == "ready" else { throw PhotoPreparationFailure.staleGeneration }
        return fileValue(asset)
    }

    func derivatives(_ handle: PhotoOriginalReference) throws -> (PhotoPreparationFile, PhotoPreparationFile) {
        _ = try resolve(handle)
        let s = try state()
        guard let original = s.references.first(where: { $0.id == handle.referenceID }) else { throw PhotoPreparationFailure.staleGeneration }
        func file(_ role: String) throws -> PhotoPreparationFile {
            guard let edge = s.references.first(where: { $0.packageID == handle.packageID && $0.ordinal == original.ordinal && $0.roleRaw == role && $0.isLive }),
                  let asset = s.assets.first(where: { $0.id == edge.assetID && $0.cleanupStateRaw == "ready" }) else {
                throw PhotoPreparationFailure.missingMedia
            }
            return fileValue(asset)
        }
        return try (file("aiInput"), file("display"))
    }

    func revision(packageID: UUID, ownerID: UUID) throws -> Int64 {
        let s = try state()
        guard let r = s.records.first(where: { $0.id == packageID && $0.ownerID == ownerID }) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        return r.revision
    }

    func saveContexts(packageID: UUID, ownerID: UUID, expectedRevision: Int64, contexts: [ObservationContext], presentation: [PhotoPreparationImagePresentation]? = nil) throws -> Int64 {
        let s = try state()
        guard let r = s.records.first(where: { $0.id == packageID && $0.ownerID == ownerID }),
              r.phaseRaw == "draftOwned", r.revision == expectedRevision, !r.retirementRequested,
              s.leases.isEmpty else { throw PhotoPreparationFailure.staleGeneration }
        let photos = try presentation ?? PhotoPreparationPolicy.decodeDraft(r.supportingContextData).presentation
        let originalIDs = Set(s.references.filter { $0.packageID == packageID && $0.roleRaw == "original" && $0.isLive }.map(\.id))
        guard photos.allSatisfy({ originalIDs.contains($0.referenceID) }) else { throw PhotoPreparationFailure.staleGeneration }
        let bytes = try PhotoPreparationPolicy.encodeDraft(contexts: contexts, presentation: photos)
        guard try PhotoPreparationPolicy.add([r.allocatedByteCount, Int64(bytes.count)]) <= PhotoPreparationPolicy.package else {
            throw PhotoPreparationFailure.sizeLimit
        }
        r.supportingContextData = bytes
        r.revision = try PhotoPreparationPolicy.add([r.revision, 1])
        try s.context.save()
        return r.revision
    }

    func filesForFreeze(_ snapshot: PhotoPreparationSnapshot, ownerID: UUID) throws -> [PhotoPreparationFile] {
        guard let first = snapshot.originals.first, snapshot.originals.count <= 2,
              snapshot.originals.allSatisfy({ $0.ownerID == ownerID && $0.packageID == first.packageID }),
              Set(snapshot.originals.map(\.referenceID)).count == snapshot.originals.count else { throw PhotoPreparationFailure.invalidMedia }
        for handle in snapshot.originals { _ = try resolve(handle) }
        let s = try state()
        guard s.leases.isEmpty,
              let r = s.records.first(where: { $0.id == first.packageID && $0.ownerID == ownerID }),
              r.phaseRaw == "draftOwned", r.revision == snapshot.expectedPackageRevision,
              try PhotoPreparationPolicy.decodeDraft(r.supportingContextData).contexts == snapshot.supportingContexts else {
            throw PhotoPreparationFailure.staleGeneration
        }
        let edges = s.references.filter { $0.packageID == r.id && $0.isLive }.sorted { $0.ordinal < $1.ordinal }
        guard edges.filter({ $0.roleRaw == "original" }).map(\.id) == snapshot.originals.map(\.referenceID) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        let originalOrdinals = edges.filter { $0.roleRaw == "original" }.map(\.ordinal)
        for role in [PhotoPreparationRole.aiInput, .display] {
            guard edges.filter({ $0.roleRaw == role.rawValue }).map(\.ordinal) == originalOrdinals else {
                throw PhotoPreparationFailure.missingMedia
            }
        }
        return try edges.map { edge in
            guard let asset = s.assets.first(where: { $0.id == edge.assetID && $0.cleanupStateRaw == "ready" }) else {
                throw PhotoPreparationFailure.missingMedia
            }
            return fileValue(asset)
        }
    }

    func freeze(_ snapshot: PhotoPreparationSnapshot, ownerID: UUID) throws -> PhotoPreparationReceipt {
        _ = try filesForFreeze(snapshot, ownerID: ownerID)
        let s = try state()
        guard let r = s.records.first(where: { $0.id == snapshot.originals.first?.packageID }) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        r.phaseRaw = "preparedHeld"
        r.revision = try PhotoPreparationPolicy.add([r.revision, 1])
        try s.context.save()
        return PhotoPreparationReceipt(packageID: r.id, revision: r.revision)
    }

    func markUncertain(packageID: UUID) throws {
        let s = try state()
        guard let r = s.records.first(where: { $0.id == packageID }) else { return }
        // If the prior commit succeeded, do not relabel a resolved save as lost work.
        guard s.leases.contains(where: { $0.packageID == packageID }) else { return }
        r.phaseRaw = "needsAttention"
        try s.context.save()
    }

    func retireDerivatives(_ handle: PhotoOriginalReference) throws -> Int64 {
        _ = try resolve(handle)
        let s = try state()
        guard s.leases.allSatisfy({ $0.writerStateRaw == "closedSourceRetained" }),
              let record = s.records.first(where: { $0.id == handle.packageID }), record.phaseRaw == "draftOwned",
              let original = s.references.first(where: { $0.id == handle.referenceID }) else {
            throw PhotoPreparationFailure.staleGeneration
        }
        for edge in s.references where edge.packageID == handle.packageID && edge.ordinal == original.ordinal && edge.roleRaw != "original" {
            edge.isLive = false
            edge.revision = try PhotoPreparationPolicy.add([edge.revision, 1])
        }
        for asset in s.assets where !s.references.contains(where: { $0.assetID == asset.id && $0.isLive }) {
            asset.cleanupStateRaw = "retiring"
        }
        record.revision = try PhotoPreparationPolicy.add([record.revision, 1])
        try s.context.save()
        return original.ordinal
    }

    func removeOriginal(_ handle: PhotoOriginalReference) throws {
        _ = try resolve(handle)
        let s = try state()
        guard !s.leases.contains(where: { $0.packageID == handle.packageID }),
              let record = s.records.first(where: { $0.id == handle.packageID }), record.phaseRaw == "draftOwned",
              let original = s.references.first(where: { $0.id == handle.referenceID }) else {
            throw PhotoPreparationFailure.cleanupPending
        }
        for edge in s.references where edge.packageID == handle.packageID && edge.ordinal == original.ordinal {
            edge.isLive = false
            edge.revision = try PhotoPreparationPolicy.add([edge.revision, 1])
        }
        for asset in s.assets where !s.references.contains(where: { $0.assetID == asset.id && $0.isLive }) {
            asset.cleanupStateRaw = "retiring"
        }
        let envelope = try PhotoPreparationPolicy.decodeDraft(record.supportingContextData)
        record.supportingContextData = try PhotoPreparationPolicy.encodeDraft(contexts: envelope.contexts,
            presentation: envelope.presentation.filter { $0.referenceID != handle.referenceID })
        for edge in s.references where edge.packageID == handle.packageID && edge.isLive && edge.ordinal > original.ordinal {
            edge.ordinal -= 1
        }
        record.revision = try PhotoPreparationPolicy.add([record.revision, 1])
        try s.context.save()
    }

    func validateSourceRelease(_ handle: PhotoOriginalReference, identity: String) throws {
        _ = try resolve(handle)
        let s = try state()
        guard s.leases.contains(where: { $0.assetID == handle.assetID && $0.packageID == handle.packageID
            && $0.ownerID == handle.ownerID && $0.sourceIdentity == identity && $0.writerStateRaw == "closedSourceRetained" }) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
    }

    func validateSourceReturn(packageID: UUID, ownerID: UUID, identity: String) throws -> UUID {
        let s = try state()
        let matches = s.leases.filter { $0.packageID == packageID && $0.ownerID == ownerID
            && $0.sourceIdentity == identity && $0.allocatedByteCount > 0 }
        guard matches.count == 1, let lease = matches.first else { throw PhotoPreparationFailure.inconsistentOwnership }
        return lease.id
    }

    func confirmSourceReturn(packageID: UUID, ownerID: UUID, identity: String, leaseID: UUID) throws {
        guard try validateSourceReturn(packageID: packageID, ownerID: ownerID, identity: identity) == leaseID else {
            throw PhotoPreparationFailure.staleGeneration
        }
        let s = try state()
        guard let lease = s.leases.first(where: { $0.id == leaseID }) else { throw PhotoPreparationFailure.staleGeneration }
        if lease.writerStateRaw == "closedSourceRetained" { s.context.delete(lease) }
        else {
            lease.allocatedByteCount = 0
            lease.sourceIdentity = nil
            lease.writerStateRaw = "closedNeedsAttention"
            lease.terminalProof = "sourceOwnerAcceptedReturn"
        }
        try s.context.save()
    }

    func confirmSourceRelease(_ handle: PhotoOriginalReference, identity: String) throws {
        let s = try state()
        guard let lease = s.leases.first(where: { $0.assetID == handle.assetID && $0.packageID == handle.packageID
            && $0.ownerID == handle.ownerID && $0.sourceIdentity == identity && $0.writerStateRaw == "closedSourceRetained" }),
              s.references.contains(where: { $0.id == handle.referenceID && $0.assetID == handle.assetID && $0.isLive }) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        s.context.delete(lease)
        try s.context.save()
    }

    func retireAll() throws {
        let records = try state().records.map { ($0.id, $0.ownerID, $0.revision) }
        for (id, owner, revision) in records { try retire(packageID: id, ownerID: owner, expectedRevision: revision) }
    }

    static func hasLiabilities(in context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) > 0
            || context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) > 0
            || context.fetchCount(FetchDescriptor<PhotoPreparationReference>()) > 0
            || context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) > 0
    }

    func recovery(ownerID: UUID) throws -> [PhotoPreparationDraft] {
        let s = try state()
        return try s.records.filter { $0.ownerID == ownerID }.map { record in
            let originals = s.references.filter { $0.packageID == record.id && $0.isLive && $0.roleRaw == "original" }
                .sorted { $0.ordinal < $1.ordinal }
            let handles = try originals.map { edge -> PhotoOriginalReference in
                guard let asset = s.assets.first(where: { $0.id == edge.assetID }) else {
                    throw PhotoPreparationFailure.inconsistentOwnership
                }
                return PhotoOriginalReference(ownerID: ownerID, packageID: record.id, referenceID: edge.id,
                    assetID: asset.id, assetGeneration: asset.generation, draftGeneration: record.draftGeneration,
                    referenceRevision: edge.revision)
            }
            return PhotoPreparationDraft(packageID: record.id, draftGeneration: record.draftGeneration,
                revision: record.revision, phase: record.phaseRaw, originals: handles,
                contexts: try PhotoPreparationPolicy.decodeDraft(record.supportingContextData).contexts,
                needsAttention: record.phaseRaw == "needsAttention" || s.leases.contains { $0.packageID == record.id }
                    || s.references.filter { $0.packageID == record.id && $0.isLive }.contains { edge in
                        s.assets.contains { $0.id == edge.assetID && $0.cleanupStateRaw == "missing" }
                    }, presentation: try PhotoPreparationPolicy.decodeDraft(record.supportingContextData).presentation,
                retainedSourceIdentities: s.leases.filter { $0.packageID == record.id && $0.allocatedByteCount > 0 }.compactMap(\.sourceIdentity))
        }
    }

    func knownFiles() throws -> (files: [PhotoPreparationFile], pending: [String]) {
        let s = try state()
        return (s.assets.map(fileValue), s.leases.filter { $0.writerStateRaw != "closedSourceRetained" }.flatMap { [$0.partialFileToken, $0.finalFileToken] })
    }

    /// No timeout-based closure: the caller already holds the exclusive namespace
    /// lock, so another conforming writer cannot still own a provider callback.
    func markMissing(assetID: UUID) throws {
        let s = try state()
        guard let asset = s.assets.first(where: { $0.id == assetID }) else { throw PhotoPreparationFailure.inconsistentOwnership }
        asset.cleanupStateRaw = "missing"
        try s.context.save()
    }

    func filesToRecover() throws -> [PhotoPreparationFile] {
        try state().assets.filter { $0.cleanupStateRaw == "ready" }.map(fileValue)
    }

    func reconcileClosedWriters() throws {
        let s = try state()
        for lease in s.leases {
            if lease.writerStateRaw == "closedSourceRetained" { continue }
            lease.writerStateRaw = "closedNeedsAttention"
            lease.terminalProof = "exclusiveNamespaceLock"
            s.records.first { $0.id == lease.packageID }?.phaseRaw = "needsAttention"
        }
        try s.context.save()
    }

    func retire(packageID: UUID, ownerID: UUID, expectedRevision: Int64) throws {
        let s = try state()
        guard let r = s.records.first(where: { $0.id == packageID && $0.ownerID == ownerID }),
              r.revision == expectedRevision else { throw PhotoPreparationFailure.staleGeneration }
        // Namespace exclusion proves our writer stopped, not that an external
        // inbox accepted its bytes back. Keep that liability until explicit ACK.
        guard !s.leases.contains(where: { $0.packageID == packageID && $0.allocatedByteCount > 0 }) else {
            throw PhotoPreparationFailure.cleanupPending
        }
        r.phaseRaw = "retiring"
        r.retirementRequested = true
        for edge in s.references where edge.packageID == packageID {
            edge.isLive = false
            edge.revision = try PhotoPreparationPolicy.add([edge.revision, 1])
        }
        for lease in s.leases where lease.packageID == packageID {
            lease.writerStateRaw = "closedRetiring"
            lease.terminalProof = "exclusiveNamespaceLock"
        }
        for asset in s.assets where !s.references.contains(where: { $0.assetID == asset.id && $0.isLive }) {
            asset.cleanupStateRaw = "retiring"
        }
        r.revision = try PhotoPreparationPolicy.add([r.revision, 1])
        try s.context.save()
    }

    func cleanupTokens() throws -> [String] {
        let s = try state()
        let closed = s.leases.filter { $0.writerStateRaw == "closedRetiring" && $0.terminalProof == "exclusiveNamespaceLock" }
        return s.assets.filter { asset in asset.cleanupStateRaw == "retiring"
            && !s.references.contains(where: { $0.assetID == asset.id && $0.isLive }) }.map(\.fileToken)
            + closed.flatMap { [$0.partialFileToken, $0.finalFileToken] }
    }

    /// Called only after all returned tokens have been confirmed absent and flushed.
    func finishCleanup(tokens: [String]) throws {
        let s = try state()
        guard Set(tokens) == Set(try cleanupTokens()) else { throw PhotoPreparationFailure.staleGeneration }
        let retiringAssets = s.assets.filter { tokens.contains($0.fileToken) }
        let deletedIDs = Set(retiringAssets.map(\.id))
        for asset in retiringAssets {
            guard !s.references.contains(where: { $0.assetID == asset.id && $0.isLive }) else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            s.context.delete(asset)
        }
        for edge in s.references where deletedIDs.contains(edge.assetID) || !edge.isLive { s.context.delete(edge) }
        for lease in s.leases where tokens.contains(lease.finalFileToken) && lease.allocatedByteCount == 0 { s.context.delete(lease) }
        for record in s.records {
            if record.retirementRequested { s.context.delete(record) }
            else {
                let ids = Set(s.references.filter { $0.packageID == record.id && $0.isLive }.map(\.assetID))
                record.allocatedByteCount = try PhotoPreparationPolicy.add(s.assets.filter { ids.contains($0.id) }.map(\.byteCount))
            }
        }
        try s.context.save()
    }

    /// Test/prepared composition may acquire an additional owner edge without a
    /// physical duplicate. Hash equality alone never calls this operation.
    func shareOriginal(_ handle: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) throws -> PhotoOriginalReference {
        let file = try resolve(handle)
        let s = try state()
        guard s.leases.allSatisfy({ $0.writerStateRaw == "closedSourceRetained" }), s.records.count < PhotoPreparationPolicy.maximumPackages,
              !s.records.contains(where: { $0.id == packageID }) else { throw PhotoPreparationFailure.storageLimit }
        let referenceID = UUID()
        s.context.insert(PhotoPreparationRecord(id: packageID, ownerID: handle.ownerID,
            contractVersion: PhotoPreparationPolicy.contract, draftID: packageID, draftGeneration: draftGeneration,
            revision: 0, phaseRaw: "draftOwned", supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []),
            allocatedByteCount: file.byteCount, retirementRequested: false))
        s.context.insert(PhotoPreparationReference(id: referenceID, packageID: packageID, assetID: handle.assetID,
            ownerID: handle.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        try s.context.save()
        return PhotoOriginalReference(ownerID: handle.ownerID, packageID: packageID, referenceID: referenceID,
            assetID: handle.assetID, assetGeneration: handle.assetGeneration, draftGeneration: draftGeneration, referenceRevision: 0)
    }

    private func fileValue(_ asset: PhotoPreparationAsset) -> PhotoPreparationFile {
        PhotoPreparationFile(assetID: asset.id, generation: asset.generation, token: asset.fileToken,
            byteCount: asset.byteCount, sha256: asset.sha256, contentType: asset.contentType)
    }
}
