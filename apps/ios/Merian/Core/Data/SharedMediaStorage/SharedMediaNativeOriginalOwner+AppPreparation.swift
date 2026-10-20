import Foundation

@MainActor
extension SharedMediaNativeOriginalOwner {
    func prepareAndPlanAppPhoto(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairPlan {
        try await appPreparationWorkflow { try await $0.prepareAndPlan(original: original, recipe: recipe) }
    }
    func savedAppPlan(packageID: UUID, pairID: UUID) async throws -> SharedMediaNativePairPlan {
        try await appPreparationWorkflow { try $0.savedPlan(packageID: packageID, pairID: pairID) }
    }
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
