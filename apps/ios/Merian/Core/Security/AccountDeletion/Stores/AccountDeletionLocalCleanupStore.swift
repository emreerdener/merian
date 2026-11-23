import Foundation

enum AccountDeletionLocalCleanupStore {
    /// Immutable evidence for one local recovery stage. It never invents an owner
    /// from the identity-free marker; composition supplies the captured library.
    @MainActor
    struct RecoveryScope {
        let expectedState: AccountDeletionLocalRecoveryState?
        let expectedCapability: PreparedDeletionRecoveryCapability?
        let capabilityStore: AccountDeletionRecoveryCapabilityStore
        let readState: @MainActor () -> AccountDeletionLocalRecoveryState?
        let validateSession: @MainActor () -> Bool
        let validateLibrary: @MainActor (AnyObject?) -> Bool
        var expectedMarker: AccountDeletionCleanupMarker?
        var readMarker: @MainActor () -> AccountDeletionCleanupMarker? = { nil }
        var markerPrepared = true

        var cleanupOperationID: UUID? { expectedMarker?.operationID }

        var isCurrent: Bool {
            markerPrepared && readMarker() == expectedMarker &&
                (expectedState?.requiresRecoveryCapability != true || expectedCapability != nil) &&
                validateSession() && validateLibrary(nil) && readState() == expectedState &&
                capabilityStore.matchesExisting(expectedCapability)
        }

        var permitsRuntimeDrain: Bool {
            (expectedState == nil || expectedState?.isIntakePending == true || isAcceptedCleanup) && isCurrent
        }

        private var isAcceptedCleanup: Bool {
            expectedState == .capabilityCleanupPending || expectedState == .capabilityRetirementPending || expectedState == .cleanupPending
        }

        func permitsLibraryPurge(in container: AnyObject) -> Bool {
            isAcceptedCleanup && isCurrent && validateLibrary(container)
        }
    }

    static func state(
        userDefaults: UserDefaults = .standard
    ) -> AccountDeletionLocalRecoveryState? {
        let key = UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        let storedValue = userDefaults.object(forKey: key)
        guard let storedValue else { return nil }
        if let marker = AccountDeletionCleanupMarker.decode(storedValue) { return marker.phase }
        if let legacy = AccountDeletionCleanupMarker.legacyState(storedValue) { return legacy }
        // Unknown or malformed data remains pending and grants no accepted cleanup.
        return .intakePending
    }

    static func marker(userDefaults: UserDefaults = .standard) -> AccountDeletionCleanupMarker? {
        AccountDeletionCleanupMarker.decode(userDefaults.object(forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup))
    }

    /// Called only by the accepted recovery composition while its session,
    /// library and durable proof still match. Reads never upgrade implicitly.
    @MainActor static func prepareAcceptedMarker(
        expected: AccountDeletionLocalRecoveryState, userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard [.cleanupPending, .capabilityCleanupPending, .capabilityRetirementPending].contains(expected),
              state(userDefaults: userDefaults) == expected else { return false }
        if let saved = marker(userDefaults: userDefaults) {
            return saved.phase == expected && persistMarker(saved, userDefaults: userDefaults)
        }
        let key = UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        guard AccountDeletionCleanupMarker.legacyState(userDefaults.object(forKey: key)) == expected else { return false }
        return persistMarker(.init(phase: expected, operationID: UUID()), userDefaults: userDefaults)
    }

    private static func persistMarker(_ marker: AccountDeletionCleanupMarker, userDefaults: UserDefaults) -> Bool {
        userDefaults.set(marker.storedValue, forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup)
        return userDefaults.synchronize() && self.marker(userDefaults: userDefaults) == marker
    }

    static func isPending(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        state(userDefaults: userDefaults) != nil
    }

    @discardableResult
    @MainActor
    static func recordIntakePending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityIntakePending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityPreparationPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityPreparationPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityLookupPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil,
        emitEvent: Bool = true
    ) -> Bool {
        record(
            .capabilityLookupPending,
            userDefaults: userDefaults,
            eventSender: eventSender,
            emitEvent: emitEvent
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityPreparedPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityPreparedPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCleanupPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityCleanupPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityRetirementPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityRetirementPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityRejectionRetirementPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityRejectionRetirementPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    /// Compatibility spelling for call sites that already hold a server
    /// receipt. New deletion requests must persist `intakePending` first.
    @discardableResult
    @MainActor
    static func record(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .cleanupPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    private static func record(
        _ state: AccountDeletionLocalRecoveryState,
        userDefaults: UserDefaults,
        eventSender: (any AppEventSending)?,
        emitEvent: Bool = true
    ) -> Bool {
        let previous = userDefaults.object(forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup)
        let saved = AccountDeletionCleanupMarker.decode(previous)
        guard previous == nil || saved != nil || AccountDeletionCleanupMarker.legacyState(previous) != nil else { return false }
        let next = AccountDeletionCleanupMarker(phase: state, operationID: saved?.operationID ?? UUID())
        guard persistMarker(next, userDefaults: userDefaults) else { return false }
        if emitEvent {
            let sender = eventSender ?? AppDIContainer.shared.appEventPublisher
            sender.send(.accountDeletionRecoveryStateChanged)
        }
        return true
    }

    @discardableResult
    @MainActor
    static func resolve(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil,
        emitEvent: Bool = true
    ) -> Bool {
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )
        guard userDefaults.synchronize(),
              state(userDefaults: userDefaults) == nil else {
            return false
        }
        if emitEvent {
            let sender = eventSender ?? AppDIContainer.shared.appEventPublisher
            sender.send(.accountDeletionRecoveryStateChanged)
        }
        return true
    }
}
