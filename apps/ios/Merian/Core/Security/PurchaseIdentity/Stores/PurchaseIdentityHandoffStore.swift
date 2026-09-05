import Foundation

enum PurchaseIdentityHandoffStoreError: Error {
    case signOutPurchaseHandoffPersistenceFailed
    case purchasePrincipalRotationPersistenceFailed
}

@MainActor
struct PurchaseIdentityHandoffStore {
    struct Dependencies {
        let loadData: (String) throws -> Data?
        let persistData: (
            Data,
            String,
            KeychainManager.Accessibility
        ) -> Bool
        let removeDataVerified: (String) throws -> Void

        static func live(keychain: KeychainManager) -> Self {
            Self(
                loadData: { key in
                    try keychain.dataOrThrow(forKey: key)
                },
                persistData: { data, key, accessibility in
                    keychain.set(
                        data,
                        forKey: key,
                        accessibility: accessibility
                    )
                },
                removeDataVerified: { key in
                    try keychain.removeObjectVerified(forKey: key)
                }
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func loadPendingSignOutPurchaseHandoff() throws
        -> PendingSignOutPurchaseHandoff? {
        let key = KeychainKeys.pendingSignOutPurchaseHandoff
        guard let data = try dependencies.loadData(key) else {
            return nil
        }
        guard let pending = try? JSONDecoder().decode(
            PendingSignOutPurchaseHandoff.self,
            from: data
        ), Self.isValid(pending) else {
            throw PurchaseIdentityHandoffStoreError
                .signOutPurchaseHandoffPersistenceFailed
        }
        return pending
    }

    func persistPendingSignOutPurchaseHandoff(
        _ pending: PendingSignOutPurchaseHandoff
    ) throws {
        guard Self.isValid(pending) else {
            throw PurchaseIdentityHandoffStoreError
                .signOutPurchaseHandoffPersistenceFailed
        }
        let data = try JSONEncoder().encode(pending)
        try persistVerified(
            data,
            forKey: KeychainKeys.pendingSignOutPurchaseHandoff,
            error: .signOutPurchaseHandoffPersistenceFailed
        )
    }

    func clearPendingSignOutPurchaseHandoff() throws {
        try dependencies.removeDataVerified(
            KeychainKeys.pendingSignOutPurchaseHandoff
        )
    }

    func loadPendingPurchasePrincipalAuthRotation() throws
        -> PendingPurchasePrincipalAuthRotation? {
        let key = KeychainKeys.pendingPurchasePrincipalAuthRotation
        guard let data = try dependencies.loadData(key) else {
            return nil
        }
        if let pending = try? JSONDecoder().decode(
            ServerPrincipalRotation.self,
            from: data
        ) {
            guard Self.isValid(pending) else {
                throw PurchaseIdentityHandoffStoreError
                    .purchasePrincipalRotationPersistenceFailed
            }
            return .server(pending)
        }
        if let legacy = try? JSONDecoder().decode(
            LegacyPrincipalRotation.self,
            from: data
        ), Self.isValid(legacy) {
            // Protocol-v1 was client-only evidence. It may be retired only
            // from its exact restored source; it can never authorize a new
            // anonymous binding.
            return .legacy(legacy)
        }
        throw PurchaseIdentityHandoffStoreError
            .purchasePrincipalRotationPersistenceFailed
    }

    func persistPendingPurchasePrincipalAuthRotation(
        _ pending: ServerPrincipalRotation
    ) throws {
        guard Self.isValid(pending) else {
            throw PurchaseIdentityHandoffStoreError
                .purchasePrincipalRotationPersistenceFailed
        }
        let data = try JSONEncoder().encode(pending)
        try persistVerified(
            data,
            forKey: KeychainKeys.pendingPurchasePrincipalAuthRotation,
            error: .purchasePrincipalRotationPersistenceFailed
        )
    }

    func clearPendingPurchasePrincipalAuthRotation() throws {
        try dependencies.removeDataVerified(
            KeychainKeys.pendingPurchasePrincipalAuthRotation
        )
    }

    private func persistVerified(
        _ data: Data,
        forKey key: String,
        error: PurchaseIdentityHandoffStoreError
    ) throws {
        guard dependencies.persistData(
            data,
            key,
            .whenUnlockedThisDeviceOnly
        ), try dependencies.loadData(key) == data else {
            throw error
        }
    }

    private static func isValid(
        _ pending: PendingSignOutPurchaseHandoff
    ) -> Bool {
        UUID(uuidString: pending.sourceUserId) != nil
            && UUID(uuidString: pending.handoffId) != nil
            && isValidSecret(pending.handoffSecret)
            && ISO8601DateFormatter().date(from: pending.expiresAt) != nil
    }

    private static func isValid(_ pending: ServerPrincipalRotation) -> Bool {
        guard pending.protocolVersion == 3,
              UUID(uuidString: pending.rotationId) != nil,
              isValidSecret(pending.rotationSecret),
              UUID(uuidString: pending.sourceUserId) != nil,
              UUID(uuidString: pending.purchasePrincipalId) != nil,
              pending.bindingGeneration > 0,
              PurchasePrincipalBinding.isValidRevenueCatAppUserId(
                  pending.revenueCatAppUserId
              ),
              PurchasePrincipalCapabilityPolicy.isValidFingerprint(
                  pending.installationCapabilityFingerprint
              ),
              ISO8601DateFormatter().date(from: pending.startedAt) != nil else {
            return false
        }
        switch pending.localState {
        case .preparing:
            return pending.expiresAt == nil
        case .prepared:
            return pending.expiresAt.map(
                PurchasePrincipalBinding.isValidServerTimestamp
            ) == true
        }
    }

    private static func isValid(_ pending: LegacyPrincipalRotation) -> Bool {
        UUID(uuidString: pending.sourceUserId) != nil
            && UUID(uuidString: pending.purchasePrincipalId) != nil
            && PurchasePrincipalBinding.isValidRevenueCatAppUserId(
                pending.revenueCatAppUserId
            )
            && PurchasePrincipalCapabilityPolicy.isValidFingerprint(
                pending.installationCapabilityFingerprint
            )
            && ISO8601DateFormatter().date(from: pending.startedAt) != nil
    }

    private static func isValidSecret(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
        ) != nil
    }
}
