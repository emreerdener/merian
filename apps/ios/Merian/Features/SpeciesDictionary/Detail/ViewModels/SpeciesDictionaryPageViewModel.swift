import Observation

@MainActor
@Observable
final class SpeciesDictionaryPageViewModel {
    struct Dependencies {
        let loadSpecies: @MainActor (
            SpeciesDictionaryDetailRequest
        ) async throws -> SpeciesDictionaryEntry
        let classifyLoadError: @MainActor (
            any Error
        ) -> SpeciesDictionaryPageLoadFailure
        let track: @MainActor (
            SpeciesDictionaryDetailTelemetryEvent
        ) -> Void
    }

    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint
    private(set) var state: SpeciesDictionaryPageState = .idle

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var hasTrackedOpen = false
    @ObservationIgnored private var requestGeneration: UInt64 = 0

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown,
        dependencies: Dependencies = .live
    ) {
        let request = SpeciesDictionaryDetailRequest(
            speciesId: speciesId,
            scientificName: scientificName
        )
        self.scientificName = request.scientificName ?? ""
        self.speciesId = request.speciesId
        self.entryPoint = entryPoint
        self.dependencies = dependencies
    }

    var loadedSpecies: SpeciesDictionaryEntry? {
        if case .loaded(let species) = state {
            return species
        }
        return nil
    }

    func load() async {
        trackOpenIfNeeded()

        requestGeneration &+= 1
        let generation = requestGeneration
        let request = SpeciesDictionaryDetailRequest(
            speciesId: speciesId,
            scientificName: scientificName
        )

        guard request.speciesId != nil || request.scientificName != nil else {
            state = .notFound
            dependencies.track(.notFound(entryPoint: entryPoint.rawValue))
            return
        }

        state = .loading

        do {
            let species = try await dependencies.loadSpecies(request)
            guard isCurrent(generation) else { return }

            state = .loaded(species)
            dependencies.track(.loaded(
                entryPoint: entryPoint.rawValue,
                contentQuality: species.effectiveContentQuality.telemetryValue
            ))
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(generation) else { return }

            switch dependencies.classifyLoadError(error) {
            case .notFound:
                state = .notFound
                dependencies.track(.notFound(
                    entryPoint: entryPoint.rawValue
                ))
            case .message(let message):
                state = .error(message)
            }
        }
    }

    func retry() async {
        dependencies.track(.retry(entryPoint: entryPoint.rawValue))
        await load()
    }

    private func trackOpenIfNeeded() {
        guard !hasTrackedOpen else { return }
        hasTrackedOpen = true
        dependencies.track(.opened(entryPoint: entryPoint.rawValue))
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        !Task.isCancelled && requestGeneration == generation
    }
}
