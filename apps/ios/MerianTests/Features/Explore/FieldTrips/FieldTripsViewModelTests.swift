@testable import Merian
import Testing

@MainActor
struct FieldTripsViewModelTests {
    @Test func catalogLoadRefreshAndErrorsRemainIndependent() async throws {
        let template = FieldTripTestFixtures.template()
        let challenge = try FieldTripTestFixtures.challenge()
        var templateLoadCount = 0
        var challengeLoadCount = 0

        let viewModel = FieldTripsViewModel(
            dependencies: FieldTripsViewModel.Dependencies(
                loadTemplates: { region in
                    #expect(region == "midwest")
                    templateLoadCount += 1
                    if templateLoadCount == 1 {
                        throw FieldTripTestError.expected
                    }
                    return [template]
                },
                loadChallenges: { region in
                    #expect(region == "midwest")
                    challengeLoadCount += 1
                    if challengeLoadCount == 2 {
                        throw FieldTripTestError.expected
                    }
                    return [challenge]
                },
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.load(userRegion: "midwest")

        #expect(viewModel.templates.isEmpty)
        #expect(viewModel.errorMessage == "expected error")
        #expect(viewModel.challenges.map(\.challengeId) == [challenge.challengeId])
        #expect(viewModel.challengeErrorMessage == nil)
        #expect(!viewModel.isLoading)

        await viewModel.load(userRegion: "midwest")
        #expect(templateLoadCount == 1)
        #expect(challengeLoadCount == 1)

        await viewModel.refresh(userRegion: "midwest")

        #expect(viewModel.templates.map(\.templateId) == [template.templateId])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.challenges.map(\.challengeId) == [challenge.challengeId])
        #expect(viewModel.challengeErrorMessage == "expected error")
        #expect(templateLoadCount == 2)
        #expect(challengeLoadCount == 2)
    }
}
