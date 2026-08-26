import Foundation
import Observation

@MainActor
@Observable
final class CommunityTaxonomySearchViewModel {
    struct Dependencies {
        let debounce: @MainActor () async throws -> Void
        let search: @MainActor (_ query: String, _ taxonomyVersionId: String?) async throws
            -> [CommunityTaxonSearchResult]
        let isCancellation: @MainActor (Error) -> Bool
        let errorMessage: @MainActor (Error) -> String
    }

    var results: [CommunityTaxonSearchResult] = []
    var isSearching = false
    var errorMessage: String?

    private let dependencies: Dependencies
    private var activeSearchId: UUID?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func search(query: String, taxonomyVersionId: String?) async {
        let searchId = UUID()
        activeSearchId = searchId

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer {
            if activeSearchId == searchId {
                isSearching = false
            }
        }

        do {
            try await dependencies.debounce()
            let searchResults = try await dependencies.search(trimmed, taxonomyVersionId)
            try Task.checkCancellation()
            guard activeSearchId == searchId else { return }

            results = searchResults
            errorMessage = searchResults.isEmpty ? "No matching taxa found." : nil
        } catch {
            guard activeSearchId == searchId,
                  !dependencies.isCancellation(error),
                  !Task.isCancelled else {
                return
            }
            errorMessage = dependencies.errorMessage(error)
        }
    }
}
