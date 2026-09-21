import Foundation

@MainActor
struct SpeciesDictionaryDetailDependencies {
    let page: SpeciesDictionaryPageViewModel.Dependencies
    let communitySightings: SpeciesCommunitySightingsViewModel.Dependencies
    let presentation: SpeciesDetailPresentationDependencies
    let makeExploreViewModel: @MainActor () -> ExploreFeedViewModel
}

@MainActor
struct SpeciesDetailPresentationDependencies {
    let makeFieldChatViewModel: @MainActor () -> InsightChatViewModel
    let isProActive: @MainActor () -> Bool
    let feedback: @MainActor (SpeciesDictionaryDetailFeedbackEffect) -> Void
    let track: @MainActor (SpeciesDictionaryDetailTelemetryEvent) -> Void
}

extension SpeciesDictionaryDetailDependencies {
    static var live: Self {
        Self(
            page: .live,
            communitySightings: .live,
            presentation: .live,
            makeExploreViewModel: { ExploreFeedViewModel() }
        )
    }
}

extension SpeciesDictionaryPageViewModel.Dependencies {
    static var live: Self {
        live(networkClient: .shared)
    }

    static func live(networkClient: MerianNetworkClient) -> Self {
        Self(
            loadSpecies: { request in
                if let speciesId = request.speciesId {
                    return try await networkClient.getSpeciesDictionary(
                        speciesId: speciesId,
                        scientificName: request.scientificName
                    )
                }
                guard let scientificName = request.scientificName else {
                    throw MerianError.invalidResponse
                }
                return try await networkClient.getSpeciesDictionary(
                    scientificName: scientificName
                )
            },
            classifyLoadError: { error in
                if let error = error as? MerianError,
                   case .httpError(let statusCode, _) = error,
                   statusCode == 404 {
                    return .notFound
                }

                let localized = error.localizedDescription
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .message(
                    localized.isEmpty
                        ? "Unable to load this species right now."
                        : localized
                )
            },
            track: SpeciesDictionaryDetailLiveTelemetry.track,
            resolveSpecies: { name in
                let identity = try await networkClient.resolveSpeciesDictionary(scientificName: name)
                try Task.checkCancellation()
                // Fetch by canonical UUID; synonyms must not alias the public name cache.
                let species = try await networkClient.getSpeciesDictionary(
                    speciesId: identity.speciesId,
                    scientificName: identity.scientificName
                )
                // Ordinary detail reads allow stale-ID recovery by name. A
                // resolution must stay bound to the identity just verified.
                guard SpeciesDictionaryIdentity.canonicalSpeciesID(species.id) ==
                    SpeciesDictionaryIdentity.canonicalSpeciesID(identity.speciesId) else {
                    throw MerianError.invalidResponse
                }
                return species
            }
        )
    }
}

extension SpeciesCommunitySightingsViewModel.Dependencies {
    static var live: Self {
        let networkClient = MerianNetworkClient.shared
        return Self { speciesId, limit, cursor in
            try await networkClient.getExploreSpeciesPosts(
                speciesId: speciesId,
                limit: limit,
                cursor: cursor
            )
        }
    }
}

extension SpeciesDetailPresentationDependencies {
    static var live: Self {
        let container = AppDIContainer.shared
        return Self(
            makeFieldChatViewModel: {
                InsightChatViewModel(source: .speciesDictionary)
            },
            isProActive: { container.revenueCatManager.isProActive },
            feedback: { effect in
                switch effect {
                case .selection:
                    container.hapticManager.triggerSelectionPulse()
                case .sheet:
                    container.hapticManager.triggerSheetSpring()
                case .error:
                    container.hapticManager.triggerErrorThump()
                }
            },
            track: SpeciesDictionaryDetailLiveTelemetry.track
        )
    }
}

@MainActor
private enum SpeciesDictionaryDetailLiveTelemetry {
    static func track(_ event: SpeciesDictionaryDetailTelemetryEvent) {
        switch event {
        case .opened(let entryPoint):
            AppTelemetry.trackSpeciesDictionaryOpened(entryPoint: entryPoint)
        case .loaded(let entryPoint, let contentQuality):
            AppTelemetry.trackSpeciesDictionaryLoaded(
                entryPoint: entryPoint,
                contentQuality: contentQuality
            )
        case .notFound(let entryPoint):
            AppTelemetry.trackSpeciesDictionaryNotFound(
                entryPoint: entryPoint
            )
        case .retry(let entryPoint):
            AppTelemetry.trackSpeciesDictionaryRetry(entryPoint: entryPoint)
        case .imageFallback(let entryPoint, let source):
            AppTelemetry.trackSpeciesDictionaryImageFallback(
                entryPoint: entryPoint,
                source: source
            )
        case .fieldChatTapped(
            let entryPoint,
            let contentQuality,
            let isPro
        ):
            AppTelemetry.trackSpeciesDictionaryFieldChatTapped(
                entryPoint: entryPoint,
                contentQuality: contentQuality,
                isPro: isPro
            )
        }
    }
}
