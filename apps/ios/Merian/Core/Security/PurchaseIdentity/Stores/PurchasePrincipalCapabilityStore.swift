import Foundation

struct PurchasePrincipalCapabilityStore {
    typealias Generator = () throws -> Data

    private let secureStore: any PurchasePrincipalSecureStore
    private let generateCapability: Generator

    init(
        secureStore: any PurchasePrincipalSecureStore
    ) {
        self.init(
            secureStore: secureStore,
            generateCapability: PurchasePrincipalSecureRandom
                .generateCapability
        )
    }

    init(
        secureStore: any PurchasePrincipalSecureStore,
        generateCapability: @escaping Generator
    ) {
        self.secureStore = secureStore
        self.generateCapability = generateCapability
    }

    func loadExisting() throws -> Data {
        guard let capability = try secureStore.dataOrThrow(
            forKey: KeychainKeys.purchasePrincipalInstallationCapability
        ), capability.count == 32 else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return capability
    }

    func loadOrCreate(allowsCreation: Bool) throws -> Data {
        let key = KeychainKeys.purchasePrincipalInstallationCapability
        if let existing = try secureStore.dataOrThrow(forKey: key) {
            guard existing.count == 32 else {
                throw PurchasePrincipalResolverError.capabilityUnavailable
            }
            return existing
        }
        guard allowsCreation else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }

        let capability = try generateCapability()
        guard capability.count == 32,
              secureStore.set(
                  capability,
                  forKey: key,
                  accessibility: .whenUnlockedThisDeviceOnly
              ),
              try secureStore.dataOrThrow(forKey: key) == capability else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return capability
    }
}
