import Foundation

enum PurchaseHandoffPreparationError: Error {
    case invalidStableBinding
}

struct PurchaseHandoffPreparationJournal {
    let persistLegacyHandoff: @MainActor (
        PendingSignOutPurchaseHandoff
    ) throws -> Void
    let persistStableRotation: @MainActor (
        ServerPrincipalRotation
    ) throws -> Void
}

struct PurchaseHandoffPreparationOperations {
    let currentCapabilityFingerprint: @MainActor () throws -> String
    let makeRotationID: @MainActor () -> UUID
    let makeRotationSecret: @MainActor () throws -> String
    let currentTimestamp: @MainActor () -> String
    let prepareStableRotation: @MainActor (
        UUID,
        String,
        PurchasePrincipalBinding,
        String
    ) async throws -> PrincipalRotationPreparation
    let prepareLegacyHandoff: @MainActor () async throws
        -> LegacyPurchaseIdentityHandoffPreparation
}

struct PurchaseHandoffPreparationDependencies {
    let journal: PurchaseHandoffPreparationJournal
    let operations: PurchaseHandoffPreparationOperations
}

/// Constructs and persists source-side purchase-continuity proofs. Auth-session
/// fencing remains with the Auth coordinator that invokes this owner.
@MainActor
struct PurchaseHandoffPreparationCoordinator {
    let dependencies: PurchaseHandoffPreparationDependencies

    func prepareStableRotation(
        sourceUserID: UUID,
        binding: PurchasePrincipalBinding
    ) async throws {
        guard binding.mode == .stable,
              let principalID = binding.purchasePrincipalId,
              let appUserID = binding.revenueCatAppUserId,
              let bindingGeneration = binding.bindingGeneration,
              bindingGeneration > 0 else {
            throw PurchaseHandoffPreparationError
                .invalidStableBinding
        }

        let capabilityFingerprint = try dependencies.operations
            .currentCapabilityFingerprint()
        let rotationID = dependencies.operations.makeRotationID()
        let rotationSecret = try dependencies.operations.makeRotationSecret()
        let draft = ServerPrincipalRotation(
            protocolVersion: 3,
            localState: .preparing,
            rotationId: rotationID.uuidString.lowercased(),
            rotationSecret: rotationSecret,
            sourceUserId: sourceUserID.uuidString.lowercased(),
            purchasePrincipalId: principalID.uuidString.lowercased(),
            revenueCatAppUserId: appUserID,
            bindingGeneration: bindingGeneration,
            installationCapabilityFingerprint: capabilityFingerprint,
            startedAt: dependencies.operations.currentTimestamp(),
            expiresAt: nil
        )

        // Persist the idempotency key and proof before network I/O. Relaunch
        // can cancel an absent, in-flight, or already-prepared reservation.
        try dependencies.journal.persistStableRotation(draft)
        try Task.checkCancellation()
        let preparation = try await dependencies.operations
            .prepareStableRotation(
                rotationID,
                rotationSecret,
                binding,
                capabilityFingerprint
            )
        let prepared = ServerPrincipalRotation(
            protocolVersion: 3,
            localState: .prepared,
            rotationId: rotationID.uuidString.lowercased(),
            rotationSecret: rotationSecret,
            sourceUserId: sourceUserID.uuidString.lowercased(),
            purchasePrincipalId:
                preparation.purchasePrincipalId.uuidString.lowercased(),
            revenueCatAppUserId: preparation.revenueCatAppUserId,
            bindingGeneration: preparation.bindingGeneration,
            installationCapabilityFingerprint: capabilityFingerprint,
            startedAt: draft.startedAt,
            expiresAt: preparation.expiresAt
        )
        try dependencies.journal.persistStableRotation(prepared)
        try Task.checkCancellation()
    }

    func prepareLegacyHandoff(sourceUserID: UUID) async throws {
        let preparation = try await dependencies.operations
            .prepareLegacyHandoff()
        let pending = PendingSignOutPurchaseHandoff(
            sourceUserId: sourceUserID.uuidString.lowercased(),
            handoffId: preparation.handoffID,
            handoffSecret: preparation.handoffSecret,
            expiresAt: preparation.expiresAt
        )
        try dependencies.journal.persistLegacyHandoff(pending)
        try Task.checkCancellation()
    }
}
