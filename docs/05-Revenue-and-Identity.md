# Revenue and Identity Management

Merian implements a seamless onboarding funnel by marrying Supabase Anonymous Authentication deeply with RevenueCat SDK bindings for entitlement checking natively.

## The Anonymous IDFV Strategy (`DeviceIdentityManager`)

To maximize user conversion, Merian demands zero upfront onboarding friction:

- Boots physically on app launch, silently pulling `UIDevice.current.identifierForVendor` via the iOS Keychain natively.
- This creates persistent tracking tied exclusively to the `.uuidString` securely across the iOS lifecycle without volatile cookie dependencies.
- It strictly acts as the new `DeviceIdentityManager` IDFV Apple Keychain fallback, permanently replacing legacy `Apple DeviceCheck` or `DCDevice` logic to track identities safely natively.
- Automatically pushes this IDFV tracking string into PostHog for telemetry mappings and RevenueCat for correct entitlement tracking seamlessly.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls strict Apple ecosystem bounds dictating core app functionalities intuitively.
- Initializes `.configure(withAPIKey:)` silently pulling the active iOS `ProcessInfo` values physically mapping to `.xcconfig` secure layers.
- **CRITICAL DEBUG NOTE**: In explicit Release configurations, if a `test_` public key is detected instead of a `pk_`, `RevenueCatManager` intercepts the boot and injects a pseudo key to successfully bypass severe Apple `SIGTRAP` crash events during TestFlight deployments.
- Uses `logIn(currentAppUserID)` binding the IDFV tracking string natively.
- Evaluates `isProActive` booleans via `.purchaserInfo()` observing `"pro_subscription"` logic seamlessly updating SwiftUI.

## Usage Limits (`UsageManager`)

A tightly coupled boundary enforcing the Paywall visually in frontend boundaries securely.

- Connects logically to `.canPerformScan(isProActive:)`.
- Grants 3 free daily validations intrinsically via `UserDefaults` keyed explicitly against `DeviceIdentityManager.shared.deviceId`.
- Resets limits predictably across calendar bounds, actively triggering `$isPaywallOpen` sheets on strict bounds.
