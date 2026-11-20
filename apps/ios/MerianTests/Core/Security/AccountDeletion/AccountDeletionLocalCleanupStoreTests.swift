import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Account deletion local cleanup store")
struct AccountDeletionLocalCleanupStoreTests {
    @Test func recoveryScopeSeparatesRuntimeJoinFromAcceptedPurge() throws {
        let container = NSObject(), foreign = NSObject()
        for state: AccountDeletionLocalRecoveryState? in [nil, .intakePending, .capabilityPreparationPending,
            .capabilityPreparedPending, .capabilityIntakePending, .cleanupPending, .capabilityCleanupPending,
            .capabilityRetirementPending, .capabilityRejectionRetirementPending, .capabilityLookupPending] {
            let store = AccountDeletionSecureStoreStub().makeCapabilityStore()
            let proof = state?.requiresRecoveryCapability == true ? try store.prepare() : nil
            var current = true
            let scope = AccountDeletionLocalCleanupStore.RecoveryScope(expectedState: state, expectedCapability: proof,
                capabilityStore: store, readState: { state }, validateSession: { current },
                validateLibrary: { $0 == nil || $0 === container })
            let accepted = state == .cleanupPending || state == .capabilityCleanupPending || state == .capabilityRetirementPending
            #expect(scope.permitsRuntimeDrain == (state == nil || state?.isIntakePending == true || accepted))
            #expect(scope.permitsLibraryPurge(in: container) == accepted)
            #expect(!scope.permitsLibraryPurge(in: foreign))
            current = false
            #expect(!scope.permitsRuntimeDrain)
            #expect(!scope.permitsLibraryPurge(in: container))
        }
    }

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

    @Test func preBootstrapResolutionDoesNotPublishRuntimeEvents() throws {
        let suiteName = "AccountDeletionCleanupStore.Bootstrap.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let events = AppEventPublisher()
        var invalidations = 0
        let cancellable = events.publisher.sink { event in
            if case .accountDeletionRecoveryStateChanged = event {
                invalidations += 1
            }
        }
        defer { cancellable.cancel() }

        #expect(AccountDeletionLocalCleanupStore.recordCapabilityLookupPending(
            userDefaults: defaults,
            eventSender: events,
            emitEvent: false
        ))
        #expect(AccountDeletionLocalCleanupStore.resolve(
            userDefaults: defaults,
            eventSender: events,
            emitEvent: false
        ))
        #expect(AccountDeletionLocalCleanupStore.state(userDefaults: defaults) == nil)
        #expect(invalidations == 0)
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
