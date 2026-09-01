@testable import Merian
import Foundation
import XCTest

@MainActor
final class ConsentManagerAuthorityTests: ConsentManagerTestCase {
    func testOverlappingAccountTransitionsOnlyNewestResolutionReopensAnalytics() throws {
        let originalUserId = UUID()
        let replacementUserId = UUID()
        consentManager.observeSession(userId: originalUserId)
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )

        let firstGeneration = consentManager.beginAnalyticsAccountTransition()
        let secondGeneration = consentManager.beginAnalyticsAccountTransition()
        XCTAssertTrue(consentManager.isAnalyticsSuppressedForAccountTransition)

        XCTAssertFalse(
            consentManager.resolveAnalyticsAccountTransition(
                generation: firstGeneration,
                userId: originalUserId
            )
        )
        XCTAssertTrue(consentManager.isAnalyticsSuppressedForAccountTransition)
        XCTAssertEqual(consentManager.currentSessionUserId, originalUserId)

        XCTAssertTrue(
            consentManager.resolveAnalyticsAccountTransition(
                generation: secondGeneration,
                userId: replacementUserId
            )
        )
        XCTAssertFalse(consentManager.isAnalyticsSuppressedForAccountTransition)
        XCTAssertEqual(consentManager.currentSessionUserId, replacementUserId)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
    }

    func testSynchronizationContextRequiresCurrentUncancelledAccount() {
        let expectedUserId = UUID()
        let otherUserId = UUID()
        let expectedGeneration: UInt = 7

        XCTAssertTrue(
            ConsentManager.isSynchronizationContextCurrent(
                expectedUserId: expectedUserId,
                expectedGeneration: expectedGeneration,
                observedUserId: expectedUserId,
                sdkUserId: expectedUserId,
                currentGeneration: expectedGeneration,
                isCancelled: false
            )
        )

        let invalidContexts: [(UUID?, UUID?, UInt, Bool)] = [
            (otherUserId, expectedUserId, expectedGeneration, false),
            (nil, expectedUserId, expectedGeneration, false),
            (expectedUserId, otherUserId, expectedGeneration, false),
            (expectedUserId, nil, expectedGeneration, false),
            (expectedUserId, expectedUserId, expectedGeneration + 1, false),
            (expectedUserId, expectedUserId, expectedGeneration, true)
        ]

        for (observedUserId, sdkUserId, currentGeneration, isCancelled) in invalidContexts {
            XCTAssertFalse(
                ConsentManager.isSynchronizationContextCurrent(
                    expectedUserId: expectedUserId,
                    expectedGeneration: expectedGeneration,
                    observedUserId: observedUserId,
                    sdkUserId: sdkUserId,
                    currentGeneration: currentGeneration,
                    isCancelled: isCancelled
                )
            )
        }
    }

    func testStaleSynchronizationMergeCannotMutateReplacementAccountLedger() throws {
        let originalUserId = UUID()
        let replacementUserId = UUID()
        consentManager.observeSession(userId: originalUserId)
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        consentManager.observeSession(userId: replacementUserId)

        let ledgerBeforeMerge = userDefaults.data(
            forKey: UserDefaultsKeys.legalConsentLedger
        )
        XCTAssertEqual(
            consentManager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: replacementUserId)
        )
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)

        XCTAssertThrowsError(
            try consentManager.merge(
                ConsentManager.RemoteState(
                    adultEligibilityReceipt: nil,
                    termsReceipt: nil,
                    aiConsentEvent: nil,
                    analyticsConsentEvent: nil,
                    aiConsentStreamHead: nil,
                    analyticsConsentStreamHead: nil
                ),
                for: originalUserId,
                generation: 0
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(consentManager.currentSessionUserId, replacementUserId)
        XCTAssertEqual(
            consentManager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: replacementUserId)
        )
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(
            userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger),
            ledgerBeforeMerge
        )
    }

    func testRestoredCachedAnalyticsGrantStaysClosedUntilRemoteRevocationMerges() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let localGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [localGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )

        XCTAssertTrue(manager.hasGrantedCurrentPostHogAnalytics)
        manager.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: ownerUserId)
        )
        XCTAssertEqual(
            applications,
            [.init(enabled: false, userId: nil)]
        )

        let remoteRevocation = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_001)
        )
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: remoteRevocation,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: remoteRevocation
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertFalse(applications.contains(where: \.enabled))

        var restartedApplications: [AppliedAnalyticsPermission] = []
        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                restartedApplications.append(
                    .init(enabled: enabled, userId: userId)
                )
            }
        )
        restarted.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            restarted.analyticsCloudAuthorityState,
            .awaitingRemote(userId: ownerUserId)
        )
        XCTAssertEqual(
            restartedApplications,
            [.init(enabled: false, userId: nil)]
        )
    }

    func testRestoredCachedAnalyticsGrantStaysClosedWhenRemoteGrantIsAbsent() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let localGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [localGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )

        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: false)
        )
        XCTAssertFalse(applications.contains(where: { $0.enabled }))
    }

    func testRestoredAnalyticsGrantOpensOnlyAfterAuthoritativeMerge() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let remoteGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [remoteGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )

        manager.observeSession(userId: ownerUserId)
        XCTAssertEqual(applications.map(\.enabled), [false])

        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: remoteGrant,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: remoteGrant
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: true)
        )
        XCTAssertEqual(applications.map(\.enabled), [false, true])
        XCTAssertEqual(applications.last?.userId, ownerUserId.uuidString)

        manager.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: true)
        )
        XCTAssertEqual(applications.map(\.enabled), [false, true, true])
    }

    func testFailedAuthoritativeMergeKeepsRestoredAnalyticsClosed() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let localGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [localGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )
        manager.observeSession(userId: ownerUserId)
        store.failLedgerWrites = true

        XCTAssertThrowsError(
            try manager.merge(
                ConsentManager.RemoteState(
                    adultEligibilityReceipt: nil,
                    termsReceipt: nil,
                    aiConsentEvent: nil,
                    analyticsConsentEvent: localGrant,
                    aiConsentStreamHead: nil,
                    analyticsConsentStreamHead: localGrant
                ),
                for: ownerUserId,
                generation: 1
            )
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: ownerUserId)
        )
        XCTAssertEqual(applications.map(\.enabled), [false])
    }

    func testAnalyticsConsentRealtimeRetryUsesBoundedExponentialBackoff() {
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 1), 1)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 2), 2)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 3), 4)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 6), 30)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 100), 30)
    }

    func testRequiredConsentRestorationRetryUsesBoundedBackoff() {
        XCTAssertEqual(
            ConsentManager.maximumAutomaticRestorationRetries,
            3
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 1),
            5
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 2),
            10
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 3),
            20
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 4),
            30
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 100),
            30
        )
    }

}
