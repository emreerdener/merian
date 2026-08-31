import CoreGraphics
import Testing

@testable import Merian

@MainActor
struct ConfidencePresentationViewModelTests {
    @Test func presentationRequiresCurrentSubjectAndOwnsItsHaptic() {
        var heavyImpactIntensities: [CGFloat] = []
        let dependencies = makeDependencies(
            feedback: IdentificationReviewFeedbackDependencies(
                heavyImpact: { heavyImpactIntensities.append($0) }
            )
        )
        let viewModel = ConfidencePresentationViewModel(
            dependencies: dependencies
        )
        let engine = biologicalEngine(scanId: "current")
        let current = subject(for: engine, scanId: "current")
        let stale = IdentificationReviewSubject(
            scanId: "stale",
            presentationGeneration: current.presentationGeneration
        )

        #expect(!viewModel.presentExplanation(
            subject: stale,
            in: engine
        ))
        #expect(heavyImpactIntensities.isEmpty)

        #expect(viewModel.presentExplanation(
            subject: current,
            in: engine
        ))
        #expect(heavyImpactIntensities == [1.0])
        #expect(viewModel.isExplanationPresented)
        #expect(viewModel.explanationSubject == current)
    }

    @Test func staleDismissalCannotClearReplacementExplanation() {
        let viewModel = ConfidencePresentationViewModel(
            dependencies: makeDependencies()
        )
        let firstEngine = biologicalEngine(scanId: "first")
        let first = subject(for: firstEngine, scanId: "first")
        _ = viewModel.presentExplanation(subject: first, in: firstEngine)

        let secondEngine = biologicalEngine(scanId: "second")
        let second = subject(for: secondEngine, scanId: "second")
        _ = viewModel.presentExplanation(subject: second, in: secondEngine)
        viewModel.dismissExplanation(ownedBy: first)

        #expect(viewModel.isExplanationPresented)
        #expect(viewModel.explanationSubject == second)
    }

    @Test func matchingOuterActionSurvivesDismissalAndResumesOnce() throws {
        let viewModel = ConfidencePresentationViewModel(
            dependencies: makeDependencies()
        )
        let engine = biologicalEngine(scanId: "scan")
        let subject = subject(for: engine, scanId: "scan")
        _ = viewModel.presentExplanation(subject: subject, in: engine)
        let action = ConfidenceExplanationDismissalAction.refineScan(
            ConfidenceExplanationActionContext(
                scanId: subject.scanId,
                presentationGeneration: subject.presentationGeneration
            ),
            initialDescription: "striped wings"
        )

        viewModel.stageDismissalAction(action)
        viewModel.dismissExplanation(ownedBy: subject)

        #expect(viewModel.takePendingDismissalAction(
            matching: subject
        ) == action)
        #expect(viewModel.takePendingDismissalAction(
            matching: subject
        ) == nil)
    }

    @Test func pendingOuterActionCannotBeConsumedBeforeDismissal() {
        let viewModel = ConfidencePresentationViewModel(
            dependencies: makeDependencies()
        )
        let engine = biologicalEngine(scanId: "scan")
        let subject = subject(for: engine, scanId: "scan")
        _ = viewModel.presentExplanation(subject: subject, in: engine)
        let action = ConfidenceExplanationDismissalAction.askCommunity(
            ConfidenceExplanationActionContext(
                scanId: subject.scanId,
                presentationGeneration: subject.presentationGeneration
            )
        )

        viewModel.stageDismissalAction(action)

        #expect(viewModel.takePendingDismissalAction(
            matching: subject
        ) == nil)
        #expect(viewModel.pendingDismissalAction == action)

        viewModel.dismissExplanation(ownedBy: subject)

        #expect(viewModel.takePendingDismissalAction(
            matching: subject
        ) == action)
    }

    @Test func refinementRouteUsesInjectedFeedbackAndRouter() {
        var selectionCount = 0
        var routes: [(String, String?)] = []
        let viewModel = ConfidencePresentationViewModel(
            dependencies: makeDependencies(
                feedback: IdentificationReviewFeedbackDependencies(
                    selection: { selectionCount += 1 }
                ),
                requestRefinementRoute: {
                    routes.append(($0, $1))
                }
            )
        )

        viewModel.requestRefinementRoute(
            scanId: "scan",
            initialDescription: "striped wings"
        )

        #expect(selectionCount == 1)
        #expect(routes.count == 1)
        #expect(routes.first?.0 == "scan")
        #expect(routes.first?.1 == "striped wings")
    }

    private func makeDependencies(
        feedback: IdentificationReviewFeedbackDependencies = .init(),
        requestRefinementRoute: @escaping @MainActor (
            String,
            String?
        ) -> Void = { _, _ in }
    ) -> ConfidenceReviewDependencies {
        ConfidenceReviewDependencies(
            candidate: CandidateReviewDependencies(feedback: feedback),
            requestRefinementRoute: requestRefinementRoute
        )
    }

    private func biologicalEngine(scanId: String) -> InferenceEngine {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "A butterfly.",
                hazardType: "none"
            ),
            confidenceScore: 0.9,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        return engine
    }

    private func subject(
        for engine: InferenceEngine,
        scanId: String
    ) -> IdentificationReviewSubject {
        IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: engine.scanPresentationGeneration
        )
    }
}
