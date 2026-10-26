import Foundation
import SwiftData
import Testing
import UIKit
@testable import Merian

@Suite("Inactive native Capture submit bridge", .serialized)
@MainActor
struct CaptureNativePhotoSubmissionTests {
    @Test(arguments: [1, 2])
    func lostAcknowledgementRecoversExactReceivedSlot(_ failingSave: Int) async throws {
        let f = try await fixture()
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection) { f.owner }
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        var saves = 0, lost = false
        try f.owner.setMetadataFault { boundary in
            if boundary == .beforeSave { saves += 1 }
            if boundary == .afterSave && saves == failingSave { lost = true }
            if boundary == .beforeReadback && lost { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await session.submit(snapshot) }
        #expect(!session.isBusy && session.receipt == nil)
        try f.owner.setMetadataFault(nil)
        _ = try await session.submit(snapshot)
        let prepared = try #require(session.prepared), receipt = try #require(session.receipt)
        let saved = try #require(try await f.owner.discoverAppReceivingSlot(packageID: f.store.packageID))
        // Received recovery is a read, even if every attempted save would fail.
        try f.owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        _ = try await session.submit(snapshot)
        #expect(session.receipt == receipt)
        #expect(try session.prepared?.encoded() == prepared.encoded())
        #expect(try await f.owner.discoverAppReceivingSlot(packageID: f.store.packageID) == saved)
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
        let recovered = CaptureNativePhotoSubmissionSession(selection: f.selection) { cold }
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        _ = try await recovered.submit(snapshot)
        #expect(recovered.receipt == receipt)
        #expect(try recovered.prepared?.encoded() == prepared.encoded())
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func changedInputAndConcurrentTapRefuseBeforeAdmission() async throws {
        let f = try await fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var admissions = 0
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection) {
            admissions += 1; await entered.open(); await release.wait(); return f.owner
        }
        var changed = f.capture
        changed.images[0] = changed.images[0].replacing(displayData: Data([1]))
        await #expect(throws: (any Error).self) { _ = try await session.submit(.init(changed)) }
        changed = f.capture; changed.observationContexts[0].context = .init(freeText: "Changed")
        await #expect(throws: (any Error).self) { _ = try await session.submit(.init(changed)) }
        #expect(admissions == 0)
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        let running = Task { try await session.submit(snapshot) }
        await entered.wait()
        #expect(session.isBusy)
        await #expect(throws: (any Error).self) { _ = try await session.submit(snapshot) }
        running.cancel()
        #expect(session.isBusy) // cancellation does not release a still-running admission
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await running.value }
        #expect(!session.isBusy && admissions == 1)
        #expect(try await f.owner.discoverAppReceivingSlot(packageID: f.store.packageID) == nil)
        _ = try await session.submit(snapshot)
        #expect(admissions == 1 && session.receipt != nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func persistedTextRaceRefusesBeforeIntentSave() async throws {
        let f = try await fixture()
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection) { f.owner }
        let changed = try await f.owner.prepareAppMetadata(packageID: f.store.packageID,
            draftGeneration: f.store.draft, contexts: [.init(freeText: "Later persisted selection")])
        _ = try await f.owner.saveAppMetadata(changed)
        var saves = 0
        try f.owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await session.submit(.init(f.capture)) }
        #expect(saves == 0)
        #expect(try await f.owner.discoverAppReceivingSlot(packageID: f.store.packageID) == nil)
        #expect(try f.store.package().supportingContextData == changed.envelope)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func abandonedSlotDoesNotStageOrReceiveAgain() async throws {
        let f = try await fixture()
        let prepared = try await f.owner.stageAppReceiving(packageID: f.store.packageID,
            draftGeneration: f.store.draft, pairIDs: f.selection.pairIDs, expectedMetadata: f.selection.metadata)
        _ = try await f.owner.abandonAppReceiving(prepared)
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection) { f.owner }
        var saves = 0
        try f.owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await session.submit(.init(f.capture)) }
        #expect(saves == 0 && session.receipt == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func missingNativeAccessCannotFallThroughAfterClearing() async throws {
        let vm = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        vm.stagedCapture.nativePhotoDraft = .init(ownerID: UUID(), packageID: UUID(), draftGeneration: UUID())
        vm.stagedCapture.observationContexts = [.init(context: .init(freeText: "Preserve"))]
        let identity = vm.stagedCapture.nativePhotoDraft
        let h = try PhotoPreparationTestHarness()
        await vm.submitStagedCapture(modelContext: ModelContext(h.container))
        #expect(vm.offlineToastMessage != nil && vm.stagedCapture.observationContexts.count == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        vm.stagedCapture.clearAll()
        #expect(vm.stagedCapture.nativePhotoDraft == identity)
        await vm.submitStagedCapture(modelContext: ModelContext(h.container))
        #expect(vm.stagedCapture.nativePhotoDraft == identity)
    }

    @Test(arguments: ["unchanged", "account", "generation", "context", "refinement"])
    func actualCallerWithholdsStalePresentation(_ change: String) async throws {
        let f = try await fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection) {
            await entered.open(); await release.wait(); return f.owner
        }
        var account: UUID? = f.store.ownerID
        let vm = viewModel(session: session, account: { account })
        vm.stagedCapture = f.capture
        let bound = vm.draftSession.bindAccount(account)
        #expect(bound)
        vm.updateAutomaticStagedSubmissionPending(true)
        await vm.submitStagedCapture(modelContext: ModelContext(f.store.container))
        #expect(session.attemptID == nil && session.receipt == nil)
        vm.offlineToastMessage = nil
        let running = Task { await vm.submitStagedCapture(modelContext: ModelContext(f.store.container)) }
        await entered.wait()
        #expect(vm.isCheckingScanAdmission && session.isBusy)
        switch change {
        case "account": account = UUID()
        case "generation": vm.draftSession.reset()
        case "context": vm.stagedCapture.observationContexts[0].context = .init(freeText: "Later visible text")
        case "refinement": vm.baseRefinementContext = .init(record: .init(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture"))
        default: break
        }
        let visible = try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture)
        await release.open(); await running.value
        #expect(session.receipt != nil && !session.isBusy && !vm.isCheckingScanAdmission)
        #expect((vm.offlineToastMessage != nil) == (change == "unchanged"))
        #expect(try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture) == visible)
        #expect(vm.pendingAnalyzeScanId == nil)
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineJobRecord>()).map(\.status) == [.needsAttention])
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    private func viewModel(session: CaptureNativePhotoSubmissionSession, account: @escaping @MainActor @Sendable () -> UUID?) -> CaptureWorkspaceViewModel {
        let base = CaptureWorkspaceDependencies.live(diContainer: .preview)
        let submission = CaptureSubmissionDependencies(context: base.submission.context,
            admission: .init(isOnline: { Issue.record("Native submit entered legacy admission"); return false },
                canStartLocally: { _ in Issue.record("Native submit entered legacy funding"); return false },
                preview: { _ in Issue.record("Native submit requested legacy preview"); return .unavailable }, accountID: account),
            deferredContext: base.submission.deferredContext, nativePhotoSubmission: session)
        let dependencies = CaptureWorkspaceDependencies(scan: base.scan, submission: submission, controls: base.controls,
            navigation: base.navigation, stagingToolbar: base.stagingToolbar, prepareImage: { _ in nil },
            prepareHistoricalAudio: { _ in nil }, externalImageImports: base.externalImageImports,
            downloadRefinementImage: { _ in nil }, prewarmConnections: {}, sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString }, requestNotificationAuthorization: { _ in }, feedback: base.feedback)
        return .init(diContainer: .preview, dependencies: dependencies, prewarmHeadersOnInit: false)
    }

    private struct Fixture {
        let store: SharedMediaNativeAppMetadataTests.Store
        let owner: SharedMediaNativeOriginalOwner
        let selection: CaptureNativePhotoSubmissionSelection
        let capture: StagedCapture
    }

    @Test func reversedPairOrderIsNotANewSelection() async throws {
        let f = try await fixture(count: 2)
        #expect(throws: (any Error).self) {
            _ = try CaptureNativePhotoSubmissionSelection(metadata: f.selection.metadata, pairs: f.selection.pairs.reversed())
        }
        var reversed = f.capture; reversed.images.reverse()
        #expect(throws: (any Error).self) { try f.selection.validate(.init(reversed)) }
        #expect(try await f.owner.discoverAppReceivingSlot(packageID: f.store.packageID) == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    private func fixture(count: Int = 1) async throws -> Fixture {
        let h = try SharedMediaNativeAppMetadataTests.Store(), owner = try await h.open()
        let bytes = PhotoPreparationTestHarness.image(), image = try #require(UIImage(data: bytes))
        let added = Date(timeIntervalSince1970: 1_700_000_000)
        var capture = StagedCapture(), pairs: [SharedMediaNativePairFileState] = []
        capture.nativePhotoDraft = .init(ownerID: h.ownerID, packageID: h.packageID, draftGeneration: h.draft)
        capture.observationContexts = [.init(context: .init(freeText: "  Exact text\nwith spacing.  "), addedAt: added)]
        for ordinal in 0..<count {
            let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: Int64(ordinal), kind: .picker)
            let acquired = try await owner.acquireAppOriginal(request) { bytes }
            let reference = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
                assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
            capture.images.append(.init(compressedData: bytes, displayData: bytes, uiImage: image,
                original: IdentifiableImage(image: image, isFromGallery: true), addedAt: added.addingTimeInterval(Double(ordinal)), photoOriginalReference: reference))
            let initial = try CaptureNativePhotoSubmissionSnapshot(capture)
            let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(initial.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
            let edit = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
                contexts: supporting.contexts, presentation: supporting.presentation)
            _ = try await owner.saveAppMetadata(edit)
            try owner.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: { .noCandidates }, drainRegistered: {})))
            let ready = try await owner.prepareAndDeliverAppPhoto(original: reference,
                recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
            pairs.append(ready)
        }
        let metadata = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft)
        let projection = try await owner.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: pairs.map { try $0.intent().pairID })
        for (index, photo) in projection.photos.enumerated() {
            capture.images[index] = capture.images[index].replacing(compressedData: photo.ai, displayData: photo.display)
        }
        let selection = try CaptureNativePhotoSubmissionSelection(metadata: metadata, pairs: pairs)
        try selection.validate(.init(capture))
        return .init(store: h, owner: owner, selection: selection, capture: capture)
    }
}
