import Foundation
import Observation

@MainActor
@Observable
final class FieldTripsViewModel {
    struct Dependencies {
        let loadTemplates: @MainActor (_ userRegion: String?) async throws -> [FieldTripTemplate]
        let loadChallenges: @MainActor (_ userRegion: String?) async throws -> [FieldTripChallenge]
        let errorMessage: @MainActor (Error) -> String
    }

    var templates: [FieldTripTemplate] = []
    var challenges: [FieldTripChallenge] = []
    var isLoading = false
    var errorMessage: String?
    var challengeErrorMessage: String?
    var toastMessage: ToastPayload?

    private let dependencies: Dependencies
    private var didLoad = false

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func load(
        userRegion: String? = nil,
        force: Bool = false
    ) async {
        guard force || !didLoad else { return }
        isLoading = true
        errorMessage = nil
        challengeErrorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }

        do {
            templates = try await dependencies.loadTemplates(userRegion)
        } catch {
            errorMessage = dependencies.errorMessage(error)
        }

        do {
            challenges = try await dependencies.loadChallenges(userRegion)
        } catch {
            challengeErrorMessage = dependencies.errorMessage(error)
        }
    }

    func refresh(userRegion: String? = nil) async {
        await load(userRegion: userRegion, force: true)
    }

    func template(withId templateId: String) -> FieldTripTemplate? {
        templates.first { $0.templateId == templateId }
    }

    func replaceTemplate(_ template: FieldTripTemplate) {
        guard let index = templates.firstIndex(where: { $0.templateId == template.templateId }) else {
            return
        }
        templates[index] = template
    }

    func challenge(withId challengeId: String) -> FieldTripChallenge? {
        challenges.first { $0.challengeId == challengeId }
    }

    func replaceChallenge(_ challenge: FieldTripChallenge) {
        guard let index = challenges.firstIndex(where: { $0.challengeId == challenge.challengeId }) else {
            return
        }
        challenges[index] = challenge
    }
}
