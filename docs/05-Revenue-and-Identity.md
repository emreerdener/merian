# Revenue and Identity Management

Merian implements a seamless onboarding funnel by marrying Supabase Anonymous Authentication deeply with RevenueCat SDK bindings for entitlement checking natively.

## The Anonymous "Ghost" Strategy (`SupabaseManager`)

To maximize user conversion, Merian demands zero upfront onboarding friction:

- **`initializeGhostSession()`**: Boots physically on app launch, silently fetching an anonymous UUID session without Apple Sign-In gates natively.
- This creates persistent tracking tied exclusively to the `.uuidString` securely across the iOS lifecycle.
- Automatically mirrors the Supabase user identity into PostHog for telemetry mappings and RevenueCat for correct entitlement tracking seamlessly.

## Paywalls and Entitlements (`RevenueCatManager`)

Controls strict Apple ecosystem bounds dictating core app functionalities intuitively.

- Initializes `.configure(withAPIKey:)` silently pulling the active iOS `ProcessInfo` values physically mapping to `.xcconfig` secure layers.
- Uses `logIn(currentAppUserID)` binding the Supabase Ghost user natively.
- Evaluates `isProActive` booleans via `.purchaserInfo()` observing `"pro_subscription"` logic seamlessly updating SwiftUI.

## Usage Limits (`UsageManager`)

A tightly coupled boundary enforcing the Paywall visually in frontend boundaries securely.

- Connects logically to `.canPerformScan(isProActive:)`.
- Grants 3 free daily validations intrinsically via `UserDefaults`.
- Resets limits predictably across calendar bounds, actively triggering `$isPaywallOpen` sheets on strict bounds.
