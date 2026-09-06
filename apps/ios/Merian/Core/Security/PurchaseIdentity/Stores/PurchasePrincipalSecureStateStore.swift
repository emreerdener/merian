import Foundation

struct PurchasePrincipalSecureStateStore {
    private let secureStore: any PurchasePrincipalSecureStore

    init(secureStore: any PurchasePrincipalSecureStore) {
        self.secureStore = secureStore
    }

    func loadStableActivationFingerprint() throws -> String? {
        guard let data = try secureStore.dataOrThrow(
            forKey: KeychainKeys.purchasePrincipalStableActivationFingerprint
        ) else {
            return nil
        }
        guard let fingerprint = String(data: data, encoding: .utf8),
              PurchasePrincipalCapabilityPolicy.isValidFingerprint(
                  fingerprint
              ) else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return fingerprint
    }

    func persistStableActivationFingerprint(
        _ fingerprint: String
    ) throws {
        guard PurchasePrincipalCapabilityPolicy.isValidFingerprint(
            fingerprint
        ) else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        if let existing = try loadStableActivationFingerprint() {
            guard existing == fingerprint else {
                throw PurchasePrincipalResolverError.capabilityUnavailable
            }
            return
        }
        let data = Data(fingerprint.utf8)
        guard secureStore.set(
            data,
            forKey: KeychainKeys.purchasePrincipalStableActivationFingerprint,
            accessibility: .whenUnlockedThisDeviceOnly
        ), try secureStore.dataOrThrow(
            forKey: KeychainKeys.purchasePrincipalStableActivationFingerprint
        ) == data else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
    }

    func advanceBindingIntentGeneration(
        requiresExisting: Bool
    ) throws -> Int64 {
        let key = KeychainKeys.purchasePrincipalBindingIntentGeneration
        let current: Int64
        if let data = try secureStore.dataOrThrow(forKey: key) {
            guard let value = String(data: data, encoding: .utf8),
                  let parsed = Int64(value),
                  parsed >= 0,
                  String(parsed) == value else {
                throw PurchasePrincipalResolverError.capabilityUnavailable
            }
            current = parsed
        } else if requiresExisting {
            // Once stable mode has activated, losing only the ordering record
            // is uncertainty. Never reset it to one and risk replaying an old
            // Auth binding against a higher server generation.
            throw PurchasePrincipalResolverError.capabilityUnavailable
        } else {
            current = 0
        }
        let next = try PurchasePrincipalBindingIntentPolicy.next(after: current)
        let encoded = Data(String(next).utf8)
        guard secureStore.set(
            encoded,
            forKey: key,
            accessibility: .whenUnlockedThisDeviceOnly
        ), try secureStore.dataOrThrow(forKey: key) == encoded else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return next
    }
}
