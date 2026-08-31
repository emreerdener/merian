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

}
