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

enum RevenueCatStableIdentityPrivacyPolicy {
    static let legacyAccountAttributeKeys =
        RevenueCatLegacySubscriberAttributeKey.allCases.map(\.rawValue)

    static var deletionAttributes: [String: String] {
        Dictionary(uniqueKeysWithValues: legacyAccountAttributeKeys.map {
            ($0, "")
        })
    }
}
