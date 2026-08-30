import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightSharingPresentationTests {
    @Test func testExploreSharingRequiresExactEngineAndRecordIdentity() throws {
        let viewModel = InsightSheetTestSupport.shareRecommendationViewModel(
            confidence: 0.99,
            inferenceTier: "flash"
        )
        let scanId = try #require(viewModel.inferenceEngine?.speciesData?.scanId)

        #expect(viewModel.presentedSpeciesScanId == scanId)
        #expect(viewModel.canShareToExplore)

        let postId = UUID().uuidString.lowercased()
        let requestId = UUID().uuidString.lowercased()
        viewModel.state.sharedExplorePostId = postId
        viewModel.state.sharedCommunityIdentificationRequestId = requestId
        viewModel.presentExplorePostComposer(
            expectedScanId: scanId,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        viewModel.presentCommunityIdentificationRequest(
            expectedScanId: scanId,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        #expect(viewModel.state.explorePostComposerPresentationPostId == postId)
        #expect(viewModel.state.communityRequestPresentationRequestId == requestId)

        viewModel.activeLocalRecordId = UUID().uuidString.lowercased()
        viewModel.inferenceEngine?.activeScanId = UUID().uuidString.lowercased()

        #expect(viewModel.presentedSpeciesScanId == nil)
        #expect(!viewModel.canShareToExplore)
        #expect(viewModel.persistentScanId == scanId)
    }

    @Test func testPreferredNameRejectsStalePresentationGeneration() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let first = LocalScanRecord(
            speciesId: "preferred_name_generation_1",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let second = LocalScanRecord(
            speciesId: "preferred_name_generation_2",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(first)
        context.insert(second)
        try context.save()
        let viewModel = InsightSheetViewModel()
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: first.id)
        #expect(viewModel.fetchLocalRecord(for: first.id, modelContext: context))
        let staleGeneration = viewModel.scanBoundActionGeneration

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: second.id)
        #expect(viewModel.fetchLocalRecord(for: second.id, modelContext: context))
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: first.id)
        #expect(viewModel.fetchLocalRecord(for: first.id, modelContext: context))

        viewModel.setPreferredCommonName(
            "Stale Monarch Name",
            for: "Danaus plexippus",
            expectedScanId: first.id,
            expectedGeneration: staleGeneration,
            modelContext: context
        )

        #expect(
            SpeciesPreferredNameRepository.preferredName(
                for: "Danaus plexippus",
                modelContext: context
            ) == nil
        )
        #expect(viewModel.state.toastMessage == nil)
    }

}
