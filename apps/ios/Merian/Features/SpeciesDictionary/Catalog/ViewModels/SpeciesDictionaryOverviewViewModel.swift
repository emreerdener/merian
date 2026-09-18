import Foundation
import Observation

@MainActor
@Observable
final class SpeciesDictionaryOverviewViewModel {
    struct Dependencies {
        let loadOverview: @MainActor (
            _ userRegion: String?
        ) async throws -> SpeciesDictionaryOverviewResponse
        let errorMessage: @MainActor (any Error) -> String
        var now: @MainActor () -> Date = { Date() }
    }

    private(set) var overview: SpeciesDictionaryOverview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var loadedRegion: String?
    @ObservationIgnored private var loadedAt: Date?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    /// Navigation reuses recent content; stale content stays visible during refresh.
    func loadIfNeeded(userRegion: String?) async {
        let region = Self.normalizedRegion(userRegion)
        if overview != nil, loadedRegion == region, let loadedAt,
           dependencies.now().timeIntervalSince(loadedAt) < 5 * 60 {
            return
        }
        await load(userRegion: region)
    }

    /// Explicit refresh and retry always fetch, independent of the freshness window.
    func load(userRegion: String?) async {
        let region = Self.normalizedRegion(userRegion)
        requestGeneration += 1
        let generation = requestGeneration
        if loadedRegion != region {
            overview = nil
            loadedAt = nil
        }
        isLoading = true
        errorMessage = nil

        defer {
            if requestGeneration == generation {
                isLoading = false
            }
        }

        do {
            let response = try await dependencies.loadOverview(
                region
            )
            guard !Task.isCancelled,
                  requestGeneration == generation
            else {
                return
            }
            overview = response.data
            loadedRegion = region
            loadedAt = dependencies.now()
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

    private static func normalizedRegion(_ region: String?) -> String? {
        region?.trimmedNonEmptyValue?.uppercased()
    }
}
