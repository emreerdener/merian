import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testCropAndNotesCannotAcquireEachOthersPresentation() throws {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        let image = makeUIImage()
        model.stagedCapture.images = [StagedImage(compressedData: makePNGData(),
            displayData: makePNGData(), uiImage: image, original: IdentifiableImage(image: image))]
        model.imageToCrop = IdentifiableImage(image: image)
        XCTAssertFalse(model.openFieldNotes())
        model.imageToCrop = nil
        XCTAssertTrue(model.openFieldNotes())
        let session = try XCTUnwrap(model.fieldNotesSession)
        // A queued thumbnail tap cannot mount a crop while the editor owns input.
        model.presentCrop(for: -1)
        model.presentCrop(for: 0)
        XCTAssertNil(model.imageToCrop)
        model.closeFieldNotes(sessionID: session.id)
        model.finishFieldNotesDismissal(sessionID: session.id)
    }

    func testAccountReplacementRetiresNotesAndRejectsLateInput() throws {
        var account: UUID? = UUID()
        let base = CaptureWorkspaceDependencies.live(diContainer: .preview)
        let submission = CaptureSubmissionDependencies(context: base.submission.context,
            admission: .init(isOnline: { false }, canStartLocally: { _ in false },
                preview: { _ in .unavailable }, accountID: { account }),
            deferredContext: base.submission.deferredContext)
        let dependencies = CaptureWorkspaceDependencies(scan: base.scan, submission: submission,
            controls: base.controls, navigation: base.navigation, stagingToolbar: base.stagingToolbar,
            prepareImage: { _ in nil }, prepareHistoricalAudio: { _ in nil },
            externalImageImports: base.externalImageImports, downloadRefinementImage: { _ in nil },
            prewarmConnections: {}, sharedExplorePostId: { _ in nil }, captureGoalAccountId: { $0?.uuidString },
            requestNotificationAuthorization: { _ in }, feedback: base.feedback)
        let model = CaptureWorkspaceViewModel(diContainer: .preview, dependencies: dependencies, prewarmHeadersOnInit: false)
        model.stagedCapture.audios = [StagedAudio(filePath: "notes-test.wav")]
        XCTAssertTrue(model.openFieldNotes())
        let session = try XCTUnwrap(model.fieldNotesSession)
        XCTAssertTrue(model.autosaveFieldNotes(ObservationContext(freeText: "Private draft"), session: session))
        account = UUID()
        XCTAssertFalse(model.autosaveFieldNotes(ObservationContext(freeText: "Late callback"), session: session))
        model.handleDraftAccountChange()
        XCTAssertFalse(session.isPresented)
        XCTAssertTrue(model.descriptionDraft.isEmpty)
        XCTAssertTrue(model.isFieldNotesOccupied)
        model.finishFieldNotesDismissal(sessionID: session.id)
        XCTAssertFalse(model.isFieldNotesOccupied)
    }

    func testQueuedDiscardCannotClearAnOpenOrDismissingNotesSession() throws {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        model.stagedCapture.audios = [StagedAudio(filePath: "notes-test.wav")]
        let generation = model.draftSession.generation
        XCTAssertTrue(model.openFieldNotes())
        let session = try XCTUnwrap(model.fieldNotesSession)
        XCTAssertTrue(model.autosaveFieldNotes(ObservationContext(freeText: "Keep these notes"), session: session))
        model.requestDraftDiscard()
        XCTAssertNil(model.discardConfirmationGeneration)
        XCTAssertFalse(model.confirmDraftDiscard(generation: generation))
        model.closeFieldNotes(sessionID: session.id)
        XCTAssertFalse(model.confirmDraftDiscard(generation: generation))
        XCTAssertEqual(model.stagedCapture.physicalItemCount, 1)
        XCTAssertEqual(model.descriptionDraft.freeText, "Keep these notes")
        model.finishFieldNotesDismissal(sessionID: session.id)
        model.requestDraftDiscard()
        XCTAssertEqual(model.discardConfirmationGeneration, generation)
        XCTAssertTrue(model.confirmDraftDiscard(generation: generation))
    }

    func testPendingNotesWaitForRootPresentationAndPickerToRelease() {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        model.stagedCapture.audios = [StagedAudio(filePath: "loaded.wav")]
        model.isPhotoLibraryPresented = true
        model.requestFieldNotesWhenReady()
        XCTAssertNil(model.fieldNotesSession)
        XCTAssertNotNil(model.pendingFieldNotesIntent)
        model.isPhotoLibraryPresented = false
        model.isFeaturePresentationAwaitingDismissal = true
        model.resumePendingFieldNotesIfPossible()
        XCTAssertNil(model.fieldNotesSession)
        XCTAssertFalse(model.openFieldNotes())
        // Only the outer preview dismissal releases the presentation barrier.
        model.isFeaturePresentationAwaitingDismissal = false
        model.resumePendingFieldNotesIfPossible()
        XCTAssertNotNil(model.fieldNotesSession)
        if let session = model.fieldNotesSession {
            model.closeFieldNotes(sessionID: session.id)
            model.finishFieldNotesDismissal(sessionID: session.id)
        }
    }

    func testPendingFieldNotesWaitsForMediaAndCannotOpenAReplacementDraft() {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        model.requestFieldNotesWhenReady()
        XCTAssertNil(model.fieldNotesSession)
        model.stagedCapture.audios = [StagedAudio(filePath: "loaded.wav")]
        model.resumePendingFieldNotesIfPossible()
        XCTAssertNotNil(model.fieldNotesSession)
        if let session = model.fieldNotesSession {
            model.closeFieldNotes(sessionID: session.id)
            model.finishFieldNotesDismissal(sessionID: session.id)
        }
        model.stagedCapture.audios.removeAll()
        model.requestFieldNotesWhenReady()
        model.draftSession.reset()
        model.stagedCapture.audios = [StagedAudio(filePath: "successor.wav")]
        model.resumePendingFieldNotesIfPossible()
        XCTAssertNil(model.fieldNotesSession)
        XCTAssertNil(model.pendingFieldNotesIntent)
    }

    func testFieldNotesRequiresMediaAndRetainsOccupancyThroughMatchingDismissal() throws {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        XCTAssertFalse(model.openFieldNotes())
        model.stagedCapture.audios = [StagedAudio(filePath: "notes-test.wav")]
        XCTAssertTrue(model.openFieldNotes())
        let first = try XCTUnwrap(model.fieldNotesSession)
        XCTAssertTrue(model.autosaveFieldNotes(ObservationContext(freeText: "Rustling in reeds"), session: first))
        XCTAssertTrue(model.areCaptureActionsBlocked)
        XCTAssertNil(model.beginDraftOperation())
        model.closeFieldNotes(sessionID: first.id)
        XCTAssertTrue(model.isFieldNotesOccupied)
        XCTAssertFalse(model.openFieldNotes())
        XCTAssertFalse(model.autosaveFieldNotes(ObservationContext(freeText: "Late callback"), session: first))
        model.finishFieldNotesDismissal(sessionID: UUID())
        XCTAssertTrue(model.isFieldNotesOccupied)
        model.finishFieldNotesDismissal(sessionID: first.id)
        XCTAssertFalse(model.isFieldNotesOccupied)
        XCTAssertTrue(model.openFieldNotes())
        let second = try XCTUnwrap(model.fieldNotesSession)
        model.finishFieldNotesDismissal(sessionID: first.id)
        XCTAssertEqual(model.fieldNotesSession?.id, second.id)
        XCTAssertEqual(model.descriptionDraft.freeText, "Rustling in reeds")
        model.closeFieldNotes(sessionID: second.id)
        model.finishFieldNotesDismissal(sessionID: second.id)
    }

    func testFieldNotesRejectsReplacedDraftAndKeepsOriginalMutationGuard() throws {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        model.stagedCapture.audios = [StagedAudio(filePath: "notes-test.wav")]
        XCTAssertTrue(model.openFieldNotes())
        let session = try XCTUnwrap(model.fieldNotesSession)
        model.isCheckingScanAdmission = true
        XCTAssertFalse(model.autosaveFieldNotes(ObservationContext(freeText: "During admission"), session: session))
        model.isCheckingScanAdmission = false
        model.draftSession.reset()
        XCTAssertFalse(model.autosaveFieldNotes(ObservationContext(freeText: "Wrong generation"), session: session))
        model.invalidateFieldNotes(clearProgress: true)
        model.finishFieldNotesDismissal(sessionID: session.id)
    }

    func testPromptProgressSurvivesCloseAndFinalMediaRemovalClearsSupplement() throws {
        let model = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        model.stagedCapture.audios = [StagedAudio(filePath: "notes-test.wav")]
        XCTAssertTrue(model.openFieldNotes())
        let session = try XCTUnwrap(model.fieldNotesSession)
        session.prompts.advanceQuestion()
        let progress = session.prompts.progress
        XCTAssertTrue(model.autosaveFieldNotes(ObservationContext(freeText: "Near water"), session: session))
        model.closeFieldNotes(sessionID: session.id)
        model.finishFieldNotesDismissal(sessionID: session.id)
        XCTAssertTrue(model.openFieldNotes())
        let reopened = try XCTUnwrap(model.fieldNotesSession)
        XCTAssertEqual(reopened.prompts.progress, progress)
        // A queued removal is blocked through the editor's outer dismissal.
        model.removeStagedAudio(at: 0)
        XCTAssertEqual(model.stagedCapture.physicalItemCount, 1)
        model.closeFieldNotes(sessionID: reopened.id)
        model.removeStagedAudio(at: 0)
        XCTAssertEqual(model.stagedCapture.physicalItemCount, 1)
        model.finishFieldNotesDismissal(sessionID: reopened.id)
        model.removeStagedAudio(at: 0)
        XCTAssertTrue(model.descriptionDraft.isEmpty)
        XCTAssertNil(model.fieldNotesPromptProgress)
        XCTAssertFalse(reopened.isPresented)
        XCTAssertFalse(model.autosaveFieldNotes(ObservationContext(freeText: "Late speech"), session: reopened))
    }
}
