import CoreLocation
import Photos
import Darwin
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Merian

@MainActor
struct PhotoPreparationTestHarness {
    let root: URL
    let container: ModelContainer
    let ownerID = UUID(uuidString: "00000000-0000-4000-8000-00000000c001")!
    let runtime = AuthRuntimeState()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nco1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: root.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
    }
    func owner() throws -> PhotoOriginalPreparationOwner {
        try .qualification(container: container, root: root,
            account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime))
    }
    static func image() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
    // Retain these bounded synthetic disk fixtures: SwiftData may keep SQLite
    // descriptors alive beyond ModelContainer scope. Never unlink a live store.
    func cleanup() {}
}

@Suite("P1 original ownership", .serialized)
@MainActor
struct PhotoOriginalPreparationTests {
    @Test func exact32MiBCohortAndCapPlusOneUseUnchangedLimits() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), package = UUID(), generation = UUID()
        var bytes = PhotoPreparationTestHarness.image()
        bytes.append(Data(repeating: 0, count: Int(PhotoPreparationPolicy.original) - bytes.count))
        let exactBytes = bytes
        let first = try await owner.acquire(packageID: package, draftGeneration: generation, ordinal: 0,
            sourceKind: "picker", load: { exactBytes })
        let second = try await owner.acquire(packageID: package, draftGeneration: generation, ordinal: 1,
            sourceKind: "camera", load: { exactBytes })
        #expect(try await owner.originalData(first) == exactBytes)
        #expect(try await owner.originalData(second) == exactBytes)
        let assets = try ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationAsset>())
        #expect(assets.reduce(Int64(0), { $0 + $1.byteCount }) == PhotoPreparationPolicy.originalCohort)
        let probe = h.root.appendingPathComponent("cap-probe")
        try exactBytes.write(to: probe)
        let fd = Darwin.open(probe.path, O_RDWR | O_NOFOLLOW)
        #expect(fd >= 0)
        defer { Darwin.close(fd) }
        #expect(try PhotoPreparationLockedFiles.boundedRead(fd: fd, maximumBytes: PhotoPreparationPolicy.original) == exactBytes)
        #expect(ftruncate(fd, off_t(PhotoPreparationPolicy.original + 1)) == 0)
        #expect(lseek(fd, 0, SEEK_SET) == 0)
        #expect(throws: PhotoPreparationFailure.self) {
            try PhotoPreparationLockedFiles.boundedRead(fd: fd, maximumBytes: PhotoPreparationPolicy.original)
        }
        let draft = try #require(try await owner.recover().first)
        try await owner.discard(packageID: package, revision: draft.revision)
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
    }

    @Test func exactOriginalAndIndependentDerivativesSurviveReopenAndFreeze() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let id = UUID(), generation = UUID()
        let handle = try await owner.acquire(packageID: id, draftGeneration: generation, ordinal: 0,
            sourceKind: "picker", load: { bytes })
        #expect(try await owner.originalData(handle) == bytes)
        try await owner.updateDerivatives(for: handle, ai: bytes, display: bytes)
        let resumed = try h.owner()
        let draft = try #require(try await resumed.recover().first)
        let contexts = [ObservationContext(freeText: "  Retain exactly.  ")]
        let revision = try await resumed.saveContexts(packageID: id, revision: draft.revision, contexts: contexts)
        let receipt = try await resumed.freeze(PhotoPreparationSnapshot(originals: [handle],
            expectedPackageRevision: revision, supportingContexts: contexts))
        #expect(receipt.packageID == id)
        #expect(try await resumed.recover().first?.phase == "preparedHeld")
        #expect(try await resumed.originalData(handle) == bytes)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        await #expect(throws: PhotoPreparationFailure.self) {
            try await resumed.saveContexts(packageID: id, revision: receipt.revision, contexts: [])
        }
    }

    @Test func sharedOriginalSurvivesFirstOwnerDeletion() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "picker", load: { bytes })
        let shared = try await owner.shareOriginal(handle, packageID: UUID(), draftGeneration: UUID())
        let original = try #require(try await owner.recover().first { $0.packageID == handle.packageID })
        try await owner.discard(packageID: original.packageID, revision: original.revision)
        #expect(try await owner.originalData(shared) == bytes)
        await #expect(throws: PhotoPreparationFailure.self) { try await owner.originalData(handle) }
        let survivor = try #require(try await owner.recover().first)
        try await owner.discard(packageID: survivor.packageID, revision: survivor.revision)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
    }

    @Test func interruptedCallbackRetainsReservationUntilExplicitDiscard() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), id = UUID()
        await #expect(throws: CancellationError.self) {
            try await owner.acquire(packageID: id, draftGeneration: UUID(), ordinal: 0,
                sourceKind: "inbox", sourceByteLiability: PhotoPreparationPolicy.original, sourceIdentity: "synthetic-inbox",
                load: { throw CancellationError() })
        }
        let context = ModelContext(h.container)
        let lease = try #require(context.fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        #expect(lease.reservedByteCount == PhotoPreparationPolicy.original)
        #expect(lease.allocatedByteCount == PhotoPreparationPolicy.original)
        let restored = try #require(try await h.owner().recover().first)
        #expect(restored.needsAttention)
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
                sourceKind: "picker", load: { Data() })
        }
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.discard(packageID: id, revision: restored.revision)
        }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
        try await owner.returnSource(packageID: id, identity: "synthetic-inbox") {}
        try await owner.discard(packageID: id, revision: restored.revision)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
    }

    @Test func forgedHandleAndStaleRevisionCannotFreeze() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "camera", load: { bytes })
        let forged = PhotoOriginalReference(ownerID: UUID(), packageID: handle.packageID,
            referenceID: handle.referenceID, assetID: handle.assetID, assetGeneration: handle.assetGeneration,
            draftGeneration: handle.draftGeneration, referenceRevision: 0)
        await #expect(throws: PhotoPreparationFailure.self) { try await owner.originalData(forged) }
        try await owner.updateDerivatives(for: handle, ai: bytes, display: bytes)
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.freeze(PhotoPreparationSnapshot(originals: [handle], expectedPackageRevision: 0, supportingContexts: []))
        }
    }

    @Test func missingAndUnknownFilesBlockRecoveryWithoutReleasingOwnership() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "picker", load: { bytes })
        let asset = try #require(ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        try FileManager.default.removeItem(at: h.root.appendingPathComponent("PhotoPreparation/" + asset.fileToken))
        await #expect(throws: PhotoPreparationFailure.self) { try await owner.originalData(handle) }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        try bytes.write(to: h.root.appendingPathComponent("PhotoPreparation/unknown"))
        await #expect(throws: PhotoPreparationFailure.self) { try await owner.recover() }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
    }

    @Test func limitsRejectBeforeProviderCallbackAndUnsupportedComposition() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner()
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
                sourceKind: "picker", maximumBytes: PhotoPreparationPolicy.original + 1,
                load: { Issue.record("Oversized reservation reached provider"); return Data() })
        }
        #expect(throws: PhotoPreparationFailure.self) {
            try PhotoOriginalPreparationOwner.qualification(container: h.container, root: h.root,
                account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), competingAllocators: ["ordinaryQueue"])
        }
        #expect(throws: PhotoPreparationFailure.self) { try PhotoPreparationPolicy.add([Int64.max, 1]) }
        #expect(throws: PhotoPreparationFailure.self) {
            try PhotoPreparationPolicy.contexts([ObservationContext(freeText: String(repeating: "x", count: 8_193))])
        }
    }
}

@Suite("P1 capture lifecycle", .serialized)
@MainActor
struct CapturePhotoPreparationTests {
    @Test func photoPreparationSeamPersistsCropReopensAndNeverCallsAdmission() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let access = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        let bytes = PhotoPreparationTestHarness.image()
        let cg = try #require(UIImage(data: bytes)?.cgImage)
        let prepared = PreparedStagedImage(compressedData: bytes, displayData: bytes,
            historicalContext: nil, previewCGImage: SendableCGImage(image: cg), focusRegion: nil)
        var image = try await access.acquire(source: "picker", load: { bytes }, prepare: { _ in prepared })
        let handle = try #require(image.photoOriginalReference)
        var original = image.original
        original.lastCropScale = 2
        original.lastCropOffset = CGSize(width: 3, height: -4)
        original.lastCropQuarterTurns = 1
        image = image.replacing(original: original)
        let context = ObservationContext(freeText: "  Saved supporting details.  ")
        try await access.persist(images: [image], contexts: [context])
        let resumed = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        var admissionCalls = 0
        let viewModel = makeViewModel(spy: CapturePhotoPreparationSpy(), admissionIsOnline: true,
            admissionPreview: { admissionCalls += 1; return .unavailable }, accountID: { h.ownerID },
            photoOriginalPreparation: resumed, prepareImage: { _ in prepared })
        await viewModel.restorePhotoPreparationDraft(packageID: access.packageID)
        let reopened = try #require(viewModel.stagedCapture.images.first)
        #expect(!viewModel.draftSession.hasUnresolvedWork)
        #expect(reopened.photoOriginalReference == handle)
        #expect(reopened.original.lastCropScale == 2 && reopened.original.lastCropQuarterTurns == 1)
        #expect(reopened.original.lastCropOffset == CGSize(width: 3, height: -4))
        #expect(viewModel.stagedCapture.observationContexts.first?.context.freeText == context.freeText)
        #expect(try await resumed.owner.originalData(handle) == bytes)
        await viewModel.submitPhotoPreparationDraft(resumed)
        #expect(resumed.receipt != nil)
        #expect(admissionCalls == 0)
        #expect(viewModel.stagedCapture.images.count == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        await #expect(throws: PhotoPreparationFailure.self) { try await resumed.persist(images: viewModel.stagedCapture.images, contexts: []) }
    }

    @Test func interruptedInboxDraftReturnsSourceToInboxBeforeDiscard() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let inbox = ExternalImageImportStore(rootURL: h.root.appendingPathComponent("inbox"))
        let source = h.root.appendingPathComponent("source.png")
        let bytes = PhotoPreparationTestHarness.image()
        try bytes.write(to: source)
        let item = try await inbox.stageIncomingImage(at: source)
        let access = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        await #expect(throws: CancellationError.self) {
            try await access.acquire(source: "inbox", sourceByteLiability: Int64(bytes.count), sourceIdentity: item.id.uuidString,
                load: { throw CancellationError() }, prepare: { _ in nil })
        }
        let resumed = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        let vm = makeViewModel(spy: CapturePhotoPreparationSpy(), accountID: { h.ownerID },
            photoOriginalPreparation: resumed, inbox: inbox)
        await vm.restorePhotoPreparationDraft(packageID: access.packageID)
        #expect(resumed.needsRecovery)
        #expect(!vm.draftSession.hasUnresolvedWork)
        vm.discardPhotoPreparationDraft(resumed)
        for _ in 0..<500 where vm.isCheckingScanAdmission { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!vm.isCheckingScanAdmission)
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        #expect(await inbox.pendingImports().contains(item))
        let retainedURL = try #require(await inbox.fileURL(for: item))
        #expect(try PhotoOriginalPickerTransfer.readInbox(retainedURL) == bytes)
    }

    @Test func missingOriginalAfterReopenBlocksOrdinarySubmissionAndRetainsDetails() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let access = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        let bytes = PhotoPreparationTestHarness.image()
        let cg = try #require(UIImage(data: bytes)?.cgImage)
        let prepared = PreparedStagedImage(compressedData: bytes, displayData: bytes,
            historicalContext: nil, previewCGImage: SendableCGImage(image: cg), focusRegion: nil)
        let image = try await access.acquire(source: "picker", load: { bytes }, prepare: { _ in prepared })
        let handle = try #require(image.photoOriginalReference)
        let details = ObservationContext(freeText: " Keep these details. ")
        try await access.persist(images: [image], contexts: [details])
        let asset = try #require(ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationAsset>()).first { $0.id == handle.assetID })
        try FileManager.default.removeItem(at: h.root.appendingPathComponent("PhotoPreparation/" + asset.fileToken))
        let resumed = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        var admissionCalls = 0
        let vm = makeViewModel(spy: CapturePhotoPreparationSpy(), admissionIsOnline: true,
            admissionPreview: { admissionCalls += 1; return .unavailable }, accountID: { h.ownerID },
            photoOriginalPreparation: resumed, prepareImage: { _ in prepared })
        await vm.restorePhotoPreparationDraft(packageID: access.packageID)
        #expect(resumed.needsRecovery)
        #expect(vm.stagedCapture.images.isEmpty)
        #expect(vm.stagedCapture.observationContexts.map(\.context) == [details])
        await vm.submitStagedCapture(modelContext: ModelContext(h.container))
        #expect(resumed.receipt == nil && admissionCalls == 0)
        #expect(vm.stagedCapture.observationContexts.map(\.context) == [details])
        #expect(try PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test(arguments: [false, true])
    func inboxPreflightPreservesManifestAndDraftForMissingOrOversizedSource(oversized: Bool) async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let root = h.root.appendingPathComponent("inbox")
        let inbox = ExternalImageImportStore(rootURL: root)
        let source = h.root.appendingPathComponent("source.png")
        try PhotoPreparationTestHarness.image().write(to: source)
        let item = try await inbox.stageIncomingImage(at: source)
        let url = try #require(await inbox.fileURL(for: item))
        if oversized {
            let fd = Darwin.open(url.path, O_WRONLY | O_NOFOLLOW)
            #expect(fd >= 0)
            defer { Darwin.close(fd) }
            #expect(ftruncate(fd, off_t(PhotoPreparationPolicy.original + 1)) == 0)
        } else { try FileManager.default.removeItem(at: url) }
        let manifest = root.appendingPathComponent("pending-image-imports.json")
        let before = try Data(contentsOf: manifest)
        let access = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        var admissionCalls = 0
        let vm = makeViewModel(spy: CapturePhotoPreparationSpy(), admissionIsOnline: true,
            admissionPreview: { admissionCalls += 1; return .unavailable }, accountID: { h.ownerID },
            photoOriginalPreparation: access,
            prepareImage: { _ in Issue.record("Rejected inbox source reached preparation"); return nil }, inbox: inbox)
        vm.descriptionDraft = ObservationContext(freeText: "Retain my draft")
        let result = await vm.importPhotoPreparationInbox(item, access: access)
        if case .temporarilyBlocked = result {} else { Issue.record("Invalid source was not blocked") }
        #expect(try Data(contentsOf: manifest) == before)
        #expect(vm.descriptionDraft.freeText == "Retain my draft")
        #expect(vm.stagedCapture.images.isEmpty && admissionCalls == 0 && access.receipt == nil)
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        if oversized {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attrs[.size] as? NSNumber)?.int64Value == PhotoPreparationPolicy.original + 1)
        }
    }

    @Test func automaticSubmissionFreezesOnlyLocalPackage() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let access = CapturePhotoOriginalPreparationAccess(owner: try h.owner())
        let bytes = PhotoPreparationTestHarness.image()
        let cg = try #require(UIImage(data: bytes)?.cgImage)
        let prepared = PreparedStagedImage(compressedData: bytes, displayData: bytes,
            historicalContext: nil, previewCGImage: SendableCGImage(image: cg), focusRegion: nil)
        var admissionCalls = 0
        let vm = makeViewModel(spy: CapturePhotoPreparationSpy(), admissionIsOnline: true,
            admissionPreview: { admissionCalls += 1; return .unavailable }, accountID: { h.ownerID }, photoOriginalPreparation: access)
        let oldSetting = vm.diContainer.appSettings.autoSubmitScans
        defer { vm.diContainer.appSettings.autoSubmitScans = oldSetting }
        vm.diContainer.appSettings.autoSubmitScans = true
        let operation = try #require(vm.beginDraftOperation())
        vm.stagedCapture.images = [try await access.acquire(source: "camera", load: { bytes }, prepare: { _ in prepared })]
        vm.completeDraftOperation(operation, succeeded: true)
        #expect(vm.isAutomaticStagedSubmissionPending)
        await vm.submitStagedCapture(modelContext: ModelContext(h.container))
        #expect(access.receipt != nil && admissionCalls == 0)
        #expect(!vm.isAutomaticStagedSubmissionPending)
        #expect(vm.stagedCapture.images.count == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    private func makeViewModel(
        spy: CapturePhotoPreparationSpy,
        captureImage: @escaping @MainActor @Sendable () async throws -> Data = {
            Data()
        },
        prepareStill: @escaping @Sendable (CaptureScanStillPreparationRequest) async throws -> PreparedCaptureScanStill? = { _ in nil },
        recording: CameraVideoRecording? = nil,
        recordingError: NSError? = nil,
        prepareVideo: @escaping @Sendable (CaptureScanVideoPreparationRequest) async throws -> PreparedCaptureScanVideo = { _ in throw CancellationError() },
        admissionIsOnline: Bool = false,
        admissionPreview: @escaping @MainActor @Sendable () async ->
            ScanAdmissionPreviewResult = {
                .unavailable
            },
        isLibraryAccessBlocked: @escaping @MainActor @Sendable () -> Bool = { false },
        accountID: @escaping @MainActor @Sendable () -> UUID? = { nil },
        photoOriginalPreparation: CapturePhotoOriginalPreparationAccess? = nil,
        prepareImage: @escaping PreparedStagedImageLoader = { _ in nil },
        inbox: ExternalImageImportStore? = nil
    ) -> CaptureWorkspaceViewModel {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scanDependencies = CaptureScanDependencies(
            camera: CaptureScanCameraDependencies(
                setFocusPoint: { spy.focusPoints.append($0) },
                captureImage: captureImage,
                recordVideo: { _, onStarted in
                    spy.recordVideoCount += 1
                    if let recordingError { throw recordingError }
                    guard let recording else { throw CancellationError() }
                    onStarted?()
                    return recording
                },
                stopVideoRecording: { spy.stopVideoCount += 1 },
                cancelVideoRecording: { spy.cancelVideoCount += 1 }
            ),
            context: CaptureScanContextDependencies(
                requestCurrentLocation: { nil },
                lastKnownLocation: { nil },
                fetchDeferredContext: {
                    EnvironmentContext(location: $0)
                }
            ),
            library: CaptureScanLibraryDependencies(
                saveImage: { _, _ in spy.saveImageCount += 1 },
                saveVideo: { _, _ in }
            ),
            media: CaptureScanMediaDependencies(
                prepareStill: { request in
                    await MainActor.run {
                        spy.prepareStillCount += 1
                    }
                    return try await prepareStill(request)
                },
                prepareVideo: prepareVideo
            ),
            canStartProScan: { true },
            feedback: CaptureScanFeedbackDependencies(
                selection: { spy.selectionCount += 1 },
                zoomOpticalStop: { spy.zoomOpticalStopCount += 1 },
                zoomTick: { spy.zoomTickCount += 1 },
                photoCapture: {},
                videoStarted: {},
                videoCompleted: {},
                success: {},
                error: {}
            )
        )
        let submissionDependencies = CaptureSubmissionDependencies(
            context: CaptureSubmissionContextDependencies(
                lastKnownLocation: { nil },
                fetchDeferredContext: {
                    EnvironmentContext(location: $0)
                }
            ),
            admission: CaptureSubmissionAdmissionDependencies(
                isOnline: { admissionIsOnline },
                canStartLocally: { _ in true },
                preview: { _ in await admissionPreview() },
                accountID: accountID,
                isLibraryAccessBlocked: isLibraryAccessBlocked
            ),
            deferredContext: CaptureSubmissionDeferredContextService(
                persistLocally: { _, _ in },
                endpoint: CaptureSubmissionDeferredContextEndpoint(
                    update: { _, _ in }
                ),
                waitBeforeRetry: {}
            )
        )
        var dependencies = CaptureWorkspaceDependencies(
            scan: scanDependencies,
            submission: submissionDependencies,
            controls: CaptureControlDependencies(
                isVisualCaptureAllowed: { true },
                isProVideoAvailable: { true },
                dismissKeyboard: {},
                trackProVideoPaywallImpression: {},
                performHapticFeedback: { _ in }
            ),
            navigation: CaptureNavigationDependencies(
                loadBadgeSnapshot: { _ in
                    CaptureNavigationBadgeSnapshot(
                        hasUnseenExternalPost: false,
                        unreadNotificationCount: nil
                    )
                },
                setHasUnseenExplorePost: { _ in },
                performRouteFeedback: {}
            ),
            stagingToolbar: CaptureStagingToolbarDependencies(
                photoLibrary: PHPhotoLibrary.shared(),
                dismissKeyboard: {},
                performCancelFeedback: {},
                hasShownTooltip: { true },
                markTooltipShown: {},
                hasShownSubmitTooltip: { true },
                markSubmitTooltipShown: {}
            ),
            prepareImage: prepareImage,
            prepareHistoricalAudio: { _ in nil },
            externalImageImports: inbox ?? ExternalImageImportStore(rootURL: rootURL),
            downloadRefinementImage: { _ in nil },
            prewarmConnections: {},
            sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString },
            requestNotificationAuthorization: { _ in },
            feedback: CaptureWorkspaceFeedback(
                selection: { _ in },
                sheet: { _ in },
                medium: {},
                error: {}
            )
        )

        dependencies.photoOriginalPreparation = photoOriginalPreparation
        return CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.preview,
            dependencies: dependencies,
            prewarmHeadersOnInit: false
        )
    }

}

@MainActor
private final class CapturePhotoPreparationSpy {
    var focusPoints: [CGPoint] = []
    var selectionCount = 0
    var zoomOpticalStopCount = 0
    var zoomTickCount = 0
    var stopVideoCount = 0
    var cancelVideoCount = 0
    var recordVideoCount = 0
    var saveImageCount = 0
    var prepareStillCount = 0
}
