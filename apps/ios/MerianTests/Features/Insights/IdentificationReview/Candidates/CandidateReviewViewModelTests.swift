import Testing

@testable import Merian

@MainActor
struct CandidateReviewViewModelTests {
    @Test func staleDismissalCannotClearNewerModalOwnership() {
        let viewModel = makeViewModel()
        let first = subject(scanId: "first", generation: 1)
        let second = subject(scanId: "second", generation: 2)

        viewModel.presentSwipeModal(subject: first)
        viewModel.presentSwipeModal(subject: second)
        viewModel.dismissSwipeModal(ownedBy: first)

        #expect(viewModel.isSwipeModalPresented)
        #expect(viewModel.swipeModalSubject == second)

        viewModel.dismissSwipeModal(ownedBy: second)

        #expect(!viewModel.isSwipeModalPresented)
        #expect(viewModel.swipeModalSubject == nil)
    }

    @Test func staleDismissalRequestCannotResumeForReplacementSubject() {
        let viewModel = makeViewModel()
        let first = subject(scanId: "first", generation: 1)
        let second = subject(scanId: "second", generation: 2)
        let staleRequest = request(subject: first, action: .confirmOriginal)

        viewModel.presentSwipeModal(subject: first)
        viewModel.presentSwipeModal(subject: second)
        viewModel.stageDismissalRequest(staleRequest)

        #expect(
            viewModel.takePendingDismissalRequest(matching: second) == nil
        )
    }

    @Test func matchingDismissalRequestIsReturnedOnceAfterDismissal() {
        let viewModel = makeViewModel()
        let subject = subject(scanId: "scan", generation: 7)
        let expected = request(
            subject: subject,
            action: .applyOverride(scientificName: "Danaus plexippus")
        )

        viewModel.presentSwipeModal(subject: subject)
        viewModel.stageDismissalRequest(expected)
        viewModel.dismissSwipeModal(ownedBy: subject)

        #expect(
            viewModel.takePendingDismissalRequest(matching: subject) ==
                expected
        )
        #expect(
            viewModel.takePendingDismissalRequest(matching: subject) == nil
        )
    }

    @Test func pendingDismissalRequestCannotBeConsumedBeforeDismissal() {
        let viewModel = makeViewModel()
        let subject = subject(scanId: "scan", generation: 8)
        let expected = request(subject: subject, action: .confirmOriginal)

        viewModel.presentSwipeModal(subject: subject)
        viewModel.stageDismissalRequest(expected)

        #expect(
            viewModel.takePendingDismissalRequest(matching: subject) == nil
        )
        #expect(viewModel.pendingDismissalRequest == expected)

        viewModel.dismissSwipeModal(ownedBy: subject)

        #expect(
            viewModel.takePendingDismissalRequest(matching: subject) ==
                expected
        )
    }

    @Test func defaultDependenciesDoNotLoadLiveCandidateImages() async {
        let output = await CandidateReviewDependencies()
            .imageDependencies
            .loadImages("Danaus plexippus")

        #expect(output.images.isEmpty)
        #expect(output.commonName == nil)
    }

    @Test func cardDismissalUsesCaseInsensitiveScanIdentity() {
        let viewModel = makeViewModel()
        viewModel.dismissCard(
            subject: subject(scanId: "SCAN-ID", generation: 3)
        )

        #expect(viewModel.shouldHideCard(scanId: "scan-id"))
        #expect(!viewModel.shouldHideCard(scanId: "another-scan"))
        #expect(!viewModel.shouldHideCard(scanId: nil))
    }

    @Test func subjectMatchingRequiresIdentityAndGeneration() {
        let subject = subject(scanId: "SCAN-ID", generation: 4)

        #expect(subject.matches(
            scanId: "scan-id",
            presentationGeneration: 4
        ))
        #expect(!subject.matches(
            scanId: "scan-id",
            presentationGeneration: 5
        ))
        #expect(!subject.matches(
            scanId: "another-scan",
            presentationGeneration: 4
        ))
    }

    private func makeViewModel() -> CandidateReviewViewModel {
        CandidateReviewViewModel(
            dependencies: CandidateReviewDependencies()
        )
    }

    private func subject(
        scanId: String,
        generation: UInt64
    ) -> IdentificationReviewSubject {
        IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: generation
        )
    }

    private func request(
        subject: IdentificationReviewSubject,
        action: CandidateSwipeDismissalAction
    ) -> CandidateSwipeDismissalRequest {
        CandidateSwipeDismissalRequest(
            action: action,
            scanId: subject.scanId,
            presentationGeneration: subject.presentationGeneration
        )
    }
}
