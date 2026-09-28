import Foundation
@_spi(Internal) import RevenueCat

enum RevenueCatSDKLogPrivacyPolicy {
    /// RevenueCat SDK messages may contain App User IDs or provider payload
    /// details. Merian deliberately discards message bodies and emits only a
    /// fixed severity marker for actionable SDK warnings and errors.
    static func safeMessage(for level: LogLevel) -> String? {
        switch level {
        case .warn:
            return "RevenueCat SDK reported a warning."
        case .error:
            return "RevenueCat SDK reported an error."
        case .verbose, .debug, .info:
            return nil
        }
    }
}

enum RevenueCatOfferingDiagnosticPolicy {
    /// Only fixed categories and numeric codes cross the public log boundary.
    /// Never forward domains, descriptions, userInfo, or underlying SDK errors.
    static func summary(for error: Error) -> String {
        let error = error as NSError
        if error.domain == RevenueCat.ErrorCode.errorDomain {
            let category: String
            switch RevenueCat.ErrorCode(rawValue: error.code) {
            case .networkError, .offlineConnectionError, .apiEndpointBlockedError:
                category = "network"
            case .configurationError, .invalidCredentialsError:
                category = "configuration"
            case .storeProblemError, .productNotAvailableForPurchaseError,
                 .productRequestTimedOut:
                category = "store"
            default:
                category = "provider"
            }
            return "source=revenuecat category=\(category) code=\(error.code)"
        }
        if error.domain == NSURLErrorDomain {
            return "source=url-loading category=network code=\(error.code)"
        }
        return "source=other category=unknown"
    }
}

enum RevenueCatStableIdentityPrivacyPolicy {
    static let legacyAccountAttributeKeys =
        RevenueCatLegacySubscriberAttributeKey.allCases.map(\.rawValue)

    static var deletionAttributes: [String: String] {
        Dictionary(uniqueKeysWithValues: legacyAccountAttributeKeys.map {
            ($0, "")
        })
    }
}
