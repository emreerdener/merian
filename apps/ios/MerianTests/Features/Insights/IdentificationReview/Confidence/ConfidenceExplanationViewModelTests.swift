import SwiftData
import Testing

@testable import Merian

@MainActor
struct ConfidenceExplanationViewModelTests {
    @Test func lateRefinementLoadCannotReplaceNewerSubject() async throws {
        var firstContinuation: CheckedContinuation<
            IdentificationReviewRefinementSnapshot?,
            Never
        >?
        var secondContinuation: CheckedContinuation<
            IdentificationReviewRefinementSnapshot?,
            Never
        >?
        let viewModel = ConfidenceExplanationViewModel(
            dependencies: ConfidenceReviewDependencies(
                candidate: CandidateReviewDependencies(),
                loadRefinementSnapshot: { scanId, _ in
                    await withCheckedContinuation { continuation in
                        if scanId == "first" {
                            firstContinuation = continuation
                        } else {
                            secondContinuation = continuation
                        }
                    }
                }
            )
        )
        let container = try modelContainer()
        let firstSubject = IdentificationReviewSubject(
            scanId: "first",
            presentationGeneration: 1
        )
        let secondSubject = IdentificationReviewSubject(
            scanId: "second",
            presentationGeneration: 2
        )

        let firstLoad = Task {
            await viewModel.loadRefinementSnapshot(
                subject: firstSubject,
                modelContainer: container
            )
        }
        while firstContinuation == nil {
            await Task.yield()
        }
        let secondLoad = Task {
            await viewModel.loadRefinementSnapshot(
                subject: secondSubject,
                modelContainer: container
            )
        }
        while secondContinuation == nil {
            await Task.yield()
        }

        secondContinuation?.resume(
            returning: IdentificationReviewRefinementSnapshot(
                scanId: "second",
                initialDescription: "current"
            )
        )
        await secondLoad.value
        firstContinuation?.resume(
            returning: IdentificationReviewRefinementSnapshot(
                scanId: "first",
                initialDescription: "stale"
            )
        )
        await firstLoad.value

        #expect(viewModel.refinementSnapshot ==
            IdentificationReviewRefinementSnapshot(
                scanId: "second",
                initialDescription: "current"
            ))
    }

    @Test func invalidationFencesAnActiveRefinementLoad() async throws {
        var continuation: CheckedContinuation<
            IdentificationReviewRefinementSnapshot?,
            Never
        >?
        let viewModel = ConfidenceExplanationViewModel(
            dependencies: ConfidenceReviewDependencies(
                candidate: CandidateReviewDependencies(),
                loadRefinementSnapshot: { _, _ in
                    await withCheckedContinuation {
                        continuation = $0
                    }
                }
            )
        )
        let container = try modelContainer()
        let subject = IdentificationReviewSubject(
            scanId: "scan",
            presentationGeneration: 1
        )
        let load = Task {
            await viewModel.loadRefinementSnapshot(
                subject: subject,
                modelContainer: container
            )
        }
        while continuation == nil {
            await Task.yield()
        }

        viewModel.invalidate()
        continuation?.resume(
            returning: IdentificationReviewRefinementSnapshot(
                scanId: "scan",
                initialDescription: "stale"
            )
        )
        await load.value

        #expect(viewModel.refinementSnapshot == nil)
    }

    private func modelContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
