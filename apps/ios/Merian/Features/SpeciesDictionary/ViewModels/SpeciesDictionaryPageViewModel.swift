import Foundation
import Observation

enum SpeciesDictionaryPageState: Equatable {
    case idle
    case loading
    case loaded(SpeciesDictionaryEntry)
    case notFound
    case error(String)
}

@MainActor
@Observable
final class SpeciesDictionaryPageViewModel {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint
    var state: SpeciesDictionaryPageState = .idle
    private var hasTrackedOpen = false

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown
    ) {
        self.scientificName = scientificName
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.entryPoint = entryPoint
    }

    var loadedSpecies: SpeciesDictionaryEntry? {
        if case .loaded(let species) = state {
            return species
        }
        return nil
    }

    func load() async {
        trackOpenIfNeeded()

        let trimmedName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speciesId != nil || !trimmedName.isEmpty else {
            state = .notFound
            AppTelemetry.trackSpeciesDictionaryNotFound(entryPoint: entryPoint.rawValue)
            return
        }

        state = .loading

        do {
            let species: SpeciesDictionaryEntry
            if let speciesId {
                species = try await MerianNetworkClient.shared.getSpeciesDictionary(
                    speciesId: speciesId,
                    scientificName: trimmedName.nilIfEmpty
                )
            } else {
                species = try await MerianNetworkClient.shared.getSpeciesDictionary(scientificName: trimmedName)
            }
            state = .loaded(species)
            AppTelemetry.trackSpeciesDictionaryLoaded(
                entryPoint: entryPoint.rawValue,
                contentQuality: species.effectiveContentQuality.telemetryValue
            )
        } catch let error as MerianError {
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                state = .notFound
                AppTelemetry.trackSpeciesDictionaryNotFound(entryPoint: entryPoint.rawValue)
            } else {
                state = .error(Self.displayMessage(for: error))
            }
        } catch {
            state = .error(Self.displayMessage(for: error))
        }
    }

    func retry() async {
        AppTelemetry.trackSpeciesDictionaryRetry(entryPoint: entryPoint.rawValue)
        await load()
    }

    private func trackOpenIfNeeded() {
        guard !hasTrackedOpen else { return }
        hasTrackedOpen = true
        AppTelemetry.trackSpeciesDictionaryOpened(entryPoint: entryPoint.rawValue)
    }

    private static func displayMessage(for error: Error) -> String {
        if let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return localized
        }
        return "Unable to load this species right now."
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
