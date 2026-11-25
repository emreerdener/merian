import SwiftUI
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testPreparedFullAspectSelectionSubmitsUnchangedBytesAndIdentityFocus() async throws {
        let model = makePhotoReviewModel(count: 1)
        let image = UIGraphicsImageRenderer(size: .init(width: 400, height: 200)).image { context in
            UIColor.green.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 200))
        }
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let original = IdentifiableImage(image: image, allowsReframing: false)
        model.stagedCapture.images = [.init(compressedData: bytes, displayData: bytes, uiImage: image,
            original: original, reviewBasis: .preparedArtifact(sha256: SharedMediaAcquisitionEncoding.digest(bytes)))]
        model.presentCrop(for: 0)
        let focus = NormalizedImageFocusRegion(x: 0.4, y: 0.2, width: 0.1, height: 0.4, source: .userSelection)
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: original.id))
        let submits = await model.commitPhotoReview(commit, croppedData: bytes, scale: 1, offset: .zero,
            displaySize: 400, quarterTurns: 0, sourceSelection: focus, preservesPixels: true)
        XCTAssertTrue(submits)
        let saved = try XCTUnwrap(model.stagedCapture.images.first)
        XCTAssertEqual(saved.compressedData, bytes)
        XCTAssertEqual(saved.displayData, bytes)
        XCTAssertEqual(saved.focusRegion, focus)
        XCTAssertTrue(saved.hasPreparedReviewIdentity)
        XCTAssertNil(saved.original.lastCropDisplaySize)
    }

    func testPhotoReviewKeepsSquareSelectionInAvailableSpaceAtLargeTextSizes() async throws {
        let suiteName = "merian.tests.photo-review-layout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hardware = HardwareOrchestrator(
            appSettings: AppSettings(userDefaults: defaults, observeExternalChanges: false),
            observeSystemChanges: false
        )
        for textSize in [DynamicTypeSize.large, .accessibility3] {
            let editor = CapturePhotoEditorState(
                original: IdentifiableImage(image: makeUIImage()), allowsManualSelection: true
            )
            let host = UIHostingController(rootView: CapturePhotoReviewPage(editor: editor, onRemove: {})
                .environment(hardware)
                .environment(\.dynamicTypeSize, textSize)
                .preferredColorScheme(.dark))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 640)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            XCTAssertGreaterThan(editor.displaySize, 44)
            XCTAssertLessThanOrEqual(editor.displaySize, window.bounds.width)
            // The square must leave room for the header and instructions, even
            // when those controls grow. Selection remains in that same viewport.
            XCTAssertLessThan(editor.displaySize, window.bounds.height - 100)
            let previewAttachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            previewAttachment.name = "Photo review helper — \(textSize)"
            previewAttachment.lifetime = .keepAlways
            add(previewAttachment)
            editor.select(at: CGPoint(x: editor.displaySize / 2, y: editor.displaySize / 2))
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            let selection = try XCTUnwrap(editor.selectionViewportRect)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: editor.displaySize, height: editor.displaySize).contains(selection))
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let attachment = XCTAttachment(image: renderer.image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = "Photo review selection — \(textSize)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testPhotoReviewGeometryStaysFixedWhileNotesOpensTypesAndCloses() async throws {
        let model = makePhotoReviewModel(count: 0)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        let bytes = try XCTUnwrap(image.pngData())
        model.stagedCapture.images = [StagedImage(compressedData: bytes, displayData: bytes,
            uiImage: image, original: IdentifiableImage(image: image, isFromGallery: true))]
        model.presentCrop(for: 0)
        let review = try XCTUnwrap(model.mediaReviewSession)
        let hardware = HardwareOrchestrator(appSettings: AppSettings(), observeSystemChanges: false)
        let host = UIHostingController(rootView: CaptureMediaReviewView(workspace: model, session: review, onSubmit: {})
            .environment(hardware).preferredColorScheme(.dark))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        host.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(500))
        let baseline = try photoMarkerBounds(in: captureNotesGeometry(window, name: "Photo before notes"))
        XCTAssertGreaterThan(baseline.height, 200)
        for cycle in 0..<2 {
            XCTAssertTrue(model.openFieldNotes(inReview: review))
            let notes = try XCTUnwrap(model.fieldNotesSession)
            try await Task.sleep(for: .milliseconds(500))
            let opened = try photoMarkerBounds(in: captureNotesGeometry(window, name: "Photo behind notes \(cycle)"))
            XCTAssertEqual(opened.minY, baseline.minY, accuracy: 1)
            XCTAssertEqual(opened.height, baseline.height, accuracy: 1)
            if cycle == 0 {
                let input = try XCTUnwrap(findNotesTextView(in: host.view))
                XCTAssertTrue(input.becomeFirstResponder())
                try await Task.sleep(for: .milliseconds(500))
                let typing = try photoMarkerBounds(in: captureNotesGeometry(window, name: "Photo behind notes keyboard"))
                XCTAssertEqual(typing.minY, baseline.minY, accuracy: 1)
                XCTAssertEqual(typing.height, baseline.height, accuracy: 1)
            }
            model.closeFieldNotes(sessionID: notes.id)
            for _ in 0..<40 where model.fieldNotesSession != nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertNil(model.fieldNotesSession)
            let closed = try photoMarkerBounds(in: captureNotesGeometry(window, name: "Photo after notes \(cycle)"))
            XCTAssertEqual(closed.minY, baseline.minY, accuracy: 1)
            XCTAssertEqual(closed.height, baseline.height, accuracy: 1)
        }
    }

    func testNotesOverlayResumesNavigationWhenPersistenceDrains() async throws {
        let model = makePhotoReviewModel(count: 1)
        let review = try XCTUnwrap(model.mediaReviewSession)
        XCTAssertTrue(model.openFieldNotes(inReview: review))
        let notes = try XCTUnwrap(model.fieldNotesSession)
        var destinations: [CapturePhotoReviewAction] = []
        let hardware = HardwareOrchestrator(appSettings: AppSettings(), observeSystemChanges: false)
        let host = UIHostingController(rootView: CaptureFieldNotesOverlay(
            workspace: model, session: notes, speechManager: model.diContainer.speechManager,
            onNavigation: { destinations.append($0) }, toolbar: { Color.clear.frame(height: 74) })
            .environment(hardware).environment(\.accessibilityReduceMotion, true))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            model.initialDraftMutationTask?.cancel(); model.initialDraftMutationTask = nil
            window.isHidden = true; window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        host.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(300))
        model.navigateFromFieldNotes(.addMore)
        // Hold the production owner's observable work flag across dismissal;
        // only the mounted overlay may retry when the flag clears.
        model.initialDraftMutationTask = Task { }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(destinations.isEmpty)
        XCTAssertTrue(model.isFieldNotesOccupied)
        model.initialDraftMutationTask = nil
        for _ in 0..<40 where destinations.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(destinations, [.addMore])
        XCTAssertFalse(model.isFieldNotesOccupied)
        XCTAssertEqual(model.mediaReviewSession?.id, review.id)
    }

    private func captureNotesGeometry(_ window: UIWindow, name: String) -> UIImage {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return image
    }

    private func photoMarkerBounds(in image: UIImage) throws -> CGRect {
        let source = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        // The sheet leaves an eight-point outer margin. Sample the synthetic
        // photo there, independent of accessibility hiding and backdrop dimming.
        let column = Int(3 * image.scale)
        let rows = (0..<source.height).filter { row in
            let offset = (row * source.width + column) * 4
            return pixels[offset] > 60 && Int(pixels[offset]) > Int(pixels[offset + 1]) * 2
                && Int(pixels[offset]) > Int(pixels[offset + 2]) * 2
        }
        let first = try XCTUnwrap(rows.first), last = try XCTUnwrap(rows.last)
        return CGRect(x: 3, y: CGFloat(first) / image.scale, width: 1,
                      height: CGFloat(last - first + 1) / image.scale)
    }

    private func findNotesTextView(in view: UIView) -> UITextView? {
        if let text = view as? UITextView { return text }
        return view.subviews.lazy.compactMap { self.findNotesTextView(in: $0) }.first
    }

    func testSingleImportIdentifyCommitsOnceAndLeavesManualRetryReady() throws {
        let model = makePhotoReviewModel(count: 1)
        let imageID = model.stagedCapture.images[0].original.id
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: imageID))
        XCTAssertFalse(model.canSubmitDraft)
        XCTAssertTrue(model.finishPhotoReviewCommit(commit, succeeded: true))
        XCTAssertNil(model.imageToCrop)
        XCTAssertTrue(model.canSubmitDraft)
        XCTAssertFalse(model.isAutomaticSubmissionArmed)
        XCTAssertFalse(model.finishPhotoReviewCommit(commit, succeeded: true))
        // Admission has not occurred: committing leaves the media available for
        // the existing submission owner and, on rejection, explicit manual retry.
        XCTAssertEqual(model.stagedCapture.images.count, 1)
    }

    func testIdentifyFromAnyImportedPhotoSubmitsWholeObservationWithoutVisitingOthers() throws {
        for selected in 0..<3 {
            let model = makePhotoReviewModel(count: 3)
            let originals = model.stagedCapture.images
            model.presentCrop(for: selected)
            let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: originals[selected].original.id))
            XCTAssertTrue(model.finishPhotoReviewCommit(commit, succeeded: true))
            XCTAssertTrue(model.canSubmitDraft)
            XCTAssertEqual(model.stagedCapture.images.map(\.original.id), originals.map(\.original.id))
            XCTAssertEqual(model.stagedCapture.images.map(\.compressedData), originals.map(\.compressedData))
            XCTAssertNil(model.imageToCrop)
        }
    }

    func testFailedEditCommitBlocksSubmissionAndRetainsSelectedImport() throws {
        let model = makePhotoReviewModel(count: 2)
        let ids = model.stagedCapture.images.map(\.original.id)
        model.presentCrop(for: 1)
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: ids[1]))
        XCTAssertFalse(model.finishPhotoReviewCommit(commit, succeeded: false))
        XCTAssertEqual(model.imageToCrop?.id, ids[1])
        XCTAssertFalse(model.canSubmitDraft)
        XCTAssertNotNil(model.beginPhotoReviewCommit(imageID: ids[1]))
    }

    func testReviewCommitBlocksCompetingRemovalDiscardNotesAndDuplicateAction() throws {
        let model = makePhotoReviewModel(count: 2)
        let firstID = model.stagedCapture.images[0].original.id
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: firstID))
        XCTAssertNil(model.beginPhotoReviewCommit(imageID: firstID))
        model.presentCrop(for: 1)
        model.removeReviewedMedia(session: try XCTUnwrap(model.mediaReviewSession))
        model.requestDraftDiscard()
        XCTAssertNil(model.discardConfirmationGeneration)
        XCTAssertFalse(model.openFieldNotes())
        XCTAssertEqual(model.imageToCrop?.id, firstID)
        XCTAssertEqual(model.stagedCapture.images.count, 2)
        XCTAssertFalse(model.finishPhotoReviewCommit(commit, succeeded: false))
        XCTAssertFalse(model.areCaptureActionsBlocked)
    }

    func testStaleReviewCompletionCannotSubmitReplacementDraftOrReleaseNewCommit() throws {
        let model = makePhotoReviewModel(count: 1)
        let imageID = model.stagedCapture.images[0].original.id
        let old = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: imageID))
        model.draftSession.reset()
        XCTAssertFalse(model.finishPhotoReviewCommit(old, succeeded: true))
        let new = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: imageID))
        XCTAssertFalse(model.finishPhotoReviewCommit(old, succeeded: true))
        XCTAssertEqual(model.photoReviewCommit, new)
    }

    func testAccountReplacementImmediatelyRetiresPhotoCommitAndCancelsItsTask() throws {
        var account: UUID? = UUID()
        let model = makePhotoReviewModel(count: 1, account: { account })
        XCTAssertTrue(model.bindDraftToCurrentAccount())
        let imageID = model.stagedCapture.images[0].original.id
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: imageID))
        let work = Task { @MainActor in }
        model.replaceActiveCropTask(with: work)
        // Retained native ownership follows the early-return account transition.
        // No storage work is needed to exercise retirement of the presentation.
        model.stagedCapture.nativePhotoDraft = .init(ownerID: try XCTUnwrap(account),
            packageID: UUID(), draftGeneration: model.draftSession.generation)
        account = UUID()
        model.handleDraftAccountChange()
        XCTAssertTrue(work.isCancelled)
        XCTAssertNil(model.photoReviewCommit)
        XCTAssertFalse(model.finishPhotoReviewCommit(commit, succeeded: true))
        XCTAssertFalse(model.draftSession.hasUnresolvedWork)
    }

    func testRemovingReviewedImageKeepsRemainingImageAvailable() throws {
        let model = makePhotoReviewModel(count: 2)
        let ids = model.stagedCapture.images.map(\.original.id)
        model.removeReviewedMedia(session: try XCTUnwrap(model.mediaReviewSession))
        XCTAssertEqual(model.imageToCrop?.id, ids[1])
    }

    func testEmptyCropCannotSubmitObservation() async throws {
        let model = makePhotoReviewModel(count: 1)
        let imageID = model.stagedCapture.images[0].original.id
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: imageID))
        let submits = await model.commitPhotoReview(commit, croppedData: Data(), scale: 1,
            offset: .zero, displaySize: 200, quarterTurns: 0)
        XCTAssertFalse(submits)
        XCTAssertEqual(model.imageToCrop?.id, imageID)
        XCTAssertNil(model.photoReviewCommit)
    }

    func testMixedMediaSwitchCanSubmitWholeObservationWithUnvisitedPhotos() throws {
        let model = makePhotoReviewModel(count: 2)
        let session = try XCTUnwrap(model.mediaReviewSession)
        let image = model.stagedCapture.images[0]
        let audio = StagedAudio(filePath: "/tmp/review-test-unused-audio.m4a")
        model.stagedCapture.audios.append(audio)
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: image.original.id,
            action: .selectMedia("audio_\(audio.id)")))
        XCTAssertFalse(model.finishPhotoReviewCommit(commit, succeeded: true))
        XCTAssertEqual(model.mediaReviewSession?.id, session.id)
        XCTAssertEqual(session.selectedNodeID, "audio_\(audio.id)")
        XCTAssertNil(model.imageToCrop)
        XCTAssertTrue(model.canSubmitDraft)
        XCTAssertEqual(model.stagedCapture.physicalItemCount, 3)
        XCTAssertTrue(model.isFeaturePresentationAwaitingDismissal)
    }

    func testNestedNotesCloseRetainsReviewAndMedia() throws {
        let model = makePhotoReviewModel(count: 1)
        let review = try XCTUnwrap(model.mediaReviewSession)
        let image = model.stagedCapture.images[0]
        XCTAssertTrue(model.openFieldNotes(inReview: review))
        let notes = try XCTUnwrap(model.fieldNotesSession)
        var text = ObservationContext()
        text.freeText = "Synthetic observation"
        XCTAssertTrue(model.autosaveFieldNotes(text, session: notes))
        model.closeFieldNotes(sessionID: notes.id)
        XCTAssertTrue(model.isFieldNotesOccupied)
        model.finishFieldNotesDismissal(sessionID: UUID())
        XCTAssertTrue(model.isFieldNotesOccupied)
        model.finishFieldNotesDismissal(sessionID: notes.id)
        XCTAssertFalse(model.isFieldNotesOccupied)
        XCTAssertEqual(model.mediaReviewSession?.id, review.id)
        XCTAssertEqual(model.imageToCrop?.id, image.original.id)
        XCTAssertEqual(model.descriptionDraft.freeText, text.freeText)
        XCTAssertTrue(model.isFeaturePresentationAwaitingDismissal)
    }

    func testReviewDismissalRejectsRapidReopenAndStaleCompletion() throws {
        let model = makePhotoReviewModel(count: 1)
        let review = try XCTUnwrap(model.mediaReviewSession)
        model.dismissMediaReview(sessionID: review.id)
        // Covers retirement before content appearance as well as animated close.
        XCTAssertEqual(model.mediaReviewPresentationID, review.id)
        XCTAssertFalse(model.presentMediaReview(nodeID: review.selectedNodeID))
        XCTAssertFalse(model.finishMediaReviewDismissal(sessionID: UUID()))
        XCTAssertTrue(model.finishMediaReviewDismissal(sessionID: review.id))
        model.isFeaturePresentationAwaitingDismissal = false // outer orchestration callback
        XCTAssertTrue(model.presentMediaReview(nodeID: review.selectedNodeID))
        let replacement = try XCTUnwrap(model.mediaReviewSession)
        XCTAssertNotEqual(replacement.id, review.id)
        XCTAssertFalse(model.finishMediaReviewDismissal(sessionID: review.id))
        model.dismissMediaReview(sessionID: review.id)
        XCTAssertEqual(model.mediaReviewSession?.id, replacement.id)
    }

    func testIdentifyWithNotesAndUnvisitedImportsKeepsReviewOccupied() throws {
        let model = makePhotoReviewModel(count: 2)
        let review = try XCTUnwrap(model.mediaReviewSession)
        XCTAssertTrue(model.openFieldNotes(inReview: review))
        let notes = try XCTUnwrap(model.fieldNotesSession)
        notes.isSubmitting = true
        let id = model.stagedCapture.images[0].original.id
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: id,
            action: .identify, notesSessionID: notes.id))
        XCTAssertTrue(model.finishPhotoReviewCommit(commit, succeeded: true))
        XCTAssertEqual(model.mediaReviewSession?.id, review.id)
        XCTAssertTrue(model.isFieldNotesOccupied)
        XCTAssertTrue(model.canSubmitDraft)
    }

    func testUnchangedReviewPreservesPreparedBytesAndFocus() throws {
        let model = makePhotoReviewModel(count: 1)
        let original = model.stagedCapture.images[0]
        XCTAssertTrue(model.canPreservePhotoReviewArtifacts(imageID: original.original.id))
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: original.original.id))
        XCTAssertTrue(model.finishPhotoReviewCommit(commit, succeeded: true))
        let unchanged = model.stagedCapture.images[0]
        XCTAssertEqual(unchanged.compressedData, original.compressedData)
        XCTAssertEqual(unchanged.displayData, original.displayData)
        XCTAssertEqual(unchanged.original.id, original.original.id)
    }

    func testFailedSwitchPreservesSelectedImageAndOuterSession() throws {
        let model = makePhotoReviewModel(count: 2)
        let review = try XCTUnwrap(model.mediaReviewSession)
        let id = model.stagedCapture.images[0].original.id
        let otherID = model.stagedCapture.images[1].original.id
        let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: id,
            action: .selectMedia("img_\(otherID)")))
        XCTAssertFalse(model.finishPhotoReviewCommit(commit, succeeded: false))
        XCTAssertEqual(review.selectedNodeID, "img_\(id)")
        XCTAssertNil(model.completedPhotoReviewCommitID)
    }

    func testReviewOccupancyBlocksQueuedCaptureAndRecordingIngress() throws {
        let model = makePhotoReviewModel(count: 1)
        let review = try XCTUnwrap(model.mediaReviewSession)
        model.imageToCrop = nil // audio/video review has no photo adapter
        XCTAssertNil(model.beginDraftOperation())
        model.dismissMediaReview(sessionID: review.id)
        XCTAssertNil(model.beginDraftOperation())
        XCTAssertTrue(model.finishMediaReviewDismissal(sessionID: review.id))
        model.isFeaturePresentationAwaitingDismissal = false
        XCTAssertNotNil(model.beginDraftOperation())
    }

    func testPhotoEditorResizePreservesRelativeCropWithoutMarkingEdit() {
        var original = IdentifiableImage(image: makeUIImage())
        original.lastCropScale = 3
        original.lastCropDisplaySize = 200
        original.lastCropOffset = .init(width: 20, height: 10)
        let editor = CapturePhotoEditorState(original: original)
        editor.resize(to: 400)
        XCTAssertEqual(editor.offset.width, 40, accuracy: 0.001)
        XCTAssertEqual(editor.offset.height, 20, accuracy: 0.001)
        XCTAssertFalse(editor.hasEdits)
        editor.resize(to: 200)
        XCTAssertEqual(editor.offset.width, 20, accuracy: 0.001)
        editor.rotate(clockwise: true)
        XCTAssertTrue(editor.hasEdits)
        XCTAssertEqual(editor.quarterTurns, 1)
    }

    private func makePhotoReviewModel(count: Int, account: (@MainActor @Sendable () -> UUID?)? = nil) -> CaptureWorkspaceViewModel {
        let base = CaptureWorkspaceDependencies.live(diContainer: .preview)
        let submission = CaptureSubmissionDependencies(context: base.submission.context,
            admission: .init(isOnline: { false }, canStartLocally: { _ in false },
                preview: { _ in .unavailable }, accountID: account ?? base.submission.admission.accountID),
            deferredContext: base.submission.deferredContext)
        let dependencies = CaptureWorkspaceDependencies(scan: base.scan, submission: submission,
            controls: base.controls, navigation: base.navigation, stagingToolbar: base.stagingToolbar,
            prepareImage: { _ in nil }, prepareHistoricalAudio: { _ in nil },
            externalImageImports: base.externalImageImports, downloadRefinementImage: { _ in nil },
            prewarmConnections: {}, sharedExplorePostId: { _ in nil }, captureGoalAccountId: { $0?.uuidString },
            requestNotificationAuthorization: { _ in }, feedback: base.feedback)
        let model = CaptureWorkspaceViewModel(diContainer: .preview, dependencies: dependencies, prewarmHeadersOnInit: false)
        // Deliberately exercise ordering beyond current entitlement limits. This
        // is state-policy coverage, not permission to admit additional media.
        for index in 0..<count {
            let image = makeUIImage()
            let original = IdentifiableImage(image: image, isFromGallery: true)
            model.stagedCapture.images.append(StagedImage(compressedData: makePNGData(), displayData: makePNGData(),
                uiImage: image, original: original, addedAt: Date(timeIntervalSince1970: Double(index))))
        }
        model.presentCrop(for: 0)
        return model
    }
}
