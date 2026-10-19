import Foundation
import SwiftData

/// Native-private fixture-store admission. No media mutation, purge or
/// production composition is exposed until the closed native owners qualify.
@MainActor
final class SharedMediaNativeStorageRepository {
    private static let mode = "nativeQualificationV1"
    private static let phase = "readyNativeAccountingV1"
    private let container: ModelContainer
    private let files: SharedMediaStorageFileOwner
    private let photos: PhotoPreparationLockedFiles
    private let originals: Bool
    private let expectedOwnerID: UUID?
    private let originalWriterEpoch: UUID?
    private let originalIO: SharedMediaNativeOriginalIO
    private let inbox: SharedMediaInboxFiles
    private let inventoryID: UUID
    private let generation: UUID
    private let storeIdentity: String
    private let rootBinding: String
    private let binding: Data
    private let nativeBinding: SharedMediaNativeBinding
    #if DEBUG
    private var debug: SharedMediaNativeDebugHooks?
    #endif
    private let sources: [String: URL]
    #if DEBUG
    static func qualification(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                              inboxRoot: URL, inventoryID: UUID) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: nil)
    }

    static func qualification(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                              inboxRoot: URL, inventoryID: UUID,
                              fault: @escaping (SharedMediaNativeInitializationBoundary) throws -> Void) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: fault)
    }
    #endif

    private init(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
                 inventoryID: UUID, fault: ((SharedMediaNativeInitializationBoundary) throws -> Void)?,
                 originals: Bool = false, expectedOwnerID: UUID? = nil, originalWriterEpoch: UUID? = nil, pause: (@Sendable () async -> Void)? = nil) throws {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.invalid }
        try SharedMediaNativeEligibility.requireTopology(storeURL: configuration.url, authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot)
        self.originalWriterEpoch = originalWriterEpoch
        self.container = container; self.inventoryID = inventoryID; self.originals = originals; self.expectedOwnerID = expectedOwnerID
        sources = [SharedMediaPhotoLedger.namespace: photoRoot, SharedMediaInboxFiles.namespace: inboxRoot]
        // The supplied container already exists. Fence before eligibility reads,
        // metadata/bindings and every subsequent operation, not before its creation.
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url, sources: sources)
        try files.requireEmpty()
        rootBinding = try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)
        storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        binding = try JSONEncoder().encode([Self.mode, inventoryID.uuidString, storeIdentity, rootBinding])
        let context = ModelContext(container); context.autosaveEnabled = false
        let existing = try originals
            ? SharedMediaNativeEligibility.originalState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding)
            : SharedMediaNativeEligibility.emptyState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding)
        if originals {
            guard let expectedOwnerID else { throw SharedMediaStorageFailure.invalid }
            try SharedMediaNativeEligibility.requireOriginalAccount(context, ownerID: expectedOwnerID)
        }
        let initializing = existing == nil
        generation = existing?.generation ?? UUID()
        if initializing { try SharedMediaNativeEligibility.requireEmptyBootstrapRoots([photoRoot, inboxRoot]) }
        let native = SharedMediaNativeBinding(bytes: binding, initializing: initializing, epoch: UUID())
        nativeBinding = SharedMediaNativeBinding(bytes: binding, initializing: false, epoch: native.epoch)
        photos = try PhotoPreparationLockedFiles(root: photoRoot, sharedBinding: .init(native: native))
        originalIO = SharedMediaNativeOriginalIO(files: photos, binding: nativeBinding, pause: pause)
        try fault?(.afterPhotoBinding)
        inbox = try SharedMediaInboxFiles(root: inboxRoot, binding: .init(native: native))
        try fault?(.afterInboxBinding)
        try files.bindStore(binding, initializing: initializing)
        try fault?(.afterAuthorityBinding)
        if initializing {
            context.insert(SharedMediaInventoryRecord(id: inventoryID, rootIdentity: rootBinding,
                storeIdentity: storeIdentity, generation: generation, revision: 0,
                modeRaw: Self.mode, phaseRaw: Self.phase, cursor: ""))
            context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: inventoryID, inventoryGeneration: generation))
            try fault?(.beforeSave)
            try context.save()
            try fault?(.afterSave)
        }
        if !originals { _ = try snapshot() }
    }

    /// Exact fresh read only. Nonempty native graphs remain unsupported here;
    /// an audit snapshot is not a constructor, writer or cleanup capability.
    func snapshot() throws -> SharedMediaStorageSnapshot {
        guard !originals else { throw SharedMediaStorageFailure.closed }
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try files.requireEmpty()
        try files.bindStore(binding, initializing: false)
        guard rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else {
            throw SharedMediaStorageFailure.conflict
        }
        try photos.requireSharedEmptyNamespace()
        try SharedMediaNativeEligibility.requireOnlyPhotoNamespace(sources[SharedMediaPhotoLedger.namespace])
        try inbox.validateInventory([])
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let row = try SharedMediaNativeEligibility.emptyState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding),
              row.generation == generation else { throw SharedMediaStorageFailure.conflict }
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }

    /// Only an account-bound grant from the registered owner admits this repository.
    static func originalAdmission(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                                  inboxRoot: URL, inventoryID: UUID, grant: SharedMediaNativeDispatchGrant,
                                  pause: (@Sendable () async -> Void)?) throws -> SharedMediaNativeStorageRepository {
        try grant.validate()
        guard grant.profile == mode else { throw SharedMediaStorageFailure.closed }
        let value = try Self(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: nil, originals: true,
            expectedOwnerID: grant.ownerID, originalWriterEpoch: grant.writerEpoch, pause: pause)
        #if DEBUG
        value.debug = grant.debug
        #endif
        try value.requireDispatch(grant)
        return value
    }

    func inspectOriginals(grant: SharedMediaNativeDispatchGrant) async throws -> SharedMediaNativeOriginalSnapshot {
        try requireDispatch(grant)
        let expected = try originalHeader(audit: true)
        guard let expectedOwnerID else { throw SharedMediaStorageFailure.closed }
        let authority = SharedMediaNativeInspectionAuthority(ownerID: expectedOwnerID) {
            try self.requireDispatch(grant); try self.requireOriginalHeader(expected)
        }
        let recovery = try await SharedMediaNativeOriginalInspection.run(reader: originalReadback(grant: grant), io: originalIO, authority: authority)
        try authority.validate()
        guard try originalHeader(audit: true) == expected else { throw SharedMediaStorageFailure.conflict }
        return .init(inventory: expected, requiresRecovery: recovery)
    }

    func originalReadback(grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativeOriginalReadback {
        try requireDispatch(grant)
        return try .init(container: container, inventoryID: inventoryID, authority: dispatchAuthority(grant))
    }
    func originalReceipt(_ request: SharedMediaAcquisitionIntent, grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaAcquisitionReceipt? {
        try requireDispatch(grant)
        try acquisitionBoundary(.beforeReadback)
        return try originalReadback(grant: grant).receipt(request)
    }
    func reservedState(_ request: SharedMediaAcquisitionIntent, grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativeReservedState {
        try requireDispatch(grant)
        try acquisitionBoundary(.beforeReadback)
        return try originalReadback(grant: grant).reservedState(request)
    }

    func reserveOriginal(_ request: SharedMediaAcquisitionIntent, grant: SharedMediaNativeDispatchGrant) throws {
        try requireDispatch(grant)
        _ = try originalHeader(audit: true)
        let transaction = try SharedMediaNativeAcquisitionMutation.reserve(container: container, request: request,
            authority: dispatchAuthority(grant), availableBytes: files.availableBytes())
        try acquisitionBoundary(.beforeReservationSave); try transaction.save(); try acquisitionBoundary(.afterReservationSave)
    }

    func writeOriginal(_ data: Data, request: SharedMediaAcquisitionIntent, grant: SharedMediaNativeDispatchGrant) async throws -> SharedMediaPhotoRetirementInspection {
        try requireDispatch(grant)
        let proof = try await originalIO.write(data, request: request)
        try requireDispatch(grant)
        try acquisitionBoundary(.afterOriginalWrite)
        return proof
    }
    func loadOriginal(_ provider: @Sendable () async throws -> Data, grant: SharedMediaNativeDispatchGrant) async throws -> Data {
        try requireDispatch(grant)
        let data = try await originalIO.load(provider)
        try requireDispatch(grant)
        return data
    }

    func completeOriginal(_ request: SharedMediaAcquisitionIntent, proof: SharedMediaPhotoRetirementInspection,
                                      grant: SharedMediaNativeDispatchGrant) throws {
        try requireDispatch(grant)
        let transaction = try SharedMediaNativeAcquisitionMutation.complete(container: container, request: request,
            authority: dispatchAuthority(grant), proof: proof)
        try acquisitionBoundary(.beforeCompletionSave); try transaction.save(); try acquisitionBoundary(.afterCompletionSave)
    }

    /// A terminated writer may settle its exact saved receipt after Auth seals
    /// dispatch. This entry has no file operation or fresh reservation path.
    func settleOriginal(_ grant: SharedMediaNativeSettlementGrant) throws -> SharedMediaAcquisitionResult? {
        try requireSettlement(grant)
        let authority = try mutationAuthority { try self.requireSettlement(grant) }
        let reader = SharedMediaNativeOriginalReadback(container: container, inventoryID: inventoryID, authority: authority)
        try acquisitionBoundary(.beforeReadback)
        guard let saved = try reader.receipt(grant.request) else {
            guard !grant.loaderStarted else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        switch saved {
        case .completed(_, let result): return result
        case .held: return nil
        case .reserved:
            do {
                let transaction = try SharedMediaNativeAcquisitionMutation.hold(container: container,
                    request: grant.request, authority: authority)
                try acquisitionBoundary(.beforeHeldSave); try transaction.save(); try acquisitionBoundary(.afterHeldSave)
            } catch { /* Exact saved acknowledgement below; no writer replay. */ }
            try acquisitionBoundary(.beforeReadback)
            guard case .held = try reader.receipt(grant.request) else { throw SharedMediaStorageFailure.conflict }
            return nil
        case .released: throw SharedMediaStorageFailure.conflict
        }
    }

    func metadata(packageID: UUID, grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativeMetadataMutation {
        try requireDispatch(grant)
        try metadataBoundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, packageID: packageID, authority: dispatchAuthority(grant))
    }
    func saveMetadata(_ request: SharedMediaNativeMetadataRequest, grant: SharedMediaNativeDispatchGrant) throws -> Int64 {
        try requireDispatch(grant)
        var available = try files.availableBytes()
        #if DEBUG
        if let limit = debug?.metadataAvailableBytes { available = min(available, limit) }
        #endif
        do {
            _ = try metadata(packageID: request.packageID, grant: grant).apply(request, availableBytes: available,
                beforeSave: { try self.metadataBoundary(.beforeSave) }, afterSave: { try self.metadataBoundary(.afterSave) })
        } catch {
            let failure = error
            do { return try metadata(packageID: request.packageID, grant: grant).result(request) } catch { throw failure }
        }
        return try metadata(packageID: request.packageID, grant: grant).result(request)
    }
    func preparationOperations(_ grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativePreparationOperations {
        try requireDispatch(grant)
        var focusFactory = ImageFocusWorkFactory()
        #if DEBUG
        focusFactory = debug?.preparationFocusFactory ?? focusFactory
        #endif
        return try .init(container: container, inventoryID: inventoryID, authority: dispatchAuthority(grant), io: originalIO, focusFactory: focusFactory,
            verifyFreezeProofs: { proofs in
                for proof in proofs { try self.photos.requireCurrentSharedInspection(proof) }
            }, availableBytes: {
                let available = try self.files.availableBytes()
                #if DEBUG
                if let limit = self.debug?.preparationAvailableBytes { return min(available, limit) }
                #endif
                return available
            }, boundary: { point in
                #if DEBUG
                try self.debug?.preparationFault?(point)
                #endif
            })
    }
    func lifecycleOperations(_ grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativeLifecycleOperations {
        try requireDispatch(grant)
        return try .init(container: container, inventoryID: inventoryID, authority: dispatchAuthority(grant), io: originalIO,
            availableBytes: { try self.files.availableBytes() }, boundary: { try self.lifecycleBoundary($0) })
    }
    private func lifecycleBoundary(_ point: SharedMediaNativeLifecycleBoundary) throws {
        #if DEBUG
        try debug?.lifecycleFault?(point)
        #endif
    }
    private func metadataBoundary(_ point: SharedMediaNativeMetadataBoundary) throws {
        #if DEBUG
        try debug?.metadataFault?(point)
        #endif
    }
    private func requireDispatch(_ grant: SharedMediaNativeDispatchGrant) throws {
        try grant.validate()
        guard originals, grant.ownerID == expectedOwnerID, grant.writerEpoch == originalWriterEpoch,
              grant.profile == Self.mode else { throw SharedMediaStorageFailure.closed }
    }
    private func requireSettlement(_ grant: SharedMediaNativeSettlementGrant) throws {
        try grant.validate()
        guard originals, grant.ownerID == expectedOwnerID, grant.writerEpoch == originalWriterEpoch,
              grant.profile == Self.mode else { throw SharedMediaStorageFailure.closed }
    }
    private func dispatchAuthority(_ grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativeMutationAuthority {
        try requireDispatch(grant)
        return try mutationAuthority { try self.requireDispatch(grant) }
    }
    private func mutationAuthority(check: @escaping @MainActor () throws -> Void) throws -> SharedMediaNativeMutationAuthority {
        guard let expectedOwnerID, let originalWriterEpoch else { throw SharedMediaStorageFailure.closed }
        return .init(binding: nativeBinding, ownerID: expectedOwnerID, writerEpoch: originalWriterEpoch) { [self] in
            try check()
            _ = try originalHeader(audit: true)
        }
    }
    private func acquisitionBoundary(_ boundary: SharedMediaNativeAcquisitionBoundary) throws {
        #if DEBUG
        try debug?.acquisitionFault?(boundary)
        #endif
    }

    private func requireOriginalHeader(_ expected: SharedMediaStorageSnapshot) throws {
        guard try originalHeader(audit: false) == expected else { throw SharedMediaStorageFailure.conflict }
    }

    private func originalHeader(audit: Bool) throws -> SharedMediaStorageSnapshot {
        guard originals, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try files.requireEmpty(); try files.bindStore(binding, initializing: false); try photos.checkIdentity()
        guard rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else { throw SharedMediaStorageFailure.conflict }
        try inbox.validateInventory([])
        #if DEBUG
        if audit { debug?.inspectionAuditCount += 1 }
        #endif
        return try SharedMediaNativeEligibility.originalHeader(container: container, inventoryID: inventoryID,
            generation: generation, storeIdentity: storeIdentity, rootBinding: rootBinding, ownerID: expectedOwnerID, audit: audit)
    }

}

/// Only the fenced native constructor can mint this immutable binding. No
/// decoding or raw-data factory is exposed outside this owner file.
struct SharedMediaNativeBinding: Sendable {
    let bytes: Data
    let initializing: Bool
    let epoch: UUID
    fileprivate init(bytes: Data, initializing: Bool, epoch: UUID) {
        self.bytes = bytes; self.initializing = initializing; self.epoch = epoch
    }
}

enum SharedMediaNativeInitializationBoundary: Sendable {
    case afterPhotoBinding, afterInboxBinding, afterAuthorityBinding, beforeSave, afterSave
}

/// Only this file's fenced repository can mint a synchronous save capability.
/// Retains the repository and checks account dispatch (or terminated-writer
/// settlement) plus fresh persistent root/store authority immediately before save.
@MainActor
struct SharedMediaNativeMutationAuthority {
    let binding: SharedMediaNativeBinding
    let ownerID: UUID
    let writerEpoch: UUID
    private let check: () throws -> Void
    fileprivate init(binding: SharedMediaNativeBinding, ownerID: UUID, writerEpoch: UUID, check: @escaping () throws -> Void) {
        self.binding = binding; self.ownerID = ownerID; self.writerEpoch = writerEpoch; self.check = check
    }
    func validate() throws { try check() }
}

/// A value-only page-read fence, minted solely by the enclosing inspection.
@MainActor
struct SharedMediaNativeInspectionAuthority {
    let ownerID: UUID
    private let check: () throws -> Void
    fileprivate init(ownerID: UUID, check: @escaping () throws -> Void) { self.ownerID = ownerID; self.check = check }
    func validate() throws { try check() }
}
