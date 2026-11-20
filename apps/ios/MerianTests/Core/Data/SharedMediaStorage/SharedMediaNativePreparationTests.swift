import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native preparation reservations", .serialized)
@MainActor
struct SharedMediaNativePreparationTests {
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test func reservationSurvivesReopenAndRequiresExplicitAbandonment() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let before = try h.state(), originalBytes = try Data(contentsOf: h.file(original))
        #expect(try SharedMediaNativeDraftEnvelope.decode(before.envelope).sequence == 0)
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(try h.state() == before) // Inspection never converts V1.
        let attempt = try await owner.reservePreparation(original: original, recipe: Self.recipe)
        #expect(attempt.sequence == 1 && attempt.previousEnvelope == before.envelope)
        let saved = try h.state()
        #expect(saved.phase == "preparing" && saved.members == before.members && saved.memberRevision == before.memberRevision)
        #expect(throws: (any Error).self) { try PhotoPreparationPolicy.decodeDraft(saved.envelope) }
        #expect(try await owner.snapshot().requiresRecovery)
        await #expect(throws: (any Error).self) { try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: []) }
        await #expect(throws: (any Error).self) { try await owner.reservePreparation(original: original, recipe: Self.recipe) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.activePreparation(packageID: h.packageID) == attempt)
        #expect(try h.state() == saved)
        try await cold.abandonPreparation(attempt)
        #expect(!(try await cold.snapshot().requiresRecovery))
        let abandoned = try h.state()
        #expect(abandoned.phase == "draftOwned" && abandoned.members == before.members)
        #expect(try SharedMediaNativeDraftEnvelope.decode(abandoned.envelope).sequence == 1)
        #expect(try Data(contentsOf: h.file(original)) == originalBytes)
        let next = try await cold.reservePreparation(original: original, recipe: Self.recipe)
        #expect(next.sequence == 2 && next.operationID != attempt.operationID)
        await #expect(throws: (any Error).self) { try await cold.abandonPreparation(attempt) }
        #expect(try await cold.activePreparation(packageID: h.packageID) == next)
        try await cold.abandonPreparation(next)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforeSave, .afterSave])
    func exactReservationAndAbandonmentAcknowledgement(_ boundary: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let before = try h.state()
        try owner.setPreparationFault { if $0 == boundary { throw Fault.injected } }
        if boundary == .beforeSave {
            await #expect(throws: Fault.self) { try await owner.reservePreparation(original: original, recipe: Self.recipe) }
            #expect(try h.state() == before)
        } else {
            let attempt = try await owner.reservePreparation(original: original, recipe: Self.recipe)
            #expect(try await owner.activePreparation(packageID: h.packageID) == attempt)
        }
        try owner.setPreparationFault(nil)
        let pending = try await owner.activePreparation(packageID: h.packageID)
        let attempt: SharedMediaNativePreparationAttempt
        if let pending { attempt = pending } else { attempt = try await owner.reservePreparation(original: original, recipe: Self.recipe) }
        let reserved = try h.state()
        try owner.setPreparationFault { if $0 == boundary { throw Fault.injected } }
        if boundary == .beforeSave {
            await #expect(throws: Fault.self) { try await owner.abandonPreparation(attempt) }
            #expect(try h.state() == reserved)
            try owner.setPreparationFault(nil)
            try await owner.abandonPreparation(attempt)
        } else { try await owner.abandonPreparation(attempt) }
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func unavailableAcknowledgementRecoversSavedAttemptWithoutReservingAgain() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        var unavailable = false
        try owner.setPreparationFault {
            if $0 == .afterSave { unavailable = true; throw Fault.injected }
            if unavailable && $0 == .beforeReadback { throw Fault.injected }
        }
        await #expect(throws: Fault.self) { try await owner.reservePreparation(original: original, recipe: Self.recipe) }
        let saved = try h.state()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open(), attempt = try #require(try await cold.activePreparation(packageID: h.packageID))
        #expect(attempt.sequence == 1)
        #expect(try h.state() == saved)
        try await cold.abandonPreparation(attempt)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func mutableV2PreservesSequenceThroughMetadataAcquisitionSharingAndRemoval() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let attempt = try await owner.reservePreparation(original: original, recipe: Self.recipe)
        try await owner.abandonPreparation(attempt)
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [.init(freeText: "  retained detail  ")])
        _ = try await owner.saveMetadata(edit)
        #expect(try SharedMediaNativeDraftEnvelope.decode(edit.envelope).sequence == 1)
        let extra = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
        let bytes = h.bytes
        _ = try await owner.acquireOriginal(extra) { bytes }
        #expect(try h.state().envelope == edit.envelope)
        let share = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.share(share)
        let context = ModelContext(h.container), destinationID = destination.packageID
        let destinationRow = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == destinationID })).first)
        #expect(try PhotoPreparationPolicy.decodeDraft(destinationRow.supportingContextData).version == 1)
        let removal = try await owner.prepareRemoval(original)
        try await owner.remove(removal)
        let after = try SharedMediaNativeDraftEnvelope.decode(h.state().envelope)
        #expect(after.sequence == 1 && after.contexts.first?.freeText == "  retained detail  ")
        #expect(try Data(contentsOf: h.file(original)) == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func capacityDenialPreservesV1AndDoesNotConsumeSequence() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let before = try h.state()
        try owner.setPreparationFault(nil, availableBytes: SharedMediaStoragePolicy.reserve)
        await #expect(throws: SharedMediaStorageFailure.capacity) { try await owner.reservePreparation(original: original, recipe: Self.recipe) }
        #expect(try h.state() == before)
        #expect(try await owner.activePreparation(packageID: h.packageID) == nil)
        try owner.setPreparationFault(nil)
        let attempt = try await owner.reservePreparation(original: original, recipe: Self.recipe)
        #expect(attempt.sequence == 1)
        try await owner.abandonPreparation(attempt)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func reservationChargesOutputAndFullMetadataHeadroomExactlyOnce() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let attempt = try await owner.reservePreparation(original: original, recipe: Self.recipe)
        let context = ModelContext(h.container)
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        #expect(budget.metadataByPackage[h.packageID] == PhotoPreparationPolicy.metadata)
        // Find the exact outstanding reservation using the accounting API;
        // available bytes already exclude the saved envelope and original.
        let actual = try h.state().envelope.count
        let receipt = try #require(context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw Fault.injected }
        let metadata = Int64(actual + (try h.state().members.count)) + (try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result))
        let required = SharedMediaStoragePolicy.reserve + attempt.outputReservation + PhotoPreparationPolicy.metadata - metadata
        #expect(throws: SharedMediaStorageFailure.capacity) { try budget.totals.checkAvailable(required - 1) }
        try budget.totals.checkAvailable(required)
        try await owner.abandonPreparation(attempt)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func concretePhotoProcessorPreservesOriginalAndCannotReplayPendingAttempt(cropped: Bool) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let originalBytes = try Data(contentsOf: h.file(original))
        let recipe = cropped ? SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
            cropDisplaySize: 200, quarterTurns: 1, scale: 1.5, offsetX: 0, offsetY: 0) : Self.recipe
        let output = try await owner.qualifyPhotoPreparation(original: original, recipe: recipe)
        #expect(output.attempt.recipe == recipe)
        try output.intent.preparation.requireMatch(output.attempt)
        try SharedMediaDerivativeWorkFiles.validate(output.ai, input: output.intent.ai)
        try SharedMediaDerivativeWorkFiles.validate(output.display, input: output.intent.display)
        #expect(try Data(contentsOf: h.file(original)) == originalBytes)
        #expect(try await owner.activePreparation(packageID: h.packageID) == output.attempt)
        await #expect(throws: (any Error).self) { try await owner.qualifyPhotoPreparation(original: original, recipe: recipe) }
        // No output files or pair rows are admitted by this qualification seam.
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.file(original).deletingLastPathComponent().path).count == 1)
        try await owner.abandonPreparation(output.attempt)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountTransitionRetainsOwnershipUntilFocusWorkerExits() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let started = ImageFocusEngineTests.Signal(), registered = ImageFocusEngineTests.Signal()
        let invalidated = ImageFocusEngineTests.Signal(), release = DispatchSemaphore(value: 0)
        let worker = ImageFocusWorkerState.qualification(worker: {
            Task { await started.open() }; release.wait(); return .noCandidates
        }, drainRegistered: { Task { await registered.open() } })
        defer { release.signal() }
        try owner.setPreparationFault(nil, focusFactory: .qualification(worker))
        let preparation = Task { try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe) }
        await started.wait()
        let transition = Task {
            let result = await owner.invalidateAndAwaitForAccountTransition()
            await invalidated.open(); return result
        }
        await registered.wait()
        #expect(!(await invalidated.isOpen))
        await #expect(throws: (any Error).self) { try await owner.reservePreparation(original: original, recipe: Self.recipe) }
        release.signal()
        await #expect(throws: (any Error).self) { try await preparation.value }
        #expect(await transition.value)
        let cold = try await h.open()
        let held = try #require(try await cold.activePreparation(packageID: h.packageID))
        #expect(held.sequence == 1)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        try await cold.abandonPreparation(held)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    enum Fault: Error { case injected }
    struct State: Equatable {
        let inventory: Int64, package: Int64, memberRevision: Int64
        let members: Data, envelope: Data, phase: String
    }
    @MainActor
    final class Harness {
        let base: URL, container: ModelContainer
        let inventoryID: UUID, ownerID: UUID, packageID: UUID, draft: UUID
        let runtime = AuthRuntimeState(), bytes = PhotoPreparationTestHarness.image()
        init() throws {
            inventoryID = UUID(); ownerID = UUID(); packageID = UUID(); draft = UUID()
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-preparation-" + UUID().uuidString)
            print("NATIVE_PREPARATION_FIXTURE " + base.path)
            for name in ["authority", "photo", "inbox", "database"] {
                try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: base.appendingPathComponent("database/ledger.store"), cloudKitDatabase: .none)])
        }
        /// Test-only reuse of the qualified V1 producer to seed exact persisted
        /// receiving facts. Does not install or convert a runtime profile.
        init(base: URL, container: ModelContainer, inventoryID: UUID, ownerID: UUID, packageID: UUID, draft: UUID) throws {
            self.base = base; self.container = container; self.inventoryID = inventoryID
            self.ownerID = ownerID; self.packageID = packageID; self.draft = draft
            for name in ["authority", "photo", "inbox"] {
                try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
            }
        }
        func open() async throws -> SharedMediaNativeOriginalOwner {
            let owner = try SharedMediaNativeOriginalOwner.qualification(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime), drain: .init())
            _ = try await owner.open(container: container, authorityRoot: base.appendingPathComponent("authority"),
                photoRoot: base.appendingPathComponent("photo"), inboxRoot: base.appendingPathComponent("inbox"), inventoryID: inventoryID)
            return owner
        }
        func acquire(_ owner: SharedMediaNativeOriginalOwner, ordinal: Int64 = 0) async throws -> PhotoOriginalReference {
            let request = try await owner.prepareOriginal(packageID: packageID, draftGeneration: draft, ordinal: ordinal, kind: .picker), data = bytes
            let result = try await owner.acquireOriginal(request) { data }
            return .init(ownerID: ownerID, packageID: packageID, referenceID: request.referenceID, assetID: request.assetID,
                assetGeneration: request.assetGeneration, draftGeneration: draft, referenceRevision: result.referenceRevision)
        }
        func file(_ ref: PhotoOriginalReference) -> URL {
            base.appendingPathComponent("photo/PhotoPreparation/" + [ownerID, packageID, ref.assetID].map { $0.uuidString.lowercased() }.joined(separator: "/"))
        }
        func state() throws -> State {
            let context = ModelContext(container), id = packageID
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first)
            let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
            return .init(inventory: inventory.revision, package: package.revision, memberRevision: member.revision,
                members: member.membersData, envelope: package.supportingContextData, phase: package.phaseRaw)
        }
    }
}
