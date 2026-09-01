import Observation

@MainActor
@Observable
final class SpeciesDictionaryOverviewViewModel {
    struct Dependencies {
        let loadOverview: @MainActor (
            _ userRegion: String?
        ) async throws -> SpeciesDictionaryOverviewResponse
        let errorMessage: @MainActor (any Error) -> String
    }

    private(set) var overview: SpeciesDictionaryOverview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var requestGeneration = 0

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func load(userRegion: String?) async {
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil

        defer {
            if requestGeneration == generation {
                isLoading = false
            }
        }

        do {
            let response = try await dependencies.loadOverview(
                userRegion?.trimmedNonEmptyValue
            )
            guard !Task.isCancelled,
                  requestGeneration == generation
            else {
                return
            }
            overview = response.data
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  requestGeneration == generation
            else {
                return
            }
            errorMessage = dependencies.errorMessage(error)
        }
    }
}
