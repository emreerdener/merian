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
        var resolveSpecies: (@MainActor (String) async throws -> SpeciesDictionaryEntry)? = nil
    }

    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint
    private(set) var state: SpeciesDictionaryPageState = .idle
    private(set) var isResolving = false
    private(set) var resolutionFailed = false

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
        isResolving = false
        resolutionFailed = false
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
            await resolveReferenceEntry(generation: generation)
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

    func retryResolution() async {
        // SwiftUI can restart the retry task when this page reappears. An old
        // retry must not invalidate a newer load or repeat a successful resolve.
        guard resolutionFailed, !isResolving else { return }
        requestGeneration &+= 1
        await resolveReferenceEntry(generation: requestGeneration)
    }

    private func resolveReferenceEntry(generation: UInt64) async {
        guard isCurrent(generation), let reference = loadedSpecies,
              SpeciesDictionaryIdentity.canonicalSpeciesID(reference.id) == nil,
              let resolve = dependencies.resolveSpecies else { return }
        isResolving = true
        resolutionFailed = false
        defer {
            if requestGeneration == generation { isResolving = false }
        }
        do {
            let canonical = try await resolve(reference.scientificName)
            guard isCurrent(generation) else { return }
            guard SpeciesDictionaryIdentity.canonicalSpeciesID(canonical.id) != nil else {
                resolutionFailed = true
                return
            }
            state = .loaded(SpeciesDictionaryResolutionContent.merging(
                canonical: canonical, reference: reference
            ))
        } catch {
            guard isCurrent(generation) else { return }
            resolutionFailed = true
        }
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
