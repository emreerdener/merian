import Foundation
import SwiftData

enum SharedMediaCaptureArtifactWriteBoundary: CaseIterable {
    case beforeReservationSave, afterReservationSave, afterPartialCreation, afterPartialSave
    case afterBytes, afterRename, beforeReadySave, afterReadySave
}

/// A single operation owns reservation, inode receipt and completion. The
/// repository retains the store/account fence and capture locks throughout I/O.
/// Neither successful materialization nor its receipt authorizes submission.
@MainActor
enum SharedMediaCaptureArtifactWriter {
    typealias Boundary = (SharedMediaCaptureArtifactWriteBoundary) throws -> Void

    static func materializeSource(_ input: SharedMediaCaptureDraftSourceInput, bytes: Data,
                                  container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                                  files: SharedMediaCaptureArtifactFiles, availableBytes: () throws -> Int64,
                                  boundary: Boundary = { _ in }) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        let header = try authority.header(container), id = input.id
        let context = ModelContext(container); context.autosaveEnabled = false
        try SharedMediaCaptureDraftJournalReceipt.requireSource(input, states: [.pending, .ready], phases: [.editing], context: context)
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        let request: SharedMediaCaptureArtifactRequest
        if let row = rows.first {
            request = try SharedMediaCaptureArtifactLedger.receipt(row).request
            let expected = try SharedMediaCaptureArtifactRequest(source: input, profile: authority.profile,
                writerEpoch: request.writerEpoch, rootBindingSHA256: files.rootBindingSHA256,
                inventoryRevision: request.inventoryRevision, allocationID: request.allocationID,
                referenceID: request.referenceID, leaseID: request.leaseID)
            guard request == expected else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard try SharedMediaCaptureSubmissionReceipt.matching(scanID: input.scanID,
                generation: input.submissionGeneration, in: context) == nil else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: input.scanID, context: context)
            request = try .init(source: input, profile: authority.profile, writerEpoch: authority.writerEpoch,
                rootBindingSHA256: files.rootBindingSHA256, inventoryRevision: header.inventory.revision,
                allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
        }
        return try await materialize(request, bytes: bytes, container: container, authority: authority,
            files: files, availableBytes: availableBytes, boundary: boundary)
    }

    static func materialize(_ input: SharedMediaCaptureArtifactInput, bytes: Data,
                            container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                            files: SharedMediaCaptureArtifactFiles, availableBytes: () throws -> Int64,
                            boundary: Boundary = { _ in }) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        let header = try authority.header(container)
        let context = ModelContext(container); context.autosaveEnabled = false
        _ = try parent(input, context: context, authority: authority, files: files)
        let id = input.id
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        let request: SharedMediaCaptureArtifactRequest
        if let row = rows.first {
            request = try SharedMediaCaptureArtifactLedger.receipt(row).request
            guard input.matches(request) else { throw SharedMediaStorageFailure.conflict }
        } else {
            request = try .init(id: input.id, profile: authority.profile, writerEpoch: authority.writerEpoch,
                scanID: input.scanID, submissionGeneration: input.submissionGeneration, planSHA256: input.planSHA256,
                rootBindingSHA256: files.rootBindingSHA256, inventoryRevision: header.inventory.revision,
                mediaID: input.mediaID, itemIndex: input.itemIndex, role: input.role, frameIndex: input.frameIndex,
                contentType: input.contentType, byteCount: input.byteCount, sha256: input.sha256,
                allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
        }
        return try await materialize(request, bytes: bytes, container: container, authority: authority,
            files: files, availableBytes: availableBytes, boundary: boundary)
    }

    private static func materialize(_ request: SharedMediaCaptureArtifactRequest, bytes: Data,
                                    container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                                    files: SharedMediaCaptureArtifactFiles, availableBytes: () throws -> Int64,
                                    boundary: Boundary = { _ in }) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        try request.validate()
        guard request.profile == authority.profile, request.rootBindingSHA256 == files.rootBindingSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        try await CaptureArtifactContentValidator().validate(bytes, request: request)
        let before = try authority.header(container)
        _ = try await audit(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        var value: SharedMediaCaptureArtifactLedger.Snapshot
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = request.id
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        if let existing = try context.fetch(query).first {
            guard try SharedMediaCaptureArtifactLedger.receipt(existing).request == request else { throw SharedMediaStorageFailure.conflict }
            value = try read(request, container: container, files: files)
        } else {
            guard request.writerEpoch == authority.writerEpoch, request.inventoryRevision == before.inventory.revision else {
                throw SharedMediaStorageFailure.stale
            }
            var totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
            let savedParent: SharedMediaCaptureSubmissionReceipt.Snapshot?
            if request.format == .v1 {
                guard let planSHA256 = request.planSHA256 else { throw SharedMediaStorageFailure.conflict }
                let input = SharedMediaCaptureArtifactInput(id: request.id, scanID: request.scanID,
                    submissionGeneration: request.submissionGeneration, mediaID: request.mediaID,
                    planSHA256: planSHA256, itemIndex: request.itemIndex, role: request.role,
                    frameIndex: request.frameIndex, contentType: request.contentType, byteCount: request.byteCount, sha256: request.sha256)
                savedParent = try parent(input, context: context, authority: authority, files: files)
            } else {
                savedParent = try SharedMediaCaptureSubmissionReceipt.matching(scanID: request.scanID,
                    generation: request.submissionGeneration, in: context)
                guard savedParent == nil else { throw SharedMediaStorageFailure.conflict }
                try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: request.scanID, context: context)
            }
            if savedParent == nil {
                let metadata = Int64(try request.encoded().count + 64 + SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 64 + 160
                    + SharedMediaCaptureRemoteStage.maximumBytes + 64)
                try totals.include(.init(packageID: request.scanID, pool: .durable, materialized: 0,
                    reserved: SharedMediaStoragePolicy.add(request.byteCount, metadata)))
            }
            try totals.checkAvailable(availableBytes())
            guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
            try reserve(request, container: container, authority: authority, boundary: boundary)
            value = try read(request, container: container, files: files)
        }
        // A saved ready receipt may be replayed only after the complete physical
        // audit above; no new inode or reservation is created on this path.
        if value.phase != .ready {
            value = try await files.materialize(value, bytes: bytes, container: container,
                authority: authority, boundary: boundary) { identity in
                    try transition(request, partial: identity, final: nil, container: container,
                        authority: authority, files: files, boundary: boundary)
                } complete: { partial, final in
                    try transition(request, partial: partial, final: final, container: container,
                        authority: authority, files: files, boundary: boundary)
                }
        }
        _ = try await audit(container, authority: authority, files: files)
        guard try read(request, container: container, files: files) == value, value.phase == .ready else {
            throw SharedMediaStorageFailure.stale
        }
        return value
    }

    /// A parent already reserves its missing members. Validate membership before
    /// saving a child, then replace that reservation with the child's ledger.
    private static func parent(_ input: SharedMediaCaptureArtifactInput, context: ModelContext,
                               authority: SharedMediaNativeAppOperationAuthority,
                               files: SharedMediaCaptureArtifactFiles) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot? {
        guard let value = try SharedMediaCaptureSubmissionReceipt.matching(scanID: input.scanID,
            generation: input.submissionGeneration, in: context) else {
            if let saved = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: input.scanID,
                generation: input.submissionGeneration, context: context) {
                guard saved.value.phase == .preparing, let attempt = saved.value.preparation,
                      try attempt.input(mediaID: input.mediaID, ownerID: authority.profile.ownerID) == input else {
                    throw SharedMediaStorageFailure.closed
                }
            }
            return nil
        }
        guard value.submission.profile == authority.profile,
              value.submission.rootBindingSHA256 == files.rootBindingSHA256,
              try value.submission.artifact(mediaID: input.mediaID) == input else { throw SharedMediaStorageFailure.conflict }
        if case .accepted = value.state {
            guard value.artifacts.contains(where: { $0.request.id == input.id && $0.phase == .ready }) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        return value
    }

    private static func audit(_ container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                              files: SharedMediaCaptureArtifactFiles) async throws -> SharedMediaNativeScopedSnapshot {
        try await SharedMediaNativeScopedAudit.runAppCapture(container: container, profile: authority.profile,
            files: files, header: { try authority.header(container) }, betweenPages: { await Task.yield() }, configure: { _ in })
    }

    private static func reserve(_ request: SharedMediaCaptureArtifactRequest, container: ModelContainer,
                                authority: SharedMediaNativeAppOperationAuthority, boundary: Boundary) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try inventory(context, profile: authority.profile)
        guard inventory.revision == request.inventoryRevision else { throw SharedMediaStorageFailure.stale }
        let id = request.id, scan = request.scanID, media = request.mediaID
        let allocation = request.allocationID, lease = request.leaseID, reference = request.referenceID
        let cohort = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.recipientScanID == scan })
        let peers = try SharedMediaCaptureArtifactCohort.activeRows(cohort, context: context) { prior in
            guard prior.request.profile == request.profile, prior.request.submissionGeneration == request.submissionGeneration,
                  prior.request.rootBindingSHA256 == request.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        }
        guard peers.count < 64 else { throw SharedMediaStorageFailure.capacity }
        for peer in peers {
            let prior = try SharedMediaCaptureArtifactLedger.auditReceipt(peer)
            let previous = prior.request
            guard previous.profile == request.profile, previous.submissionGeneration == request.submissionGeneration,
                  previous.rootBindingSHA256 == request.rootBindingSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            if previous.format == request.format {
                guard previous.planSHA256 == request.planSHA256,
                      previous.itemIndex != request.itemIndex || previous.role != request.role || previous.frameIndex != request.frameIndex else {
                    throw SharedMediaStorageFailure.conflict
                }
            } else {
                guard request.format == .v1, prior.phase == .ready, prior.remoteStage == nil else {
                    throw SharedMediaStorageFailure.conflict
                }
                if let parent = try SharedMediaCaptureSubmissionReceipt.matching(scanID: scan,
                    generation: request.submissionGeneration, in: context) {
                    guard parent.artifacts.contains(where: { $0.request == previous && $0.phase == .ready }) else {
                        throw SharedMediaStorageFailure.conflict
                    }
                } else {
                    try SharedMediaCapturePreparedAttempt.requireMember(request, context: context)
                    let input = try SharedMediaCaptureDraftSourceInput(retained: previous)
                    try SharedMediaCaptureDraftJournalReceipt.requireSource(input, states: [.ready], phases: [.preparing], context: context)
                }
            }
        }
        // Reject unique-key collisions before insertion: SwiftData upsert is
        // never accepted as evidence that this operation owned an older row.
        try absent(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate {
            $0.id == id || ($0.recipientScanID == scan && $0.mediaID == media)
                || $0.allocationID == allocation || $0.referenceID == reference || $0.leaseID == lease
        }))
        try absent(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == allocation }))
        try absent(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease || $0.allocationID == allocation }))
        try absent(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == reference || $0.allocationID == allocation }))
        try absent(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == allocation }))
        try absent(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease || $0.assetID == allocation }))
        try absent(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == reference || $0.assetID == allocation }))
        let record = SharedMediaOrdinaryArtifactRecord(id: id, inventoryID: request.profile.inventoryID,
            inventoryGeneration: request.profile.generation, ownerID: request.profile.ownerID,
            recipientScanID: scan, submissionGeneration: request.submissionGeneration,
            mediaID: media, itemIndex: request.itemIndex, roleRaw: request.role.rawValue, frameIndex: request.frameIndex,
            allocationID: allocation, referenceID: reference, leaseID: lease, writerEpoch: request.writerEpoch,
            requestData: try request.encoded(), requestSHA256: try request.digest)
        record.schemaVersion = request.schemaVersion
        context.insert(record)
        context.insert(SharedMediaAllocationRecord(id: allocation, inventoryID: request.profile.inventoryID,
            accountID: request.profile.ownerID, packageID: scan, namespaceRaw: SharedMediaCaptureRootJournal.namespace,
            fileToken: request.finalName, poolRaw: "durable", stateRaw: "reserved", materializedBytes: 0,
            reservedBytes: request.byteCount, physicalIdentity: nil))
        context.insert(SharedMediaLeaseRecord(id: lease, allocationID: allocation, processEpoch: request.writerEpoch,
            purposeRaw: SharedMediaCaptureArtifactLedger.leasePurpose, stateRaw: "open"))
        context.insert(SharedMediaReferenceRecord(id: reference, allocationID: allocation, accountID: request.profile.ownerID,
            ownerID: id.uuidString.lowercased(), roleRaw: SharedMediaCaptureRootJournal.namespace, stateRaw: "held", revision: 0))
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        _ = try authority.header(container)
        try boundary(.beforeReservationSave)
        _ = try authority.header(container)
        try context.save()
        try boundary(.afterReservationSave)
        _ = try authority.header(container)
    }

    private static func transition(_ request: SharedMediaCaptureArtifactRequest, partial: String, final: String?,
                                   container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                                   files: SharedMediaCaptureArtifactFiles, boundary: Boundary) throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        _ = try authority.header(container); try files.check()
        let before = try read(request, container: container, files: files)
        guard before.phase == (final == nil ? .reserved : .writing),
              final == nil || before.stage?.partialIdentity == partial else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try inventory(context, profile: authority.profile)
        let id = request.id, allocationID = request.allocationID, leaseID = request.leaseID
        let row = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id }))
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == allocationID }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }))
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: inventory.revision,
            partialIdentity: partial, finalIdentity: final)
        row.phaseRaw = final == nil ? "writing" : "ready"; row.revision = final == nil ? 1 : 2
        row.stageReceiptData = try stage.encoded(request: request)
        row.stageReceiptSHA256 = SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: request))
        allocation.stateRaw = row.phaseRaw; allocation.physicalIdentity = final ?? partial
        allocation.materializedBytes = final == nil ? 0 : request.byteCount
        allocation.reservedBytes = final == nil ? request.byteCount : 0
        lease.stateRaw = final == nil ? "open" : "closed"
        _ = try authority.header(container); try files.check()
        if final != nil { try boundary(.beforeReadySave) }
        _ = try authority.header(container)
        try context.save()
        try boundary(final == nil ? .afterPartialSave : .afterReadySave)
        _ = try authority.header(container)
        return try read(request, container: container, files: files)
    }

    private static func read(_ request: SharedMediaCaptureArtifactRequest, container: ModelContainer,
                             files: SharedMediaCaptureArtifactFiles) throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        let result = try SharedMediaCaptureArtifactLedger.read(id: request.id, profile: request.profile,
            rootBindingSHA256: files.rootBindingSHA256, context: context)
        guard result.request == request else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    private static func inventory(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> SharedMediaInventoryRecord {
        let id = profile.inventoryID
        let result = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(result) == profile else { throw SharedMediaStorageFailure.stale }
        return result
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
    private static func absent<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws {
        var query = descriptor; query.fetchLimit = 1
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
}

private actor CaptureArtifactContentValidator {
    func validate(_ bytes: Data, request: SharedMediaCaptureArtifactRequest) throws {
        try Task.checkCancellation()
        guard bytes.count == request.byteCount, SharedMediaAcquisitionEncoding.digest(bytes) == request.sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        try Task.checkCancellation()
    }
}
