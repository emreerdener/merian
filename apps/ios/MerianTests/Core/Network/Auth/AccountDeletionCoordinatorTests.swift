import Foundation
@testable import Merian
import XCTest

@MainActor
final class AccountDeletionCoordinatorTests: XCTestCase {
    func testFreshV2DeletionSequencesLiveEffectsAndRetiresProofLast() async throws {
        let harness = AccountDeletionCoordinatorHarness()
        let secureStore = AccountDeletionSecureStoreStub()
        let capabilityStore = secureStore.makeCapabilityStore()
        var recoveryCapability: String?
        var acknowledgementCapability: String?

        let receipt = acceptedReceipt(protocolVersion: 2)
        let result = try await AccountDeletionCoordinator(
            dependencies: harness.makeDependencies()
        ).deleteCurrentAccount(
            prepareDeletionV2: { _, recovery, acknowledgement in
                harness.events.append("prepare-v2")
                recoveryCapability = recovery
                acknowledgementCapability = acknowledgement
                return AccountDeletionPreparationReceipt(
                    success: true,
                    status: .prepared,
                    protocolVersion: 2,
                    recoveryCapabilityExpiresAt: "2026-09-15T00:00:00Z"
                )
            },
            commitDeletionV2: { _, recovery in
                harness.events.append("commit-v2")
                XCTAssertEqual(recovery, recoveryCapability)
                return receipt
            },
            recoverDeletionV2: { _ in
                XCTFail("Fresh accepted intake must not enter recovery")
                return receipt
            },
            requestDeletion: { _, _ in
                XCTFail("A v2 proof must not use the legacy intake")
                return receipt
            },
            acknowledgeDeletion: { _ in
                XCTFail("A v2 proof must not use legacy acknowledgement")
                return self.acknowledgedReceipt(protocolVersion: 1)
            },
            acknowledgeDeletionV2: { acknowledgement in
                harness.events.append("acknowledge-v2")
                XCTAssertEqual(acknowledgement, acknowledgementCapability)
                return self.acknowledgedReceipt(protocolVersion: 2)
            },
            recoveryCapabilityStore: capabilityStore,
            recordManualProviderRevocation: {
                harness.events.append("record-manual-revocation")
            },
            purgeLocalData: {
                harness.events.append("purge")
                return true
            }
        )

        XCTAssertEqual(result, receipt)
        XCTAssertEqual(recoveryCapability?.count, 43)
        XCTAssertEqual(acknowledgementCapability?.count, 43)
        XCTAssertNotEqual(recoveryCapability, acknowledgementCapability)
        XCTAssertNil(harness.recoveryState)
        XCTAssertEqual(
            secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
        XCTAssertEqual(
            harness.events,
            [
                "begin-account-deletion",
                "phase-deletingAccount",
                "verify-session",
                "record-capability-preparation",
                "prepare-v2",
                "record-capability-prepared",
                "record-intake",
                "commit-v2",
                "phase-finalizing",
                "record-cleanup",
                "record-manual-revocation",
                "sign-out",
                "purge",
                "acknowledge-v2",
                "record-capability-retirement",
                "resolve",
                "finish"
            ]
        )
    }

    func testFreshDeletionRejectsPendingPurchaseBeforeTransition() async {
        let harness = AccountDeletionCoordinatorHarness()
        harness.hasPendingPurchaseIdentityHandoff = true

        do {
            _ = try await invokeWithoutNetwork(harness: harness)
            XCTFail("A pending purchase handoff must fence deletion")
        } catch SupabaseAuthTransitionError.signOutPurchaseContinuityPending {
            XCTAssertTrue(harness.events.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFreshDeletionRejectsPreflightCancellationBeforeTransition() async {
        let harness = AccountDeletionCoordinatorHarness()

        let error = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await self.invokeWithoutNetwork(harness: harness)
                return nil as Error?
            } catch {
                return error
            }
        }.value

        XCTAssertTrue(error is CancellationError)
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertNil(harness.recoveryState)
    }

    func testFreshDeletionRejectsExistingRecoveryBeforeTransition() async {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = .capabilityCleanupPending

        do {
            _ = try await invokeWithoutNetwork(harness: harness)
            XCTFail("An existing recovery marker must fence fresh deletion")
        } catch SupabaseAuthTransitionError.accountDeletionRecoveryPending {
            XCTAssertTrue(harness.events.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func invokeWithoutNetwork(
        harness: AccountDeletionCoordinatorHarness
    ) async throws -> AccountDeletionReceipt {
        try await AccountDeletionCoordinator(
            dependencies: harness.makeDependencies()
        ).deleteCurrentAccount(
            prepareDeletionV2: { _, _, _ in
                XCTFail("Network work must remain fenced")
                return self.preparationReceipt
            },
            commitDeletionV2: { _, _ in
                XCTFail("Network work must remain fenced")
                return self.acceptedReceipt(protocolVersion: 2)
            },
            recoverDeletionV2: { _ in
                XCTFail("Network work must remain fenced")
                return self.acceptedReceipt(protocolVersion: 2)
            },
            requestDeletion: { _, _ in
                XCTFail("Network work must remain fenced")
                return self.acceptedReceipt(protocolVersion: 1)
            },
            acknowledgeDeletion: { _ in
                XCTFail("Network work must remain fenced")
                return self.acknowledgedReceipt(protocolVersion: 1)
            },
            acknowledgeDeletionV2: { _ in
                XCTFail("Network work must remain fenced")
                return self.acknowledgedReceipt(protocolVersion: 2)
            },
            recoveryCapabilityStore:
                AccountDeletionSecureStoreStub().makeCapabilityStore(),
            recordManualProviderRevocation: {
                XCTFail("Local work must remain fenced")
            },
            purgeLocalData: {
                XCTFail("Local work must remain fenced")
                return false
            }
        )
    }

    private var preparationReceipt: AccountDeletionPreparationReceipt {
        AccountDeletionPreparationReceipt(
            success: true,
            status: .prepared,
            protocolVersion: 2,
            recoveryCapabilityExpiresAt: "2026-09-15T00:00:00Z"
        )
    }

    private func acceptedReceipt(protocolVersion: Int)
        -> AccountDeletionReceipt {
        AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: true,
            protocolVersion: protocolVersion
        )
    }

    private func acknowledgedReceipt(protocolVersion: Int)
        -> AccountDeletionReceipt {
        AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false,
            recoveryAcknowledged: true,
            protocolVersion: protocolVersion
        )
    }
}
