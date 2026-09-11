import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Account deletion local cleanup store")
struct AccountDeletionLocalCleanupStoreTests {
    @Test func persistenceContractValuesRemainStable() {
        #expect(
            UserDefaultsKeys.pendingManualAppleRevocationNotice ==
                "pendingManualAppleRevocationNotice.v1"
        )
        #expect(
            UserDefaultsKeys.pendingLocalAccountDeletionCleanup ==
                "pendingLocalAccountDeletionCleanup.v1"
        )

        let expectedStates: [(AccountDeletionLocalRecoveryState, String)] = [
            (
                .capabilityPreparationPending,
                "capability_preparation_pending"
            ),
            (.capabilityPreparedPending, "capability_prepared_pending"),
            (.intakePending, "intake_pending"),
            (.cleanupPending, "cleanup_pending"),
            (.capabilityIntakePending, "capability_intake_pending"),
            (.capabilityCleanupPending, "capability_cleanup_pending"),
            (.capabilityRetirementPending, "capability_retirement_pending"),
            (
                .capabilityRejectionRetirementPending,
                "capability_rejection_retirement_pending"
            ),
            (.capabilityLookupPending, "capability_lookup_pending")
        ]

        for (state, rawValue) in expectedStates {
            #expect(state.rawValue == rawValue)
            #expect(
                AccountDeletionLocalRecoveryState(rawValue: rawValue) == state
            )
        }
    }

    @Test func cleanupPersistsUntilResolutionAndPublishesInvalidations() throws {
        let suiteName =
            "merian.tests.account-deletion-cleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let events = AppEventPublisher()
        var recoveryInvalidations = 0
        var statesObservedAtInvalidation: [
            AccountDeletionLocalRecoveryState?
        ] = []
        let cancellable = events.publisher.sink { event in
            if case .accountDeletionRecoveryStateChanged = event {
                recoveryInvalidations += 1
                statesObservedAtInvalidation.append(
                    AccountDeletionLocalCleanupStore.state(
                        userDefaults: defaults
                    )
                )
            }
        }
        defer { cancellable.cancel() }

        #expect(
            !AccountDeletionLocalCleanupStore.isPending(userDefaults: defaults)
        )
        #expect(
            AccountDeletionLocalCleanupStore.recordIntakePending(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityIntakePending
        )
        #expect(
            AccountDeletionLocalCleanupStore.recordCleanupPending(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(
            AccountDeletionLocalCleanupStore.isPending(userDefaults: defaults)
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityCleanupPending
        )
        #expect(
            AccountDeletionLocalCleanupStore
                .recordCapabilityRetirementPending(
                    userDefaults: defaults,
                    eventSender: events
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityRetirementPending
        )
        #expect(
            AccountDeletionLocalCleanupStore
                .recordCapabilityRejectionRetirementPending(
                    userDefaults: defaults,
                    eventSender: events
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityRejectionRetirementPending
        )
        #expect(
            AccountDeletionLocalCleanupStore.resolve(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(
            !AccountDeletionLocalCleanupStore.isPending(userDefaults: defaults)
        )
        #expect(recoveryInvalidations == 5)
        #expect(
            statesObservedAtInvalidation == [
                .capabilityIntakePending,
                .capabilityCleanupPending,
                .capabilityRetirementPending,
                .capabilityRejectionRetirementPending,
                nil
            ]
        )
    }

    @Test func legacyAcceptedReceiptUsesCapabilityFreeCleanupState() throws {
        let suiteName = "AccountDeletionCleanupStore.Compat.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let events = AppEventPublisher()

        #expect(
            AccountDeletionLocalCleanupStore.record(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .cleanupPending
        )
    }

    @Test func legacyBooleanMigratesAsAcceptedCleanup() throws {
        let suiteName = "AccountDeletionCleanupStore.Legacy.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            true,
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )

        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .cleanupPending
        )
    }

    @Test func unknownStateFailsClosedBeforeLocalErasure() throws {
        let suiteName = "AccountDeletionCleanupStore.Unknown.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "future_state",
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )

        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .intakePending
        )
    }
}
