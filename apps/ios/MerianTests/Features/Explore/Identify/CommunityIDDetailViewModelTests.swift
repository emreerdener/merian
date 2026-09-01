@testable import Merian
import Testing

@MainActor
@Suite("Community Identification Detail View Model")
struct CommunityIDDetailViewModelTests {
    @Test func loadOwnershipAndMutationsUseInjectedBoundaries() async throws {
        let detail = try CommunityIdentificationTestFixtures.detail(
            requestId: "request-1",
            authorUserId: "AUTHOR-1"
        )
        let taxon = CommunityIdentificationTestFixtures.taxon()
        var loadCount = 0
        var updates: [CommunityIdentificationUpdateRequest] = []
        var postReports: [CommunityIdentificationPostReportRequest] = []
        var submissions: [CommunityIdentificationSubmissionRequest] = []
        var withdrawnIds: [String] = []
        var restoredIds: [String] = []
        var changedRequestIds: [String] = []
        var successFeedbackCount = 0
        var selectionFeedbackCount = 0

        let viewModel = CommunityIdentificationDetailViewModel(
            requestId: "request-1",
            dependencies: CommunityIdentificationDetailViewModel.Dependencies(
                loadDetail: { requestId in
                    #expect(requestId == "request-1")
                    loadCount += 1
                    return detail
                },
                updateRequest: { updates.append($0) },
                reportPost: { postReports.append($0) },
                submitIdentification: { submissions.append($0) },
                withdrawIdentification: { withdrawnIds.append($0) },
                restoreIdentification: { restoredIds.append($0) },
                currentUserId: { "author-1" },
                requestDidChange: { changedRequestIds.append($0) },
                successFeedback: { successFeedbackCount += 1 },
                selectionFeedback: { selectionFeedbackCount += 1 },
                errorFeedback: {},
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.load()

        #expect(viewModel.detail == detail)
        #expect(viewModel.isOwnedByCurrentUser(detail))
        #expect(!viewModel.isLoading)

        let didUpdate = await viewModel.updateRequest(
            note: "Updated note",
            locationSharing: .privateLocation
        )
        await viewModel.report(detail)
        let didSubmit = await viewModel.submit(
            taxon: taxon,
            disagreementMode: .maverick,
            reasoning: "Different field marks",
            isGenusBestPossible: false
        )
        await viewModel.withdraw(identificationId: "identification-1")
        await viewModel.restore(identificationId: "identification-1")

        #expect(didUpdate)
        #expect(didSubmit)
        #expect(updates.count == 1)
        #expect(updates.first?.requestId == "request-1")
        #expect(updates.first?.note == "Updated note")
        #expect(updates.first?.locationSharing == .privateLocation)
        #expect(postReports.first?.postId == detail.postId)
        #expect(submissions.first?.requestId == "request-1")
        #expect(submissions.first?.taxonId == taxon.taxonId)
        #expect(submissions.first?.disagreementMode == .maverick)
        #expect(submissions.first?.reasoning == "Different field marks")
        #expect(withdrawnIds == ["identification-1"])
        #expect(restoredIds == ["identification-1"])
        #expect(changedRequestIds == ["request-1", "request-1", "request-1"])
        #expect(loadCount == 5)
        #expect(successFeedbackCount == 3)
        #expect(selectionFeedbackCount == 2)
        #expect(viewModel.toastMessage != nil)
    }

    @Test func failedSubmissionRestoresInteractionStateAndDoesNotPublishAnEvent() async {
        let taxon = CommunityIdentificationTestFixtures.taxon()
        var changedRequestIds: [String] = []
        var errorFeedbackCount = 0

        let viewModel = CommunityIdentificationDetailViewModel(
            requestId: "request-1",
            dependencies: CommunityIdentificationDetailViewModel.Dependencies(
                loadDetail: { _ in try CommunityIdentificationTestFixtures.detail() },
                updateRequest: { _ in },
                reportPost: { _ in },
                submitIdentification: { _ in
                    throw CommunityIdentificationTestError.expected
                },
                withdrawIdentification: { _ in },
                restoreIdentification: { _ in },
                currentUserId: { nil },
                requestDidChange: { changedRequestIds.append($0) },
                successFeedback: {},
                selectionFeedback: {},
                errorFeedback: { errorFeedbackCount += 1 },
                errorMessage: { _ in "expected error" }
            )
        )

        let didSubmit = await viewModel.submit(
            taxon: taxon,
            disagreementMode: .implicitSupport,
            reasoning: nil,
            isGenusBestPossible: false
        )

        #expect(!didSubmit)
        #expect(!viewModel.isSubmitting)
        #expect(viewModel.errorMessage == "expected error")
        #expect(changedRequestIds.isEmpty)
        #expect(errorFeedbackCount == 1)
    }

    @Test func failedPostReportRestoresInteractionState() async throws {
        let detail = try CommunityIdentificationTestFixtures.detail()
        var reportedPostIds: [String] = []
        var errorFeedbackCount = 0

        let viewModel = CommunityIdentificationDetailViewModel(
            requestId: detail.requestId,
            dependencies: CommunityIdentificationDetailViewModel.Dependencies(
                loadDetail: { _ in detail },
                updateRequest: { _ in },
                reportPost: { request in
                    reportedPostIds.append(request.postId)
                    throw CommunityIdentificationTestError.expected
                },
                submitIdentification: { _ in },
                withdrawIdentification: { _ in },
                restoreIdentification: { _ in },
                currentUserId: { nil },
                requestDidChange: { _ in },
                successFeedback: {},
                selectionFeedback: {},
                errorFeedback: { errorFeedbackCount += 1 },
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.report(detail)

        #expect(reportedPostIds == [detail.postId])
        #expect(!viewModel.isReporting)
        #expect(viewModel.toastMessage != nil)
        #expect(errorFeedbackCount == 1)
    }

    @Test func presentationCallbacksRetainMutationSuccessOrdering() async throws {
        let detail = try CommunityIdentificationTestFixtures.detail()
        let taxon = CommunityIdentificationTestFixtures.taxon()
        var events: [String] = []

        let viewModel = CommunityIdentificationDetailViewModel(
            requestId: detail.requestId,
            dependencies: CommunityIdentificationDetailViewModel.Dependencies(
                loadDetail: { _ in
                    events.append("load")
                    return detail
                },
                updateRequest: { _ in events.append("update") },
                reportPost: { _ in },
                submitIdentification: { _ in events.append("submit") },
                withdrawIdentification: { _ in },
                restoreIdentification: { _ in },
                currentUserId: { nil },
                requestDidChange: { _ in events.append("event") },
                successFeedback: { events.append("success") },
                selectionFeedback: {},
                errorFeedback: {},
                errorMessage: { _ in "expected error" }
            )
        )

        _ = await viewModel.updateRequest(
            note: nil,
            locationSharing: .obscured,
            onUpdated: { events.append("dismiss edit") }
        )

        #expect(events == ["update", "load", "dismiss edit", "success"])

        events = []
        _ = await viewModel.submit(
            taxon: taxon,
            disagreementMode: .implicitSupport,
            reasoning: nil,
            isGenusBestPossible: false,
            onSubmitted: { events.append("dismiss resolver") }
        )

        #expect(
            events
                == ["submit", "dismiss resolver", "success", "load", "event"]
        )
    }
}
