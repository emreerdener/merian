import Foundation
import SwiftData
import Testing
import UIKit
@testable import Merian

@Suite("Native camera current-process draft", .serialized)
@MainActor
struct CaptureNativeCameraDraftTests {
    @Test(arguments: ["camera", "cameraCamera", "cameraPicker", "pickerCamera"], [false, true])
    func actualShutterFreezesFramingAndExplicitLocalReceipt(_ order: String, text: Bool) async throws {
        let pro = order != "camera"
        let f = try await fixture(pro: pro)
        #expect(f.vm.stagedCaptureLimit == (pro ? stagedCaptureCapacity : 1))
        f.spy.capture = {
            #expect(f.vm.stagedCapture.nativePhotoDraft == f.session.identity)
            #expect(f.session.items.last?.request?.kind == .camera)
            #expect(f.session.isBusy && f.vm.isDraftMutationLocked)
            f.vm.composingZoneVerticalCenter = 0.8 // changes after shutter admission
            return f.spy.bytes
        }
        for kind in order == "camera" ? ["camera"] : order == "cameraCamera" ? ["camera", "camera"] : order == "cameraPicker" ? ["camera", "picker"] : ["picker", "camera"] {
            if kind == "camera" {
                f.vm.composingZoneVerticalCenter = 0.25
                f.vm.executeCapture()
                await f.vm.nativePhotoImportTask?.value
            } else {
                f.vm.importNativePhotoItems([.init(localIdentifier: nil, load: { @MainActor in f.spy.bytes })])
                await f.vm.nativePhotoImportTask?.value
                let image = try #require(f.vm.stagedCapture.images.last)
                f.vm.confirmNativePhotoCrop(imageID: image.original.id, thumbnailData: f.spy.bytes,
                    scale: 1, offset: .zero, displaySize: 200, quarterTurns: 0)
            }
        }
        if !pro {
            // A completed free capture still consumes the sole physical-media slot.
            f.vm.executeCapture()
            #expect(f.vm.nativePhotoImportTask == nil)
        }
        #expect(f.session.items.allSatisfy { $0.recipe?.isPro == pro })
        #expect(f.session.items.count == (order == "camera" ? 1 : 2))
        #expect(f.spy.shutters == (order == "cameraCamera" ? 2 : 1))
        #expect(f.session.items.filter { $0.request?.kind == .camera }.allSatisfy { $0.recipe?.cameraVerticalCenter == 0.25 })
        #expect(!f.vm.isAutomaticSubmissionArmed && f.vm.preFetchTask == nil)
        #expect(f.vm.stagedCapture.images.filter { !$0.original.isFromGallery }.allSatisfy { $0.original.environmentContext?.captureDate != nil })
        #expect(f.vm.stagedCapture.images.allSatisfy { $0.compressedData.isEmpty && $0.displayData.isEmpty })
        if text { f.vm.updateDescriptionDraft(.init(freeText: "  Camera detail\nretained exactly.  ")) }
        let before = try CaptureNativePhotoSubmissionSnapshot(f.vm.stagedCapture)
        await f.vm.submitStagedCapture(modelContext: f.store.context())
        let prepared = try #require(f.session.prepared)
        #expect(prepared.submission.receipt != nil && f.session.isFrozen)
        #expect(prepared.submission.selection.supportingBytes == before.supportingBytes)
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        f.vm.executeCapture()
        #expect(f.vm.nativePhotoImportTask == nil)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["account", "generation", "cancel"], ["shutter", "context"])
    func delayedCallbacksNeverRestoreStaleCameraUI(_ change: String, boundary: String) async throws {
        let f = try await fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        if boundary == "shutter" { f.spy.capture = { await entered.open(); await release.wait(); return f.spy.bytes } }
        else { f.spy.context = { await entered.open(); await release.wait(); return EnvironmentContext(location: nil) } }
        f.vm.executeCapture()
        let task = try #require(f.vm.nativePhotoImportTask)
        await entered.wait()
        let request = try #require(f.session.items.first?.request)
        f.vm.executeCapture() // no second shutter while the first is unresolved
        if change == "account" { f.spy.account = UUID(); f.vm.handleDraftAccountChange() }
        else if change == "generation" { f.vm.draftSession.reset() }
        else { f.vm.cancelStillCapture() }
        await release.open(); await task.value
        #expect(f.spy.shutters == 1 && f.spy.saves == 0)
        #expect(f.vm.stagedCapture.images.isEmpty && f.session.needsAttention)
        #expect(f.session.items.first?.request == request && f.session.prepared == nil)
        #expect(f.vm.stagedCapture.nativePhotoDraft == f.session.identity)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func explicitCropReplacesCameraRecipeAndDiscardAcknowledgesOriginal() async throws {
        let f = try await fixture()
        f.vm.composingZoneVerticalCenter = 0.1
        f.vm.executeCapture(); await f.vm.nativePhotoImportTask?.value
        let image = try #require(f.vm.stagedCapture.images.first)
        let camera = try #require(f.session.items.first?.recipe)
        // Opening/cancelling only changes presentation; retained recipe stays exact.
        f.vm.imageToCrop = image.original
        f.vm.imageToCrop = nil
        #expect(f.session.items.first?.recipe == camera)
        #expect(f.vm.stagedCapture.images.first?.original.initialCameraVerticalCenter == 0.1)
        f.vm.confirmNativePhotoCrop(imageID: image.original.id, thumbnailData: f.spy.bytes,
            scale: 1.5, offset: CGSize(width: 2, height: 3), displaySize: 200, quarterTurns: 1)
        #expect(f.session.items.first?.recipe?.format == .stillImage)
        #expect(f.session.items.first?.recipe?.cameraVerticalCenter == nil)
        #expect(f.vm.stagedCapture.images.first?.original.initialCameraVerticalCenter == nil)
        f.vm.discardNativePhotoDraft(); await f.vm.nativePhotoDispositionTask?.value
        #expect(f.session.isDiscarded && f.vm.stagedCapture.isEmpty)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func failedShutterRetainsIntentWithoutAutomaticRetry() async throws {
        let f = try await fixture()
        f.spy.capture = { throw SharedMediaStorageFailure.unavailable }
        f.vm.executeCapture(); await f.vm.nativePhotoImportTask?.value
        let request = try #require(f.session.items.first?.request)
        f.vm.executeCapture(); await f.vm.nativePhotoImportTask?.value
        #expect(f.spy.shutters == 1 && f.spy.saves == 0 && f.session.needsAttention)
        #expect(f.session.items.first?.request == request && f.vm.stagedCapture.images.isEmpty)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }

    @MainActor
    private final class Spy {
        let bytes = PhotoPreparationTestHarness.image()
        var account: UUID?
        var shutters = 0, saves = 0
        var capture: (() async throws -> Data)?
        var context: (() async -> EnvironmentContext)?
        init(account: UUID) { self.account = account }
    }
    private struct Fixture {
        let store: SharedMediaNativeAppMetadataTests.Store
        let owner: SharedMediaNativeOriginalOwner
        let session: CaptureNativePhotoDraftSession
        let vm: CaptureWorkspaceViewModel
        let spy: Spy
    }
    private func fixture(pro: Bool = false) async throws -> Fixture {
        let store = try SharedMediaNativeAppMetadataTests.Store(), owner = try await store.open()
        try owner.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: { .noCandidates }, drainRegistered: {})))
        let session = CaptureNativePhotoDraftSession(identity: .init(ownerID: store.ownerID, packageID: store.packageID, draftGeneration: store.draft)) { owner }
        let spy = Spy(account: store.ownerID), base = CaptureWorkspaceDependencies.live(diContainer: .preview)
        let scan = CaptureScanDependencies(camera: .init(setFocusPoint: { _ in }, captureImage: {
            spy.shutters += 1
            return try await spy.capture?() ?? spy.bytes
        }, recordVideo: base.scan.camera.recordVideo, stopVideoRecording: {}, cancelVideoRecording: {}),
            context: .init(requestCurrentLocation: { nil }, lastKnownLocation: { nil }, fetchDeferredContext: { _ in
                await spy.context?() ?? EnvironmentContext(location: nil)
            }), library: .init(saveImage: { bytes, _ in #expect(bytes == spy.bytes); spy.saves += 1 }, saveVideo: { _, _ in }),
            media: .init(prepareStill: { _ in Issue.record("Legacy preparation"); return nil }, prepareVideo: base.scan.media.prepareVideo),
            canStartProScan: { pro }, feedback: .init(selection: {}, zoomOpticalStop: {}, zoomTick: {}, photoCapture: {}, videoStarted: {}, videoCompleted: {}, success: {}, error: {}))
        let submission = CaptureSubmissionDependencies(context: base.submission.context,
            admission: .init(isOnline: { Issue.record("Legacy network admission"); return false },
                canStartLocally: { _ in Issue.record("Legacy funding admission"); return false },
                preview: { _ in Issue.record("Legacy preview"); return .unavailable }, accountID: { spy.account }),
            deferredContext: base.submission.deferredContext, nativePhotoDraftFactory: { _ in session })
        let dependencies = CaptureWorkspaceDependencies(scan: scan, submission: submission, controls: base.controls,
            navigation: base.navigation, stagingToolbar: base.stagingToolbar, prepareImage: { _ in Issue.record("Legacy preparation"); return nil },
            prepareHistoricalAudio: { _ in nil }, externalImageImports: base.externalImageImports,
            downloadRefinementImage: { _ in nil }, prewarmConnections: {}, sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString }, requestNotificationAuthorization: { _ in }, feedback: base.feedback)
        return .init(store: store, owner: owner, session: session,
            vm: .init(diContainer: .preview, dependencies: dependencies, prewarmHeadersOnInit: false), spy: spy)
    }
}
