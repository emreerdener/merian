@testable import Merian
import Testing

@MainActor
@Suite("Identify Dashboard View Model")
struct IdentifyDashboardViewModelTests {
    @Test func loadRefreshAndSectionErrorsRemainIndependent() async throws {
        let requestItem = try CommunityIdentificationTestFixtures.requestItem()
        let activityItem = try CommunityIdentificationTestFixtures.activityItem()
        var requestLoads: [IdentifyRequestPageRequest] = []
        var activityLoads: [IdentifyActivityPageRequest] = []
        var shouldFailRequests = true
        var shouldFailActivity = false

        let viewModel = IdentifyDashboardViewModel(
            dependencies: IdentifyDashboardViewModel.Dependencies(
                loadRequests: { request in
                    requestLoads.append(request)
                    if shouldFailRequests {
                        throw CommunityIdentificationTestError.expected
                    }
                    return [requestItem]
                },
                loadActivity: { request in
                    activityLoads.append(request)
                    if shouldFailActivity {
                        throw CommunityIdentificationTestError.expected
                    }
                    return [activityItem]
                },
                requestErrorMessage: { _ in "requests failed" },
                activityErrorMessage: { _ in "activity failed" }
            )
        )

        await viewModel.reload(
            filter: .birds,
            latitude: 30.25,
            longitude: -97.75,
            clearExisting: true
        )

        #expect(viewModel.requestItems.isEmpty)
        #expect(viewModel.loadState.requestErrorMessage == "requests failed")
        #expect(viewModel.activityItems == [activityItem])
        #expect(viewModel.loadState.activityErrorMessage == nil)
        #expect(requestLoads.first?.limit == 12)
        #expect(requestLoads.first?.filter == .birds)
        #expect(requestLoads.first?.latitude == 30.25)
        #expect(requestLoads.first?.longitude == -97.75)
        #expect(activityLoads.first?.limit == 10)
        #expect(activityLoads.first?.filter == .birds)

        shouldFailRequests = false
        shouldFailActivity = true

        await viewModel.reload(
            filter: .mine,
            latitude: nil,
            longitude: nil,
            clearExisting: false
        )

        #expect(viewModel.requestItems == [requestItem])
        #expect(viewModel.loadState.requestErrorMessage == nil)
        #expect(viewModel.activityItems == [activityItem])
        #expect(viewModel.loadState.activityErrorMessage == "activity failed")
        #expect(requestLoads.last?.filter == .mine)
        #expect(activityLoads.last?.filter == .mine)
    }

    @Test func individualRetriesOnlyReloadTheirOwnedSection() async throws {
        let requestItem = try CommunityIdentificationTestFixtures.requestItem()
        let activityItem = try CommunityIdentificationTestFixtures.activityItem()
        var requestLoadCount = 0
        var activityLoadCount = 0

        let viewModel = IdentifyDashboardViewModel(
            dependencies: IdentifyDashboardViewModel.Dependencies(
                loadRequests: { _ in
                    requestLoadCount += 1
                    return [requestItem]
                },
                loadActivity: { _ in
                    activityLoadCount += 1
                    return [activityItem]
                },
                requestErrorMessage: { _ in "requests failed" },
                activityErrorMessage: { _ in "activity failed" }
            )
        )

        await viewModel.reload(
            filter: .all,
            latitude: nil,
            longitude: nil,
            clearExisting: true
        )
        await viewModel.reloadRequests(
            filter: .all,
            latitude: nil,
            longitude: nil
        )
        await viewModel.reloadActivity(filter: .all)

        #expect(requestLoadCount == 2)
        #expect(activityLoadCount == 2)
        #expect(viewModel.contains(requestId: requestItem.requestId))
        #expect(viewModel.contains(requestId: activityItem.requestId))
    }
}
