# Revenue and Identity Management

Merian implements a seamless onboarding funnel by marrying Supabase Anonymous Authentication deeply with RevenueCat SDK bindings for entitlement checking natively.

## The Anonymous IDFV Strategy (`DeviceIdentityManager`)

To maximize user conversion, Merian demands zero upfront onboarding friction:

- Boots physically on app launch, silently pulling `UIDevice.current.identifierForVendor` (or `WKInterfaceDevice.current().identifierForVendor` natively compiled for watchOS) via the Apple Keychain natively.
- This creates persistent tracking tied exclusively to the `.uuidString` securely across the ecosystem lifecycle without volatile session cookie dependencies.
- It strictly acts as the unified Apple Keychain fallback permanently solving "split-brain" tracking between databases. `SupabaseManager` intercepts Anonymous sign-ins and unconditionally enforces `DeviceIdentityManager.shared.deviceId` directly into both RevenueCat and PostHog, explicitly abandoning the Supabase ghost session UUID to ensure identity remains contiguous.
- **Identity Resolution & Native OAuth**: Merian actively leverages standard Apple (`ASAuthorizationAppleIDProvider`) and Google (`GIDSignIn`) native iOS libraries to authenticate securely without clunky web-view boundaries.
  - When a user taps "Sign in with Apple" or "Sign in with Google", iOS acquires the raw cryptographically signed `.idToken`.
  - Merian passes this `idToken` natively through Supabase's `signInWithIdToken(provider: .apple/.google, idToken: token)` edge capability, mapping instantly back into a true `Session` object.
  - Once the `session.user.id.uuidString` generates, `SupabaseManager` intercepts it and explicitly calls `RevenueCatManager.shared.linkWithSupabase(userId: newUserId)` and `PostHogManager.shared.identifyUser(userId: newUserId)`. This sequence securely aliases their prior native IDFV/Ghost physical tracking payload logic cleanly into their fresh permanent Cloud Identity, guaranteeing they never mysteriously lose tracking arrays, life lists, or paid `Pro` App Store tier entitlements during account transitions or multi-device upgrades.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls strict Apple ecosystem bounds dictating core app functionalities intuitively.
- Initializes `.configure(withAPIKey:)` silently pulling the active iOS `ProcessInfo` values physically mapping to `.xcconfig` secure layers.
- **CRITICAL DEBUG NOTE**: In explicit Release configurations, if a `test_` public key is detected instead of a `pk_`, `RevenueCatManager` intercepts the boot and injects a pseudo key to successfully bypass severe Apple `SIGTRAP` crash events during TestFlight deployments.
- Uses `logIn(currentAppUserID)` binding the IDFV tracking string natively.
- Evaluates `isProActive` booleans via `.purchaserInfo()` observing `"pro_subscription"` logic seamlessly updating SwiftUI.

## RevenueCat Webhook (`revenuecat-webhook`)

To ensure the Supabase PostgreSQL backend perfectly mirrors the iOS RevenueCat entitlement state, a dedicated `revenuecat-webhook` Edge Function passively listens for global subscription events (`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, and `UNCANCELLATION`):

1. **Tier Syndication**: Automatically updates the `users.subscription_tier` enum to `pro` upon initialization/renewal, and securely downgrades it back to `free` on expiration.
2. **Cloudflare Data Migration**: When an arbitrary user upgrades to `pro`, the webhook queries the `scans` table looking for orphaned images stranded inside the `public_uploads/free/` boundary. It leverages the AWS S3 SDK to perform remote mathematical `PUT` copies, dynamically elevating the physics binary bytes natively into the permanent `public_uploads/pro/{userId}/` tier, completely protecting the payer from the Rolling Cloud Window 90-day expiration purge. It automatically destroys the original `/free/` counterpart using a subsequent `DELETE` command and updates the `scans.image_storage_urls` array transparently so iOS clients experience zero 404 dead links.

## Usage Limits (`UsageManager`)

A tightly coupled boundary enforcing the Paywall visually in frontend boundaries securely.

- Connects logically to `.canPerformScan(isProActive:)`.
- Grants 3 free daily validations intrinsically via `UserDefaults` keyed explicitly against `DeviceIdentityManager.shared.deviceId`.
- Resets limits predictably across calendar bounds, actively triggering `$isPaywallOpen` sheets on strict bounds.
