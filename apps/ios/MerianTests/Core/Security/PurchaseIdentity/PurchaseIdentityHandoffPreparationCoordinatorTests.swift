import Foundation
@testable import Merian
import Testing

private actor PurchaseIdentityHandoffPreparationGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        while !released && continuations.isEmpty {
            await Task.yield()
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

@Suite("Purchase Identity Handoff Preparation Coordinator")
@MainActor
struct HandoffPreparationCoordinatorTests {
    private let sourceUserID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    private let principalID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )!
    private let rotationID = UUID(
        uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
    )!

    @Test func stableRotationPersistsDraftBeforeRemoteAndPreparedAfter() async throws {
        var events: [String] = []
        var persisted: [ServerPrincipalRotation] = []
        let binding = try stableBinding()
        let coordinator = makeCoordinator(
            persistStable: { rotation in
                persisted.append(rotation)
                events.append("persist-\(rotation.localState.rawValue)")
            },
            prepareStable: { rotationID, secret, receivedBinding, fingerprint in
                events.append("prepare-remote")
                #expect(rotationID == self.rotationID)
                #expect(secret == "rotation-secret")
                #expect(receivedBinding == binding)
                #expect(fingerprint == String(repeating: "f", count: 64))
                return self.preparation()
            }
        )

        try await coordinator.prepareStableRotation(
            sourceUserID: sourceUserID,
            binding: binding
        )

        #expect(events == [
            "persist-preparing",
            "prepare-remote",
            "persist-prepared"
        ])
        #expect(persisted.count == 2)
        #expect(persisted[0].rotationId == rotationID.uuidString.lowercased())
        #expect(persisted[0].sourceUserId == sourceUserID.uuidString.lowercased())
        #expect(persisted[0].purchasePrincipalId == principalID.uuidString.lowercased())
        #expect(persisted[0].revenueCatAppUserId == "merian_test_principal")
        #expect(persisted[0].bindingGeneration == 7)
        #expect(persisted[0].startedAt == "2026-09-15T12:00:00Z")
        #expect(persisted[0].expiresAt == nil)
        #expect(persisted[1].localState == .prepared)
        #expect(persisted[1].expiresAt == "2026-09-15T12:10:00Z")
    }

    @Test func cancellationAfterRemoteStillPersistsPreparedCheckpoint() async {
        let gate = PurchaseIdentityHandoffPreparationGate()
        var persistedStates: [PrincipalRotationLocalState] = []
        let coordinator = makeCoordinator(
            persistStable: { rotation in
                persistedStates.append(rotation.localState)
            },
            prepareStable: { _, _, _, _ in
                await gate.wait()
                return self.preparation()
            }
        )
        let binding = try! stableBinding()

        let task = Task { @MainActor in
            try await coordinator.prepareStableRotation(
                sourceUserID: sourceUserID,
                binding: binding
            )
        }
        await gate.waitUntilBlocked()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(persistedStates == [.preparing, .prepared])
    }

    @Test func legacyHandoffPersistsNormalizedSourceAndRemoteProof() async throws {
        var persisted: PendingSignOutPurchaseHandoff?
        let coordinator = makeCoordinator(
            persistLegacy: { persisted = $0 },
            prepareLegacy: {
                LegacyPurchaseIdentityHandoffPreparation(
                    handoffID: "dddddddd-dddd-dddd-dddd-dddddddddddd",
                    handoffSecret: "legacy-secret",
                    expiresAt: "2026-09-15T12:10:00Z"
                )
            }
        )

        try await coordinator.prepareLegacyHandoff(
            sourceUserID: sourceUserID
        )

        #expect(persisted == PendingSignOutPurchaseHandoff(
            sourceUserId: sourceUserID.uuidString.lowercased(),
            handoffId: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            handoffSecret: "legacy-secret",
            expiresAt: "2026-09-15T12:10:00Z"
        ))
    }

    @Test func legacyCancellationAfterRemoteStillPersistsProof() async {
        let gate = PurchaseIdentityHandoffPreparationGate()
        var persisted: PendingSignOutPurchaseHandoff?
        let coordinator = makeCoordinator(
            persistLegacy: { persisted = $0 },
            prepareLegacy: {
                await gate.wait()
                return LegacyPurchaseIdentityHandoffPreparation(
                    handoffID: "dddddddd-dddd-dddd-dddd-dddddddddddd",
                    handoffSecret: "legacy-secret",
                    expiresAt: "2026-09-15T12:10:00Z"
                )
            }
        )
        let task = Task { @MainActor in
            try await coordinator.prepareLegacyHandoff(
                sourceUserID: sourceUserID
            )
        }
        await gate.waitUntilBlocked()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(persisted?.sourceUserId == sourceUserID.uuidString.lowercased())
        #expect(persisted?.handoffId
            == "dddddddd-dddd-dddd-dddd-dddddddddddd")
    }

    @Test func invalidStableBindingStopsBeforeJournalOrRemoteEffects() async {
        var events: [String] = []
        let coordinator = makeCoordinator(
            persistStable: { _ in events.append("persist") },
            prepareStable: { _, _, _, _ in
                events.append("remote")
                return self.preparation()
            }
        )

        await #expect(
            throws: PurchaseHandoffPreparationError.self
        ) {
            try await coordinator.prepareStableRotation(
                sourceUserID: sourceUserID,
                binding: .legacyFallback
            )
        }
        #expect(events.isEmpty)
    }

    private func makeCoordinator(
        persistLegacy: @escaping @MainActor (
            PendingSignOutPurchaseHandoff
        ) throws -> Void = { _ in },
        persistStable: @escaping @MainActor (
            ServerPrincipalRotation
        ) throws -> Void = { _ in },
        prepareStable: @escaping @MainActor (
            UUID,
            String,
            PurchasePrincipalBinding,
            String
        ) async throws -> PrincipalRotationPreparation = { _, _, _, _ in
            throw PurchaseHandoffPreparationError.invalidStableBinding
        },
        prepareLegacy: @escaping @MainActor () async throws
            -> LegacyPurchaseIdentityHandoffPreparation = {
                LegacyPurchaseIdentityHandoffPreparation(
                    handoffID: "dddddddd-dddd-dddd-dddd-dddddddddddd",
                    handoffSecret: "legacy-secret",
                    expiresAt: "2026-09-15T12:10:00Z"
                )
            }
    ) -> PurchaseHandoffPreparationCoordinator {
        PurchaseHandoffPreparationCoordinator(
            dependencies: .init(
                journal: .init(
                    persistLegacyHandoff: persistLegacy,
                    persistStableRotation: persistStable
                ),
                operations: .init(
                    currentCapabilityFingerprint: {
                        String(repeating: "f", count: 64)
                    },
                    makeRotationID: { rotationID },
                    makeRotationSecret: { "rotation-secret" },
                    currentTimestamp: { "2026-09-15T12:00:00Z" },
                    prepareStableRotation: prepareStable,
                    prepareLegacyHandoff: prepareLegacy
                )
            )
        )
    }

    private func stableBinding() throws -> PurchasePrincipalBinding {
        try PurchasePrincipalBinding(
            response: PurchasePrincipalResolveResponse(
                success: true,
                mode: "stable",
                purchase_principal_id: principalID.uuidString,
                revenuecat_app_user_id: "merian_test_principal",
                binding_generation: 7,
                account_grants_allowed: true,
                minimum_client_protocol: PurchasePrincipalProtocol.current
            )
        )
    }

    private func preparation() -> PrincipalRotationPreparation {
        PrincipalRotationPreparation(
            rotationId: rotationID,
            purchasePrincipalId: principalID,
            revenueCatAppUserId: "merian_test_principal",
            bindingGeneration: 7,
            expiresAt: "2026-09-15T12:10:00Z"
        )
    }
}
