import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct CandidateReviewViewModelTests {
    @Test(arguments: [false, true])
    func delayedCandidateDismissalRetainsReviewAndCannotConfirmAfterRevisionChange(rejected: Bool) async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer(), engine = confirmationEngine()
        let expected = try #require(engine.speciesData?.aiReview)
        var calls = 0
        let viewModel = CandidateReviewViewModel(dependencies: .init(confirmOriginal: { _, _, _, _ in calls += 1 }))
        let subject = subject(scanId: "confirmation", generation: engine.scanPresentationGeneration)
        viewModel.presentSwipeModal(subject: subject)
        viewModel.stageDismissalRequest(.init(action: .confirmOriginal, scanId: subject.scanId,
            presentationGeneration: subject.presentationGeneration, expectedReview: expected))
        viewModel.dismissSwipeModal(ownedBy: subject)
        engine.speciesData?.aiReview = .init(authority: .init(revision: 1, state: rejected ? .aiRejected : .clear,
            originScanID: "00000000-0000-4000-8000-000000000001", originIdentification: nil))
        let request = try #require(viewModel.takePendingDismissalRequest(matching: subject))
        #expect(request.expectedReview == expected)
        let confirmed = await viewModel.confirmOriginal(subject: subject, inferenceEngine: engine,
            modelContext: container.mainContext, expectedReview: request.expectedReview)
        #expect(!confirmed && calls == 0 && engine.speciesData?.userConfirmedIdentification == false)
    }

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

    @Test func failedConfirmationDoesNotReportSuccessAndCanBeRetried() async throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let engine = confirmationEngine()
        var attempts = 0
        let viewModel = CandidateReviewViewModel(dependencies: .init(confirmOriginal: { engine, _, _, _ in
            attempts += 1
            if attempts == 2 { engine.speciesData?.userConfirmedIdentification = true }
        }))
        let subject = subject(scanId: "confirmation", generation: engine.scanPresentationGeneration)
        let first = await viewModel.confirmOriginal(subject: subject, inferenceEngine: engine,
            modelContext: container.mainContext)
        #expect(!first)
        #expect(viewModel.confirmationMessage != nil)
        let second = await viewModel.confirmOriginal(subject: subject, inferenceEngine: engine,
            modelContext: container.mainContext)
        #expect(second)
        #expect(viewModel.confirmationMessage == nil)
        #expect(attempts == 2)
    }

    @Test func queuedConfirmationIsNotSuccessAndRetryDoesNotDuplicateIt() async throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let engine = confirmationEngine()
        var attempts = 0
        let viewModel = CandidateReviewViewModel(dependencies: .init(confirmOriginal: { engine, _, _, _ in
            attempts += 1
            engine.speciesData?.aiReview.pending = AIIdentificationReviewRequest(
                scanID: "confirmation", expectedRevision: 0, operationID: "synthetic-operation",
                action: .confirmPrimary, scientificName: nil, expectedSpeciesReviewRevision: nil)
        }))
        let subject = subject(scanId: "confirmation", generation: engine.scanPresentationGeneration)
        let first = await viewModel.confirmOriginal(subject: subject, inferenceEngine: engine,
            modelContext: container.mainContext)
        #expect(!first)
        #expect(viewModel.confirmationMessage?.contains("waiting to sync") == true)
        let second = await viewModel.confirmOriginal(subject: subject, inferenceEngine: engine,
            modelContext: container.mainContext)
        #expect(!second)
        #expect(attempts == 1)
    }

    @Test func confirmationCompletionCannotReportSuccessForAReplacementScan() async throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let engine = confirmationEngine()
        let viewModel = CandidateReviewViewModel(dependencies: .init(confirmOriginal: { engine, _, _, _ in
            engine.speciesData = SpeciesData(scanId: "replacement", commonName: "Replacement",
                scientificName: "Fixtureus replacement",
                insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
                confidenceScore: 0.8, isBiological: true)
            engine.speciesData?.userConfirmedIdentification = true
        }))
        let subject = subject(scanId: "confirmation", generation: engine.scanPresentationGeneration)
        let confirmed = await viewModel.confirmOriginal(subject: subject, inferenceEngine: engine,
            modelContext: container.mainContext)
        #expect(!confirmed)
        #expect(viewModel.confirmationMessage == nil)
    }

    private func confirmationEngine() -> InferenceEngine {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(scanId: "confirmation", commonName: "Fixture",
            scientificName: "Fixtureus species",
            insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
            confidenceScore: 0.8, isBiological: true)
        return engine
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
