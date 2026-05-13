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
    var state: SpeciesDictionaryPageState = .idle

    init(scientificName: String) {
        self.scientificName = scientificName
    }

    var loadedSpecies: SpeciesDictionaryEntry? {
        if case .loaded(let species) = state {
            return species
        }
        return nil
    }

    func load() async {
        let trimmedName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state = .notFound
            return
        }

        state = .loading

        do {
            let species = try await MerianNetworkClient.shared.getSpeciesDictionary(scientificName: trimmedName)
            state = .loaded(species)
        } catch let error as MerianError {
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                state = .notFound
            } else {
                state = .error(Self.displayMessage(for: error))
            }
        } catch {
            state = .error(Self.displayMessage(for: error))
        }
    }

    func retry() async {
        await load()
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
