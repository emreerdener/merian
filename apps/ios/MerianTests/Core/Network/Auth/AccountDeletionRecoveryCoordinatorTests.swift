import Foundation
@testable import Merian
import XCTest

@MainActor
final class AccountDeletionRecoveryCoordinatorTests: XCTestCase {
    func testAcceptedRecoveryCannotAdvanceAfterLibraryLoss() async throws {
        let context = try makeV2RecoveryContext(state: .capabilityIntakePending)
        let result = await invokeRecovery(context: context, v2Receipt: acceptedReceipt,
            afterV2Recovery: { context.harness.libraryContextIsCurrent = false })
        XCTAssertFalse(result)
        XCTAssertEqual(context.harness.recoveryState, .capabilityIntakePending)
        XCTAssertNotNil(try context.capabilityStore.loadExistingIfPresent())
        XCTAssertTrue(context.secureStore.removals.isEmpty)
        XCTAssertFalse(context.harness.events.contains("record-cleanup"))
        XCTAssertFalse(context.harness.events.contains("sign-out"))
    }

    func testNonCommitRestorationKeepsBarrierIfOriginalLibraryIsLostDuringSessionLoad() async throws {
        let context = try makeV2RecoveryContext(state: .capabilityPreparedPending)
        context.harness.duringCachedSessionLoad = { await Task.yield(); context.harness.libraryContextIsCurrent = false }
        let result = await invokeRecovery(context: context,
            v2Receipt: AccountDeletionReceipt(success: true, status: .notCommitted,
                manualProviderRevocationRequired: false, protocolVersion: 2))
        XCTAssertFalse(result)
        XCTAssertEqual(context.harness.recoveryState, .capabilityRejectionRetirementPending)
        XCTAssertFalse(context.harness.events.contains("resolve"))
        XCTAssertFalse(context.harness.events.contains("publish-cached-session"))
    }

    func testOriginalLibraryLossOrFailedAcknowledgementPreservesCleanup() async throws {
        for stage in ["sign-out", "purge", "acknowledgement"] {
            let context = try makeV2RecoveryContext(state: .capabilityCleanupPending)
            if stage == "sign-out" { context.harness.duringSignOut = { await Task.yield(); context.harness.libraryContextIsCurrent = false } }
            if stage == "acknowledgement" { context.harness.acknowledgementSucceeds = false }
            let result = await invokeRecovery(context: context, v2Receipt: acceptedReceipt,
                duringPurge: { if stage == "purge" { await Task.yield(); context.harness.libraryContextIsCurrent = false } })
            XCTAssertFalse(result)
            XCTAssertEqual(context.harness.recoveryState, .capabilityCleanupPending)
            XCTAssertNotNil(try context.capabilityStore.loadExistingIfPresent())
            XCTAssertTrue(context.secureStore.removals.isEmpty)
            XCTAssertFalse(context.harness.events.contains("resolve"))
            XCTAssertFalse(context.harness.events.contains("acknowledge-v2"))
            if stage == "sign-out" { XCTAssertFalse(context.harness.events.contains("purge")) }
        }
    }

    func testChangedRecoveryProofCannotAdvanceCleanupOrRetireReplacement() async throws {
        for stage in ["recovery", "sign-out", "purge", "acknowledgement"] {
            for removeProof in [true, false] {
                let context = try makeV2RecoveryContext(state: .capabilityCleanupPending)
                let mutate: @MainActor () -> Void = {
                    context.secureStore.values[KeychainKeys.accountDeletionRecoveryCapability] =
                        removeProof ? nil : Data(repeating: 9, count: 32)
                }
                if stage == "sign-out" { context.harness.duringSignOut = { await Task.yield(); mutate() } }
                let result = await invokeRecovery(
                    context: context, v2Receipt: acceptedReceipt,
                    afterV2Recovery: { if stage == "recovery" { mutate() } },
                    duringPurge: { if stage == "purge" { await Task.yield(); mutate() } },
                    duringAcknowledgement: { if stage == "acknowledgement" { await Task.yield(); mutate() } }
                )
                XCTAssertFalse(result)
                XCTAssertEqual(context.harness.recoveryState, .capabilityCleanupPending)
                XCTAssertTrue(context.secureStore.removals.isEmpty)
                XCTAssertEqual(context.secureStore.values[KeychainKeys.accountDeletionRecoveryCapability],
                               removeProof ? nil : Data(repeating: 9, count: 32))
                XCTAssertFalse(context.harness.events.contains("resolve"))
                if stage == "recovery" { XCTAssertFalse(context.harness.events.contains("sign-out")) }
                if stage == "recovery" || stage == "sign-out" { XCTAssertFalse(context.harness.events.contains("purge")) }
                if stage != "acknowledgement" { XCTAssertFalse(context.harness.events.contains("acknowledge-v2")) }
            }
        }
    }

    func testStaleNonCommitReceiptCannotRetireChangedMarkerOrProof() async throws {
        for change in ["marker", "proof", "library"] {
            let context = try makeV2RecoveryContext(state: .capabilityPreparedPending)
            let result = await invokeRecovery(
                context: context,
                v2Receipt: AccountDeletionReceipt(success: true, status: .notCommitted,
                    manualProviderRevocationRequired: false, protocolVersion: 2),
                afterV2Recovery: {
                    if change == "library" { context.harness.libraryContextIsCurrent = false }
                    else if change == "marker" { context.harness.recoveryState = .capabilityIntakePending }
                    else { context.secureStore.values[KeychainKeys.accountDeletionRecoveryCapability] = Data(repeating: 9, count: 32) }
                }
            )
            XCTAssertFalse(result)
            XCTAssertTrue(context.secureStore.removals.isEmpty)
            XCTAssertFalse(context.harness.events.contains("resolve"))
            XCTAssertFalse(context.harness.events.contains("record-rejection-retirement"))
            XCTAssertFalse(context.harness.events.contains("sign-out"))
        }
    }

    func testCleanupContextChangesPreserveProofAndStopLaterEffects() async throws {
        // These are coordinator paths, including proof-already-removed retirement
        // and the installed legacy accepted marker. No network is used for either.
        for initialState: AccountDeletionLocalRecoveryState in [
            .capabilityCleanupPending, .capabilityRetirementPending, .cleanupPending
        ] {
            for stage in ["sign-out", "purge", "acknowledge-v2"] {
                if stage == "acknowledge-v2", initialState != .capabilityCleanupPending { continue }
                for changeMarker in [true, false] {
                    let context = try makeV2RecoveryContext(state: initialState)
                    if initialState != .capabilityCleanupPending {
                        try context.capabilityStore.clearVerified()
                    }
                    let removalsBefore = context.secureStore.removals
                    let mutate: @MainActor () async -> Void = {
                        await Task.yield()
                        if changeMarker {
                            context.harness.recoveryState = .capabilityIntakePending
                        } else {
                            context.harness.sessionMatchesTransition = false
                        }
                    }
                    if stage == "sign-out" { context.harness.duringSignOut = mutate }
                    let result = await invokeRecovery(
                        context: context,
                        v2Receipt: acceptedReceipt,
                        duringPurge: { if stage == "purge" { await mutate() } },
                        duringAcknowledgement: { if stage == "acknowledge-v2" { await mutate() } }
                    )
                    XCTAssertFalse(result, "\(initialState) / \(stage) / \(changeMarker)")
                    XCTAssertEqual(context.secureStore.removals, removalsBefore)
                    XCTAssertEqual(context.harness.recoveryState,
                                   changeMarker ? .capabilityIntakePending : initialState)
                    XCTAssertFalse(context.harness.events.contains("resolve"))
                    XCTAssertFalse(context.harness.events.contains("record-capability-retirement"))
                    if stage == "sign-out" { XCTAssertFalse(context.harness.events.contains("purge")) }
                    if stage != "acknowledge-v2" {
                        XCTAssertFalse(context.harness.events.contains("acknowledge-v2"))
                    }
                    XCTAssertEqual(try context.capabilityStore.loadExistingIfPresent() != nil,
                                   initialState == .capabilityCleanupPending)
                }
            }
        }
    }

    func testRecoveryWithoutMarkerIsANoOp() async {
        let harness = AccountDeletionCoordinatorHarness()
        let secureStore = AccountDeletionSecureStoreStub()

        let result = await invokeRecovery(
            context: RecoveryContext(
                harness: harness,
                secureStore: secureStore,
                capabilityStore: secureStore.makeCapabilityStore(),
                acknowledgementCapability: "unused"
            ),
            v2Receipt: acceptedReceipt
        )

        XCTAssertTrue(result)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testV2NonCommitRetiresProofThenRestoresExactCachedSession() async throws {
        let context = try makeV2RecoveryContext(
            state: .capabilityPreparedPending
        )

        let result = await invokeRecovery(
            context: context,
            v2Receipt: AccountDeletionReceipt(
                success: true,
                status: .notCommitted,
                manualProviderRevocationRequired: false,
                protocolVersion: 2
            )
        )

        XCTAssertTrue(result)
        XCTAssertNil(context.harness.recoveryState)
        XCTAssertEqual(
            context.harness.publishedIdentity,
            context.harness.sourceIdentity
        )
        XCTAssertEqual(
            context.secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
        XCTAssertEqual(
            context.harness.events,
            [
                "begin-account-deletion",
                "phase-deletingAccount",
                "recover-v2",
                "record-rejection-retirement",
                "load-cached-session",
                "adopt-cached-session",
                "resolve",
                "publish-cached-session",
                "finish"
            ]
        )
    }

    func testV2AcceptedRecoveryCompletesErasureAndAcknowledgement() async throws {
        let context = try makeV2RecoveryContext(
            state: .capabilityIntakePending
        )

        let result = await invokeRecovery(
            context: context,
            v2Receipt: acceptedReceipt
        )

        XCTAssertTrue(result)
        XCTAssertNil(context.harness.recoveryState)
        XCTAssertNil(context.harness.publishedIdentity)
        XCTAssertEqual(
            context.secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
        XCTAssertEqual(
            context.harness.events,
            [
                "begin-account-deletion",
                "phase-deletingAccount",
                "recover-v2",
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

    func testV2NonCommitRefusesToPublishAChangedCachedSession() async throws {
        let context = try makeV2RecoveryContext(
            state: .capabilityPreparedPending
        )
        let replacement = AuthTransitionSession(
            userID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            isAnonymous: false
        )

        let result = await invokeRecovery(
            context: context,
            v2Receipt: AccountDeletionReceipt(
                success: true,
                status: .notCommitted,
                manualProviderRevocationRequired: false,
                protocolVersion: 2
            ),
            afterV2Recovery: {
                context.harness.currentCachedIdentity = replacement
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(
            context.harness.recoveryState,
            .capabilityRejectionRetirementPending
        )
        XCTAssertNil(context.harness.publishedIdentity)
        XCTAssertEqual(
            context.secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
        XCTAssertEqual(
            context.harness.events,
            [
                "begin-account-deletion",
                "phase-deletingAccount",
                "recover-v2",
                "record-rejection-retirement",
                "load-cached-session",
                "finish"
            ]
        )
    }

    func testV2AcknowledgementFailureRetainsCleanupAndProof() async throws {
        let context = try makeV2RecoveryContext(
            state: .capabilityIntakePending
        )

        let result = await invokeRecovery(
            context: context,
            v2Receipt: acceptedReceipt,
            acknowledgementError: AccountDeletionSecureStoreStub.Failure()
        )

        XCTAssertFalse(result)
        XCTAssertEqual(
            context.harness.recoveryState,
            .capabilityCleanupPending
        )
        XCTAssertTrue(context.secureStore.removals.isEmpty)
        XCTAssertEqual(
            context.harness.events,
            [
                "begin-account-deletion",
                "phase-deletingAccount",
                "recover-v2",
                "phase-finalizing",
                "record-cleanup",
                "record-manual-revocation",
                "sign-out",
                "purge",
                "acknowledge-v2",
                "finish"
            ]
        )
    }

    func testMixedV2EnvelopeChecksLegacyDomainBeforeRestoration() async throws {
        let context = try makeV2RecoveryContext(
            state: .capabilityIntakePending
        )
        let unknown = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_invalid"}"#
        )
        let expectedProof = try context.capabilityStore.loadExistingValue()
        var legacyModes: [Bool] = []

        let result = await invokeRecovery(
            context: context,
            v2Receipt: acceptedReceipt,
            v2Error: unknown,
            legacyRecovery: { proof, acknowledge in
                XCTAssertEqual(proof, expectedProof)
                legacyModes.append(acknowledge)
                return AccountDeletionReceipt(
                    success: true,
                    status: acknowledge ? .completed : .pending,
                    manualProviderRevocationRequired: false,
                    recoveryAcknowledged: acknowledge,
                    protocolVersion: 1
                )
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(legacyModes, [false, true])
        XCTAssertNil(context.harness.recoveryState)
        XCTAssertEqual(
            context.secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
    }

    func testRetirementRecoveryReverifiesCleanupBeforeProofRemoval() async {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = .capabilityRetirementPending
        let secureStore = AccountDeletionSecureStoreStub()
        let capabilityStore = secureStore.makeCapabilityStore()

        let result = await invokeRecovery(
            context: RecoveryContext(
                harness: harness,
                secureStore: secureStore,
                capabilityStore: capabilityStore,
                acknowledgementCapability: "unused"
            ),
            v2Receipt: acceptedReceipt
        )

        XCTAssertTrue(result)
        XCTAssertNil(harness.recoveryState)
        XCTAssertEqual(
            secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
        XCTAssertEqual(
            harness.events,
            [
                "begin-account-deletion-cleanup",
                "sign-out",
                "purge",
                "resolve",
                "finish"
            ]
        )
    }

    func testLookupWithoutProofRestoresSessionWithoutNetworkReplay() async {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = .capabilityLookupPending
        let secureStore = AccountDeletionSecureStoreStub()

        let result = await invokeRecovery(
            context: RecoveryContext(
                harness: harness,
                secureStore: secureStore,
                capabilityStore: secureStore.makeCapabilityStore(),
                acknowledgementCapability: "unused"
            ),
            v2Receipt: acceptedReceipt
        )

        XCTAssertTrue(result)
        XCTAssertNil(harness.recoveryState)
        XCTAssertTrue(secureStore.removals.isEmpty)
        XCTAssertEqual(harness.publishedIdentity, harness.sourceIdentity)
        XCTAssertEqual(
            harness.events,
            [
                "begin-account-deletion-cleanup",
                "load-cached-session",
                "adopt-cached-session",
                "resolve",
                "publish-cached-session",
                "finish"
            ]
        )
    }

    func testPreparedMarkerWithoutProofCancelsWithoutDestructiveReplay() async {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = .capabilityPreparedPending
        let secureStore = AccountDeletionSecureStoreStub()

        let result = await invokeRecovery(
            context: RecoveryContext(
                harness: harness,
                secureStore: secureStore,
                capabilityStore: secureStore.makeCapabilityStore(),
                acknowledgementCapability: "unused"
            ),
            v2Receipt: acceptedReceipt
        )

        XCTAssertTrue(result)
        XCTAssertNil(harness.recoveryState)
        XCTAssertTrue(secureStore.values.isEmpty)
        XCTAssertEqual(harness.publishedIdentity, harness.sourceIdentity)
        XCTAssertEqual(
            harness.events,
            [
                "begin-account-deletion",
                "load-cached-session",
                "adopt-cached-session",
                "resolve",
                "publish-cached-session",
                "finish"
            ]
        )
    }

    func testPreCapabilityIntakeKeepsV1ProofAcrossAmbiguousReplay() async throws {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = .intakePending
        let secureStore = AccountDeletionSecureStoreStub()
        let capabilityStore = secureStore.makeCapabilityStore()
        var requestProofs: [String] = []
        var recoveryCalls: [(proof: String, acknowledge: Bool)] = []

        let firstResult = await AccountDeletionRecoveryCoordinator(
            dependencies: harness.makeDependencies()
        ).resumePendingLocalCleanup(
            requestDeletion: { _, proof in
                requestProofs.append(proof)
                throw AccountDeletionSecureStoreStub.Failure()
            },
            recoverDeletion: { proof, acknowledge in
                recoveryCalls.append((proof, acknowledge))
                throw AccountDeletionSecureStoreStub.Failure()
            },
            recoverDeletionV2: { _ in
                XCTFail("A legacy replay proof must not enter v2 recovery")
                return self.acceptedReceipt
            },
            acknowledgeDeletionV2: { _ in
                XCTFail("A legacy replay proof must not enter v2 acknowledgement")
                return self.acknowledgedReceipt
            },
            recoveryCapabilityStore: capabilityStore,
            recordManualProviderRevocation: {
                XCTFail("No accepted receipt was returned")
            },
            purgeLocalData: { _ in
                XCTFail("Ambiguous recovery must not purge local data")
                return false
            }
        )

        let persisted = try capabilityStore.loadExisting()
        XCTAssertFalse(firstResult)
        XCTAssertEqual(
            harness.recoveryState,
            .capabilityIntakePending
        )
        XCTAssertEqual(persisted.protocolVersion, 1)
        XCTAssertNil(persisted.acknowledgementValue)
        XCTAssertEqual(
            secureStore.values[
                KeychainKeys.accountDeletionRecoveryCapability
            ]?.count,
            32
        )

        let secondResult = await AccountDeletionRecoveryCoordinator(
            dependencies: harness.makeDependencies()
        ).resumePendingLocalCleanup(
            requestDeletion: { _, proof in
                requestProofs.append(proof)
                return AccountDeletionReceipt(
                    success: true,
                    status: .pending,
                    manualProviderRevocationRequired: false,
                    protocolVersion: 1
                )
            },
            recoverDeletion: { proof, acknowledge in
                recoveryCalls.append((proof, acknowledge))
                return AccountDeletionReceipt(
                    success: true,
                    status: .completed,
                    manualProviderRevocationRequired: false,
                    recoveryAcknowledged: true,
                    protocolVersion: 1
                )
            },
            recoverDeletionV2: { _ in
                XCTFail("A legacy replay proof must not enter v2 recovery")
                return self.acceptedReceipt
            },
            acknowledgeDeletionV2: { _ in
                XCTFail("A legacy replay proof must not enter v2 acknowledgement")
                return self.acknowledgedReceipt
            },
            recoveryCapabilityStore: capabilityStore,
            recordManualProviderRevocation: {
                XCTFail("The receipt does not require manual revocation")
            },
            purgeLocalData: { _ in true }
        )

        XCTAssertTrue(secondResult)
        XCTAssertNil(harness.recoveryState)
        XCTAssertEqual(
            requestProofs,
            [persisted.recoveryValue, persisted.recoveryValue]
        )
        XCTAssertEqual(recoveryCalls.count, 2)
        XCTAssertEqual(
            recoveryCalls.map { $0.proof },
            [persisted.recoveryValue, persisted.recoveryValue]
        )
        XCTAssertEqual(
            recoveryCalls.map { $0.acknowledge },
            [false, true]
        )
        XCTAssertEqual(
            secureStore.removals,
            [KeychainKeys.accountDeletionRecoveryCapability]
        )
    }

    func testLegacyIntakeReplaysAuthenticatedRequestAndAcknowledges() async {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = .capabilityIntakePending
        let secureStore = AccountDeletionSecureStoreStub()
        secureStore.values[KeychainKeys.accountDeletionRecoveryCapability] =
            Data(repeating: 0x21, count: 32)
        let capabilityStore = secureStore.makeCapabilityStore()
        var recoveryModes: [Bool] = []

        let result = await AccountDeletionRecoveryCoordinator(
            dependencies: harness.makeDependencies()
        ).resumePendingLocalCleanup(
            requestDeletion: { _, _ in
                harness.events.append("request-v1")
                return AccountDeletionReceipt(
                    success: true,
                    status: .pending,
                    manualProviderRevocationRequired: false,
                    protocolVersion: 1
                )
            },
            recoverDeletion: { _, acknowledge in
                recoveryModes.append(acknowledge)
                harness.events.append("recover-v1-acknowledge")
                return AccountDeletionReceipt(
                    success: true,
                    status: .completed,
                    manualProviderRevocationRequired: false,
                    recoveryAcknowledged: true,
                    protocolVersion: 1
                )
            },
            recoverDeletionV2: { _ in
                XCTFail("A legacy proof must not use v2 recovery")
                return self.acceptedReceipt
            },
            acknowledgeDeletionV2: { _ in
                XCTFail("A legacy proof must not use v2 acknowledgement")
                return self.acknowledgedReceipt
            },
            recoveryCapabilityStore: capabilityStore,
            recordManualProviderRevocation: {
                XCTFail("The receipt does not require manual revocation")
            },
            purgeLocalData: { _ in
                harness.events.append("purge")
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(recoveryModes, [true])
        XCTAssertNil(harness.recoveryState)
        XCTAssertEqual(
            harness.events,
            [
                "begin-account-deletion",
                "phase-deletingAccount",
                "verify-session",
                "request-v1",
                "phase-finalizing",
                "record-cleanup",
                "sign-out",
                "purge",
                "recover-v1-acknowledge",
                "record-capability-retirement",
                "resolve",
                "finish"
            ]
        )
    }

    private struct RecoveryContext {
        let harness: AccountDeletionCoordinatorHarness
        let secureStore: AccountDeletionSecureStoreStub
        let capabilityStore: AccountDeletionRecoveryCapabilityStore
        let acknowledgementCapability: String
    }

    private func makeV2RecoveryContext(
        state: AccountDeletionLocalRecoveryState
    ) throws -> RecoveryContext {
        let harness = AccountDeletionCoordinatorHarness()
        harness.recoveryState = state
        let secureStore = AccountDeletionSecureStoreStub()
        let capabilityStore = secureStore.makeCapabilityStore()
        let capability = try capabilityStore.prepare()
        let acknowledgement = try XCTUnwrap(
            capability.acknowledgementValue
        )
        return RecoveryContext(
            harness: harness,
            secureStore: secureStore,
            capabilityStore: capabilityStore,
            acknowledgementCapability: acknowledgement
        )
    }

    private func invokeRecovery(
        context: RecoveryContext,
        v2Receipt: AccountDeletionReceipt,
        v2Error: Error? = nil,
        acknowledgementError: Error? = nil,
        afterV2Recovery: @MainActor @escaping () -> Void = {},
        duringPurge: @MainActor @escaping () async -> Void = {},
        duringAcknowledgement: @MainActor @escaping () async -> Void = {},
        legacyRecovery: (@MainActor (String, Bool) async throws
            -> AccountDeletionReceipt)? = nil
    ) async -> Bool {
        await AccountDeletionRecoveryCoordinator(
            dependencies: context.harness.makeDependencies()
        ).resumePendingLocalCleanup(
            requestDeletion: { _, _ in
                XCTFail("A v2 proof must not use legacy intake")
                return self.acceptedReceipt
            },
            recoverDeletion: { proof, acknowledge in
                if let legacyRecovery {
                    return try await legacyRecovery(proof, acknowledge)
                }
                XCTFail("A v2 proof must not use legacy recovery")
                return self.acceptedReceipt
            },
            recoverDeletionV2: { _ in
                context.harness.events.append("recover-v2")
                afterV2Recovery()
                if let v2Error {
                    throw v2Error
                }
                return v2Receipt
            },
            acknowledgeDeletionV2: { acknowledgement in
                context.harness.events.append("acknowledge-v2")
                await duringAcknowledgement()
                if let acknowledgementError {
                    throw acknowledgementError
                }
                XCTAssertEqual(
                    acknowledgement,
                    context.acknowledgementCapability
                )
                return self.acknowledgedReceipt
            },
            recoveryCapabilityStore: context.capabilityStore,
            recordManualProviderRevocation: {
                context.harness.events.append("record-manual-revocation")
            },
            purgeLocalData: { _ in
                context.harness.events.append("purge")
                await duringPurge()
                return true
            }
        )
    }

    private var acceptedReceipt: AccountDeletionReceipt {
        AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: true,
            protocolVersion: 2
        )
    }

    private var acknowledgedReceipt: AccountDeletionReceipt {
        AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false,
            recoveryAcknowledged: true,
            protocolVersion: 2
        )
    }
}
