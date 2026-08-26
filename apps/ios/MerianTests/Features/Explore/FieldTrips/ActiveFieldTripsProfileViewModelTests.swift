@testable import Merian
import Testing

@MainActor
struct ActiveFieldTripsProfileViewModelTests {
    @Test func activeProfileLoadsItemsPatchesAndSignedOutState() async {
        let template = FieldTripTestFixtures.template(
            activeProgress: FieldTripTestFixtures.progress(
                currentLevelNumber: 2,
                completedCount: 1
            )
        )
        var requestedLimit: Int?
        var patchUpdates: [[EarnedFieldTripPatch]] = []
        var loadingUpdates: [Bool] = []

        let viewModel = ActiveFieldTripsProfileViewModel(
            dependencies: ActiveFieldTripsProfileViewModel.Dependencies(
                loadTemplates: { limit in
                    requestedLimit = limit
                    return [template]
                },
                earnedPatchesDidChange: { patchUpdates.append($0) },
                loadingDidChange: { loadingUpdates.append($0) }
            )
        )

        await viewModel.load(isAuthenticated: true)

        #expect(requestedLimit == 80)
        #expect(viewModel.items.map(\.template.templateId) == [template.templateId])
        #expect(patchUpdates.last?.map(\.imageName) == [
            "fieldtrip-backyard-level-1-patch"
        ])
        #expect(loadingUpdates == [true, false])
        #expect(viewModel.hasLoaded)
        #expect(!viewModel.isLoading)

        await viewModel.load(isAuthenticated: false)

        #expect(viewModel.items.isEmpty)
        #expect(patchUpdates.last?.isEmpty == true)
        #expect(loadingUpdates == [true, false, false])
    }
}
