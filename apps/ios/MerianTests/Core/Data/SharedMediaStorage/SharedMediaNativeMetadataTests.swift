import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native draft metadata", .serialized)
@MainActor
struct SharedMediaNativeMetadataTests {
    @Test func exactBytesPresentationAndMembershipSurviveReplayAndReopen() async throws {
        let h = try Harness(); let owner = try await h.open(); let original = try await h.acquire(owner)
        let before = try h.state(), receipt = try h.receiptBytes()
        let request = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "  synthetic \n detail  ")], presentation: [photo(original.referenceID)])
        #expect(try await owner.saveMetadata(request) == before.package + 1)
        let saved = try h.state()
        #expect(saved.envelope == request.envelope && saved.inventory == before.inventory + 1)
        #expect(saved.members == before.members && saved.memberRevision == before.memberRevision)
        #expect(try h.receiptBytes() == receipt)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        #expect(try await owner.saveMetadata(request) == saved.package)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open()
        #expect(try await reopened.saveMetadata(request) == saved.package)
        let next = try await h.edit(reopened, "next")
        #expect(try PhotoPreparationPolicy.decodeDraft(next.envelope).presentation.first?.referenceID == original.referenceID)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativeMetadataBoundary.beforeSave, .afterSave])
    func lostSaveAcknowledgementRecoversOnlyExactUpdate(_ boundary: SharedMediaNativeMetadataBoundary) async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let request = try await h.edit(owner, "saved detail"), before = try h.state()
        try owner.setMetadataFault { if $0 == boundary { throw Fault.injected } }
        if boundary == .beforeSave {
            await #expect(throws: Fault.self) { try await owner.saveMetadata(request) }
            #expect(try h.state() == before)
        } else { #expect(try await owner.saveMetadata(request) == request.packageRevision + 1) }
        try owner.setMetadataFault(nil)
        #expect(try await owner.saveMetadata(request) == request.packageRevision + 1)
        #expect(try h.state().inventory == request.inventoryRevision + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func anotherOriginalPreservesEditedTextAndPresentation() async throws {
        let h = try Harness(); let owner = try await h.open(); let first = try await h.acquire(owner)
        let request = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "retained draft")], presentation: [photo(first.referenceID)])
        _ = try await owner.saveMetadata(request)
        let second = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
        let bytes = h.bytes
        _ = try await owner.acquireOriginal(second) { bytes }
        #expect(try h.state().envelope == request.envelope)
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func unavailableReadbackKeepsExactRequestRecoverableAfterRestart() async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let request = try await h.edit(owner, "uncertain acknowledgement")
        var unavailable = false
        try owner.setMetadataFault {
            if $0 == .afterSave { unavailable = true; throw Fault.injected }
            if $0 == .beforeReadback && unavailable { throw Fault.injected }
        }
        await #expect(throws: Fault.self) { try await owner.saveMetadata(request) }
        #expect(try h.state().envelope == request.envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.saveMetadata(request) == request.packageRevision + 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func laterEditsAreStaleEvenWhenDesiredBytesMatch() async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let first = try await h.edit(owner, "first"), competing = try await h.edit(owner, "competing")
        _ = try await owner.saveMetadata(first)
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(competing) }
        let second = try await h.edit(owner, "second"); _ = try await owner.saveMetadata(second)
        let third = try await h.edit(owner, "first")
        _ = try await owner.saveMetadata(copy(third, envelope: first.envelope))
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(first) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["owner", "inventory", "generation", "draft", "member", "previous", "overflow"])
    func alteredPreconditionsCannotMutate(_ field: String) async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let request = try await h.edit(owner, "new"), before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(copy(request, field: field)) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["foreign", "duplicate", "geometry"])
    func invalidPresentationIsRejectedBeforeMutation(_ kind: String) async throws {
        let h = try Harness(); let owner = try await h.open(); let original = try await h.acquire(owner)
        let before = try h.state()
        let photos = kind == "duplicate" ? [photo(original.referenceID), photo(original.referenceID)]
            : [photo(kind == "foreign" ? UUID() : original.referenceID, scale: kind == "geometry" ? 0 : 1)]
        await #expect(throws: (any Error).self) {
            try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [], presentation: photos)
        }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func liveOriginalFromAnotherPackageCannotSupplyPresentation() async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let other = try await owner.prepareOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        let bytes = h.bytes
        _ = try await owner.acquireOriginal(other) { bytes }
        await #expect(throws: (any Error).self) {
            try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [], presentation: [photo(other.referenceID)])
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func graphAuditRejectsPresentationWhoseOriginalIsNoLongerLive() async throws {
        let h = try Harness(); let owner = try await h.open(); let original = try await h.acquire(owner)
        let request = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [], presentation: [photo(original.referenceID)])
        _ = try await owner.saveMetadata(request)
        let context = ModelContext(h.container)
        let ref = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>()).first)
        ref.isLive = false; try context.save()
        await #expect(throws: (any Error).self) { try await owner.snapshot() }
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(request) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func combinedMetadataBudgetRejectsIndividuallyValidEnvelope() async throws {
        let h = try Harness(); let owner = try await h.open(); let original = try await h.acquire(owner)
        let empty = try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: [photo(original.referenceID, location: "")])
        let fill = Int(PhotoPreparationPolicy.metadata) - 100 - empty.count
        let request = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [], presentation: [photo(original.referenceID, location: String(repeating: "x", count: fill))])
        #expect(request.envelope.count < PhotoPreparationPolicy.metadata)
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(request) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func growthReservesFreeBytesAndShrinkReceivesNoAdvanceCredit() async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let request = try await h.edit(owner, String(repeating: "x", count: 100)), before = try h.state()
        #expect(request.growth > 0)
        try owner.setMetadataFault(nil, availableBytes: SharedMediaStoragePolicy.reserve + request.growth - 1)
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(request) }
        #expect(try h.state() == before)
        try owner.setMetadataFault(nil, availableBytes: SharedMediaStoragePolicy.reserve + request.growth)
        _ = try await owner.saveMetadata(request)
        let shrink = try await h.edit(owner, "")
        #expect(shrink.growth == 0)
        try owner.setMetadataFault(nil, availableBytes: SharedMediaStoragePolicy.reserve - 1)
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(shrink) }
        #expect(try h.state().envelope == request.envelope)
        try owner.setMetadataFault(nil, availableBytes: SharedMediaStoragePolicy.reserve)
        _ = try await owner.saveMetadata(shrink)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["retained", "work", "suspended"])
    func ineligibleOwnerOrPackageCannotEdit(_ kind: String) async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let request = try await h.edit(owner, "denied")
        if kind == "retained" {
            let context = ModelContext(h.container)
            let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
            row.accountingTierRaw = "retained"
            for member in try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { context.delete(member) }
            try context.save()
        } else if kind == "work" {
            let intent = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
            await #expect(throws: (any Error).self) { try await owner.acquireOriginal(intent) { Data() } }
        } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(request) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func beforeSaveRechecksExactRevisionInsteadOfOverwritingNewerState() async throws {
        let h = try Harness(); let owner = try await h.open(); _ = try await h.acquire(owner)
        let request = try await h.edit(owner, "must not overwrite")
        try owner.setMetadataFault { boundary in
            if boundary == .beforeSave {
                let context = ModelContext(h.container)
                let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
                row.revision += 1; try context.save()
            }
        }
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(request) }
        #expect(try h.state().envelope == request.previousEnvelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func multiPageInspectionAuditsWholeGraphOnlyAtItsBoundaries() async throws {
        let h = try Harness(); let owner = try await h.open()
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        for _ in 0..<(SharedMediaStoragePolicy.pageSize * 2 + 1) {
            let row = SharedMediaAcquisitionReceiptRecord(operationID: UUID(), inventoryID: h.inventoryID,
                inventoryGeneration: inventory.generation, ownerID: h.ownerID,
                requestFingerprint: String(repeating: "a", count: 64), packageID: UUID(), assetID: UUID(), requestData: Data())
            row.revision = 2; row.phaseRaw = "terminal"; row.terminalOutcomeRaw = "released"
            row.requestData = nil; row.packageID = nil; row.assetID = nil
            context.insert(row)
        }
        try context.save()
        let before = owner.inspectionAuditCount
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(owner.inspectionAuditCount - before == 2)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private enum Fault: Error { case injected }
    private func copy(_ r: SharedMediaNativeMetadataRequest, field: String = "", envelope: Data? = nil) -> SharedMediaNativeMetadataRequest {
        .init(inventoryID: field == "inventory" ? UUID() : r.inventoryID,
            inventoryGeneration: field == "generation" ? UUID() : r.inventoryGeneration,
            ownerID: field == "owner" ? UUID() : r.ownerID, packageID: r.packageID,
            draftGeneration: field == "draft" ? UUID() : r.draftGeneration,
            inventoryRevision: field == "overflow" ? Int64.max : r.inventoryRevision, packageRevision: r.packageRevision,
            membershipRevision: field == "member" ? r.membershipRevision + 1 : r.membershipRevision,
            membershipBytes: r.membershipBytes, previousEnvelope: field == "previous" ? Data() : r.previousEnvelope,
            envelope: envelope ?? r.envelope)
    }
    private func photo(_ id: UUID, scale: Double = 1, location: String? = nil) -> PhotoPreparationImagePresentation {
        .init(referenceID: id, addedAt: Date(timeIntervalSince1970: 0), isFromGallery: true, cropQuarterTurns: 1,
            cropScale: scale, cropOffsetX: 0, cropOffsetY: 0, focus: nil, latitude: nil, longitude: nil,
            locationName: location, weatherCondition: nil, weatherTemperature: nil, captureDate: nil)
    }

    private struct State: Equatable { let inventory: Int64, package: Int64, memberRevision: Int64?; let members: Data?, envelope: Data }

    @MainActor private struct Harness {
        let base: URL, container: ModelContainer
        let inventoryID = UUID(), ownerID = UUID(), packageID = UUID(), draft = UUID()
        let runtime = AuthRuntimeState()
        let bytes = PhotoPreparationTestHarness.image()
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-metadata-" + UUID().uuidString)
            print("NATIVE_METADATA_FIXTURE " + base.path)
            for name in ["authority", "photo", "inbox", "database"] {
                try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: base.appendingPathComponent("database/ledger.store"), cloudKitDatabase: .none)])
        }
        func open() async throws -> SharedMediaNativeOriginalOwner {
            let owner = try SharedMediaNativeOriginalOwner.qualification(
                account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime), drain: .init())
            _ = try await owner.open(container: container, authorityRoot: base.appendingPathComponent("authority"),
                photoRoot: base.appendingPathComponent("photo"), inboxRoot: base.appendingPathComponent("inbox"), inventoryID: inventoryID)
            return owner
        }
        func acquire(_ owner: SharedMediaNativeOriginalOwner) async throws -> SharedMediaAcquisitionIntent {
            let request = try await owner.prepareOriginal(packageID: packageID, draftGeneration: draft, ordinal: 0, kind: .picker)
            let data = bytes
            _ = try await owner.acquireOriginal(request) { data }
            return request
        }
        func edit(_ owner: SharedMediaNativeOriginalOwner, _ text: String) async throws -> SharedMediaNativeMetadataRequest {
            try await owner.prepareMetadata(packageID: packageID, draftGeneration: draft, contexts: [.init(freeText: text)])
        }
        func file(_ request: SharedMediaAcquisitionIntent) -> URL { base.appendingPathComponent("photo/PhotoPreparation/" + request.finalToken) }
        func receiptBytes() throws -> Data? { try ModelContext(container).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.resultData }
        func state() throws -> State {
            let context = ModelContext(container)
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
            let member = try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first
            return .init(inventory: inventory.revision, package: package.revision, memberRevision: member?.revision, members: member?.membersData, envelope: package.supportingContextData)
        }
        // Only the evidence runner removes these exact emitted paths, after host exit.
    }
}
