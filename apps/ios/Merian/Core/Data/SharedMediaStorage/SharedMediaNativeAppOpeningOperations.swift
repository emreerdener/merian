import Foundation
import SwiftData

/// Executes only an already-authorized open. The registered owner alone mints
/// grants, retains the repository, promotes its state and publishes readiness.
@MainActor
enum SharedMediaNativeAppOpeningOperations {
    static func open(container: ModelContainer, parent: URL, inventoryID: UUID, ownerID: UUID,
        discovery: SharedMediaNativeBootstrapDiscovery?, initialization: SharedMediaNativeAppGrant?,
        initializationOnly: Bool, retain: (SharedMediaNativeStorageRepository) -> Void,
        dispatch: (SharedMediaNativeAppProfile) -> SharedMediaNativeAppDispatchGrant) async throws -> SharedMediaNativeAppOpenResult {
        let candidate: SharedMediaNativeStorageRepository, grant: SharedMediaNativeAppDispatchGrant
        if let initialization {
            candidate = try .initializeApp(container: container, parent: parent, inventoryID: inventoryID,
                grant: initialization, discovery: discovery)
            retain(candidate)
            let snapshot = try candidate.appInitializationSnapshot(grant: initialization)
            try initialization.validate()
            if initializationOnly { return .initialization(snapshot) }
            let profile = try candidate.promoteInitializedApp(grant: initialization, parent: parent)
            // Synchronous callback: paired owner promotion and dispatch minting
            // follow repository promotion with no suspension or throwing gap.
            grant = dispatch(profile)
        } else {
            guard !initializationOnly else { throw SharedMediaStorageFailure.closed }
            // The owner selects this branch only for an existing profile.
            let profile = try SharedMediaNativeAppEligibility.identity(container: container,
                inventoryID: inventoryID, ownerID: ownerID)
            grant = dispatch(profile)
            #if DEBUG
            grant.debug.inspectionTrace?.enter(.repository)
            #endif
            candidate = try .openApp(container: container, parent: parent, inventoryID: inventoryID,
                grant: grant, discovery: discovery)
            retain(candidate)
        }
        #if DEBUG
        grant.debug.inspectionTrace?.enter(.inspect)
        #endif
        let snapshot = try await candidate.inspectApp(grant: grant)
        try grant.validate()
        return .dispatch(snapshot)
    }
}
