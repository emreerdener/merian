import Foundation

extension InsightSheetViewModel {
    func presentExplore(
        target: InsightExplorePresentationTarget,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        state.explorePresentationTarget = target
        state.explorePresentationScanId = expectedScanId
        state.explorePresentationGeneration = expectedGeneration
        state.showExploreSheet = true
    }

    func presentExplorePostComposer(
        expectedScanId: String,
        expectedGeneration: UInt64? = nil
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
        let postId = state.sharedExplorePostId else {
            return
        }
        state.explorePostComposerPresentationScanId = expectedScanId
        state.explorePostComposerPresentationGeneration =
            scanBoundActionGeneration
        state.explorePostComposerPresentationPostId = postId
        state.isExplorePostComposerPresented = true
    }

    func presentCommunityIdentificationRequest(
        expectedScanId: String,
        expectedGeneration: UInt64? = nil
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        state.communityRequestPresentationScanId = expectedScanId
        state.communityRequestPresentationGeneration =
            scanBoundActionGeneration
        state.communityRequestPresentationRequestId =
            state.sharedCommunityIdentificationRequestId
        state.isCommunityRequestSheetPresented = true
    }

    func explorePresentationAction(
        target: InsightExplorePresentationTarget,
        scanId: String,
        generation: UInt64
    ) -> () -> Void {
        { [weak self] in
            guard let self,
                  self.isPresentingLocalRecord(
                      scanId: scanId,
                      generation: generation
                  ) else {
                return
            }
            self.presentExplore(
                target: target,
                expectedScanId: scanId,
                expectedGeneration: generation
            )
        }
    }
}
