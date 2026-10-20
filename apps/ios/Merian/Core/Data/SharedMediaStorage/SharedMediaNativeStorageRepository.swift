import Foundation
import SwiftData

/// Native-private fixture-store admission. No media mutation, purge or
/// production composition is exposed until the closed native owners qualify.
@MainActor
final class SharedMediaNativeStorageRepository {
    private enum OpenKind { case qualificationEmpty, qualificationOriginal, scopedInspection, appInitialization, appDispatch }
    private let openKind: OpenKind
    private let scopedIdentity: SharedMediaNativeScopeIdentity?
    private let scopedRoots: (authority: URL, photo: URL, inbox: URL)?
    private static let mode = "nativeQualificationV1"
    private static let phase = "readyNativeAccountingV1"
    private let container: ModelContainer
    private let files: SharedMediaStorageFileOwner
    private let photos: PhotoPreparationLockedFiles
    private let originals: Bool
    private let expectedOwnerID: UUID?, originalWriterEpoch: UUID?
    private let originalIO: SharedMediaNativeOriginalIO
    private let inbox: SharedMediaInboxFiles
    private let inventoryID: UUID, generation: UUID
    private let storeIdentity: String, rootBinding: String
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
        openKind = originals ? .qualificationOriginal : .qualificationEmpty
        scopedIdentity = nil; scopedRoots = nil
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
        guard openKind == .qualificationEmpty, !originals else { throw SharedMediaStorageFailure.closed }
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

    static func scopedInspection(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                                 inboxRoot: URL, grant: SharedMediaNativeScopedReadGrant) throws -> SharedMediaNativeStorageRepository {
        try grant.validate()
        return try .init(scoped: container, authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot, grant: grant)
    }

    /// Exact existing profile only. No bootstrap, marker creation, source scan,
    /// media processing or mutation capability is available from this branch.
    private init(scoped container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
                 grant: SharedMediaNativeScopedReadGrant) throws {
        try grant.validate()
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeScopedEligibility.requireRoots(authority: authorityRoot, photo: photoRoot, inbox: inboxRoot)
        openKind = .scopedInspection; scopedIdentity = grant.scope
        scopedRoots = (authorityRoot, photoRoot, inboxRoot)
        self.container = container; inventoryID = grant.scope.inventoryID; generation = grant.scope.generation
        originals = false; expectedOwnerID = grant.scope.ownerID; originalWriterEpoch = grant.writerEpoch
        sources = [SharedMediaPhotoLedger.namespace: photoRoot, SharedMediaInboxFiles.namespace: inboxRoot]
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url,
            sources: sources, requireExistingFence: true)
        rootBinding = try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)
        storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        guard rootBinding == grant.scope.rootBinding, storeIdentity == grant.scope.storeIdentity else { throw SharedMediaStorageFailure.conflict }
        binding = try grant.scope.binding
        nativeBinding = .init(bytes: binding, initializing: false, epoch: UUID())
        let context = ModelContext(container); context.autosaveEnabled = false
        _ = try SharedMediaNativeScopedEligibility.header(context: context, scope: grant.scope)
        try files.bindStore(binding, initializing: false)
        photos = try PhotoPreparationLockedFiles(root: photoRoot, sharedBinding: .init(native: nativeBinding))
        inbox = try SharedMediaInboxFiles(root: inboxRoot, binding: .init(native: nativeBinding))
        originalIO = SharedMediaNativeOriginalIO(files: photos, binding: nativeBinding, pause: nil)
        #if DEBUG
        debug = grant.debug
        #endif
        try requireScoped(grant)
    }
    func inspectScoped(grant: SharedMediaNativeScopedReadGrant) async throws -> SharedMediaNativeScopedSnapshot {
        try requireScoped(grant)
        let expected = try scopedSnapshot(grant.scope)
        let result = try await SharedMediaNativeScopedAudit(container: container, scope: grant.scope, expected: expected,
            check: {
                try self.requireScoped(grant)
                guard try self.scopedSnapshot(grant.scope) == expected else { throw SharedMediaStorageFailure.conflict }
            }, betweenPages: {
                #if DEBUG
                await self.debug?.scopedPagePause?()
                #endif
                await Task.yield()
            }).run()
        try requireScoped(grant)
        guard try scopedSnapshot(grant.scope) == expected else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    private func scopedSnapshot(_ scope: SharedMediaNativeScopeIdentity) throws -> SharedMediaStorageSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = try SharedMediaNativeScopedEligibility.header(context: context, scope: scope)
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }

    private func requireScoped(_ grant: SharedMediaNativeScopedReadGrant) throws {
        try grant.validate()
        guard openKind == .scopedInspection, scopedIdentity == grant.scope,
              originalWriterEpoch == grant.writerEpoch, let roots = scopedRoots,
              !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        try SharedMediaNativeScopedEligibility.requireRoots(authority: roots.authority, photo: roots.photo, inbox: roots.inbox)
        try files.check(); try files.bindStore(binding, initializing: false)
        try photos.checkIdentity(); try inbox.check()
        guard rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else { throw SharedMediaStorageFailure.conflict }
    }

    static func initializeApp(container: ModelContainer, parent: URL, inventoryID: UUID,
                              grant: SharedMediaNativeAppGrant) throws -> SharedMediaNativeStorageRepository {
        try grant.validate()
        return try .init(app: container, parent: parent, inventoryID: inventoryID, grant: grant)
    }

    private init(app container: ModelContainer, parent: URL, inventoryID: UUID, grant: SharedMediaNativeAppGrant) throws {
        try grant.validate()
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        self.container = container; self.inventoryID = inventoryID
        openKind = .appInitialization; scopedIdentity = nil; scopedRoots = nil
        originals = false; expectedOwnerID = grant.ownerID; originalWriterEpoch = grant.writerEpoch
        let authorityRoot = parent.appendingPathComponent("authority", isDirectory: true), photoRoot = parent.appendingPathComponent("photo", isDirectory: true), inboxRoot = parent.appendingPathComponent("inbox", isDirectory: true)
        sources = [SharedMediaPhotoLedger.namespace: photoRoot, SharedMediaInboxFiles.namespace: inboxRoot]
        storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        let bootstrap = SharedMediaNativeBootstrapAuthority(parent: parent, inventoryID: inventoryID,
            storeIdentity: storeIdentity, container: container, grant: grant)
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url, sources: sources, bootstrap: bootstrap)
        let profile = try files.bootstrapProfile()
        generation = profile.generation; rootBinding = try profile.rootIdentity; binding = try profile.binding
        nativeBinding = .init(bytes: binding, initializing: false, epoch: UUID())
        photos = try PhotoPreparationLockedFiles(root: photoRoot, sharedBinding: .init(native: nativeBinding), nativeRoot: files.bootstrapRoot("photo"))
        inbox = try SharedMediaInboxFiles(root: inboxRoot, binding: .init(native: nativeBinding), nativeRoot: files.bootstrapRoot("inbox"))
        originalIO = SharedMediaNativeOriginalIO(files: photos, binding: nativeBinding, pause: nil)
        #if DEBUG
        debug = grant.debug
        #endif
        try files.check(); try files.bindStore(binding, initializing: false)
        try photos.requireSharedEmptyNamespace(); try inbox.validateInventory([])
        try bootstrap.validateDatabase(profile: profile)
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = inventoryID
        let rows = try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        if rows.isEmpty {
            context.insert(SharedMediaInventoryRecord(id: inventoryID, rootIdentity: rootBinding,
                storeIdentity: storeIdentity, generation: generation, revision: 0,
                modeRaw: SharedMediaNativeAppProfile.mode, phaseRaw: SharedMediaNativeAppProfile.phase, cursor: ""))
            let membership = SharedMediaMembershipBootstrapRecord(inventoryID: inventoryID, inventoryGeneration: generation)
            membership.contractVersion = 2; context.insert(membership)
            try bootstrap.boundary(.beforeSave); try files.check(); try context.save(); try bootstrap.boundary(.afterSave)
        }
        try bootstrap.validateDatabase(profile: profile)
    }
    func appInitializationSnapshot(grant: SharedMediaNativeAppGrant) throws -> SharedMediaStorageSnapshot {
        try grant.validate()
        guard openKind == .appInitialization, expectedOwnerID == grant.ownerID,
              originalWriterEpoch == grant.writerEpoch, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        try files.check(); try files.bindStore(binding, initializing: false); try photos.checkIdentity(); try inbox.check()
        return try SharedMediaNativeBootstrapDatabase.initialSnapshot(container, inventoryID: inventoryID,
            rootBinding: rootBinding, storeIdentity: storeIdentity, generation: generation)
    }

    static func openApp(container: ModelContainer, parent: URL, inventoryID: UUID,
                        grant: SharedMediaNativeAppDispatchGrant) throws -> SharedMediaNativeStorageRepository {
        try grant.validate()
        guard parent == grant.parent, inventoryID == grant.profile.inventoryID else { throw SharedMediaStorageFailure.closed }
        return try .init(existingApp: container, parent: parent, inventoryID: inventoryID, grant: grant)
    }
    private init(existingApp container: ModelContainer, parent: URL, inventoryID: UUID, grant: SharedMediaNativeAppDispatchGrant) throws {
        try grant.validate()
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        self.container = container; self.inventoryID = inventoryID; openKind = .appDispatch
        originals = false; expectedOwnerID = grant.ownerID; originalWriterEpoch = grant.writerEpoch
        let authorityRoot = parent.appendingPathComponent("authority", isDirectory: true)
        let photoRoot = parent.appendingPathComponent("photo", isDirectory: true), inboxRoot = parent.appendingPathComponent("inbox", isDirectory: true)
        scopedRoots = (authorityRoot, photoRoot, inboxRoot)
        sources = [SharedMediaPhotoLedger.namespace: photoRoot, SharedMediaInboxFiles.namespace: inboxRoot]
        storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        let control = SharedMediaNativeBootstrapAuthority(existingParent: parent, inventoryID: inventoryID,
            storeIdentity: storeIdentity, container: container, grant: grant)
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url, sources: sources,
            requireExistingFence: true, bootstrap: control)
        let profile = try files.bootstrapProfile()
        generation = profile.generation; rootBinding = try profile.rootIdentity; binding = try profile.binding
        scopedIdentity = .init(inventoryID: inventoryID, generation: generation, ownerID: grant.ownerID,
            storeIdentity: storeIdentity, rootBinding: rootBinding)
        nativeBinding = .init(bytes: binding, initializing: false, epoch: UUID())
        photos = try PhotoPreparationLockedFiles(root: photoRoot, sharedBinding: .init(native: nativeBinding), nativeRoot: files.bootstrapRoot("photo"))
        inbox = try SharedMediaInboxFiles(root: inboxRoot, binding: .init(native: nativeBinding), nativeRoot: files.bootstrapRoot("inbox"))
        originalIO = SharedMediaNativeOriginalIO(files: photos, binding: nativeBinding, pause: nil)
        #if DEBUG
        debug = grant.debug
        #endif
        try control.validateDatabase(profile: profile); try requireApp(grant)
    }
    private func requireApp(_ grant: SharedMediaNativeAppDispatchGrant) throws {
        try grant.validate()
        try requireAppIdentity(profile: grant.profile, epoch: grant.writerEpoch)
    }
    private func requireAppIdentity(profile: SharedMediaNativeAppProfile, epoch: UUID) throws {
        guard openKind == .appDispatch, expectedOwnerID == profile.ownerID,
              originalWriterEpoch == epoch, let roots = scopedRoots,
              !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        try SharedMediaNativeScopedEligibility.requireRoots(authority: roots.authority, photo: roots.photo, inbox: roots.inbox)
        try files.check(); try files.bindStore(binding, initializing: false); try photos.checkIdentity(); try inbox.check()
        let persisted = try files.bootstrapProfile()
        guard persisted == profile, profile.generation == generation,
              profile.physicalBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else { throw SharedMediaStorageFailure.conflict }
    }
    private func appHeader() throws -> SharedMediaNativeAppEligibility.Header {
        guard let scope = scopedIdentity else { throw SharedMediaStorageFailure.closed }
        let context = ModelContext(container); context.autosaveEnabled = false
        return try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
    }
    func inspectApp(grant: SharedMediaNativeAppDispatchGrant) async throws -> SharedMediaNativeScopedSnapshot {
        try requireApp(grant)
        let expected = try appHeader(), profile = try files.bootstrapProfile()
        let result = try await SharedMediaNativeScopedAudit(app: container, profile: profile, expected: expected.inventory,
            check: {
                try self.requireApp(grant)
                guard try self.appHeader() == expected else { throw SharedMediaStorageFailure.conflict }
            }, betweenPages: {
                #if DEBUG
                await self.debug?.scopedPagePause?()
                #endif
                await Task.yield()
            }).run()
        try requireApp(grant); guard try appHeader() == expected else { throw SharedMediaStorageFailure.conflict }; return result
    }
    func appMetadata(grant: SharedMediaNativeAppDispatchGrant) async throws -> SharedMediaNativeAppMetadataOperations {
        try requireApp(grant)
        let authority = SharedMediaNativeAppOperationAuthority(container: container, profile: grant.profile, writerEpoch: grant.writerEpoch) {
            try self.requireApp(grant); return try self.appHeader()
        }
        return try await .audited(container: container, authority: authority,
            availableBytes: { try self.files.availableBytes() }, boundary: metadataBoundary)
    }
    func appPreparation(grant: SharedMediaNativeAppDispatchGrant) async throws -> SharedMediaNativeAppPreparationOperations {
        try requireApp(grant)
        let authority = SharedMediaNativeAppOperationAuthority(container: container, profile: grant.profile, writerEpoch: grant.writerEpoch) { try self.requireApp(grant); return try self.appHeader() }
        var focus = ImageFocusWorkFactory()
        #if DEBUG
        focus = debug?.preparationFocusFactory ?? focus
        #endif
        return try await .audited(container: container, authority: authority, availableBytes: {
            var bytes = try self.files.availableBytes()
            #if DEBUG
            if let limit = self.debug?.preparationAvailableBytes { bytes = min(bytes, limit) }
            #endif
            return bytes
        }, boundary: { point in
            #if DEBUG
            try self.debug?.preparationFault?(point)
            #endif
        }, io: originalIO, focusFactory: focus, files: photos, binding: nativeBinding, observed: { proof in
            #if DEBUG
            self.debug?.preparationFileEpochObserved?(proof.epoch)
            #endif
        })
    }
    func appPending(grant: SharedMediaNativeAppDispatchGrant) async throws -> SharedMediaNativeAppPendingOperations {
        try requireApp(grant)
        let authority = SharedMediaNativeAppOperationAuthority(container: container, profile: grant.profile, writerEpoch: grant.writerEpoch) { try self.requireApp(grant); return try self.appHeader() }
        return try await .audited(container: container, authority: authority, io: originalIO, binding: nativeBinding, files: photos, boundary: { point in
            #if DEBUG
            try self.debug?.lifecycleFault?(point)
            #endif
        })
    }
    func appReceiving(grant: SharedMediaNativeAppDispatchGrant, lock: SharedMediaNativeReceivingLockGrant) async throws -> SharedMediaNativeAppReceivingOperations {
        try lock.validate(); try requireApp(grant)
        let authority = SharedMediaNativeAppOperationAuthority(container: container, profile: grant.profile, writerEpoch: grant.writerEpoch) { try lock.validate(); try self.requireApp(grant); return try self.appHeader() }
        return try await .audited(container: container, authority: authority, io: originalIO, binding: nativeBinding,
            availableBytes: { try self.files.availableBytes() }, boundary: metadataBoundary,
            verify: { try self.photos.requireCurrentSharedInspection($0) })
    }
    func appAcquisition(grant: SharedMediaNativeAppDispatchGrant, request: SharedMediaAcquisitionIntent?) async throws -> SharedMediaNativeAppAcquisitionOperations {
        try requireApp(grant)
        let authority = SharedMediaNativeAppAcquisitionAuthority(container: container, profile: grant.profile,
            binding: nativeBinding, writerEpoch: grant.writerEpoch) { try self.requireApp(grant); return try self.appHeader() }
        return try await .audited(container: container, authority: authority, io: originalIO, request: request,
            availableBytes: { try self.files.availableBytes() }, boundary: acquisitionBoundary)
    }
    func settleAppOriginal(_ grant: SharedMediaNativeAppSettlementGrant) throws -> SharedMediaAcquisitionResult? {
        try grant.validate(); try requireAppIdentity(profile: grant.ticket.profile, epoch: grant.writerEpoch)
        let authority = SharedMediaNativeAppAcquisitionAuthority(container: container, profile: grant.ticket.profile,
            binding: nativeBinding, writerEpoch: grant.writerEpoch, settlementRequest: grant.ticket.request) {
                try grant.validate(); try self.requireAppIdentity(profile: grant.ticket.profile, epoch: grant.writerEpoch)
                return try self.appHeader()
            }
        return try SharedMediaNativeAppAcquisitionOperations.settle(container: container, authority: authority,
            ticket: grant.ticket, loaderStarted: grant.loaderStarted, boundary: acquisitionBoundary)
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
        let recovery = try await SharedMediaNativeOriginalInspection.run(reader: qualificationOperations(grant: grant).originalReadback(), io: originalIO, authority: authority)
        try authority.validate()
        guard try originalHeader(audit: true) == expected else { throw SharedMediaStorageFailure.conflict }
        return .init(inventory: expected, requiresRecovery: recovery)
    }

    func qualificationOperations(grant: SharedMediaNativeDispatchGrant) throws -> SharedMediaNativeQualificationOperations {
        try requireDispatch(grant)
        let value = try SharedMediaNativeQualificationOperations(container: container, inventoryID: inventoryID,
            authority: dispatchAuthority(grant), io: originalIO, checkDispatch: { try self.requireDispatch(grant) }, availableBytes: { try self.files.availableBytes() },
            verifyProof: { try self.photos.requireCurrentSharedInspection($0) },
            acquisitionBoundary: acquisitionBoundary, metadataBoundary: metadataBoundary)
        #if DEBUG
        return value.withDebug(debug)
        #else
        return value
        #endif
    }
    /// A terminated writer may settle its exact saved receipt after Auth seals
    /// dispatch. This entry has no file operation or fresh reservation path.
    func settleOriginal(_ grant: SharedMediaNativeSettlementGrant) throws -> SharedMediaAcquisitionResult? {
        try requireSettlement(grant)
        let authority = try mutationAuthority { try self.requireSettlement(grant) }
        return try SharedMediaNativeQualificationPersistence.settle(container: container, inventoryID: inventoryID,
            grant: grant, authority: authority, boundary: acquisitionBoundary)
    }

    private func metadataBoundary(_ point: SharedMediaNativeMetadataBoundary) throws {
        #if DEBUG
        try debug?.metadataFault?(point)
        #endif
    }
    private func requireDispatch(_ grant: SharedMediaNativeDispatchGrant) throws {
        try grant.validate()
        guard openKind == .qualificationOriginal, originals, grant.ownerID == expectedOwnerID, grant.writerEpoch == originalWriterEpoch,
              grant.profile == Self.mode else { throw SharedMediaStorageFailure.closed }
    }
    private func requireSettlement(_ grant: SharedMediaNativeSettlementGrant) throws {
        try grant.validate()
        guard openKind == .qualificationOriginal, originals, grant.ownerID == expectedOwnerID, grant.writerEpoch == originalWriterEpoch,
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
    #if DEBUG
    func setAcquisitionEntryPause(_ pause: (@Sendable (SharedMediaNativeOriginalIOEntry) async -> Void)?) async { await originalIO.setAcquisitionEntryPause(pause) }
    #endif
    private func acquisitionBoundary(_ boundary: SharedMediaNativeAcquisitionBoundary) throws {
        #if DEBUG
        try debug?.acquisitionFault?(boundary)
        #endif
    }

    private func requireOriginalHeader(_ expected: SharedMediaStorageSnapshot) throws {
        guard try originalHeader(audit: false) == expected else { throw SharedMediaStorageFailure.conflict }
    }

    private func originalHeader(audit: Bool) throws -> SharedMediaStorageSnapshot {
        guard openKind == .qualificationOriginal, originals, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
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

/// Only the native repository can authorize filesystem bootstrap, after the
/// registered owner has acquired its real account-bound operation.
@MainActor
final class SharedMediaNativeBootstrapAuthority {
    let parent: URL, ownerID: UUID, inventoryID: UUID, storeIdentity: String
    private let container: ModelContainer
    private let grant: SharedMediaNativeAppGrant?
    private let existingGrant: SharedMediaNativeAppDispatchGrant?
    var existingOnly: Bool { existingGrant != nil }
    fileprivate init(parent: URL, inventoryID: UUID, storeIdentity: String,
                     container: ModelContainer, grant: SharedMediaNativeAppGrant) {
        self.parent = parent; self.inventoryID = inventoryID; self.storeIdentity = storeIdentity
        ownerID = grant.ownerID; self.container = container; self.grant = grant; existingGrant = nil
    }
    fileprivate init(existingParent: URL, inventoryID: UUID, storeIdentity: String,
                     container: ModelContainer, grant: SharedMediaNativeAppDispatchGrant) {
        parent = existingParent; self.inventoryID = inventoryID; self.storeIdentity = storeIdentity
        ownerID = grant.ownerID; self.container = container; self.grant = nil; existingGrant = grant
    }
    var availableBytes: Int64? {
        #if DEBUG
        grant?.debug.bootstrapAvailableBytes
        #else
        nil
        #endif
    }
    func validate() throws {
        if let grant { try grant.validate() } else if let existingGrant { try existingGrant.validate() } else { throw SharedMediaStorageFailure.closed }
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
    }
    func boundary(_ value: SharedMediaNativeBootstrapBoundary) throws {
        try validate()
        #if DEBUG
        try grant?.debug.bootstrapFault?(value)
        #endif
    }
    func isCommitted() throws -> Bool {
        try validateDatabase()
        if existingOnly { return true }
        let context = ModelContext(container); context.autosaveEnabled = false
        return try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1
    }
    func requireUnassociatedDatabase() throws {
        try validate(); guard !existingOnly else { throw SharedMediaStorageFailure.closed }
        try SharedMediaNativeBootstrapDatabase.requireUnassociated(container)
        try validate()
    }
    func validateDatabase(profile: SharedMediaNativeAppProfile? = nil) throws {
        try validate()
        try SharedMediaNativeBootstrapDatabase.validate(container, inventoryID: inventoryID,
            ownerID: ownerID, storeIdentity: storeIdentity, existingProfile: existingGrant?.profile,
            expectedProfile: profile)
        try validate()
    }
}

/// Repository-minted operation fence. It exposes only read validation, never a
/// save callback. A typed operation must audit before constructing its witness.
@MainActor
struct SharedMediaNativeAppOperationAuthority {
    let profile: SharedMediaNativeAppProfile
    let writerEpoch: UUID
    private let containerID: ObjectIdentifier
    private let check: () throws -> SharedMediaNativeAppEligibility.Header
    fileprivate init(container: ModelContainer, profile: SharedMediaNativeAppProfile, writerEpoch: UUID,
                     check: @escaping () throws -> SharedMediaNativeAppEligibility.Header) {
        containerID = ObjectIdentifier(container); self.profile = profile; self.writerEpoch = writerEpoch; self.check = check
    }
    func header(_ container: ModelContainer) throws -> SharedMediaNativeAppEligibility.Header {
        guard ObjectIdentifier(container) == containerID else { throw SharedMediaStorageFailure.closed }
        try Task.checkCancellation(); return try check()
    }
}

/// Repository-minted V2 acquisition fence, separate from the V1 mutation grant.
@MainActor
struct SharedMediaNativeAppAcquisitionAuthority {
    let profile: SharedMediaNativeAppProfile
    let binding: SharedMediaNativeBinding
    let writerEpoch: UUID
    let settlementRequest: SharedMediaAcquisitionIntent?
    private let containerID: ObjectIdentifier
    private let check: () throws -> SharedMediaNativeAppEligibility.Header
    fileprivate init(container: ModelContainer, profile: SharedMediaNativeAppProfile, binding: SharedMediaNativeBinding,
                     writerEpoch: UUID, settlementRequest: SharedMediaAcquisitionIntent? = nil,
                     check: @escaping () throws -> SharedMediaNativeAppEligibility.Header) {
        containerID = ObjectIdentifier(container); self.profile = profile; self.binding = binding
        self.writerEpoch = writerEpoch; self.settlementRequest = settlementRequest; self.check = check
    }
    func header(_ container: ModelContainer) throws -> SharedMediaNativeAppEligibility.Header {
        guard ObjectIdentifier(container) == containerID else { throw SharedMediaStorageFailure.closed }
        if settlementRequest == nil { try Task.checkCancellation() }; return try check()
    }
}
