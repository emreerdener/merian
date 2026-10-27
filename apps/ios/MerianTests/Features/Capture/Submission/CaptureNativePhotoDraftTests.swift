import Foundation
import SwiftData
import Testing
import UIKit
@testable import Merian

@Suite("Native picker current-process draft", .serialized)
@MainActor
struct CaptureNativePhotoDraftTests {
    @Test(arguments: [1, 2], [false, true])
    func actualPickerCropDetailsAndExplicitLocalReceipt(_ count: Int, text: Bool) async throws {
        let f = try await fixture()
        await importPhotos(f, count: count)
        #expect(f.session.references.count == count && f.vm.stagedCapture.images.count == count)
        #expect(f.session.metadataRequest == nil && f.session.prepared == nil)
        #expect(!f.vm.isAutomaticSubmissionArmed && f.vm.hasPendingRequiredGalleryCrop)
        #expect(f.vm.stagedCapture.images.allSatisfy { $0.compressedData.isEmpty && $0.displayData.isEmpty && $0.focusRegion == nil })
        confirmCrops(f)
        if text { f.vm.updateDescriptionDraft(.init(freeText: "  Exact optional text\nsecond line.  ")) }
        let before = try CaptureNativePhotoSubmissionSnapshot(f.vm.stagedCapture)
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        let prepared = try #require(f.session.prepared), receipt = try #require(prepared.submission.receipt)
        #expect(prepared.submission.selection.supportingBytes == before.supportingBytes)
        #expect(f.session.isFrozen && !f.session.canEdit && f.vm.isDraftMutationLocked)
        #expect(f.vm.stagedCapture.images.allSatisfy { !$0.compressedData.isEmpty && !$0.displayData.isEmpty })
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(f.vm.stagedCapture, selection: prepared.submission.selection)
        f.vm.updateDescriptionDraft(.init(freeText: "Forbidden edit"))
        var note = ObservationContext()
        f.vm.saveStagedDescription(at: 0, text: "Forbidden edit", pendingDraft: &note)
        f.vm.removeStagedDescription(at: 0, pendingDraft: &note)
        f.vm.removeNativePhoto(imageID: f.vm.stagedCapture.images[0].original.id)
        f.vm.discardNativePhotoDraft()
        #expect(f.vm.nativePhotoDispositionTask == nil)
        #expect(try CaptureNativePhotoSubmissionSnapshot(f.vm.stagedCapture, selection: prepared.submission.selection) == snapshot)
        try f.owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        #expect(prepared.submission.receipt == receipt && f.vm.pendingAnalyzeScanId == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["requiredCancel", "remove", "discard"])
    func everyDispositionEntryAcknowledgesOriginals(_ route: String) async throws {
        let f = try await fixture()
        await importPhotos(f, count: 2)
        let marker = f.vm.stagedCapture.nativePhotoDraft
        if route == "discard" {
            f.vm.requestDraftDiscard()
            #expect(f.vm.confirmDraftDiscard(generation: f.vm.draftSession.generation))
        } else {
            let id = f.vm.stagedCapture.images[0].original.id
            if route == "requiredCancel" { f.vm.cancelRequiredGalleryCrop(for: id) }
            else { confirmCrops(f); f.vm.removeNativePhoto(imageID: id) }
        }
        await f.vm.nativePhotoDispositionTask?.value
        if route != "discard" {
            #expect(f.vm.stagedCapture.images.count == 1 && f.session.items[0].removed)
            #expect(f.vm.stagedCapture.nativePhotoDraft == marker)
            f.vm.discardNativePhotoDraft()
            await f.vm.nativePhotoDispositionTask?.value
        }
        #expect(f.session.isDiscarded && f.session.items.allSatisfy(\.removed))
        #expect(f.vm.stagedCapture.nativePhotoDraft == nil && f.vm.stagedCapture.isEmpty)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["account", "generation", "cancel"])
    func delayedAcquisitionCannotRestoreStaleUI(_ change: String) async throws {
        let store = try SharedMediaNativeAppMetadataTests.Store(), owner = try await store.open()
        let session = CaptureNativePhotoDraftSession(identity: .init(ownerID: store.ownerID, packageID: store.packageID, draftGeneration: store.draft)) { owner }
        var account: UUID? = store.ownerID
        let vm = viewModel(session: session, account: { account })
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let bytes = PhotoPreparationTestHarness.image()
        vm.importNativePhotoItems([.init(localIdentifier: nil, load: { await entered.open(); await release.wait(); return bytes })])
        let running = try #require(vm.nativePhotoImportTask)
        await entered.wait()
        #expect(session.isBusy && vm.isDraftMutationLocked && vm.stagedCapture.nativePhotoDraft == session.identity)
        if change == "account" { account = UUID(); vm.handleDraftAccountChange() }
        else if change == "generation" { vm.draftSession.reset() }
        else { running.cancel() }
        await release.open(); await running.value
        #expect(vm.stagedCapture.images.isEmpty && vm.stagedCapture.nativePhotoDraft == session.identity)
        #expect(session.needsAttention && !session.canEdit && session.items.count == 1)
        #expect(session.items[0].request != nil && session.prepared == nil)
        if change == "account" { #expect(session.items.allSatisfy { $0.preview == nil }) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func partialImportRetainsWholeSelectionAndNeverReloads() async throws {
        let f = try await fixture(), bytes = PhotoPreparationTestHarness.image()
        let inputs: [CaptureNativePhotoPickerInput] = [.init(localIdentifier: nil, load: { bytes }),
            .init(localIdentifier: nil, load: { throw SharedMediaStorageFailure.unavailable })]
        f.vm.importNativePhotoItems(inputs)
        await f.vm.nativePhotoImportTask?.value
        #expect(f.vm.nativePhotoPickerInputs.map(\.id) == inputs.map(\.id))
        #expect(f.session.items.map(\.id) == inputs.map(\.id))
        #expect(f.session.needsAttention && f.vm.stagedCapture.images.count == 1)
        let requests = f.session.items.map(\.request)
        f.vm.importNativePhotoItems([.init(localIdentifier: nil, load: { Issue.record("Unexpected reload"); return bytes })])
        #expect(f.vm.nativePhotoImportTask == nil && f.session.items.map(\.request) == requests)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["metadata", "preparation"])
    func failedPreparationHoldsFrozenInputsWithoutRepeating(_ boundary: String) async throws {
        let f = try await fixture()
        await importPhotos(f, count: 2); confirmCrops(f)
        if boundary == "metadata" {
            try f.owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.unavailable } }
        } else {
            try f.owner.setPreparationFault { if $0 == .beforeFileReserve { throw SharedMediaStorageFailure.unavailable } }
        }
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        #expect(f.session.isFrozen && f.session.needsAttention && f.session.prepared == nil)
        let request = try #require(f.session.metadataRequest)
        try f.owner.setMetadataFault(nil); try f.owner.setPreparationFault(nil)
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        #expect(f.session.metadataRequest?.envelope == request.envelope && f.session.prepared == nil)
        #expect(f.vm.nativePhotoDispositionTask == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["tooMany", "audio", "video"])
    func mixedOrOversizedSelectionRefusesWithoutTruncation(_ shape: String) async throws {
        let f = try await fixture()
        if shape == "audio" { f.vm.stagedCapture.audios = [.init(filePath: "synthetic-fixture.m4a")] }
        if shape == "video" {
            f.vm.stagedCapture.videos = [.init(filePath: "synthetic-fixture.mov", sampledImages: [])]
        }
        let inputs = (0..<(shape == "tooMany" ? 3 : 1)).map { _ in
            CaptureNativePhotoPickerInput(localIdentifier: nil, load: { Issue.record("Refused input loaded"); return Data() })
        }
        f.vm.importNativePhotoItems(inputs)
        #expect(f.vm.nativePhotoImportTask == nil && f.session.items.isEmpty)
        #expect(f.vm.beginDraftOperation() == nil)
        #expect(await f.vm.importNextPendingExternalImage() == .temporarilyBlocked)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func preAcquisitionFailureCanLeaveWithoutDurableCleanup() async throws {
        let identity = StagedCapture.NativePhotoDraft(ownerID: UUID(), packageID: UUID(), draftGeneration: UUID())
        let session = CaptureNativePhotoDraftSession(identity: identity) { throw SharedMediaStorageFailure.unavailable }
        let vm = viewModel(session: session, account: { identity.ownerID })
        vm.importNativePhotoItems([.init(localIdentifier: nil, load: { Issue.record("Unadmitted load"); return Data() })])
        await vm.nativePhotoImportTask?.value
        #expect(session.hasNoNativeAcquisition && !session.needsAttention)
        #expect(vm.stagedCapture.nativePhotoDraft == nil && vm.nativePhotoDraftSession == nil)
        #expect(!vm.isDraftMutationLocked)
    }

    @Test func secondPairFailureCannotRepeatTheFirstPair() async throws {
        let f = try await fixture()
        await importPhotos(f, count: 2); confirmCrops(f)
        var reserves = 0
        try f.owner.setPreparationFault {
            if $0 == .beforeFileReserve {
                reserves += 1
                if reserves == 2 { throw SharedMediaStorageFailure.unavailable }
            }
        }
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        #expect(reserves == 2 && f.session.isFrozen && f.session.needsAttention && f.session.prepared == nil)
        try f.owner.setPreparationFault { if $0 == .beforeFileReserve { Issue.record("Repeated preparation") } }
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        f.vm.removeNativePhoto(imageID: f.vm.stagedCapture.images[0].original.id)
        f.vm.discardNativePhotoDraft()
        #expect(f.vm.nativePhotoDispositionTask == nil && f.session.prepared == nil)
        #expect(f.vm.stagedCapture.nativePhotoDraft == f.session.identity && f.vm.isDraftMutationLocked)
        #expect(f.vm.nativePhotoPickerInputs.count == 2)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func discardedOrInvalidatedSessionNeverReacquires() async throws {
        let f = try await fixture()
        await importPhotos(f, count: 1)
        f.session.clearPrivatePreviews()
        await #expect(throws: (any Error).self) { _ = try await f.session.acquire(itemID: UUID()) { Issue.record("Invalidated loader called"); return Data() } }
        #expect(f.session.items.allSatisfy { $0.preview == nil })
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func partialDiscardRetainsMarkerAndUnfinishedItem() async throws {
        let f = try await fixture()
        await importPhotos(f, count: 2)
        var saves = 0
        try f.owner.setLifecycleFault {
            if $0 == .beforeSave { saves += 1; if saves == 2 { throw SharedMediaStorageFailure.unavailable } }
        }
        f.vm.discardNativePhotoDraft()
        await f.vm.nativePhotoDispositionTask?.value
        #expect(saves == 2 && f.session.items[0].removed && !f.session.items[1].removed)
        #expect(f.session.items[1].removal != nil && f.session.needsAttention && !f.session.isDiscarded)
        #expect(f.vm.stagedCapture.nativePhotoDraft == f.session.identity)
        #expect(f.vm.stagedCapture.images.count == 2) // whole-draft clear never acknowledged
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountChangeDuringPreparationCannotRetainReadyPresentation() async throws {
        let initial = try await fixture()
        var account: UUID? = initial.store.ownerID
        let f = Fixture(store: initial.store, owner: initial.owner, session: initial.session,
            vm: viewModel(session: initial.session, account: { account }))
        await importPhotos(f, count: 1); confirmCrops(f)
        let entered = ImageFocusEngineTests.Signal(), release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        try f.owner.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: {
            Task { await entered.open() }; release.wait(); return .noCandidates
        }, drainRegistered: {})))
        let running = Task { await f.vm.submitStagedCapture(modelContext: f.store.context()) }
        await entered.wait()
        account = UUID(); f.vm.handleDraftAccountChange()
        release.signal(); await running.value
        #expect(f.session.prepared == nil && f.session.items.allSatisfy { $0.preview == nil })
        #expect(f.vm.stagedCapture.isEmpty && f.vm.stagedCapture.nativePhotoDraft == f.session.identity)
        #expect(f.vm.pendingAnalyzeScanId == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    private struct Fixture {
        let store: SharedMediaNativeAppMetadataTests.Store
        let owner: SharedMediaNativeOriginalOwner
        let session: CaptureNativePhotoDraftSession
        let vm: CaptureWorkspaceViewModel
    }
    private func fixture() async throws -> Fixture {
        let store = try SharedMediaNativeAppMetadataTests.Store(), owner = try await store.open()
        try owner.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: { .noCandidates }, drainRegistered: {})))
        let session = CaptureNativePhotoDraftSession(identity: .init(ownerID: store.ownerID, packageID: store.packageID, draftGeneration: store.draft)) { owner }
        return .init(store: store, owner: owner, session: session, vm: viewModel(session: session, account: { store.ownerID }))
    }
    private func importPhotos(_ f: Fixture, count: Int) async {
        let bytes = PhotoPreparationTestHarness.image()
        f.vm.importNativePhotoItems((0..<count).map { _ in .init(localIdentifier: nil, load: { bytes }) })
        await f.vm.nativePhotoImportTask?.value
    }
    private func confirmCrops(_ f: Fixture) {
        for (index, image) in f.vm.stagedCapture.images.enumerated() {
            f.vm.confirmNativePhotoCrop(imageID: image.original.id, thumbnailData: PhotoPreparationTestHarness.image(),
                scale: 1, offset: .zero, displaySize: 200, quarterTurns: index)
        }
    }
    private func viewModel(session: CaptureNativePhotoDraftSession, account: @escaping @MainActor @Sendable () -> UUID?) -> CaptureWorkspaceViewModel {
        let base = CaptureWorkspaceDependencies.live(diContainer: .preview)
        let submission = CaptureSubmissionDependencies(context: base.submission.context,
            admission: .init(isOnline: { Issue.record("Legacy network admission"); return false },
                canStartLocally: { _ in Issue.record("Legacy funding admission"); return false },
                preview: { _ in Issue.record("Legacy preview"); return .unavailable }, accountID: account),
            deferredContext: base.submission.deferredContext, nativePhotoDraftFactory: { _ in session })
        let dependencies = CaptureWorkspaceDependencies(scan: base.scan, submission: submission, controls: base.controls,
            navigation: base.navigation, stagingToolbar: base.stagingToolbar, prepareImage: { _ in Issue.record("Legacy preparation"); return nil },
            prepareHistoricalAudio: { _ in nil }, externalImageImports: base.externalImageImports,
            downloadRefinementImage: { _ in nil }, prewarmConnections: {}, sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString }, requestNotificationAuthorization: { _ in }, feedback: base.feedback)
        return .init(diContainer: .preview, dependencies: dependencies, prewarmHeadersOnInit: false)
    }
}
