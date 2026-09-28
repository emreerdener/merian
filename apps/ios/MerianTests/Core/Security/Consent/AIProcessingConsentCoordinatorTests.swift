import Foundation
import XCTest

@testable import Merian

@MainActor
final class AIProcessingConsentCoordinatorTests: XCTestCase {
    private let userId = UUID(uuidString: "00000000-0000-0000-0000-00000000c011")!

    private func harness(collectionEnabled: Bool = false) -> (
        FaultInjectingConsentLedgerStore, ConsentLedgerRepository,
        ConsentMutationService, AIProcessingConsentCoordinator
    ) {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let mutation = ConsentMutationService(
            ledgerRepository: repository,
            dependencies: .init(
                now: { Date(timeIntervalSince1970: 1_790_000_000) },
                makeUUID: { UUID() }, appVersion: { "test" }, appBuild: { "1" }
            ))
        let coordinator = AIProcessingConsentCoordinator(
            repository: repository, mutationService: mutation,
            isOpenAICollectionEnabled: collectionEnabled
        )
        coordinator.setHandlers(
            contextProvider: { [userId] in
                .init(observedUserId: userId, sdkUserId: userId, isAccountTransitionInProgress: false)
            }, synchronize: {})
        coordinator.refresh(ownerUserId: userId)
        return (store, repository, mutation, coordinator)
    }

    func testDisabledCollectionNeverCreatesImplicitOpenAIConsent() throws {
        let (_, repository, mutation, coordinator) = harness()
        try mutation.setAIProcessingEnabled(true, processor: .gemini, ownerUserId: userId)
        coordinator.refresh(ownerUserId: userId)
        XCTAssertFalse(coordinator.showsOpenAIChoice)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertThrowsError(try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId))
        XCTAssertEqual(repository.ledger.aiConsentEvents.map(\.provider), [ConsentPolicy.geminiProvider])
    }

    func testCollectionRequiresExplicitGrantAndDoesNotClaimCloudReceipt() throws {
        XCTAssertTrue(ConsentPolicy.openAIConsentCollectionEnabled)
        let (_, repository, mutation, coordinator) = harness(
            collectionEnabled: ConsentPolicy.openAIConsentCollectionEnabled
        )
        var syncCount = 0
        coordinator.setHandlers(
            contextProvider: { [userId] in
                .init(observedUserId: userId, sdkUserId: userId, isAccountTransitionInProgress: false)
            }, synchronize: { syncCount += 1 }
        )
        try mutation.setAIProcessingEnabled(true, processor: .gemini, ownerUserId: userId)
        coordinator.refresh(ownerUserId: userId)
        XCTAssertTrue(coordinator.canManageOpenAIPermission)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertEqual(syncCount, 0)
        XCTAssertEqual(repository.ledger.aiConsentEvents.map(\.provider), [ConsentPolicy.geminiProvider])

        try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId)
        let grant = try XCTUnwrap(repository.ledger.aiConsentEvents.last)
        XCTAssertEqual(grant.provider, ConsentPolicy.openAIProvider)
        XCTAssertNil(grant.recordedAt)
        XCTAssertNil(grant.syncedUserId)
        XCTAssertTrue(coordinator.hasGrantedOpenAI)
        XCTAssertEqual(syncCount, 1)
    }

    func testProviderPermissionsAndCausalParentsRemainIndependent() throws {
        let (_, repository, mutation, coordinator) = harness(collectionEnabled: true)
        try mutation.setAIProcessingEnabled(true, processor: .gemini, ownerUserId: userId)
        let geminiGrant = try XCTUnwrap(repository.ledger.aiConsentEvents.last)
        try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId)
        let openAIGrant = try XCTUnwrap(repository.ledger.aiConsentEvents.last)
        XCTAssertNil(openAIGrant.causalParentId)
        XCTAssertTrue(coordinator.hasGrantedOpenAI)
        try coordinator.withdrawGeminiPermission(hasGranted: true, ownerUserId: userId)
        let geminiWithdrawal = try XCTUnwrap(repository.ledger.aiConsentEvents.last)
        XCTAssertEqual(geminiWithdrawal.causalParentId, geminiGrant.id)
        coordinator.refresh(ownerUserId: userId)
        XCTAssertTrue(coordinator.hasGrantedOpenAI)
        try coordinator.setOpenAIEnabled(false, expectedOwnerUserId: userId)
        let openAIWithdrawal = try XCTUnwrap(repository.ledger.aiConsentEvents.last)
        XCTAssertEqual(openAIWithdrawal.causalParentId, openAIGrant.id)
        XCTAssertEqual(openAIWithdrawal.provider, ConsentPolicy.openAIProvider)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertEqual(
            ConsentAuthorityPolicy.currentAIConsentEvent(
                ownerUserId: userId, in: repository.ledger)?.id, geminiWithdrawal.id)
    }

    func testExistingPermissionCanBeWithdrawnWithCollectionDisabled() throws {
        let (_, repository, mutation, coordinator) = harness()
        try mutation.setAIProcessingEnabled(true, processor: .openAI, ownerUserId: userId)
        coordinator.refresh(ownerUserId: userId)
        XCTAssertTrue(coordinator.showsOpenAIChoice)
        XCTAssertTrue(coordinator.hasGrantedOpenAI)
        try coordinator.setOpenAIEnabled(false, expectedOwnerUserId: userId)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertEqual(repository.ledger.aiConsentEvents.last?.eventKind, .revoked)
    }

    func testOldDisclosureGrantRemainsWithdrawableWithCollectionDisabled() throws {
        let (_, repository, _, coordinator) = harness()
        let oldGrant = ConsentManager.AIConsentEvent(
            id: UUID(), ownerUserId: userId, syncedUserId: userId,
            provider: ConsentPolicy.openAIProvider, disclosureVersion: "2026-09-25",
            eventKind: .granted, occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            disclosureText: "Synthetic older disclosure", actionText: "Synthetic approval",
            platform: "ios", appVersion: "test", appBuild: "1", consentRevision: 5
        )
        var ledger = repository.ledger
        ledger.aiConsentEvents.append(oldGrant)
        try repository.persistLedger(ledger)
        coordinator.refresh(ownerUserId: userId)
        XCTAssertTrue(coordinator.showsOpenAIChoice)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertTrue(coordinator.hasOpenAIGrantToWithdraw)
        try coordinator.setOpenAIEnabled(false, expectedOwnerUserId: userId)
        XCTAssertFalse(coordinator.hasOpenAIGrantToWithdraw)
        XCTAssertEqual(repository.ledger.aiConsentEvents.last?.eventKind, .revoked)
        XCTAssertEqual(repository.ledger.aiConsentEvents.last?.causalParentId, oldGrant.id)
    }

    func testStaleDialogSDKMismatchAndAccountTransitionCannotSave() throws {
        let (_, repository, _, coordinator) = harness(collectionEnabled: true)
        let otherId = UUID()
        XCTAssertThrowsError(try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: otherId))
        for context in [
            AIProcessingConsentCoordinator.Context(
                observedUserId: userId, sdkUserId: otherId, isAccountTransitionInProgress: false),
            .init(observedUserId: otherId, sdkUserId: otherId, isAccountTransitionInProgress: false),
            .init(observedUserId: userId, sdkUserId: userId, isAccountTransitionInProgress: true),
        ] {
            coordinator.setHandlers(
                contextProvider: { context }, synchronize: { XCTFail("stale context synchronized") })
            XCTAssertFalse(coordinator.hasCurrentAccount)
            XCTAssertFalse(coordinator.canManageOpenAIPermission)
            XCTAssertThrowsError(try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId))
        }
        coordinator.setHandlers(contextProvider: { nil }, synchronize: {})
        XCTAssertFalse(coordinator.canManageOpenAIPermission)
        XCTAssertTrue(repository.ledger.aiConsentEvents.isEmpty)
        coordinator.refresh(ownerUserId: otherId)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
    }

    func testCancelledActionCannotRecordPermission() async throws {
        let (_, repository, _, coordinator) = harness(collectionEnabled: true)
        let task = Task { @MainActor [userId] in
            XCTAssertThrowsError(try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId))
        }
        task.cancel()
        try await task.value
        XCTAssertTrue(repository.ledger.aiConsentEvents.isEmpty)
    }

    func testFailedGrantDoesNotPublishAndFailedWithdrawalRemainsRetryable() throws {
        let (store, repository, _, coordinator) = harness(collectionEnabled: true)
        store.failLedgerWrites = true
        XCTAssertThrowsError(try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId))
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertTrue(repository.ledger.aiConsentEvents.isEmpty)
        store.failLedgerWrites = false
        try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId)
        store.failLedgerWrites = true
        XCTAssertThrowsError(try coordinator.setOpenAIEnabled(false, expectedOwnerUserId: userId))
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertTrue(coordinator.hasPendingOpenAIWithdrawal)
        XCTAssertTrue(coordinator.canManageOpenAIPermission)
        store.failLedgerWrites = false
        try coordinator.setOpenAIEnabled(false, expectedOwnerUserId: userId)
        XCTAssertFalse(coordinator.hasPendingOpenAIWithdrawal)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertEqual(repository.ledger.aiConsentEvents.last?.eventKind, .revoked)
    }

    func testAccountSwitchAndGhostRebindingPreserveSeparateEvidence() throws {
        let (store, repository, mutation, coordinator) = harness(collectionEnabled: true)
        try mutation.setAIProcessingEnabled(true, processor: .gemini, ownerUserId: userId)
        try coordinator.setOpenAIEnabled(true, expectedOwnerUserId: userId)
        let original = repository.ledger
        let otherId = UUID()
        coordinator.refresh(ownerUserId: otherId)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        XCTAssertFalse(coordinator.hasOpenAIHistory)
        coordinator.refresh(ownerUserId: nil)
        XCTAssertFalse(coordinator.hasGrantedOpenAI)
        let decoded = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: XCTUnwrap(store.ledgerData))
        XCTAssertEqual(decoded.aiConsentEvents, original.aiConsentEvents)
        let rebound = ConsentLedgerOwnershipPolicy.rebinding(original, from: userId, to: otherId)
        XCTAssertEqual(rebound.aiConsentEvents.map(\.provider), original.aiConsentEvents.map(\.provider))
        XCTAssertTrue(rebound.aiConsentEvents.allSatisfy { $0.ownerUserId == otherId })
    }
}
