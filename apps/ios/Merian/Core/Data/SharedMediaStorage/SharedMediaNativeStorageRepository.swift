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
    fileprivate var lifecycleFault: ((SharedMediaNativeLifecycleBoundary) throws -> Void)?
    fileprivate var preparationAvailableBytes: Int64?
    fileprivate var preparationFocusFactory = ImageFocusWorkFactory()
    fileprivate var preparationFault: ((SharedMediaNativePreparationBoundary) throws -> Void)?
    fileprivate var metadataFault: ((SharedMediaNativeMetadataBoundary) throws -> Void)?
    fileprivate var metadataAvailableBytes: Int64?
    fileprivate var inspectionAuditCount = 0
    fileprivate var acquisitionFault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?
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

    /// Only the same-file registered controller can begin nonempty admission.
    fileprivate static func originalAdmission(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                                              inboxRoot: URL, inventoryID: UUID, ownerID: UUID, writerEpoch: UUID,
                                              pause: (@Sendable () async -> Void)?) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: nil, originals: true, expectedOwnerID: ownerID, originalWriterEpoch: writerEpoch, pause: pause)
    }

    fileprivate func inspectOriginals(check: @escaping @MainActor () throws -> Void) async throws -> SharedMediaNativeOriginalSnapshot {
        try check()
        let expected = try originalHeader(audit: true)
        guard let expectedOwnerID else { throw SharedMediaStorageFailure.closed }
        let authority = SharedMediaNativeInspectionAuthority(ownerID: expectedOwnerID) {
            try check(); try self.requireOriginalHeader(expected)
        }
        let recovery = try await SharedMediaNativeOriginalInspection.run(reader: originalReadback(), io: originalIO, authority: authority)
        try authority.validate()
        guard try originalHeader(audit: true) == expected else { throw SharedMediaStorageFailure.conflict }
        return .init(inventory: expected, requiresRecovery: recovery)
    }

    fileprivate func originalReadback() throws -> SharedMediaNativeOriginalReadback {
        try .init(container: container, inventoryID: inventoryID, authority: mutationAuthority(check: {}))
    }
    fileprivate func originalReceipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
        try acquisitionBoundary(.beforeReadback)
        return try originalReadback().receipt(request)
    }
    fileprivate func reservedState(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativeReservedState {
        try acquisitionBoundary(.beforeReadback)
        return try originalReadback().reservedState(request)
    }

    fileprivate func reserveOriginal(_ request: SharedMediaAcquisitionIntent, check: @escaping @MainActor () throws -> Void) throws {
        _ = try originalHeader(audit: true)
        let transaction = try SharedMediaNativeAcquisitionMutation.reserve(container: container, request: request,
            authority: mutationAuthority(check: check), availableBytes: files.availableBytes())
        try acquisitionBoundary(.beforeReservationSave); try transaction.save(); try acquisitionBoundary(.afterReservationSave)
    }

    fileprivate func writeOriginal(_ data: Data, request: SharedMediaAcquisitionIntent) async throws -> SharedMediaPhotoRetirementInspection {
        let proof = try await originalIO.write(data, request: request)
        try acquisitionBoundary(.afterOriginalWrite)
        return proof
    }
    fileprivate func loadOriginal(_ provider: @Sendable () async throws -> Data) async throws -> Data { try await originalIO.load(provider) }

    fileprivate func completeOriginal(_ request: SharedMediaAcquisitionIntent, proof: SharedMediaPhotoRetirementInspection,
                                      check: @escaping @MainActor () throws -> Void) throws {
        let transaction = try SharedMediaNativeAcquisitionMutation.complete(container: container, request: request,
            authority: mutationAuthority(check: check), proof: proof)
        try acquisitionBoundary(.beforeCompletionSave); try transaction.save(); try acquisitionBoundary(.afterCompletionSave)
    }

    fileprivate func holdOriginal(_ request: SharedMediaAcquisitionIntent) throws {
        let transaction = try SharedMediaNativeAcquisitionMutation.hold(container: container, request: request,
            authority: mutationAuthority(check: {}))
        try acquisitionBoundary(.beforeHeldSave); try transaction.save(); try acquisitionBoundary(.afterHeldSave)
    }
    fileprivate func metadata(packageID: UUID, check: @escaping @MainActor () throws -> Void) throws -> SharedMediaNativeMetadataMutation {
        try metadataBoundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, packageID: packageID, authority: mutationAuthority(check: check))
    }
    fileprivate func saveMetadata(_ request: SharedMediaNativeMetadataRequest, check: @escaping @MainActor () throws -> Void) throws -> Int64 {
        var available = try files.availableBytes()
        #if DEBUG
        if let limit = metadataAvailableBytes { available = min(available, limit) }
        #endif
        do {
            _ = try metadata(packageID: request.packageID, check: check).apply(request, availableBytes: available,
                beforeSave: { try self.metadataBoundary(.beforeSave) }, afterSave: { try self.metadataBoundary(.afterSave) })
        } catch {
            let failure = error
            do { return try metadata(packageID: request.packageID, check: check).result(request) } catch { throw failure }
        }
        return try metadata(packageID: request.packageID, check: check).result(request)
    }
    fileprivate func preparationOperations(_ check: @escaping @MainActor () throws -> Void) throws -> SharedMediaNativePreparationOperations {
        var focusFactory = ImageFocusWorkFactory()
        #if DEBUG
        focusFactory = preparationFocusFactory
        #endif
        return try .init(container: container, inventoryID: inventoryID, authority: mutationAuthority(check: check), io: originalIO, focusFactory: focusFactory,
            verifyFreezeProofs: { proofs in
                for proof in proofs { try self.photos.requireCurrentSharedInspection(proof) }
            }, availableBytes: {
                let available = try self.files.availableBytes()
                #if DEBUG
                if let limit = self.preparationAvailableBytes { return min(available, limit) }
                #endif
                return available
            }, boundary: { point in
                #if DEBUG
                try self.preparationFault?(point)
                #endif
            })
    }
    fileprivate func lifecycleOperations(_ check: @escaping @MainActor () throws -> Void) throws -> SharedMediaNativeLifecycleOperations {
        try .init(container: container, inventoryID: inventoryID, authority: mutationAuthority(check: check), io: originalIO,
            availableBytes: { try self.files.availableBytes() }, boundary: { try self.lifecycleBoundary($0) })
    }
    private func lifecycleBoundary(_ point: SharedMediaNativeLifecycleBoundary) throws {
        #if DEBUG
        try lifecycleFault?(point)
        #endif
    }
    private func metadataBoundary(_ point: SharedMediaNativeMetadataBoundary) throws {
        #if DEBUG
        try metadataFault?(point)
        #endif
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
        try acquisitionFault?(boundary)
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
        if audit { inspectionAuditCount += 1 }
        #endif
        return try SharedMediaNativeEligibility.originalHeader(container: container, inventoryID: inventoryID,
            generation: generation, storeIdentity: storeIdentity, rootBinding: rootBinding, ownerID: expectedOwnerID, audit: audit)
    }

}

/// Registered before admission, so Auth can reach an in-flight open. This
/// qualification composition owns acquisition and settlement; live wiring stays disabled.
@MainActor
final class SharedMediaNativeOriginalOwner {
    private enum Phase { case unopened, opening, ready, failed, suspended }
    private let account: PhotoOriginalPreparationOwner.AccountAccess
    private let drain: SharedMediaNativeOriginalDrain
    private var registration: SharedMediaNativeOriginalDrain.Registration?
    private var phase = Phase.unopened
    private let writerEpoch = UUID()
    private var pendingSettlement: (request: SharedMediaAcquisitionIntent, loaderStarted: Bool)?
    private var storage: SharedMediaNativeStorageRepository?
    private var cancelActive: (() -> Void)?
    private var awaitActive: (() async -> Void)?

    private init(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain) {
        self.account = account; self.drain = drain
    }

    #if DEBUG
    static func qualification(account: PhotoOriginalPreparationOwner.AccountAccess,
                              drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        let owner = SharedMediaNativeOriginalOwner(account: account, drain: drain)
        owner.registration = try drain.register { [weak owner] in
            guard let owner else { return true }
            return await owner.invalidateAndAwaitForAccountTransition()
        }
        return owner
    }

    func open(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
              inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeOriginalSnapshot {
        guard phase == .unopened, let registration, drain.isCurrent(registration) else { throw SharedMediaStorageFailure.closed }
        phase = .opening
        do {
            return try await perform { [self] lease in
                let candidate = try SharedMediaNativeStorageRepository.originalAdmission(container: container,
                    authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot, inventoryID: inventoryID, ownerID: account.ownerID, writerEpoch: writerEpoch, pause: pause)
                storage = candidate
                let result = try await candidate.inspectOriginals { try self.check(lease) }
                try check(lease)
                phase = .ready
                return result
            }
        } catch {
            if phase != .suspended { phase = .failed }
            storage = nil
            throw error
        }
    }
    #endif

    func snapshot() async throws -> SharedMediaNativeOriginalSnapshot {
        guard phase == .ready else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try await storage.inspectOriginals { try self.check(lease) }
        }
    }

    #if DEBUG
    func setAcquisitionFault(_ fault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?) throws {
        guard (phase == .ready || phase == .suspended), cancelActive == nil, let storage else { throw SharedMediaStorageFailure.closed }
        storage.acquisitionFault = fault
    }
    var inspectionAuditCount: Int { storage?.inspectionAuditCount ?? 0 }
    func setMetadataFault(_ fault: ((SharedMediaNativeMetadataBoundary) throws -> Void)?, availableBytes: Int64? = nil) throws {
        guard phase == .ready, cancelActive == nil, let storage else { throw SharedMediaStorageFailure.closed }
        storage.metadataFault = fault; storage.metadataAvailableBytes = availableBytes
    }
    #endif

    func prepareShare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) async throws -> SharedMediaNativeShareRequest {
        try await lifecycle { storage, check in try storage.lifecycleOperations(check).prepareShare(source, packageID: packageID, draftGeneration: draftGeneration) }
    }
    func share(_ request: SharedMediaNativeShareRequest) async throws -> PhotoOriginalReference {
        try await lifecycle { storage, check in try storage.lifecycleOperations(check).share(request) }
    }
    func prepareRemoval(_ source: PhotoOriginalReference) async throws -> SharedMediaNativeRemovalRequest {
        try await lifecycle { storage, check in try storage.lifecycleOperations(check).prepareRemoval(source) }
    }
    func remove(_ request: SharedMediaNativeRemovalRequest) async throws {
        try await lifecycle { storage, check in try await storage.lifecycleOperations(check).remove(request) }
        try await recoverRetirements()
    }
    func recoverRetirements() async throws {
        try await lifecycle(recovery: true) { storage, check in try await storage.lifecycleOperations(check).recoverRetirements() }
    }
    func abandonPendingAcquisition(_ request: SharedMediaAcquisitionIntent) async throws {
        try await lifecycle(recovery: true) { storage, check in try await storage.lifecycleOperations(check).abandon(request) }
        try await recoverPendingAbandonments()
    }
    func recoverPendingAbandonments() async throws {
        try await lifecycle(recovery: true) { storage, check in try await storage.lifecycleOperations(check).recoverPendingAbandonments() }
    }
    private func lifecycle<T: Sendable>(recovery: Bool = false,
        _ body: @escaping @MainActor (SharedMediaNativeStorageRepository, @escaping @MainActor () throws -> Void) async throws -> T) async throws -> T {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals { try self.check(lease) }
            guard recovery || !snapshot.requiresRecovery else { throw PhotoPreparationFailure.cleanupPending }
            return try await body(storage, { try self.check(lease) })
        }
    }
    #if DEBUG
    func setLifecycleFault(_ fault: ((SharedMediaNativeLifecycleBoundary) throws -> Void)?) throws {
        guard phase == .ready, cancelActive == nil, let storage else { throw SharedMediaStorageFailure.closed }; storage.lifecycleFault = fault
    }
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try await lifecycle(recovery: true) { storage, check in try await storage.lifecycleOperations(check).setReleaseFault(fault) }
    }
    #endif

    /// Reserves an explicit native attempt without dispatching a processor.
    /// Callers receive assertions, never a source URL or write access.
    func reservePreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePreparationAttempt {
        try await lifecycle { storage, check in
            try storage.preparationOperations(check).reserve(original: original, recipe: recipe)
        }
    }
    func activePreparation(packageID: UUID) async throws -> SharedMediaNativePreparationAttempt? {
        try await lifecycle(recovery: true) { storage, check in try storage.preparationOperations(check).active(packageID: packageID) }
    }
    func abandonPreparation(_ attempt: SharedMediaNativePreparationAttempt) async throws {
        try await lifecycle(recovery: true) { storage, check in try storage.preparationOperations(check).abandon(attempt) }
    }
    #if DEBUG
    func setPreparationFault(_ fault: ((SharedMediaNativePreparationBoundary) throws -> Void)?, availableBytes: Int64? = nil, focusFactory: ImageFocusWorkFactory = .init()) throws {
        guard phase == .ready, cancelActive == nil, let storage else { throw SharedMediaStorageFailure.closed }
        storage.preparationFault = fault; storage.preparationAvailableBytes = availableBytes; storage.preparationFocusFactory = focusFactory
    }
    #endif

    func prepareFreeze(packageID: UUID, pairIDs: [UUID], operationID: UUID) async throws -> SharedMediaNativeFreezeRequest {
        try await lifecycle { storage, check in
            try await storage.preparationOperations(check).prepareFreeze(packageID: packageID, pairIDs: pairIDs, operationID: operationID)
        }
    }
    /// Exact saved acknowledgement precedes current physical availability checks.
    func freeze(_ request: SharedMediaNativeFreezeRequest) async throws -> SharedMediaNativeFreezeCommit {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try await storage.preparationOperations({ try self.check(lease) }).freeze(request)
        }
    }

    func preparedFileState(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairFileState {
        try await lifecycle(recovery: true) { storage, check in try storage.preparationOperations(check).fileState(packageID: packageID, pairID: pairID) }
    }
    func recoverPreparedFiles(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairFileState {
        try await lifecycle(recovery: true) { storage, check in try await storage.preparationOperations(check).recoverFiles(packageID: packageID, pairID: pairID) }
    }
    func retirePreparedFiles(_ state: SharedMediaNativePairFileState) async throws {
        try await lifecycle(recovery: true) { storage, check in try await storage.preparationOperations(check).retireFiles(state) }
    }
    #if DEBUG
    func qualifyPreparedFiles(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairFileState {
        try await lifecycle { storage, check in try await storage.preparationOperations(check).prepareFiles(original: original, recipe: recipe) }
    }
    func setPairFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async throws {
        try await lifecycle(recovery: true) { storage, check in try await storage.preparationOperations(check).setPairFileFault(fault) }
    }
    #endif

    func plannedPreparation(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairPlan? {
        try await lifecycle(recovery: true) { storage, check in try storage.preparationOperations(check).plan(packageID: packageID, pairID: pairID) }
    }
    func abandonPlannedPreparation(_ plan: SharedMediaNativePairPlan) async throws {
        try await lifecycle(recovery: true) { storage, check in try storage.preparationOperations(check).abandonPlan(plan) }
    }
    func prepareMetadata(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                         presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> SharedMediaNativeMetadataRequest {
        try await lifecycle { storage, check in
            try storage.metadata(packageID: packageID, check: check)
                .request(draftGeneration: draftGeneration, contexts: contexts, presentation: presentation)
        }
    }
    func saveMetadata(_ request: SharedMediaNativeMetadataRequest) async throws -> Int64 {
        try await lifecycle { storage, check in try storage.saveMetadata(request, check: check) }
    }
    #if DEBUG
    /// Qualification only until the native pair owner consumes outputs in the
    /// same retained operation. Never used by live Capture or queue composition.
    func qualifyPhotoPreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe, savePlan: Bool = false) async throws -> SharedMediaNativePreparedOutputs {
        try await lifecycle { storage, check in
            try await storage.preparationOperations(check).prepare(original: original, recipe: recipe, savePlan: savePlan)
        }
    }
    #endif

    func prepareOriginal(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                         kind: SharedMediaAcquisitionIntent.Kind) async throws -> SharedMediaAcquisitionIntent {
        try await lifecycle { [self] storage, _ in
            try storage.originalReadback().request(packageID: packageID, draftGeneration: draftGeneration, ordinal: ordinal, kind: kind, epoch: writerEpoch)
        }
    }

    func acquireOriginal(_ request: SharedMediaAcquisitionIntent,
                         load: @escaping @Sendable () async throws -> Data) async throws -> SharedMediaAcquisitionResult {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals { try self.check(lease) }
            if let existing = try storage.originalReceipt(request) {
                if case .completed(_, let result) = existing { return result }
                throw PhotoPreparationFailure.cleanupPending
            }
            guard !snapshot.requiresRecovery, request.writerEpoch == writerEpoch else { throw PhotoPreparationFailure.cleanupPending }
            try check(lease)
            var loaderStarted = false
            do {
                do { try storage.reserveOriginal(request) { try self.check(lease) } } catch { /* Exact saved-state recovery below. */ }
                guard case .reserved = try storage.originalReceipt(request) else { throw SharedMediaStorageFailure.conflict }
                let reserved = try storage.reservedState(request)
                try check(lease)
                // This is the sole loader invocation. Cold reservations never reach it.
                loaderStarted = true
                let data = try await storage.loadOriginal(load)
                try check(lease)
                guard try storage.reservedState(request) == reserved else { throw SharedMediaStorageFailure.stale }
                let proof = try await storage.writeOriginal(data, request: request)
                try check(lease)
                guard try storage.reservedState(request) == reserved else { throw SharedMediaStorageFailure.stale }
                do { try storage.completeOriginal(request, proof: proof) { try self.check(lease) } } catch { /* Exact saved-state recovery below. */ }
                guard case .completed(_, let result) = try storage.originalReceipt(request) else { throw SharedMediaStorageFailure.conflict }
                return result
            } catch {
                pendingSettlement = (request, loaderStarted)
                if let result = try? reconcileSettlement() { return result }
                throw error
            }
        }
    }

    /// Called only after the actual loader/file operation has returned. This
    /// settlement path deliberately does not reuse a cancelled dispatch check.
    private func reconcileSettlement() throws -> SharedMediaAcquisitionResult? {
        guard let pending = pendingSettlement, let storage else { return nil }
        if let saved = try storage.originalReceipt(pending.request) {
            switch saved {
            case .completed(_, let result): pendingSettlement = nil; return result
            case .held: pendingSettlement = nil
            case .reserved:
                do { try storage.holdOriginal(pending.request) } catch { /* Fresh exact readback below. */ }
                guard case .held = try storage.originalReceipt(pending.request) else { throw SharedMediaStorageFailure.conflict }
                pendingSettlement = nil
            case .released: throw SharedMediaStorageFailure.conflict
            }
        } else {
            guard !pending.loaderStarted else { throw SharedMediaStorageFailure.conflict }
            pendingSettlement = nil
        }
        return nil
    }

    private func check(_ lease: AccountBoundWorkLease) throws {
        guard phase == .opening || phase == .ready, let registration, drain.isCurrent(registration),
              lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
    }

    private func perform<T: Sendable>(_ body: @escaping @MainActor (AccountBoundWorkLease) async throws -> T) async throws -> T {
        guard cancelActive == nil, let registration, drain.isCurrent(registration) else { throw PhotoPreparationFailure.busy }
        let lease = try account.begin()
        do { try check(lease) } catch { account.finish(lease); throw error }
        let task = Task { @MainActor in
            defer { account.finish(lease); cancelActive = nil; awaitActive = nil }
            let result = try await body(lease)
            try check(lease)
            return result
        }
        cancelActive = { task.cancel() }
        awaitActive = { _ = await task.result }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard phase == .ready, drain.isCurrent(registration) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
        return result
    }

    func invalidateAndAwaitForAccountTransition() async -> Bool {
        phase = .suspended
        if let registration { drain.seal(registration) }
        cancelActive?()
        await awaitActive?()
        // Durable held settlement retains liability but permits process-fence
        // release after actual termination. Unknown settlement remains closed.
        do { _ = try reconcileSettlement() } catch { return false }
        guard pendingSettlement == nil else { return false }
        storage = nil
        return true
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
