import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightQueuedHandoffTests {
    @Test func testQueuedMediaCachePreservesFocusRegionsAcrossLifecycleHandoffs() throws {
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.12,
            y: 0.18,
            width: 0.42,
            height: 0.51
        )
        let descriptorData = try JSONEncoder().encode([
            IdentifyVisualMediaItem.image(
                sourceIndex: 0,
                focusRegion: focusRegion
            )
        ])
        let visualMediaItemsJSON = try #require(
            String(data: descriptorData, encoding: .utf8)
        )

        func queuedContext(
            id: String,
            imagePath: String,
            queueState: ScanQueueState
        ) -> QueuedScanContext {
            QueuedScanContext(
                id: id,
                capturedMediaItems: [.image(.documents(imagePath))],
                queueState: queueState,
                timestamp: Date(timeIntervalSince1970: 1),
                visualMediaItemsJSON: visualMediaItemsJSON
            )
        }

        let initialContext = queuedContext(
            id: "queued_focus_1",
            imagePath: "initial.webp",
            queueState: .pending
        )
        let viewModel = InsightSheetViewModel(queuedContext: initialContext)

        #expect(viewModel.cachedActiveMedia?.focusRegionsBySourceIndex[0] == focusRegion)

        let refreshedContext = queuedContext(
            id: initialContext.id,
            imagePath: "refreshed.webp",
            queueState: .inferencing
        )
        #expect(viewModel.refreshQueuedContextIfCurrent(
            refreshedContext,
            expectedScanId: initialContext.id
        ))
        #expect(viewModel.cachedActiveMedia?.focusRegionsBySourceIndex[0] == focusRegion)

        let replacementContext = queuedContext(
            id: "queued_focus_2",
            imagePath: "replacement.webp",
            queueState: .inferencing
        )
        viewModel.bindQueuedPresentation(replacementContext)

        #expect(viewModel.cachedActiveMedia?.focusRegionsBySourceIndex[0] == focusRegion)
        #expect(
            viewModel.resolvedMedia(for: replacementContext)
                .focusRegionsBySourceIndex[0] == focusRegion
        )
    }

    @Test func testFocusCustomizationAndOverlaySurviveQueuedOwnerHandoff() throws {
        let queuedContext = QueuedScanContext(
            id: "queued_focus_handoff",
            capturedMediaItems: [.image(.documents("focus.webp"))],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let viewModel = InsightSheetViewModel(queuedContext: queuedContext)
        let identity = FocusInteractionIdentity(
            scanID: queuedContext.id,
            stillImageSourceIndex: 0
        )
        let customizedRect = try #require(NormalizedFocusOverlayRect(
            rect: CGRect(x: 210, y: 70, width: 105, height: 285),
            in: CGSize(width: 390, height: 440)
        ))
        viewModel.focusOverlayInteractionState[identity] = customizedRect

        #expect(viewModel.isCarouselAnalysisActive(for: queuedContext))

        viewModel.releaseQueuedPresentation(expectedScanId: queuedContext.id)

        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.isCarouselAnalysisActive(for: nil))
        #expect(
            viewModel.focusOverlayInteractionState.resolvedScanID(for: nil) ==
                queuedContext.id
        )
        #expect(viewModel.focusOverlayInteractionState[
            FocusInteractionIdentity(
                scanID: viewModel.focusOverlayInteractionState.resolvedScanID(for: nil),
                stillImageSourceIndex: 0
            )
        ] == customizedRect)

        viewModel.reset()
        #expect(viewModel.focusOverlayInteractionState[identity] == nil)
    }

    @Test func carouselAnalysisRemainsActiveAcrossExactLiveQueueHandoff() {
        let scanId = "live_visual_queue_handoff"
        let engine = InferenceEngine()
        engine.simulateProgressiveAnalyzing(
            automaticallyAdvances: false,
            scanId: scanId
        )
        #expect(engine.debugTransitionProgressiveAnalyzingToQueue(
            scanId: scanId
        ))
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)

        func context(
            id: String = scanId,
            state: ScanQueueState,
            needsAttention: Bool = false
        ) -> QueuedScanContext {
            QueuedScanContext(
                id: id,
                capturedMediaItems: [.image(.documents("handoff.png"))],
                queueState: state,
                timestamp: Date(timeIntervalSince1970: 1),
                queueNeedsAttention: needsAttention
            )
        }

        for state in [
            ScanQueueState.pending,
            .uploading,
            .staged,
            .inferencing
        ] {
            #expect(viewModel.isCarouselAnalysisActive(
                for: context(state: state)
            ))
        }

        for state in [
            ScanQueueState.pending,
            .uploading,
            .staged
        ] {
            #expect(!viewModel.isCarouselAnalysisActive(
                for: context(id: "ordinary_queued_scan", state: state)
            ))
        }
        #expect(viewModel.isCarouselAnalysisActive(
            for: context(id: "ordinary_queued_scan", state: .inferencing)
        ))
        #expect(!viewModel.isCarouselAnalysisActive(
            for: context(state: .failed)
        ))
        #expect(!viewModel.isCarouselAnalysisActive(
            for: context(state: .externalImport)
        ))
        #expect(!viewModel.isCarouselAnalysisActive(
            for: context(state: .inferencing, needsAttention: true)
        ))
    }

    @Test func testQueuedRefreshRejectsChangedPresentationIdentity() {
        let first = QueuedScanContext(
            id: "queued_scan_1",
            capturedMediaItems: [.image("first.webp")],
            queueState: .pending,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let second = QueuedScanContext(
            id: "queued_scan_2",
            capturedMediaItems: [.image("second-old.webp")],
            queueState: .pending,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let staleFirstRefresh = QueuedScanContext(
            id: first.id,
            capturedMediaItems: [.image("stale-first.webp")],
            queueState: .failed,
            timestamp: first.timestamp,
            queueLastErrorCode: "stale"
        )
        let currentSecondRefresh = QueuedScanContext(
            id: second.id,
            capturedMediaItems: [.image("second-new.webp")],
            queueState: .uploading,
            timestamp: second.timestamp
        )
        let viewModel = InsightSheetViewModel(queuedContext: first)
        viewModel.queuedContext = second

        #expect(!viewModel.refreshQueuedContextIfCurrent(
            staleFirstRefresh,
            expectedScanId: first.id
        ))
        #expect(viewModel.queuedContext?.id == second.id)
        #expect(viewModel.queuedContext?.queueState == .pending)
        #expect(viewModel.refreshQueuedContextIfCurrent(
            currentSecondRefresh,
            expectedScanId: second.id
        ))
        #expect(viewModel.queuedContext?.queueState == .uploading)
        #expect(
            viewModel.cachedActiveMedia?.imagePathsForUpload ==
                ["second-new.webp"]
        )
    }

    @Test func testQueuedPresentationSwitchInvalidatesPriorQueueIdentity() {
        let first = QueuedScanContext(
            id: "queued_presentation_1",
            capturedMediaItems: [.image("first.webp")],
            queueState: .uploading,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let second = QueuedScanContext(
            id: "queued_presentation_2",
            capturedMediaItems: [.image("second.webp")],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let viewModel = InsightSheetViewModel(queuedContext: first)
        let firstGeneration = viewModel.scanBoundActionGeneration
        viewModel.state.fieldNotesText = "First queued note"
        viewModel.state.isFieldNotesSheetPresented = true
        viewModel.state.fieldNotesPresentationScanId = first.id
        viewModel.state.fieldNotesPresentationGeneration = firstGeneration
        viewModel.state.showDeleteConfirmation = true
        viewModel.state.toastMessage = .information("First queued toast")

        viewModel.bindQueuedPresentation(second)

        #expect(viewModel.queuedContext?.id == second.id)
        #expect(viewModel.queuedContext?.queueState == .inferencing)
        #expect(viewModel.scanBoundActionGeneration != firstGeneration)
        #expect(viewModel.state.fieldNotesText.isEmpty)
        #expect(!viewModel.state.isFieldNotesSheetPresented)
        #expect(viewModel.state.fieldNotesPresentationScanId == nil)
        #expect(viewModel.state.fieldNotesPresentationGeneration == nil)
        #expect(!viewModel.state.showDeleteConfirmation)
        #expect(viewModel.state.toastMessage == nil)
        #expect(viewModel.cachedActiveMedia?.imagePathsForUpload == ["second.webp"])
    }

    @Test func testQueuedPromotionRejectsChangedPresentationIdentity() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let firstRecord = LocalScanRecord(
            speciesId: "queued_promotion_species_1",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let secondRecord = LocalScanRecord(
            speciesId: "queued_promotion_species_2",
            scientificName: "Acer rubrum",
            commonName: "Red Maple"
        )
        secondRecord.hasBeenViewed = false
        context.insert(firstRecord)
        context.insert(secondRecord)
        try context.save()

        let firstContext = QueuedScanContext(
            id: firstRecord.id,
            capturedMediaItems: [],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let secondContext = QueuedScanContext(
            id: secondRecord.id,
            capturedMediaItems: [],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(
            queuedContext: secondContext,
            inferenceEngine: engine
        )
        let queuedGeneration = viewModel.scanBoundActionGeneration

        #expect(!viewModel.promoteQueuedScanIfLocalRecordExists(
            scanId: firstContext.id,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext?.id == secondContext.id)
        #expect(engine.speciesData == nil)
        #expect(viewModel.promoteQueuedScanIfLocalRecordExists(
            scanId: secondContext.id,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.scanBoundActionGeneration != queuedGeneration)
        #expect(engine.speciesData?.scanId == secondRecord.id)
        #expect(secondRecord.hasBeenViewed)
    }

    @Test func testQueuedPresentationPrefersPersistedCompletionOverStaleRoute() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "queued_completed_route_species",
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal"
        )
        context.insert(record)
        try context.save()

        let staleQueuedRoute = QueuedScanContext(
            id: record.id,
            capturedMediaItems: [.audio(.documents("cardinal.wav"))],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 3)
        )
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        let queuedGeneration = viewModel.scanBoundActionGeneration

        #expect(viewModel.bindQueuedPresentationPreferringCompletedRecord(
            staleQueuedRoute,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.presentedLocalRecordScanId == record.id)
        #expect(engine.speciesData?.scanId == record.id)
        #expect(engine.speciesData?.commonName == "Northern Cardinal")
        #expect(engine.speciesData?.isBiological == true)
        #expect(engine.speciesData?.isHumanSubject == false)
        #expect(viewModel.isProcessing == false)
        #expect(viewModel.scanBoundActionGeneration != queuedGeneration)
        #expect(viewModel.toolbarRecordSnapshot?.scanId == record.id)
        #expect(!viewModel.revealBottomBarTools(
            expectedScanId: record.id,
            expectedGeneration: queuedGeneration
        ))
        #expect(!viewModel.state.showBottomBarTools)
        #expect(viewModel.revealBottomBarTools(
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        ))
        #expect(viewModel.state.showBottomBarTools)

        let completedGeneration = viewModel.scanBoundActionGeneration
        #expect(viewModel.bindQueuedPresentationPreferringCompletedRecord(
            staleQueuedRoute,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.scanBoundActionGeneration == completedGeneration)
        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.presentedLocalRecordScanId == record.id)
        #expect(viewModel.state.showBottomBarTools)
    }

}
