import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Shared media durable whole-library purge", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaPurgeTests {
    enum Fault: Error { case injected }

    @Test(arguments: [false, true])
    func readyAndFrozenPackagesCloseWithoutReopening(_ frozen: Bool) async throws {
        let h = try Harness(); defer { h.cleanup() }
        var owner: SharedMediaInboxOwner? = try h.owner()
        let original = try await h.original(owner!)
        _ = try await h.pair(owner!, original)
        if frozen {
            let request = try await owner!.prepareFreeze(h.snapshot(owner!, [original]), account: h.account)
            _ = try await owner!.freeze(request, account: h.account)
        }
        owner!.setHandoffAvailableBytes(0)
        let id = UUID()
        var completion: SharedMediaPurgeCompletion? = try await owner!.purgeWholeLibrary(resetID: id)
        try completion!.validate(in: ModelContext(h.container))
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: ModelContext(h.container)))
        #expect(try h.inventoryRow().phaseRaw == "purgedP1")
        #expect(FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").path))
        let bytes = PhotoPreparationTestHarness.image()
        await #expect(throws: (any Error).self) { _ = try await owner!.stage { bytes } }
        _ = try await owner!.purgeWholeLibrary(resetID: id)
        completion = nil; owner = nil
        #expect(throws: (any Error).self) { _ = try h.owner() }
        #expect(throws: (any Error).self) { _ = try h.resume(UUID()) }
        let resumed = try h.resume(id)
        try await resumed.purgeWholeLibrary(resetID: id).validate(in: ModelContext(h.container))
    }

    @Test(arguments: [SharedMediaPurgeBoundary.beforeDrainSave, .beforeRetirementSave,
                       .afterRetirementSave, .beforeReleaseSave, .afterReleaseSave, .beforeTerminalSave])
    func persistedPurgeResumesAfterSaveInterruption(_ boundary: SharedMediaPurgeBoundary) async throws {
        let h = try Harness(); defer { h.cleanup() }
        var owner: SharedMediaInboxOwner? = try h.owner()
        _ = try await h.original(owner!)
        let id = UUID()
        owner!.setPurgeFault { if $0 == boundary { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner!.purgeWholeLibrary(resetID: id) }
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: ModelContext(h.container)))
        owner = nil
        #expect(throws: (any Error).self) { _ = try h.owner() }
        let resumed = try h.resume(id)
        try await resumed.purgeWholeLibrary(resetID: id).validate(in: ModelContext(h.container))
    }

    @Test(arguments: [SharedMediaPurgeBoundary.afterIntentSave, .afterDrainSave, .afterTerminalSave])
    func exactLostAcknowledgementDoesNotRepeatMediaWork(_ boundary: SharedMediaPurgeBoundary) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(); _ = try await h.original(owner)
        owner.setPurgeFault { if $0 == boundary { throw Fault.injected } }
        try await owner.purgeWholeLibrary(resetID: UUID()).validate(in: ModelContext(h.container))
    }

    @Test(arguments: [SharedMediaPhotoReleaseBoundary.afterUnlink, .beforeSync, .afterSync])
    func originalAbsenceRequiresSavedRetirement(_ point: SharedMediaPhotoReleaseBoundary) async throws {
        let h = try Harness(); defer { h.cleanup() }
        var owner: SharedMediaInboxOwner? = try h.owner(); _ = try await h.original(owner!)
        let id = UUID()
        await owner!.setPurgeReleaseFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner!.purgeWholeLibrary(resetID: id) }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        owner = nil
        let resumed = try h.resume(id)
        try await resumed.purgeWholeLibrary(resetID: id).validate(in: ModelContext(h.container))
    }

    @Test(arguments: ["missing", "substitution", "directory"])
    func unexplainedIdentityLossBlocksAndRetainsAuthority(_ kind: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(); _ = try await h.original(owner)
        let context = ModelContext(h.container), asset = try #require(context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        let url = h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(asset.fileToken)
        if kind == "directory" {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("retained"))
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        } else {
            try FileManager.default.removeItem(at: url)
            if kind == "substitution" { try PhotoPreparationTestHarness.image().write(to: url) }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.purgeWholeLibrary(resetID: UUID()) }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try h.inventoryRow().phaseRaw == "purgingP1")
    }

    @Test(arguments: [false, true])
    func missingSourceOrDerivativeWithoutRetirementRemainsCharged(_ derivative: Bool) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        if derivative {
            let original = try await h.original(owner)
            _ = try await h.pair(owner, original)
            let context = ModelContext(h.container)
            let reference = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>()).first { $0.roleRaw == "aiInput" })
            let asset = try #require(context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first { $0.id == reference.assetID })
            try FileManager.default.removeItem(at: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(asset.fileToken))
        } else {
            _ = try await owner.stage { data }
            let row = try #require(ModelContext(h.container).fetch(FetchDescriptor<SharedMediaInboxSourceRecord>()).first)
            try FileManager.default.removeItem(at: h.inbox.appendingPathComponent("InboxSources").appendingPathComponent(row.finalToken))
        }
        await #expect(throws: (any Error).self) { _ = try await owner.purgeWholeLibrary(resetID: UUID()) }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) > 0)
        #expect(try h.inventoryRow().phaseRaw == "purgingP1")
    }

    @Test(arguments: [false, true])
    func attachedHandoffAndAccountlessSourcesAreReleased(_ incomplete: Bool) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { data }
        _ = try await owner.stage { data }
        let request = try owner.prepareHandoff(source, account: h.account, packageID: UUID(), draftGeneration: UUID())
        if incomplete { await owner.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } } }
        if incomplete { await #expect(throws: (any Error).self) { _ = try await owner.handoff(request, account: h.account) } }
        else { _ = try await owner.handoff(request, account: h.account) }
        await owner.setHandoffFileFault(nil)
        owner.setHandoffAvailableBytes(0)
        try await owner.purgeWholeLibrary(resetID: UUID()).validate(in: ModelContext(h.container))
    }

    @Test func committedSourceRetirementResumesBeforeDestinationCleanup() async throws {
        let h = try Harness(); defer { h.cleanup() }
        var owner: SharedMediaInboxOwner? = try h.owner()
        let data = PhotoPreparationTestHarness.image(), source = try await owner!.stage { data }
        let request = try owner!.prepareHandoff(source, account: h.account, packageID: UUID(), draftGeneration: UUID())
        _ = try await owner!.handoff(request, account: h.account)
        await owner!.setFileFault { if $0 == .afterFinalUnlink { throw Fault.injected } }
        await #expect(throws: (any Error).self) { try await owner!.retireHandoffSource(request, account: h.account) }
        owner = nil
        let reopened = try h.owner()
        try await reopened.purgeWholeLibrary(resetID: UUID()).validate(in: ModelContext(h.container))
    }

    @Test func saturatedSourcesAndDetachedDestinationReleaseBeforeAbandonment() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner()
        var data = PhotoPreparationTestHarness.image()
        data.append(Data(count: 16 * 1024 * 1024 - data.count))
        let bytes = data
        let first = try await owner.stage(maximumBytes: 16 * 1024 * 1024) { bytes }
        let detached = try owner.prepareHandoff(first, account: h.account, packageID: UUID(), draftGeneration: UUID())
        await owner.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(detached, account: h.account) }
        await owner.setHandoffFileFault(nil)
        try await owner.abandonHandoff(detached)
        let second = try await owner.stage(maximumBytes: 16 * 1024 * 1024) { bytes }
        _ = try await owner.stage(maximumBytes: 16 * 1024 * 1024) { bytes }
        let attached = try owner.prepareHandoff(second, account: h.account, packageID: UUID(), draftGeneration: UUID())
        await owner.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(attached, account: h.account) }
        await owner.setHandoffFileFault(nil)
        // S48 + H32 + A16 = 96 MiB before reclamation. No new free space.
        owner.setHandoffAvailableBytes(0)
        try await owner.purgeWholeLibrary(resetID: UUID()).validate(in: ModelContext(h.container))
    }

    @Test func sharedOriginalIsUnlinkedOnlyAfterLastReference() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(), original = try await h.original(owner)
        // Construct a valid existing second reference, without another copy.
        let context = ModelContext(h.container)
        let asset = try #require(context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        let package = UUID(), reference = UUID()
        context.insert(PhotoPreparationRecord(id: package, ownerID: original.ownerID,
            contractVersion: PhotoPreparationPolicy.contract, draftID: package, draftGeneration: UUID(), revision: 0,
            phaseRaw: "draftOwned", supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []),
            allocatedByteCount: asset.byteCount, retirementRequested: false))
        context.insert(PhotoPreparationReference(id: reference, packageID: package, assetID: asset.id,
            ownerID: original.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: reference, allocationID: asset.id, accountID: original.ownerID,
            ownerID: reference.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        try context.save()
        var retiredReferences = 0
        owner.setPurgeFault { boundary in
            if boundary == .afterRetirementSave {
                retiredReferences += 1
                if retiredReferences == 1 {
                    let fresh = ModelContext(h.container)
                    let referenceCount = try fresh.fetchCount(FetchDescriptor<PhotoPreparationReference>())
                    #expect(referenceCount == 1)
                    #expect(FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(asset.fileToken).path))
                }
            }
        }
        try await owner.purgeWholeLibrary(resetID: UUID()).validate(in: ModelContext(h.container))
        #expect(retiredReferences == 2)
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.beforeReservationSave, .duringWrite, .afterRename])
    func partialDerivativePairIsRetiredWithoutReprocessing(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(), original = try await h.original(owner), data = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareDerivatives(original, ai: data, display: data, account: h.account)
        owner.setHandoffFault { if $0 == point { throw Fault.injected } }
        await owner.setHandoffFileFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        owner.setHandoffFault(nil); await owner.setHandoffFileFault(nil)
        try await owner.purgeWholeLibrary(resetID: UUID()).validate(in: ModelContext(h.container))
    }

    @Test func lateLoadMustActuallyExitBeforePurgeCompletes() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(), gate = Gate(), data = PhotoPreparationTestHarness.image()
        let staging = Task { try await owner.stage { await gate.wait(); return data } }
        await gate.started()
        var callback = false
        let purge = Task { try await owner.purgeWholeLibrary(resetID: UUID()) { callback = true } }
        while try h.inventoryRow().phaseRaw == "readyP1" { await Task.yield() }
        #expect(!callback)
        await #expect(throws: (any Error).self) { _ = try await owner.stage { data } }
        await gate.release()
        _ = await staging.result
        try await purge.value.validate(in: ModelContext(h.container))
        #expect(callback)
    }

    @Test func completionCannotCrossContainersOrHideNewRows() async throws {
        let h = try Harness(), other = try Harness(); defer { h.cleanup(); other.cleanup() }
        let owner = try h.owner(), completion = try await owner.purgeWholeLibrary(resetID: UUID())
        #expect(throws: (any Error).self) { try completion.validate(in: ModelContext(other.container)) }
        let dirty = ModelContext(h.container)
        dirty.insert(OfflineJobRecord(id: "synthetic-uncommitted", kind: .scanIngestion))
        #expect(throws: (any Error).self) { try completion.validate(in: dirty) }
        dirty.rollback()
        try completion.validate(in: dirty)
    }

    @Test func serviceRejectsWrongTargetBeforeClosingOrDeletingEitherStore() async throws {
        let h = try Harness(), other = try Harness(); defer { h.cleanup(); other.cleanup() }
        let owner = try h.owner(), otherOwner = try other.owner()
        let original = try await h.original(owner), otherOriginal = try await other.original(otherOwner)
        let name = "shared-purge-mismatch-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        var callbacks = 0
        #expect(!(await ScanLibraryPurgeService.purge(modelContext: ModelContext(other.container), userDefaults: defaults,
            resetRuntimeState: { callbacks += 1 }, sharedMedia: .init(owner: owner, resetID: UUID()),
            erasePhotoPreparation: { callbacks += 1 }, eraseReanalysis: { callbacks += 1 })))
        #expect(callbacks == 0)
        #expect(try h.inventoryRow().phaseRaw == "readyP1")
        #expect(try other.inventoryRow().phaseRaw == "readyP1")
        #expect(try await owner.destinationOriginalData(original, account: h.account) == PhotoPreparationTestHarness.image())
        #expect(try await otherOwner.destinationOriginalData(otherOriginal, account: other.account) == PhotoPreparationTestHarness.image())
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.stage { bytes }; _ = try await otherOwner.stage { bytes }
    }

    @Test func serviceFailureRetainsPreferencesAndDefersCallbacks() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(); _ = try await h.original(owner)
        let name = "shared-purge-" + UUID().uuidString, id = UUID()
        let defaults = try #require(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        var reset = false, reanalysis = false
        owner.setPurgeFault { if $0 == .beforeRetirementSave { throw Fault.injected } }
        #expect(!(await ScanLibraryPurgeService.purge(modelContext: ModelContext(h.container), userDefaults: defaults,
            resetRuntimeState: { reset = true }, sharedMedia: .init(owner: owner, resetID: id), eraseReanalysis: { reanalysis = true })))
        #expect(!reset && !reanalysis)
        owner.setPurgeFault(nil)
        #expect(await ScanLibraryPurgeService.purge(modelContext: ModelContext(h.container), userDefaults: defaults,
            resetRuntimeState: { reset = true }, sharedMedia: .init(owner: owner, resetID: id), eraseReanalysis: { reanalysis = true }))
        #expect(reset && reanalysis)
        #expect(try h.inventoryRow().phaseRaw == "purgedP1")
    }

    actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func started() async { while continuation == nil { await Task.yield() } }
        func release() { continuation?.resume(); continuation = nil }
    }
    @MainActor private struct Harness {
        let authority: URL, inbox: URL, photo: URL
        let container: ModelContainer
        let inventory = UUID(), accountID = UUID(), runtime = AuthRuntimeState()
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime) }
        init() throws {
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("shared-purge-" + UUID().uuidString)
            authority = root.appendingPathComponent("authority"); inbox = root.appendingPathComponent("inbox"); photo = root.appendingPathComponent("photo")
            let database = root.appendingPathComponent("database")
            for url in [authority, inbox, photo, database] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner() throws -> SharedMediaInboxOwner { try .init(container: container, authorityRoot: authority, inboxRoot: inbox, photoRoot: photo, inventoryID: inventory) }
        func cleanup() {
            for root in [authority, inbox, photo] { try? FileManager.default.removeItem(at: root) }
            // Core Data may retain SQLite/WAL handles beyond container release.
            // Preserve this unique database root through test-process exit.
        }
        func resume(_ id: UUID) throws -> SharedMediaInboxOwner {
            try .resumePurge(id: id, container: container, authorityRoot: authority, inboxRoot: inbox, photoRoot: photo, inventoryID: inventory)
        }
        func inventoryRow() throws -> SharedMediaInventoryRecord {
            try #require(ModelContext(container).fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        }
        func draft(_ owner: SharedMediaInboxOwner, _ id: UUID) async throws -> PhotoPreparationDraft {
            try #require(try await owner.draftCatalog(account: account).first { $0.packageID == id })
        }
        func snapshot(_ owner: SharedMediaInboxOwner, _ originals: [PhotoOriginalReference]) async throws -> PhotoPreparationSnapshot {
            let draft = try await draft(owner, originals[0].packageID)
            return .init(originals: originals, expectedPackageRevision: draft.revision, supportingContexts: draft.contexts)
        }
        func original(_ owner: SharedMediaInboxOwner, package: PhotoOriginalReference? = nil) async throws -> PhotoOriginalReference {
            let data = PhotoPreparationTestHarness.image(), source = try await owner.stage { data }
            let request = try owner.prepareHandoff(source, account: account, packageID: package?.packageID ?? UUID(), draftGeneration: package?.draftGeneration ?? UUID(), ordinal: package == nil ? 0 : 1)
            let result = try await owner.handoff(request, account: account)
            try await owner.retireHandoffSource(request, account: account); return result
        }
        func pair(_ owner: SharedMediaInboxOwner, _ original: PhotoOriginalReference) async throws -> SharedMediaDerivativeRequest {
            let data = PhotoPreparationTestHarness.image()
            let request = try await owner.prepareDerivatives(original, ai: data, display: data, account: account)
            _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: account); return request
        }
    }
}
