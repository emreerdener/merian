import Foundation
@_spi(Internal) import RevenueCat

enum SevenDayPassAccessPolicy {
    static let productIdentifier = "pro_week"
    static let duration: TimeInterval = 7 * 24 * 60 * 60

    static func isActive(
        purchases: [SevenDayPassPurchase],
        now: Date = Date()
    ) -> Bool {
        purchases.contains { purchase in
            guard purchase.productIdentifier == productIdentifier else {
                return false
            }
            return purchase.purchaseDate.addingTimeInterval(duration) > now
        }
    }
}

enum RevenueCatOfferingPolicy {
    static let annualProductIdentifier = "pro_annual"
    static let requiredProductIdentifiers = Set([
        SevenDayPassAccessPolicy.productIdentifier,
        annualProductIdentifier
    ])

    static func missingRequiredProducts(
        in productIdentifiers: Set<String>
    ) -> Set<String> {
        requiredProductIdentifiers.subtracting(productIdentifiers)
    }
}

enum RevenueCatCustomerInfoVerificationPolicy {
    /// RevenueCat informational verification keeps the SDK available while
    /// making trust an explicit Merian decision. Only server-signed responses
    /// and StoreKit 2 data verified on-device may open local paid access.
    static func allowsPaidAccess(_ result: VerificationResult) -> Bool {
        result == .verified || result == .verifiedOnDevice
    }
}

enum RevenueCatEntitlementProvenancePolicy {
    static var allowsTestStoreForCurrentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func hasActiveStoreBackedSubscription(
        productIdentifiers: Set<String>,
        storeByProductIdentifier: [String: Store],
        accountGrantsAllowed: Bool
    ) -> Bool {
        let annualProductIdentifier =
            RevenueCatOfferingPolicy.annualProductIdentifier
        guard productIdentifiers.contains(annualProductIdentifier),
              let store = storeByProductIdentifier[annualProductIdentifier]
        else {
            return false
        }
        return allowsStoreBackedAccess(
            store: store,
            accountGrantsAllowed: accountGrantsAllowed
        )
    }

    static func allowsStoreBackedAccess(
        store: Store,
        accountGrantsAllowed: Bool,
        allowsTestStore: Bool = allowsTestStoreForCurrentBuild
    ) -> Bool {
        switch store {
        case .appStore:
            return true
        case .promotional:
            return accountGrantsAllowed
        case .testStore:
            return allowsTestStore
        case .macAppStore, .playStore, .stripe, .unknownStore, .amazon,
             .rcBilling, .external, .paddle, .galaxy:
            return false
        @unknown default:
            return false
        }
    }
}
