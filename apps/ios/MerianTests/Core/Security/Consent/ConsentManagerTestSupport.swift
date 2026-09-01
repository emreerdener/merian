@testable import Merian
import Foundation
import XCTest

enum RequiredConsentSynchronizationStubError: Error {
    case unavailable
}

@MainActor
class ConsentManagerTestCase: XCTestCase {
    var appSettings: AppSettings!
    var consentManager: ConsentManager!
    var userDefaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "merian.tests.onboarding.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
        consentManager = ConsentManager(userDefaults: userDefaults)
        appSettings.hasCompletedOnboarding = false
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = nil
        consentManager = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func makeAnalyticsEvent(
        ownerUserId: UUID,
        eventKind: ConsentManager.AnalyticsConsentEventKind,
        recordedAt: Date
    ) -> ConsentManager.AnalyticsConsentEvent {
        ConsentManager.AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: ConsentPolicy.analyticsDisclosureVersion,
            eventKind: eventKind,
            occurredAt: recordedAt.addingTimeInterval(-1),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    func makeAdultReceipt(
        ownerUserId: UUID,
        recordedAt: Date
    ) -> ConsentManager.AdultEligibilityReceipt {
        ConsentManager.AdultEligibilityReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            policyVersion: ConsentPolicy.adultEligibilityVersion,
            confirmedAt: recordedAt.addingTimeInterval(-1),
            confirmationMethod: .selfAttestation,
            confirmationText: ConsentPolicy.adultConfirmationText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    func makeTermsReceipt(
        ownerUserId: UUID,
        recordedAt: Date
    ) -> ConsentManager.TermsAcceptanceReceipt {
        ConsentManager.TermsAcceptanceReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            termsVersion: ConsentPolicy.termsVersion,
            acceptedAt: recordedAt.addingTimeInterval(-1),
            acceptanceText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    func makeAIConsentEvent(
        ownerUserId: UUID,
        recordedAt: Date,
        consentRevision: Int64
    ) -> ConsentManager.AIConsentEvent {
        ConsentManager.AIConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: ConsentPolicy.geminiDisclosureVersion,
            eventKind: .granted,
            occurredAt: recordedAt.addingTimeInterval(-1),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt,
            causalParentId: nil,
            consentRevision: consentRevision,
            supersededByEventId: nil,
            supersededByRevision: nil
        )
    }
}

struct AppliedAnalyticsPermission: Equatable {
    let enabled: Bool
    let userId: String?
}

final class FaultInjectingConsentLedgerStore: ConsentLedgerStoring {
    enum Failure: Error {
        case injected
    }

    var ledgerData: Data?
    var revocationIntentData: Data?
    var failLedgerReads = false
    var failLedgerWrites = false
    var failRevocationIntentReads = false
    var failRevocationIntentWrites = false
    var failRevocationIntentClears = false
    var operations: [String] = []

    func loadLedgerData() throws -> Data? {
        if failLedgerReads { throw Failure.injected }
        return ledgerData
    }

    func saveLedgerData(_ data: Data) throws {
        operations.append("saveLedger")
        if failLedgerWrites { throw Failure.injected }
        ledgerData = data
        guard ledgerData == data else { throw Failure.injected }
    }

    func loadAnalyticsRevocationIntentData() throws -> Data? {
        if failRevocationIntentReads { throw Failure.injected }
        return revocationIntentData
    }

    func saveAnalyticsRevocationIntentData(_ data: Data) throws {
        operations.append("saveIntent")
        if failRevocationIntentWrites { throw Failure.injected }
        revocationIntentData = data
        guard revocationIntentData == data else { throw Failure.injected }
    }

    func clearAnalyticsRevocationIntentData() throws {
        operations.append("clearIntent")
        if failRevocationIntentClears { throw Failure.injected }
        revocationIntentData = nil
        guard revocationIntentData == nil else { throw Failure.injected }
    }
}
