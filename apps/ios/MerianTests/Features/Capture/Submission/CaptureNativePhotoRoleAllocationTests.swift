import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureNativePhotoRoleAllocationTests {
    typealias Wire = InitialPhotoAllocationTransportTests

    @Test(arguments: [false, true])
    func twoPhotoRoleAllocationAndColdRecoveryPreserveSubmission(lostReply: Bool) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture(count: 2)
        let wire = Wire.Fixture(ownerID: f.store.ownerID); defer { wire.close() }
        var authorizations = 0, actions: [InitialPhotoAllocationRequest.Action] = []
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            try validate(); authorizations += 1
            return .init(recipient: .gemini, validate: {})
        }, sendRoles: { request, validate, settle in
            #expect(request.projection == .roles && request.allocation.version == 2)
            actions.append(request.action)
            let data = try Wire.reply(request), body = request.body, lose = lostReply && request.action == .create
            wire.mock.register(path: Wire.path) { outgoing in
                #expect(MockURLProtocol.bodyData(for: outgoing) == body)
                if lose { throw URLError(.networkConnectionLost) }
                return (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await wire.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        })
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection,
            preflight: { _, _, _ in .init(recipient: .gemini, validate: {}) }, allocationAccess: access, resolveOwner: { f.owner })
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        let prepared = try #require(session.prepared), local = try #require(session.receipt)
        if lostReply { await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) } }
        else {
            _ = try await session.allocate(snapshot)
            #expect(session.allocation?.roleMapping?.entries.count == 6)
        }
        #expect(session.receipt == local && !session.isBusy)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
        let recovered = CaptureNativePhotoSubmissionSession(selection: f.selection, preflight: { _, _, _ in
            Issue.record("Recovery rediscovered processor"); throw SharedMediaStorageFailure.closed
        }, allocationAccess: access, resolveOwner: { cold })
        _ = try await recovered.submit(snapshot)
        #expect(try recovered.prepared?.encoded() == prepared.encoded())
        #expect(recovered.receipt == local)
        _ = try await recovered.allocate(snapshot)
        #expect(actions == [.create, .status] && authorizations == 1)
        #expect(recovered.allocation?.roleMapping?.entries.count == 6)
        #expect(recovered.allocation?.remainingAdvances == 0)
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func actualCaptureCallerPreservesLaterSelectionWithRoleProjection(changeSelection: Bool) async throws {
        let harness = CaptureNativePhotoSubmissionTests(), f = try await harness.fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let wire = Wire.Fixture(ownerID: f.store.ownerID); defer { wire.close() }
        var actions: [InitialPhotoAllocationRequest.Action] = []
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            try validate(); return .init(recipient: .gemini, validate: {})
        }, sendRoles: { request, validate, settle in
            try validate(); actions.append(request.action)
            await entered.open(); await release.wait()
            let data = try Wire.reply(request)
            wire.mock.register(path: Wire.path) { outgoing in
                (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await wire.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        })
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection,
            preflight: { _, _, _ in .init(recipient: .gemini, validate: {}) }, allocationAccess: access, resolveOwner: { f.owner })
        let vm = harness.viewModel(session: session, account: { f.store.ownerID })
        vm.stagedCapture = f.capture
        let bound = vm.draftSession.bindAccount(f.store.ownerID)
        #expect(bound)
        let running = Task { await vm.submitStagedCapture(modelContext: ModelContext(f.store.container)) }
        await entered.wait()
        if changeSelection { vm.stagedCapture.observationContexts[0].context = .init(freeText: "Later selection") }
        let visible = try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture)
        await release.open(); await running.value
        #expect(actions == [.create] && session.allocation?.roleMapping?.entries.count == 3)
        #expect(try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture) == visible)
        #expect((vm.offlineToastMessage != nil) == !changeSelection)
        #expect(vm.pendingAnalyzeScanId == nil && !vm.isCheckingScanAdmission)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }
}
