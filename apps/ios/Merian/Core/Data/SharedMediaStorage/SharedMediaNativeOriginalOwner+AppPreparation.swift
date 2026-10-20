import Foundation

@MainActor
extension SharedMediaNativeOriginalOwner {
    func prepareAndPlanAppPhoto(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairPlan {
        try await appPreparationWorkflow { try await $0.prepareAndPlan(original: original, recipe: recipe) }
    }
    func prepareAndDeliverAppPhoto(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairFileState {
        try await appPreparationWorkflow { try await $0.prepareAndDeliver(original: original, recipe: recipe) }
    }
    func recoverAppPhotoPair(packageID: UUID, pairID: UUID) async throws -> SharedMediaNativePairFileState {
        try await appPreparationWorkflow { try await $0.recoverFiles(packageID: packageID, pairID: pairID) }
    }
    #if DEBUG
    func setAppPairFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async throws {
        try await appPreparationWorkflow { await $0.setFileFault(fault) }
    }
    #endif
    func savedAppPlan(packageID: UUID, pairID: UUID) async throws -> SharedMediaNativePairPlan {
        try await appPreparationWorkflow { try $0.savedPlan(packageID: packageID, pairID: pairID) }
    }
    func abandonAppPlan(_ plan: SharedMediaNativePairPlan) async throws {
        try await appPreparationWorkflow { try await $0.abandonPlan(plan) }
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
