@testable import Merian
import Testing

@MainActor
struct FieldTripTemplateDetailViewModelTests {
    @Test func outingLoadAndLifecycleMutationsUseInjectedDependencies() async {
        let unstarted = FieldTripTestFixtures.template()
        let activeProgress = FieldTripTestFixtures.progress()
        let active = FieldTripTestFixtures.template(activeProgress: activeProgress)
        let stopped = FieldTripTestFixtures.template(
            stoppedProgress: FieldTripTestFixtures.progress(
                stoppedAt: "2026-07-19T10:00:00Z"
            )
        )
        var requestedTemplateId: String?
        var requestedCommunityTemplateId: String?
        var mutationIDs: [String] = []
        var successFeedbackCount = 0
        var progressChangeCount = 0

        let viewModel = FieldTripTemplateDetailViewModel(
            reference: .id(unstarted.templateId),
            dependencies: FieldTripTemplateDetailViewModel.Dependencies(
                loadById: { templateId in
                    requestedTemplateId = templateId
                    return unstarted
                },
                loadBySlug: { _ in throw FieldTripTestError.expected },
                start: { templateId in
                    mutationIDs.append("start:\(templateId)")
                    return active
                },
                stop: { userFieldTripId in
                    mutationIDs.append("stop:\(userFieldTripId)")
                    return stopped
                },
                reset: { userFieldTripId in
                    mutationIDs.append("reset:\(userFieldTripId)")
                    return unstarted
                },
                loadCommunity: { templateId in
                    requestedCommunityTemplateId = templateId
                    return []
                },
                successFeedback: { successFeedbackCount += 1 },
                errorFeedback: {},
                progressDidChange: { progressChangeCount += 1 },
                detailErrorMessage: { _ in "detail error" },
                mutationErrorMessage: { _ in "mutation error" }
            )
        )
        var loadedTemplateId: String?

        await viewModel.load(force: false) {
            loadedTemplateId = $0.templateId
        }

        #expect(viewModel.template == unstarted)
        #expect(requestedTemplateId == unstarted.templateId)
        #expect(requestedCommunityTemplateId == unstarted.templateId)
        #expect(loadedTemplateId == unstarted.templateId)
        #expect(!viewModel.isLoading)
        #expect(!viewModel.isLoadingCommunityPreview)

        await viewModel.start(unstarted)
        #expect(viewModel.template == active)

        await viewModel.stop(active)
        #expect(viewModel.template == stopped)

        await viewModel.reset(stopped)
        #expect(viewModel.template == unstarted)
        #expect(mutationIDs == [
            "start:\(unstarted.templateId)",
            "stop:\(activeProgress.userFieldTripId)",
            "reset:\(activeProgress.userFieldTripId)"
        ])
        #expect(successFeedbackCount == 3)
        #expect(progressChangeCount == 3)
        #expect(!viewModel.isLifecycleMutating)
    }

    @Test func outingLoadFailureDoesNotRequestCommunityContent() async {
        var didRequestCommunity = false
        let viewModel = FieldTripTemplateDetailViewModel(
            reference: .slug("missing"),
            dependencies: FieldTripTemplateDetailViewModel.Dependencies(
                loadById: { _ in throw FieldTripTestError.expected },
                loadBySlug: { _ in throw FieldTripTestError.expected },
                start: { _ in throw FieldTripTestError.expected },
                stop: { _ in throw FieldTripTestError.expected },
                reset: { _ in throw FieldTripTestError.expected },
                loadCommunity: { _ in
                    didRequestCommunity = true
                    return []
                },
                successFeedback: {},
                errorFeedback: {},
                progressDidChange: {},
                detailErrorMessage: { _ in "detail error" },
                mutationErrorMessage: { _ in "mutation error" }
            )
        )

        await viewModel.load(force: false)

        #expect(viewModel.template == nil)
        #expect(viewModel.errorMessage == "detail error")
        #expect(!didRequestCommunity)
        #expect(!viewModel.isLoading)
    }
}
