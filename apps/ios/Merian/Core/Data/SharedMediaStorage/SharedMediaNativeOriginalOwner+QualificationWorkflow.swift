import Foundation

/// Inactive V1 workflow conveniences. The owner retains dispatch, account drain,
/// writer activity and settlement. Bodies receive only its typed scoped helper.
@MainActor
extension SharedMediaNativeOriginalOwner {
    func prepareShare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) async throws -> SharedMediaNativeShareRequest {
        try await qualificationWorkflow { operations in try operations.lifecycleOperations().prepareShare(source, packageID: packageID, draftGeneration: draftGeneration) }
    }

    func share(_ request: SharedMediaNativeShareRequest) async throws -> PhotoOriginalReference {
        try await qualificationWorkflow { operations in try operations.lifecycleOperations().share(request) }
    }

    func prepareRemoval(_ source: PhotoOriginalReference) async throws -> SharedMediaNativeRemovalRequest {
        try await qualificationWorkflow { operations in try operations.lifecycleOperations().prepareRemoval(source) }
    }

    func remove(_ request: SharedMediaNativeRemovalRequest) async throws {
        try await qualificationWorkflow { operations in try await operations.lifecycleOperations().remove(request) }
        try await recoverRetirements()
    }

    func recoverRetirements() async throws {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.lifecycleOperations().recoverRetirements() }
    }

    func abandonPendingAcquisition(_ request: SharedMediaAcquisitionIntent) async throws {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.lifecycleOperations().abandon(request) }
        try await recoverPendingAbandonments()
    }

    func recoverPendingAbandonments() async throws {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.lifecycleOperations().recoverPendingAbandonments() }
    }

    func reservePreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePreparationAttempt {
        try await qualificationWorkflow { operations in
            try operations.preparationOperations().reserve(original: original, recipe: recipe)
        }
    }

    func activePreparation(packageID: UUID) async throws -> SharedMediaNativePreparationAttempt? {
        try await qualificationWorkflow(recovery: true) { operations in try operations.preparationOperations().active(packageID: packageID) }
    }

    func abandonPreparation(_ attempt: SharedMediaNativePreparationAttempt) async throws {
        try await qualificationWorkflow(recovery: true) { operations in try operations.preparationOperations().abandon(attempt) }
    }

    func prepareFreeze(packageID: UUID, pairIDs: [UUID], operationID: UUID) async throws -> SharedMediaNativeFreezeRequest {
        try await qualificationWorkflow { operations in
            try await operations.preparationOperations().prepareFreeze(packageID: packageID, pairIDs: pairIDs, operationID: operationID)
        }
    }

    func preparedFileState(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairFileState {
        try await qualificationWorkflow(recovery: true) { operations in try operations.preparationOperations().fileState(packageID: packageID, pairID: pairID) }
    }

    func recoverPreparedFiles(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairFileState {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.preparationOperations().recoverFiles(packageID: packageID, pairID: pairID) }
    }

    func retirePreparedFiles(_ state: SharedMediaNativePairFileState) async throws {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.preparationOperations().retireFiles(state) }
    }

    func plannedPreparation(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairPlan? {
        try await qualificationWorkflow(recovery: true) { operations in try operations.preparationOperations().plan(packageID: packageID, pairID: pairID) }
    }

    func abandonPlannedPreparation(_ plan: SharedMediaNativePairPlan) async throws {
        try await qualificationWorkflow(recovery: true) { operations in try operations.preparationOperations().abandonPlan(plan) }
    }

    func prepareMetadata(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                         presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> SharedMediaNativeMetadataRequest {
        try await qualificationWorkflow { operations in
            try operations.metadata(packageID: packageID)
                .request(draftGeneration: draftGeneration, contexts: contexts, presentation: presentation)
        }
    }

    func saveMetadata(_ request: SharedMediaNativeMetadataRequest) async throws -> Int64 {
        try await qualificationWorkflow { operations in try operations.saveMetadata(request) }
    }

    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.lifecycleOperations().setReleaseFault(fault) }
    }
    #endif

    #if DEBUG
    func qualifyPreparedFiles(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairFileState {
        try await qualificationWorkflow { operations in try await operations.preparationOperations().prepareFiles(original: original, recipe: recipe) }
    }
    #endif

    #if DEBUG
    func setPairFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async throws {
        try await qualificationWorkflow(recovery: true) { operations in try await operations.preparationOperations().setPairFileFault(fault) }
    }
    #endif

    #if DEBUG
    func qualifyPhotoPreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe, savePlan: Bool = false) async throws -> SharedMediaNativePreparedOutputs {
        try await qualificationWorkflow { operations in
            try await operations.preparationOperations().prepare(original: original, recipe: recipe, savePlan: savePlan)
        }
    }
    #endif
}
