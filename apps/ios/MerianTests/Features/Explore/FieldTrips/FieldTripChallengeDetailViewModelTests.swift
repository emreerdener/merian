@testable import Merian
import Testing

@MainActor
struct FieldTripChallengeDetailViewModelTests {
    @Test func eventJoinAndEntryPaginationPreserveCursorOrder() async throws {
        let initial = try FieldTripTestFixtures.challenge(entryCount: 12)
        let joined = try FieldTripTestFixtures.challenge(
            entryCount: 12,
            participation: true
        )
        let nextEntry = FieldTripTestFixtures.challengeEntry(index: 12)
        var pageRequest: FieldTripChallengeDetailViewModel.EntriesPageRequest?
        var progressChangeCount = 0

        let viewModel = FieldTripChallengeDetailViewModel(
            challengeId: initial.challengeId,
            dependencies: FieldTripChallengeDetailViewModel.Dependencies(
                loadChallenge: { challengeId, entriesLimit in
                    #expect(challengeId == initial.challengeId)
                    #expect(entriesLimit == 12)
                    return initial
                },
                joinChallenge: { challengeId in
                    #expect(challengeId == initial.challengeId)
                    return joined
                },
                loadEntriesPage: { request in
                    pageRequest = request
                    return [nextEntry]
                },
                successFeedback: {},
                errorFeedback: {},
                progressDidChange: { progressChangeCount += 1 },
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.load()
        #expect(viewModel.entries.count == 12)
        #expect(viewModel.hasMoreEntries)

        await viewModel.join()
        #expect(viewModel.challenge?.viewerParticipation != nil)
        #expect(viewModel.entries.count == 12)
        #expect(progressChangeCount == 1)

        await viewModel.loadMoreEntries()

        #expect(viewModel.entries.map(\.entryId).last == nextEntry.entryId)
        #expect(viewModel.entries.count == 13)
        #expect(!viewModel.hasMoreEntries)
        #expect(pageRequest?.challengeId == initial.challengeId)
        #expect(pageRequest?.limit == 12)
        #expect(pageRequest?.beforeEntryId == "entry-11")
        #expect(pageRequest?.beforePublishedAt == initial.entries.last?.publishedAt)
    }
}
