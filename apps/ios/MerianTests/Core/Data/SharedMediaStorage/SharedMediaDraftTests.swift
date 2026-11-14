import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Shared draft metadata and local freeze", .serialized)
@MainActor
struct SharedMediaDraftTests {
    enum Fault: Error { case injected }

    @Test func metadataPreservesPresentationAndExactContexts() async throws {
        let h = try Harness(), owner = try h.owner(), original = try await h.original(owner)
        let before = try await h.draft(owner, original.packageID)
        let detail = ObservationContext(freeText: "  Keep these words exactly.  ")
        let revision = try await owner.saveDraftMetadata(packageID: original.packageID, revision: before.revision,
            contexts: [detail], presentation: [photo(original.referenceID)], account: h.account)
        _ = try await owner.saveDraftMetadata(packageID: original.packageID, revision: revision, contexts: [], account: h.account)
        let draft = try await h.draft(owner, original.packageID)
        #expect(draft.contexts.isEmpty && draft.presentation.count == 1 && draft.presentation[0].referenceID == original.referenceID)
        await #expect(throws: (any Error).self) { _ = try await owner.saveDraftMetadata(packageID: original.packageID, revision: revision, contexts: [detail], account: h.account) }
        await #expect(throws: (any Error).self) { _ = try await owner.saveDraftMetadata(packageID: original.packageID, revision: draft.revision, contexts: [], presentation: [photo(UUID())], account: h.account) }
        await #expect(throws: (any Error).self) { _ = try await owner.saveDraftMetadata(packageID: original.packageID, revision: draft.revision, contexts: [ObservationContext(freeText: String(repeating: "x", count: 8193))], account: h.account) }
        #expect(try await h.draft(owner, original.packageID).revision == draft.revision)
    }

    @Test func metadataGrowthNeedsActualFreeHeadroomButShrinkDoesNot() async throws {
        let h = try Harness(), owner = try h.owner(), original = try await h.original(owner)
        let before = try await h.draft(owner, original.packageID)
        owner.setHandoffAvailableBytes(SharedMediaStoragePolicy.reserve)
        await #expect(throws: (any Error).self) { _ = try await owner.saveDraftMetadata(packageID: original.packageID, revision: before.revision,
            contexts: [ObservationContext(freeText: String(repeating: "x", count: 2048))], account: h.account) }
        #expect(try await h.draft(owner, original.packageID).revision == before.revision)
        owner.setHandoffAvailableBytes(SharedMediaStoragePolicy.reserve + 8192)
        let updated = try await owner.saveDraftMetadata(packageID: original.packageID, revision: before.revision,
            contexts: [ObservationContext(freeText: String(repeating: "x", count: 2048))], account: h.account)
        owner.setHandoffAvailableBytes(0)
        #expect(try await owner.saveDraftMetadata(packageID: original.packageID, revision: updated, contexts: [], account: h.account) == updated + 1)
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterMetadataSave, .afterFreezeSave])
    func lostAcknowledgementRecoversOnlyExactSavedResult(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), original = try await h.original(owner)
        _ = try await h.pair(owner, original)
        owner.setHandoffFault { if $0 == point { throw Fault.injected } }
        let before = try await h.draft(owner, original.packageID)
        let revision = try await owner.saveDraftMetadata(packageID: original.packageID, revision: before.revision, contexts: [], account: h.account)
        let request = try await owner.prepareFreeze(.init(originals: [original], expectedPackageRevision: revision, supportingContexts: []), account: h.account)
        let receipt = try await owner.freeze(request, account: h.account)
        #expect(receipt.revision == revision + 1)
        #expect(try await owner.freeze(request, account: h.account) == receipt)
    }

    @Test func frozenPackageReopensWithRetainedRequestAndRejectsMutations() async throws {
        let h = try Harness()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let original = try await h.original(owner!), pair = try await h.pair(owner!, original)
        let snapshot = try await h.snapshot(owner!, [original])
        let request = try await owner!.prepareFreeze(snapshot, account: h.account)
        let receipt = try await owner!.freeze(request, account: h.account)
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.freeze(request, account: h.account) == receipt)
        await #expect(throws: (any Error).self) { _ = try await reopened.prepareFreeze(snapshot, account: h.account) }
        await #expect(throws: (any Error).self) { _ = try await reopened.saveDraftMetadata(packageID: original.packageID, revision: receipt.revision, contexts: [], account: h.account) }
        let data = PhotoPreparationTestHarness.image()
        await #expect(throws: (any Error).self) { _ = try await reopened.prepareDerivatives(original, ai: data, display: data, account: h.account) }
        await #expect(throws: (any Error).self) { try await reopened.discardDerivatives(pair, account: h.account) }
        let source = try await reopened.stage { data }
        let handoff = try reopened.prepareHandoff(source, account: h.account, packageID: original.packageID, draftGeneration: original.draftGeneration, ordinal: 1)
        await #expect(throws: (any Error).self) { _ = try await reopened.handoff(handoff, account: h.account) }
        #expect(try await h.draft(reopened, original.packageID).phase == "preparedHeld")
        #expect(try await reopened.destinationOriginalData(original, account: h.account) == data)
    }

    @Test func recoveryComparesEntireEnvelopeNotJustContexts() async throws {
        let h = try Harness(), owner = try h.owner(), original = try await h.original(owner)
        _ = try await h.pair(owner, original)
        let draft = try await h.draft(owner, original.packageID)
        _ = try await owner.saveDraftMetadata(packageID: original.packageID, revision: draft.revision,
            contexts: [], presentation: [photo(original.referenceID)], account: h.account)
        let request = try await owner.prepareFreeze(h.snapshot(owner, [original]), account: h.account)
        _ = try await owner.freeze(request, account: h.account)
        let changed = SharedMediaFreezeRequest(inventoryID: request.inventoryID, inventoryGeneration: request.inventoryGeneration,
            snapshot: request.snapshot, envelope: try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: [photo(original.referenceID, scale: 2)]),
            files: request.files, identities: request.identities)
        await #expect(throws: (any Error).self) { _ = try await owner.freeze(changed, account: h.account) }
        #expect(try await owner.freeze(request, account: h.account).revision == request.snapshot.expectedPackageRevision + 1)
    }

    @Test(arguments: [false, true])
    func accountLossAfterFreezeSaveCannotReturnReceipt(_ lostAck: Bool) async throws {
        let h = try Harness(), owner = try h.owner(), original = try await h.original(owner)
        _ = try await h.pair(owner, original)
        let base = h.account
        var current = true
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: base.ownerID, begin: base.begin,
            isCurrent: { current && base.isCurrent($0) }, finish: base.finish)
        let request = try await owner.prepareFreeze(h.snapshot(owner, [original]), account: account)
        owner.setHandoffFault { if $0 == .afterFreezeSave { current = false; if lostAck { throw Fault.injected } } }
        await #expect(throws: PhotoPreparationFailure.accountChanged) { _ = try await owner.freeze(request, account: account) }
        #expect(try await h.draft(owner, original.packageID).phase == "preparedHeld")
        owner.setHandoffFault(nil)
        #expect(try await owner.freeze(request, account: h.account).revision == request.snapshot.expectedPackageRevision + 1)
    }

    @Test(arguments: ["missing", "substituted"])
    func changedFilePreventsFreezeAndDoesNotCreateReceipt(_ kind: String) async throws {
        let h = try Harness(), owner = try h.owner(), original = try await h.original(owner)
        _ = try await h.pair(owner, original)
        let request = try await owner.prepareFreeze(h.snapshot(owner, [original]), account: h.account)
        let path = h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(request.files[1].token)
        try FileManager.default.removeItem(at: path)
        if kind == "substituted" { try PhotoPreparationTestHarness.image().write(to: path) }
        await #expect(throws: (any Error).self) { _ = try await owner.freeze(request, account: h.account) }
        #expect(try await h.draft(owner, original.packageID).phase == "draftOwned")
    }

    @Test func targetPackageReadinessDoesNotRequireUnrelatedPairCompletion() async throws {
        let h = try Harness(), owner = try h.owner(), first = try await h.original(owner)
        _ = try await h.pair(owner, first)
        let second = try await h.original(owner)
        let data = PhotoPreparationTestHarness.image()
        let next = try await owner.prepareDerivatives(second, ai: data, display: data, account: h.account)
        owner.setHandoffFault { if $0 == .beforeReservationSave { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(next, ai: data, display: data, account: h.account) }
        owner.setHandoffFault(nil)
        let request = try await owner.prepareFreeze(h.snapshot(owner, [first]), account: h.account)
        _ = try await owner.freeze(request, account: h.account)
        await #expect(throws: (any Error).self) { _ = try await owner.prepareFreeze(h.snapshot(owner, [second]), account: h.account) }
    }

    @Test func orderedOriginalsAndSupportingContextsMustMatch() async throws {
        let h = try Harness(), owner = try h.owner(), first = try await h.original(owner)
        let second = try await h.original(owner, package: first)
        _ = try await h.pair(owner, first); _ = try await h.pair(owner, second)
        let snapshot = try await h.snapshot(owner, [first, second])
        await #expect(throws: (any Error).self) { _ = try await owner.prepareFreeze(.init(originals: [second, first], expectedPackageRevision: snapshot.expectedPackageRevision, supportingContexts: []), account: h.account) }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareFreeze(.init(originals: [first, second], expectedPackageRevision: snapshot.expectedPackageRevision, supportingContexts: [ObservationContext(freeText: "Changed")]), account: h.account) }
        let request = try await owner.prepareFreeze(snapshot, account: h.account)
        #expect(request.files.count == 6)
        _ = try await owner.freeze(request, account: h.account)
    }

    private func photo(_ id: UUID, scale: Double = 1) -> PhotoPreparationImagePresentation {
        .init(referenceID: id, addedAt: Date(timeIntervalSince1970: 1), isFromGallery: true,
              cropQuarterTurns: 0, cropScale: scale, cropOffsetX: 0, cropOffsetY: 0, focus: nil,
              latitude: nil, longitude: nil, locationName: nil, weatherCondition: nil, weatherTemperature: nil, captureDate: nil)
    }

    @MainActor private struct Harness {
        let authority: URL, inbox: URL, photo: URL
        let container: ModelContainer
        let inventory = UUID(), accountID = UUID(), runtime = AuthRuntimeState()
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime) }
        init() throws {
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("shared-draft-" + UUID().uuidString)
            authority = root.appendingPathComponent("authority"); inbox = root.appendingPathComponent("inbox"); photo = root.appendingPathComponent("photo")
            let database = root.appendingPathComponent("database")
            for url in [authority, inbox, photo, database] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner() throws -> SharedMediaInboxOwner { try .init(container: container, authorityRoot: authority, inboxRoot: inbox, photoRoot: photo, inventoryID: inventory) }
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
