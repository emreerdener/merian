import Foundation

@MainActor
extension SharedMediaNativeOriginalOwner {
    func reserveAppPreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePreparationAttempt {
        try await appPreparationWorkflow { try $0.reserve(original: original, recipe: recipe) }
    }
    func activeAppPreparation(packageID: UUID) async throws -> SharedMediaNativePreparationAttempt? {
        try await appPreparationWorkflow { try $0.active(packageID: packageID) }
    }
    func abandonAppPreparation(_ request: SharedMediaNativePreparationAttempt) async throws {
        try await appPreparationWorkflow { try $0.abandon(request) }
    }
}
