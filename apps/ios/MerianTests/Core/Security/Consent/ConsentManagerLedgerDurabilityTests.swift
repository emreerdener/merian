import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentManagerLedgerDurabilityTests: ConsentManagerTestCase {
    func testFailedAnalyticsRevocationRemainsOffAcrossRestartAndReplaysExactEvent() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let manager = ConsentManager(ledgerStore: store)
        manager.observeSession(userId: ownerUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        XCTAssertTrue(manager.hasGrantedCurrentPostHogAnalytics)

        store.operations.removeAll()
        store.failLedgerWrites = true
        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        let intentData = try XCTUnwrap(store.revocationIntentData)
        let journal = try JSONDecoder().decode(
            ConsentManager.AnalyticsRevocationJournal.self,
            from: intentData
        )
        let intent = try XCTUnwrap(journal.intents.last)
        XCTAssertEqual(
            journal.formatVersion,
            ConsentManager.AnalyticsRevocationJournal.currentFormatVersion
        )
        XCTAssertEqual(intent.event.eventKind, .revoked)
        XCTAssertEqual(intent.event.ownerUserId, ownerUserId)
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])

        let restoredWhileStorageFails = ConsentManager(ledgerStore: store)
        restoredWhileStorageFails.observeSession(userId: ownerUserId)
        XCTAssertFalse(
            restoredWhileStorageFails.hasGrantedCurrentPostHogAnalytics
        )
        XCTAssertEqual(store.revocationIntentData, intentData)

        store.failLedgerWrites = false
        try restoredWhileStorageFails.setPostHogAnalyticsEnabled(false)
        XCTAssertFalse(
            restoredWhileStorageFails.hasGrantedCurrentPostHogAnalytics
        )
        XCTAssertNil(store.revocationIntentData)

        let recoveredData = try XCTUnwrap(store.ledgerData)
        let recoveredLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: recoveredData
        )
        XCTAssertEqual(
            recoveredLedger.analyticsConsentEvents.last(where: {
                $0.id == intent.event.id
            }),
            intent.event
        )

        let finalRestart = ConsentManager(ledgerStore: store)
        finalRestart.observeSession(userId: ownerUserId)
        XCTAssertFalse(finalRestart.hasGrantedCurrentPostHogAnalytics)
    }

    func testRevocationUsesAtomicLedgerWhenJournalWriteFails() throws {
        let store = FaultInjectingConsentLedgerStore()
        let manager = ConsentManager(ledgerStore: store)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        store.failRevocationIntentWrites = true

        XCTAssertNoThrow(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNil(store.revocationIntentData)

        let restored = ConsentManager(ledgerStore: store)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
    }

    func testRevocationJournalCleanupFailureRemainsOffAcrossRestart() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let manager = ConsentManager(ledgerStore: store)
        manager.observeSession(userId: ownerUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        store.failRevocationIntentClears = true

        XCTAssertNoThrow(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNotNil(store.revocationIntentData)

        let restored = ConsentManager(ledgerStore: store)
        restored.observeSession(userId: ownerUserId)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNotNil(store.revocationIntentData)

        store.failRevocationIntentClears = false
        try restored.setPostHogAnalyticsEnabled(false)

        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNil(store.revocationIntentData)
    }

    func testRevocationClosesInMemoryGateWhenBothDurableBoundariesFail() throws {
        let store = FaultInjectingConsentLedgerStore()
        let manager = ConsentManager(ledgerStore: store)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        store.operations.removeAll()
        store.failRevocationIntentWrites = true
        store.failLedgerWrites = true

        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])
    }

    func testRevocationJournalRetainsMultipleAccountsWhenLedgerStaysUnavailable() throws {
        let store = FaultInjectingConsentLedgerStore()
        let firstUserId = UUID()
        let secondUserId = UUID()
        let manager = ConsentManager(ledgerStore: store)
        manager.observeSession(userId: firstUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        manager.observeSession(userId: secondUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )

        store.failLedgerWrites = true
        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        manager.observeSession(userId: firstUserId)
        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )

        let journalData = try XCTUnwrap(store.revocationIntentData)
        let journal = try JSONDecoder().decode(
            ConsentManager.AnalyticsRevocationJournal.self,
            from: journalData
        )
        XCTAssertEqual(journal.intents.count, 2)
        XCTAssertEqual(
            Set(journal.intents.compactMap(\.event.ownerUserId)),
            Set([firstUserId, secondUserId])
        )

        let restored = ConsentManager(ledgerStore: store)
        restored.observeSession(userId: firstUserId)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
        restored.observeSession(userId: secondUserId)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)

        store.failLedgerWrites = false
        try restored.setPostHogAnalyticsEnabled(false)
        XCTAssertNil(store.revocationIntentData)
        let recoveredData = try XCTUnwrap(store.ledgerData)
        let recoveredLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: recoveredData
        )
        let recoveredRevocationOwners = Set(
            recoveredLedger.analyticsConsentEvents
                .filter { $0.eventKind == .revoked }
                .compactMap(\.ownerUserId)
        )
        XCTAssertTrue(recoveredRevocationOwners.contains(firstUserId))
        XCTAssertTrue(recoveredRevocationOwners.contains(secondUserId))
    }

    func testCorruptStoredLedgerCannotBeOverwrittenByOnboarding() {
        let store = FaultInjectingConsentLedgerStore()
        store.ledgerData = Data("not-json".utf8)
        let manager = ConsentManager(ledgerStore: store)
        let originalData = store.ledgerData

        XCTAssertThrowsError(
            try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
                analyticsEnabled: false
            )
        )
        XCTAssertFalse(manager.hasCurrentRequiredConsent)
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(store.ledgerData, originalData)
    }

    func testDurableStoreAtomicallyMigratesAndVerifiesLegacyLedger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsentLedgerStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyData = Data("legacy-ledger".utf8)
        let replacementData = Data("replacement-ledger".utf8)
        userDefaults.set(
            legacyData,
            forKey: UserDefaultsKeys.legalConsentLedger
        )
        let store = DurableConsentLedgerStore(
            userDefaults: userDefaults,
            applicationSupportDirectory: root
        )

        XCTAssertEqual(try store.loadLedgerData(), legacyData)
        XCTAssertNil(
            userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger)
        )
        try store.saveLedgerData(replacementData)
        XCTAssertEqual(try store.loadLedgerData(), replacementData)

        let ledgerURL = root
            .appendingPathComponent("Naturebook", isDirectory: true)
            .appendingPathComponent("Consent", isDirectory: true)
            .appendingPathComponent("ledger-v1.json", isDirectory: false)
        XCTAssertEqual(try Data(contentsOf: ledgerURL), replacementData)
    }

}
