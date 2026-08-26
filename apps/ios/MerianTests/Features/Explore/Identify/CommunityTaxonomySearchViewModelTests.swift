@testable import Merian
import Testing

@MainActor
@Suite("Community Taxonomy Search View Model")
struct CommunityTaxonomySearchViewModelTests {
    @Test func minimumQueryTrimmingAndPinnedTaxonomyVersionRemainStable() async {
        let taxon = CommunityIdentificationTestFixtures.taxon()
        var searches: [(String, String?)] = []
        let viewModel = CommunityTaxonomySearchViewModel(
            dependencies: CommunityTaxonomySearchViewModel.Dependencies(
                debounce: {},
                search: { query, taxonomyVersionId in
                    searches.append((query, taxonomyVersionId))
                    return [taxon]
                },
                isCancellation: { _ in false },
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.search(query: " h ", taxonomyVersionId: "taxonomy-v1")

        #expect(searches.isEmpty)
        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.isSearching)

        await viewModel.search(query: "  hawk  ", taxonomyVersionId: "taxonomy-v1")

        #expect(searches.count == 1)
        #expect(searches.first?.0 == "hawk")
        #expect(searches.first?.1 == "taxonomy-v1")
        #expect(viewModel.results == [taxon])
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isSearching)
    }

    @Test func emptyAndFailedSearchesKeepDistinctFeedback() async {
        var shouldFail = false
        let viewModel = CommunityTaxonomySearchViewModel(
            dependencies: CommunityTaxonomySearchViewModel.Dependencies(
                debounce: {},
                search: { _, _ in
                    if shouldFail {
                        throw CommunityIdentificationTestError.expected
                    }
                    return []
                },
                isCancellation: { _ in false },
                errorMessage: { _ in "search failed" }
            )
        )

        await viewModel.search(query: "hawk", taxonomyVersionId: nil)
        #expect(viewModel.errorMessage == "No matching taxa found.")

        shouldFail = true
        await viewModel.search(query: "eagle", taxonomyVersionId: nil)
        #expect(viewModel.errorMessage == "search failed")
        #expect(!viewModel.isSearching)
    }
}
