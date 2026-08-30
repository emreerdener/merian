import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightShellCapabilitiesTests {
    @Test func testTopMenuHidesConfirmAndReviewForStrongNonCompetitiveCandidates() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "strong_hidden_candidates",
            commonName: "Genista Broom Moth",
            scientificName: "Uresiphita reversalis",
            insightData: InsightData(aiReasoning: "A strong identification.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: "flash",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Pieris rapae",
                    commonName: "Cabbage White",
                    confidenceScore: 0.70
                )
            ]
        )
        viewModel.inferenceEngine = engine
        InsightSheetTestSupport.bindToolbarPresentation(
            viewModel,
            scanId: "strong_hidden_candidates"
        )

        #expect(viewModel.canConfirm == false)
        #expect(viewModel.canReviewAlternatives == false)
        #expect(viewModel.canReanalyze == true)
    }

    @Test func testUnresolvedAudioKeepsReanalysisWithoutSpeciesActions() {
        let scanId = "unresolved_audio_reanalysis"
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.activeMedia = ActiveScanMedia(items: [.audio("unresolved.wav")])
        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Unidentified Wildlife",
            scientificName: "Taxonomy Unavailable",
            insightData: InsightData(
                aiReasoning: "A non-human sound is present but unresolved.",
                hazardType: "none"
            ),
            confidenceScore: 0.98,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        viewModel.inferenceEngine = engine

        let record = LocalScanRecord(
            id: scanId,
            speciesId: "unresolved_audio_subject",
            scientificName: "Taxonomy Unavailable",
            commonName: "Unidentified Wildlife"
        )
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)

        #expect(viewModel.hasStandaloneAudio)
        #expect(viewModel.canReanalyze)
        #expect(!viewModel.canConfirm)
        #expect(!viewModel.canReviewAlternatives)
        #expect(!viewModel.canShareToExplore)
    }

    @Test func testIdentificationConcernCandidatesUseStoredAlternativesWithoutChangingToolbarPolicy() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "strong_hidden_candidates",
            commonName: "Genista Broom Moth",
            scientificName: "Uresiphita reversalis",
            insightData: InsightData(aiReasoning: "A strong identification.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: "flash",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Pieris rapae",
                    commonName: "Cabbage White",
                    confidenceScore: 0.70
                )
            ]
        )
        viewModel.inferenceEngine = engine
        InsightSheetTestSupport.bindToolbarPresentation(
            viewModel,
            scanId: "strong_hidden_candidates"
        )

        #expect(viewModel.canReviewAlternatives == false)
        #expect(viewModel.canReviewIdentificationConcernCandidates == true)
        #expect(viewModel.candidateSwipeCandidates.isEmpty)

        viewModel.presentCandidateSwipe(source: .identificationConcern)

        #expect(viewModel.candidateSwipeCandidates.map(\.scientificName) == ["Pieris rapae"])
        #expect(
            viewModel.state.candidateSwipeEnginePresentationGeneration ==
                engine.scanPresentationGeneration
        )
    }

    @Test func testTopMenuShowsConfirmAndReviewForVisibleCompetitiveCandidates() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "strong_competitive_candidates",
            commonName: "Genista Broom Moth",
            scientificName: "Uresiphita reversalis",
            insightData: InsightData(aiReasoning: "A competitive alternative exists.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: "flash",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Pieris rapae",
                    commonName: "Cabbage White",
                    confidenceScore: 0.82
                )
            ]
        )
        viewModel.inferenceEngine = engine
        InsightSheetTestSupport.bindToolbarPresentation(
            viewModel,
            scanId: "strong_competitive_candidates"
        )

        #expect(viewModel.canConfirm == true)
        #expect(viewModel.canReviewAlternatives == true)
        #expect(viewModel.canReanalyze == true)
    }

    @Test func testShareRecommendationUsesFlashStrongThreshold() {
        let lowConfidence = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0.94, inferenceTier: "flash")
        #expect(lowConfidence.shareRecommendation == .askCommunity)
        #expect(lowConfidence.requiresExplorePublishConfirmation == true)

        let strongConfidence = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0.95, inferenceTier: "flash")
        #expect(strongConfidence.shareRecommendation == .publishToExplore)
        #expect(strongConfidence.requiresExplorePublishConfirmation == false)
    }

    @Test func testShareRecommendationUsesProStrongThreshold() {
        let lowConfidence = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0.84, inferenceTier: "pro")
        #expect(lowConfidence.shareRecommendation == .askCommunity)

        let strongConfidence = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0.85, inferenceTier: "pro")
        #expect(strongConfidence.shareRecommendation == .publishToExplore)
    }

    @Test func testShareRecommendationTreatsMissingConfidenceAsAskCommunity() {
        let missingConfidenceFallback = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0, inferenceTier: nil)
        #expect(missingConfidenceFallback.shareRecommendation == .askCommunity)
        #expect(missingConfidenceFallback.requiresExplorePublishConfirmation == true)
    }

    @Test func testShareRecommendationTreatsReviewedIdentificationAsExploreReady() {
        let confirmed = InsightSheetTestSupport.shareRecommendationViewModel(
            confidence: 0.42,
            inferenceTier: "flash",
            userConfirmedIdentification: true
        )
        #expect(confirmed.shareRecommendation == .publishToExplore)

        let overridden = InsightSheetTestSupport.shareRecommendationViewModel(
            confidence: 0.42,
            inferenceTier: "flash",
            userIdentificationOverride: "Rosa gallica"
        )
        #expect(overridden.shareRecommendation == .publishToExplore)
    }

    @Test func testShareRecommendationRestoresCommunityRequestStates() {
        let pending = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0.99, inferenceTier: "flash")
        pending.state.sharedCommunityIdentificationRequestId = "request_pending"
        pending.state.sharedCommunityIdentificationStatus = .needsId
        #expect(pending.shareRecommendation == .communityPending)

        let resolved = InsightSheetTestSupport.shareRecommendationViewModel(confidence: 0.99, inferenceTier: "flash")
        resolved.state.sharedCommunityIdentificationRequestId = "request_resolved"
        resolved.state.sharedCommunityIdentificationStatus = .resolved
        #expect(resolved.shareRecommendation == .communityResolvedNeedsPublish)

        resolved.state.sharedExplorePostId = "post_visible"
        resolved.state.isExploreFeedVisible = true
        #expect(resolved.shareRecommendation == .publishToExplore)
    }

    @Test func testTopMenuStateShowsExplorePostActionsForPublishedPost() {
        let state = InsightTopMenuState(
            sharedExplorePostId: "post_123",
            sharedCommunityIdentificationRequestId: nil,
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: false
        )

        #expect(state.showsExplorePostSection == true)
        #expect(state.communityAction == .askCommunity)
    }

    @Test func testTopMenuStateHidesExplorePostActionsWithoutPublishedPost() {
        let state = InsightTopMenuState(
            sharedExplorePostId: nil,
            sharedCommunityIdentificationRequestId: nil,
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: false
        )

        #expect(state.showsExplorePostSection == false)
        #expect(state.communityAction == .askCommunity)
    }

    @Test func testTopMenuStateUsesViewCommunityRequestWhenRequestExists() {
        let state = InsightTopMenuState(
            sharedExplorePostId: "post_123",
            sharedCommunityIdentificationRequestId: "request_123",
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: true
        )

        #expect(state.showsExplorePostSection == true)
        #expect(state.communityAction == .viewCommunityRequest)
        #expect(state.communityAction?.title == "View community request")
    }

    @Test func testTopMenuStateUsesAskCommunityWhenNoRequestExists() {
        let state = InsightTopMenuState(
            sharedExplorePostId: "post_123",
            sharedCommunityIdentificationRequestId: nil,
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: true
        )

        #expect(state.communityAction == .askCommunity)
        #expect(state.communityAction?.title == "Ask the community")
    }

    @Test func testToolbarLeadingControlsExposeStableAccessibilityContracts() {
        #expect(TopToolbar.LeadingControl.close.accessibilityLabel == "Close")
        #expect(
            TopToolbar.LeadingControl.close.accessibilityIdentifier ==
                "InsightSheetCloseButton"
        )
        #expect(TopToolbar.LeadingControl.back.accessibilityLabel == "Back")
        #expect(
            TopToolbar.LeadingControl.back.accessibilityIdentifier ==
                "InsightSheetBackButton"
        )
    }

}
