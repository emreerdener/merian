import Foundation

enum AccountDeletionLocalCleanupStore {
    static func state(
        userDefaults: UserDefaults = .standard
    ) -> AccountDeletionLocalRecoveryState? {
        let key = UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        let storedValue = userDefaults.object(forKey: key)
        if let rawValue = storedValue as? String {
            // An unknown future state remains fail-closed at the non-destructive
            // intake boundary. This build must re-confirm server acceptance,
            // never infer permission to erase local state from an unknown value.
            return AccountDeletionLocalRecoveryState(rawValue: rawValue)
                ?? .intakePending
        }
        // Builds predating the two-phase protocol stored a Boolean only after
        // server acceptance. Preserve that recovery meaning during upgrade.
        if let legacyAcceptedMarker = storedValue as? Bool,
           legacyAcceptedMarker {
            return .cleanupPending
        }
        return nil
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
        userDefaults.set(
            state.rawValue,
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )
        // This marker is the local side of an irreversible request. Force the
        // preferences domain to disk, then read it back before allowing the
        // network mutation to start.
        guard userDefaults.synchronize(),
              self.state(userDefaults: userDefaults) == state else {
            return false
        }
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
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )
        guard userDefaults.synchronize(),
              state(userDefaults: userDefaults) == nil else {
            return false
        }
        let sender = eventSender ?? AppDIContainer.shared.appEventPublisher
        sender.send(.accountDeletionRecoveryStateChanged)
        return true
    }
}
