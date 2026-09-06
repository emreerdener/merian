import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentLedgerRepositoryTests: XCTestCase {
    func testLaunchRecoveryPersistsExactWithdrawalBeforeClearingJournal() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let revocation = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .revoked
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: []
            )
        )
        store.revocationIntentData = try JSONEncoder().encode(
            ConsentManager.AnalyticsRevocationJournal(
                intents: [.init(event: revocation)]
            )
        )

        let repository = ConsentLedgerRepository(store: store)

        XCTAssertFalse(repository.isLedgerStorageUncertain)
        XCTAssertFalse(repository.isRevocationIntentStorageUncertain)
        XCTAssertFalse(repository.isAnalyticsWithdrawalInProgress)
        XCTAssertFalse(repository.hasPendingAnalyticsRevocationJournal)
        XCTAssertEqual(
            repository.ledger.analyticsConsentEvents,
            [revocation]
        )
        XCTAssertEqual(store.operations, ["saveLedger", "clearIntent"])
    }

    func testMalformedLedgerRemainsUnavailableAndCannotBeOverwritten() {
        let store = FaultInjectingConsentLedgerStore()
        let malformedData = Data("not-json".utf8)
        store.ledgerData = malformedData
        let repository = ConsentLedgerRepository(store: store)

        XCTAssertTrue(repository.isLedgerStorageUncertain)
        XCTAssertEqual(repository.ledger, .empty)
        XCTAssertThrowsError(
            try repository.persistLedger(.empty)
        ) { error in
            guard case ConsentPersistenceError.storedLedgerUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(store.ledgerData, malformedData)
        XCTAssertTrue(store.operations.isEmpty)
    }

    func testFailedLedgerWriteDoesNotPublishOrNotifyCandidateState() throws {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        var notificationCount = 0
        repository.setStateChangeHandler {
            notificationCount += 1
        }
        var candidate = ConsentManager.LocalLedger.empty
        candidate.activeUserId = UUID()
        store.failLedgerWrites = true

        XCTAssertThrowsError(try repository.persistLedger(candidate))
        XCTAssertEqual(repository.ledger, .empty)
        XCTAssertEqual(notificationCount, 0)

        store.failLedgerWrites = false
        try repository.persistLedger(candidate)

        XCTAssertEqual(repository.ledger, candidate)
        XCTAssertEqual(notificationCount, 1)
    }

    func testLedgerAndJournalReadFailuresRemainIndependentlyFailClosed() {
        let ledgerFailureStore = FaultInjectingConsentLedgerStore()
        ledgerFailureStore.failLedgerReads = true
        let ledgerFailureRepository = ConsentLedgerRepository(
            store: ledgerFailureStore
        )

        XCTAssertTrue(ledgerFailureRepository.isLedgerStorageUncertain)
        XCTAssertFalse(
            ledgerFailureRepository.isRevocationIntentStorageUncertain
        )

        let journalFailureStore = FaultInjectingConsentLedgerStore()
        journalFailureStore.failRevocationIntentReads = true
        let journalFailureRepository = ConsentLedgerRepository(
            store: journalFailureStore
        )

        XCTAssertFalse(journalFailureRepository.isLedgerStorageUncertain)
        XCTAssertTrue(
            journalFailureRepository.isRevocationIntentStorageUncertain
        )
    }

    func testMalformedWithdrawalJournalKeepsAnalyticsStorageUnavailable() throws {
        let store = FaultInjectingConsentLedgerStore()
        store.revocationIntentData = Data("not-json".utf8)
        let repository = ConsentLedgerRepository(store: store)
        let candidate = ConsentManager.LocalLedger.empty

        XCTAssertTrue(repository.isRevocationIntentStorageUncertain)
        XCTAssertThrowsError(
            try repository.persistConsentChange(
                candidate,
                analyticsEvent: makeAnalyticsEvent(eventKind: .granted)
            )
        ) { error in
            guard case ConsentPersistenceError.revocationIntentInvalid = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(store.operations.isEmpty)
        XCTAssertNotNil(store.revocationIntentData)
    }

    func testNonRevocationJournalIsRejectedWithoutOverwritingEvidence() throws {
        let store = FaultInjectingConsentLedgerStore()
        let originalData = try JSONEncoder().encode(
            ConsentManager.AnalyticsRevocationJournal(
                intents: [
                    .init(event: makeAnalyticsEvent(eventKind: .granted))
                ]
            )
        )
        store.revocationIntentData = originalData

        let repository = ConsentLedgerRepository(store: store)

        XCTAssertTrue(repository.isRevocationIntentStorageUncertain)
        XCTAssertFalse(repository.hasPendingAnalyticsRevocationJournal)
        XCTAssertEqual(store.revocationIntentData, originalData)
        XCTAssertTrue(store.operations.isEmpty)
    }

    func testFailedLedgerWriteRetainsExactWriteAheadIntentForRetry() throws {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let revocation = makeAnalyticsEvent(eventKind: .revoked)
        var candidate = ConsentManager.LocalLedger.empty
        candidate.analyticsConsentEvents = [revocation]
        repository.setAnalyticsWithdrawalInProgress(true)
        store.failLedgerWrites = true

        XCTAssertThrowsError(
            try repository.persistConsentChange(
                candidate,
                analyticsEvent: revocation
            )
        )
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])
        XCTAssertEqual(repository.ledger, .empty)
        let retainedData = try XCTUnwrap(store.revocationIntentData)
        let retainedJournal = try JSONDecoder().decode(
            ConsentManager.AnalyticsRevocationJournal.self,
            from: retainedData
        )
        XCTAssertEqual(retainedJournal.intents.map(\.event), [revocation])
        XCTAssertTrue(repository.hasPendingAnalyticsRevocationJournal)
        XCTAssertTrue(repository.isAnalyticsWithdrawalInProgress)

        store.operations.removeAll()
        store.failLedgerWrites = false
        try repository.persistConsentChange(
            candidate,
            analyticsEvent: revocation
        )

        XCTAssertEqual(store.operations, ["saveLedger", "clearIntent"])
        XCTAssertFalse(repository.hasPendingAnalyticsRevocationJournal)
        XCTAssertFalse(repository.isAnalyticsWithdrawalInProgress)
        XCTAssertEqual(repository.ledger, candidate)
    }

    func testJournalFailureFallsBackToVerifiedLedgerPersistence() throws {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let revocation = makeAnalyticsEvent(eventKind: .revoked)
        var candidate = ConsentManager.LocalLedger.empty
        candidate.analyticsConsentEvents = [revocation]
        repository.setAnalyticsWithdrawalInProgress(true)
        store.failRevocationIntentWrites = true

        try repository.persistConsentChange(
            candidate,
            analyticsEvent: revocation
        )

        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])
        XCTAssertNil(store.revocationIntentData)
        XCTAssertEqual(repository.ledger, candidate)
        XCTAssertFalse(repository.isAnalyticsWithdrawalInProgress)
    }

    func testPendingJournalRebindsBeforePermanentAccountRecovery() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let unrelatedUserId = UUID()
        let ghostRevocation = makeAnalyticsEvent(
            ownerUserId: ghostUserId,
            eventKind: .revoked
        )
        let unrelatedRevocation = makeAnalyticsEvent(
            ownerUserId: unrelatedUserId,
            eventKind: .revoked
        )
        store.revocationIntentData = try JSONEncoder().encode(
            ConsentManager.AnalyticsRevocationJournal(
                intents: [
                    .init(event: ghostRevocation),
                    .init(event: unrelatedRevocation)
                ]
            )
        )
        store.failLedgerWrites = true
        let repository = ConsentLedgerRepository(store: store)
        XCTAssertTrue(repository.hasPendingAnalyticsRevocationJournal)

        store.operations.removeAll()
        store.failLedgerWrites = false
        try repository.rebindPendingAnalyticsRevocationJournal(
            from: ghostUserId,
            to: permanentUserId
        )

        XCTAssertEqual(store.operations, ["saveIntent"])
        let data = try XCTUnwrap(store.revocationIntentData)
        let journal = try JSONDecoder().decode(
            ConsentManager.AnalyticsRevocationJournal.self,
            from: data
        )
        XCTAssertEqual(
            journal.intents.map(\.event.ownerUserId),
            [permanentUserId, unrelatedUserId]
        )
        XCTAssertEqual(
            journal.intents[0].event.syncedUserId,
            permanentUserId
        )
        XCTAssertEqual(
            journal.intents[1].event.syncedUserId,
            unrelatedUserId
        )

        try repository.rebindLedger(
            from: ghostUserId,
            to: permanentUserId
        )
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])
        XCTAssertEqual(repository.ledger.activeUserId, permanentUserId)
        XCTAssertEqual(
            repository.ledger.analyticsConsentEvents.map(\.ownerUserId),
            [permanentUserId, unrelatedUserId]
        )
        XCTAssertEqual(
            repository.ledger.analyticsConsentEvents.map(\.syncedUserId),
            [permanentUserId, unrelatedUserId]
        )

        try repository.recoverPendingAnalyticsRevocation()
        XCTAssertEqual(
            store.operations,
            ["saveIntent", "saveLedger", "saveLedger", "clearIntent"]
        )
        XCTAssertFalse(repository.hasPendingAnalyticsRevocationJournal)
        XCTAssertEqual(repository.ledger.analyticsConsentEvents.count, 2)
    }

    private func makeAnalyticsEvent(
        ownerUserId: UUID? = UUID(),
        eventKind: ConsentManager.AnalyticsConsentEventKind
    ) -> ConsentManager.AnalyticsConsentEvent {
        ConsentManager.AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: ConsentPolicy.analyticsDisclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_750_000_000),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: nil
        )
    }
}
