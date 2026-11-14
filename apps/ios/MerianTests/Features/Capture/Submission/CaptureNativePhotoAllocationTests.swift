import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive Capture photo allocation", .serialized)
@MainActor
struct CaptureNativePhotoAllocationTests {
    private let positive = SharedMediaNativePhotoAllocation.Receipt(assignmentDigest: String(repeating: "a", count: 64),
        createdAtMilliseconds: 1_700_000_000_000, expiresAtMilliseconds: 1_700_001_800_000)

    @Test(arguments: [false, true])
    func explicitAllocationAndColdStatusPreserveLocalReceipt(_ lostCreate: Bool) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture(count: 2)
        var authorizations = 0, actions: [InitialPhotoAllocationRequest.Action] = []
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { value, validate in
            try validate(); authorizations += 1
            #expect(value.photoAdmission?.expectedProcessorPermission == .gemini)
            return .init(recipient: .gemini, validate: {})
        }, send: { request, validate, settle in
            try validate(); actions.append(request.action)
            if lostCreate && request.action == .create { throw SharedMediaStorageFailure.unavailable }
            try settle(); return .allocated(positive)
        })
        let session = session(f, access: access), snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        let prepared = try #require(session.prepared), receipt = try #require(session.receipt)
        #expect(actions.isEmpty && session.allocation == nil)
        if lostCreate { await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) } }
        else { _ = try await session.allocate(snapshot) }
        #expect(session.receipt == receipt && !session.isBusy)
        await #expect(throws: (any Error).self) { _ = try await f.owner.discoverAppReceivingSlot(packageID: f.store.packageID) }
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
        let recovered = CaptureNativePhotoSubmissionSession(selection: f.selection, preflight: { _, _, _ in
            Issue.record("Recovery rediscovered recipient"); throw SharedMediaStorageFailure.closed
        }, allocationAccess: access, resolveOwner: { cold })
        _ = try await recovered.submit(snapshot)
        #expect(try recovered.prepared?.encoded() == prepared.encoded())
        #expect(recovered.receipt == receipt)
        _ = try await recovered.allocate(snapshot)
        #expect(actions == [.create, .status] && authorizations == 1)
        #expect(recovered.allocation?.receipt == positive)
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeClaim", "beforeSave", "afterSave", "afterResponse", "differentProcessor"])
    func consentFencesDoNotBlockSavedStatus(_ boundary: String) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture()
        var permitted = boundary != "beforeClaim", authorizations = 0, actions: [InitialPhotoAllocationRequest.Action] = []
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            try validate(); authorizations += 1
            return .init(recipient: boundary == "differentProcessor" ? .openAI : .gemini) {
                guard permitted else { throw MerianError.aiConsentRequired }
            }
        }, send: { request, validate, settle in
            try validate(); actions.append(request.action)
            if boundary == "afterResponse" { permitted = false }
            try settle(); return .allocated(positive)
        })
        let session = session(f, access: access), snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        let local = try #require(session.receipt)
        try f.owner.setMetadataFault {
            if (boundary == "beforeSave" && $0 == .beforeSave) || (boundary == "afterSave" && $0 == .afterSave) { permitted = false }
        }
        if boundary == "afterResponse" { _ = try await session.allocate(snapshot) }
        else { await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) } }
        #expect(session.receipt == local)
        let saved = try #require(try await f.owner.discoverAppPhotoSubmission(packageID: f.store.packageID))
        #expect((saved.allocation != nil) == (boundary == "afterSave" || boundary == "afterResponse"))
        if saved.allocation != nil {
            try f.owner.setMetadataFault(nil)
            _ = try await session.allocate(snapshot)
            #expect(authorizations == 1 && actions.last == .status)
            #expect(session.allocation?.receipt == positive)
        } else { #expect(actions.isEmpty) }
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func claimAppearingDuringAuthorizationIsStatusOnly() async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture()
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { prepared, validate in
            try validate()
            let context = f.store.context()
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
            let result = try SharedMediaNativeReceivingIntent.Received.decode(try #require(row.resultData), prepared: prepared)
            let allocation = SharedMediaNativePhotoAllocation(claim: try .init(prepared: prepared, received: result, attemptID: UUID()))
            row.allocationData = try allocation.encoded(); row.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(row.allocationData!)
            let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            inventory.revision += 1; try context.save()
            return .init(recipient: .gemini, validate: {})
        }, send: { request, validate, settle in
            try validate(); #expect(request.action == .status); try settle(); return .held(.notFound)
        })
        let session = session(f, access: access), snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot); _ = try await session.allocate(snapshot)
        #expect(session.allocation != nil && session.allocation?.receipt == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func changedOrDeletedSubmissionDuringAuthorizationCannotClaim(_ deleted: Bool) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture()
        var sends = 0
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            try validate()
            let context = f.store.context()
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
            if deleted { context.delete(row) } else { row.preparedSHA256 = String(repeating: "f", count: 64) }
            try context.save()
            return .init(recipient: .gemini, validate: {})
        }, send: { _, _, _ in sends += 1; return .held(.notFound) })
        let session = session(f, access: access), snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) }
        #expect(sends == 0 && session.receipt != nil && session.allocation == nil)
        #expect(try f.store.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).allSatisfy { $0.allocationData == nil })
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func legacyAndMissingCompositionRemainLocalOnly(_ legacy: Bool) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture()
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, _ in
            Issue.record("Legacy receipt entered allocation consent"); throw SharedMediaStorageFailure.closed
        }, send: { _, _, _ in Issue.record("Local-only session sent allocation"); return .held(.notFound) })
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection,
            preflight: legacy ? nil : { _, _, _ in .init(recipient: .gemini, validate: {}) },
            allocationAccess: legacy ? access : nil, resolveOwner: { f.owner })
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        #expect(!session.canAllocate && session.receipt != nil)
        await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) }
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["authorize", "send"], [false, true])
    func cancellationAndAccountShutdownDrainExplicitPhase(_ pause: String, shutdown: Bool) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var closed = false
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            if pause == "authorize" { await entered.open(); await release.wait() }
            try validate(); return .init(recipient: .gemini, validate: {})
        }, send: { _, validate, settle in
            await entered.open(); await release.wait()
            try validate(); try settle(); return .allocated(positive)
        })
        let session = session(f, access: access), snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        let running = Task { try await session.allocate(snapshot) }
        await entered.wait()
        await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) }
        let closing: Task<Bool, Never>?
        if shutdown {
            closing = Task { let result = await f.owner.invalidateAndAwaitForAccountTransition(); closed = true; return result }
            while !f.owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        } else { closing = nil; running.cancel() }
        #expect(!closed && session.isBusy)
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await running.value }
        #expect(!session.isBusy && session.receipt != nil && session.allocation == nil)
        if let closing { #expect(await closing.value) }
        else { #expect(await f.owner.invalidateAndAwaitForAccountTransition()) }
        let row = try #require(try f.store.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        #expect((row.allocationData != nil) == (pause == "send"))
    }

    @Test(arguments: [false, true])
    func actualCallerAllocatesAndPreservesLaterSelection(_ changeSelection: Bool) async throws {
        let harness = CaptureNativePhotoSubmissionTests(), f = try await harness.fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var actions: [InitialPhotoAllocationRequest.Action] = []
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            try validate(); return .init(recipient: .gemini, validate: {})
        }, send: { request, validate, settle in
            try validate(); actions.append(request.action)
            await entered.open(); await release.wait(); try settle(); return .allocated(positive)
        })
        let session = session(f, access: access), vm = harness.viewModel(session: session, account: { f.store.ownerID })
        vm.stagedCapture = f.capture
        let bound = vm.draftSession.bindAccount(f.store.ownerID)
        #expect(bound)
        let running = Task { await vm.submitStagedCapture(modelContext: ModelContext(f.store.container)) }
        await entered.wait()
        if changeSelection { vm.stagedCapture.observationContexts[0].context = .init(freeText: "Later selection") }
        let visible = try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture)
        await release.open(); await running.value
        #expect(actions == [.create] && session.allocation?.receipt == positive)
        #expect(try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture) == visible)
        #expect((vm.offlineToastMessage != nil) == !changeSelection)
        #expect(vm.pendingAnalyzeScanId == nil && !vm.isCheckingScanAdmission)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    private func session(_ f: CaptureNativePhotoSubmissionTests.Fixture,
                         access: SharedMediaNativePhotoAllocationAccess) -> CaptureNativePhotoSubmissionSession {
        .init(selection: f.selection, preflight: { _, _, _ in .init(recipient: .gemini, validate: {}) },
            allocationAccess: access, resolveOwner: { f.owner })
    }
}
