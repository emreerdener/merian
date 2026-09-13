import SwiftData
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    private func makeDescriptionRefinementWorkspace() -> CaptureWorkspaceViewModel {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.baseRefinementContext = RefinementScanContext(record: LocalScanRecord(
            speciesId: "refinement-description",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly"
        ))
        viewModel.commitPreparedStagedImages([makePreparedStagedImage()])
        return viewModel
    }

    func testAnalyzeIncludesRefinementDraftWithOriginalImage() {
        let viewModel = makeDescriptionRefinementWorkspace()
        var draft = ObservationContext(freeText: "Look at the wing edges")

        XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))

        XCTAssertTrue(draft.isEmpty)
        XCTAssertEqual(viewModel.stagedCapture.totalItemCount, 2)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.first?.context.freeText, "Look at the wing edges")
        XCTAssertEqual(viewModel.availableStagedCaptureSlots, 1)
    }

    func testRefinementDescriptionDoesNotConsumeAdditionalMediaSlotInEitherOrder() {
        for descriptionFirst in [false, true] {
            for addsAudio in [false, true] {
                let viewModel = makeDescriptionRefinementWorkspace()
                var draft = ObservationContext(freeText: "Look at the wing edges")
                if descriptionFirst {
                    XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))
                    XCTAssertEqual(viewModel.availableStagedCaptureSlots, 1)
                }
                if addsAudio {
                    viewModel.stagedCapture.audios.append(StagedAudio(filePath: "additional.wav"))
                } else {
                    XCTAssertEqual(viewModel.commitPreparedStagedImages([makePreparedStagedImage()]), 1)
                }
                XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))

                XCTAssertTrue(draft.isEmpty)
                XCTAssertEqual(viewModel.stagedCapture.totalItemCount, 3)
                XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
                XCTAssertFalse(viewModel.hasAvailableStagedCaptureSlot)
                XCTAssertTrue(viewModel.canUseCaptureControls(in: .describe))
                XCTAssertFalse(viewModel.canUseCaptureControls(in: .visual))
                XCTAssertFalse(viewModel.canUseCaptureControls(in: .audio))
                XCTAssertEqual(viewModel.commitPreparedStagedImages([makePreparedStagedImage()]), 0)
                let payload = CaptureSubmissionPayload(nodes: viewModel.stagedCapture.orderedNodes)
                XCTAssertEqual(payload.mediaTimeline.count, 3)
                XCTAssertEqual(payload.mediaTimeline.observationContexts, [
                    ObservationContext(freeText: "Look at the wing edges")
                ])
            }
        }
    }

    func testPlusThenAnalyzeUpdatesSupplementWithoutDuplicatingOrReordering() async throws {
        let viewModel = makeDescriptionRefinementWorkspace()
        viewModel.commitPreparedStagedImages([makePreparedStagedImage()])
        XCTAssertFalse(viewModel.hasAvailableStagedCaptureSlot)
        let context = try makeModelContext()
        let firstText = ObservationContext(freeText: "First description")
        let stagedFirst = await viewModel.submitDescribe(observationContext: firstText, modelContext: context)
        XCTAssertTrue(stagedFirst)
        XCTAssertEqual(viewModel.stagedCapture.totalItemCount, 3)
        let addedAt = viewModel.stagedCapture.observationContexts.first?.addedAt
        var emptyDraft = ObservationContext()
        XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &emptyDraft))
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)

        viewModel.stagedCapture.lastSubmitTime = nil
        let editedText = ObservationContext(freeText: "Updated description")
        let stagedEdit = await viewModel.submitDescribe(observationContext: editedText, modelContext: context)
        XCTAssertTrue(stagedEdit)
        var draft = ObservationContext(freeText: "Final description")
        XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.first?.addedAt, addedAt)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.first?.context.freeText, "Final description")
    }

    func testRefinementDraftPreservesHistoricalDescriptionAndRemovalReleasesAssociation() {
        let viewModel = makeDescriptionRefinementWorkspace()
        viewModel.stagedCapture.images.removeAll()
        let historical = ObservationContext(freeText: "Original observation")
        viewModel.stagedCapture.observationContexts = [StagedObservationContext(context: historical)]
        XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(
            ObservationContext(freeText: "Please reconsider")
        ), .staged)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.map(\.context), [
            historical, ObservationContext(freeText: "Please reconsider")
        ])
        viewModel.stagedCapture.observationContexts.remove(at: 1)
        XCTAssertNil(viewModel.stagedCapture.refinementSupplementIndex)
        XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(
            ObservationContext(freeText: "Replacement note")
        ), .staged)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.first?.context, historical)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 2)
    }

    func testTraySaveSupersedesPendingRefinementDraftWithoutChangingOrder() throws {
        let viewModel = makeDescriptionRefinementWorkspace()
        XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(
            ObservationContext(freeText: "Staged note")
        ), .staged)
        let index = try XCTUnwrap(viewModel.stagedCapture.refinementSupplementIndex)
        let addedAt = viewModel.stagedCapture.observationContexts[index].addedAt
        var draft = ObservationContext(freeText: "Older pending editor draft")

        viewModel.saveStagedDescription(at: index, text: " Latest tray edit ", pendingDraft: &draft)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts[index].context.freeText, "Latest tray edit")
        XCTAssertEqual(viewModel.stagedCapture.observationContexts[index].addedAt, addedAt)
        XCTAssertEqual(viewModel.stagedCapture.refinementSupplementIndex, index)
    }

    func testTrayRemovalCannotBeUndoneByPendingRefinementDraft() throws {
        for savesEmptyText in [false, true] {
            let viewModel = makeDescriptionRefinementWorkspace()
            XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(
                ObservationContext(freeText: "Staged note")
            ), .staged)
            let index = try XCTUnwrap(viewModel.stagedCapture.refinementSupplementIndex)
            var draft = ObservationContext(freeText: "Older pending editor draft")
            if savesEmptyText {
                viewModel.saveStagedDescription(at: index, text: " ", pendingDraft: &draft)
            } else {
                viewModel.removeStagedDescription(at: index, pendingDraft: &draft)
            }
            XCTAssertTrue(draft.isEmpty)
            XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))
            XCTAssertTrue(viewModel.stagedCapture.observationContexts.isEmpty)
            XCTAssertNil(viewModel.stagedCapture.refinementSupplementIndex)
        }
    }

    func testHistoricalTrayEditsDoNotDiscardPendingSupplement() {
        let viewModel = makeDescriptionRefinementWorkspace()
        viewModel.stagedCapture.images.removeAll()
        viewModel.stagedCapture.observationContexts = [StagedObservationContext(
            context: ObservationContext(freeText: "Historical evidence")
        )]
        var draft = ObservationContext(freeText: "New supplementary draft")
        viewModel.saveStagedDescription(at: 0, text: "Edited historical evidence", pendingDraft: &draft)
        XCTAssertEqual(draft.freeText, "New supplementary draft")
        viewModel.removeStagedDescription(at: 0, pendingDraft: &draft)
        XCTAssertEqual(draft.freeText, "New supplementary draft")
    }

    func testReplacementRefinementDiscardsPreviousTargetMediaAndSupplement() {
        let viewModel = makeDescriptionRefinementWorkspace()
        XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(
            ObservationContext(freeText: "Old target supplement")
        ), .staged)
        let replacementDescription = ObservationContext(freeText: "Replacement original evidence")
        let snapshot = CapturedMediaSnapshot(items: [.description(replacementDescription)])
        let replacement = LocalScanRecord(
            speciesId: "replacement", scientificName: "Strix varia", commonName: "Barred Owl",
            capturedMediaJSON: snapshot.jsonString
        )

        XCTAssertTrue(viewModel.startRefinementScan(from: replacement, initialDescription: "New draft"))

        XCTAssertEqual(viewModel.baseRefinementContext?.scanId, replacement.id)
        XCTAssertEqual(viewModel.refinementInitialDescriptionDraft, "New draft")
        XCTAssertTrue(viewModel.stagedCapture.images.isEmpty)
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.map(\.context), [replacementDescription])
        XCTAssertNil(viewModel.stagedCapture.refinementSupplementIndex)
        var draft = ObservationContext(freeText: "New target supplement")
        XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.map(\.context), [
            replacementDescription, ObservationContext(freeText: "New target supplement")
        ])
        viewModel.cancelRefinementStaging()
        XCTAssertNil(viewModel.stagedCapture.refinementSupplementIndex)
        viewModel.clearStagedCaptureAndCropState()
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
    }

    func testRejectedDescriptionDoesNotClearDraftOrStartSubmission() {
        let viewModel = makeDescriptionRefinementWorkspace()
        // Simulate an invalid/full draft arriving from an overlapping staging operation.
        viewModel.stagedCapture.audios = [
            StagedAudio(filePath: "first.wav"), StagedAudio(filePath: "second.wav")
        ]
        var draft = ObservationContext(freeText: "Do not lose this description")
        let before = CaptureSubmissionAdmissionSnapshot(viewModel.stagedCapture)

        XCTAssertFalse(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))

        XCTAssertEqual(draft.freeText, "Do not lose this description")
        XCTAssertEqual(CaptureSubmissionAdmissionSnapshot(viewModel.stagedCapture), before)
        XCTAssertEqual(viewModel.offlineToastMessage?.title,
                       "Your description couldn’t be added. Please try again.")
        XCTAssertNil(viewModel.pendingAnalyzeScanId)
        XCTAssertFalse(viewModel.isCheckingScanAdmission)
    }

    func testWhitespaceAndBusySubmissionPreserveStagedDescription() {
        let viewModel = makeDescriptionRefinementWorkspace()
        XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(
            ObservationContext(freeText: "Already staged")
        ), .staged)
        var blank = ObservationContext(freeText: " \n\t ")
        XCTAssertEqual(viewModel.stagePendingDescribeDraftForActiveSubmission(blank), .emptyDraft)
        XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &blank))
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
        var pending = ObservationContext(freeText: "Still editing")
        viewModel.isCheckingScanAdmission = true
        XCTAssertFalse(viewModel.prepareActiveStagedSubmission(descriptionDraft: &pending))
        viewModel.isCheckingScanAdmission = false
        viewModel.isStagingRefinement = true
        XCTAssertFalse(viewModel.prepareActiveStagedSubmission(descriptionDraft: &pending))
        XCTAssertEqual(pending.freeText, "Still editing")
        XCTAssertEqual(viewModel.stagedCapture.observationContexts.first?.context.freeText, "Already staged")
    }
}
