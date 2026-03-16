# Revenue and Identity Management

Merian implements a seamless onboarding funnel by marrying Supabase Anonymous Authentication deeply with RevenueCat SDK bindings for entitlement checking natively.

## The Anonymous IDFV Strategy (`DeviceIdentityManager`)

To maximize user conversion, Merian demands zero upfront onboarding friction:

- Boots physically on app launch, silently pulling `UIDevice.current.identifierForVendor` (or `WKInterfaceDevice.current().identifierForVendor` natively compiled for watchOS) via the Apple Keychain natively.
- This creates persistent tracking tied exclusively to the `.uuidString` securely across the ecosystem lifecycle without volatile session cookie dependencies.
- It strictly acts as the unified Apple Keychain fallback permanently solving "split-brain" tracking between databases. `SupabaseManager` intercepts Anonymous sign-ins and explicitly links the physical Supabase Auth UUID natively into both RevenueCat and PostHog, abandoning the `DeviceIdentityManager.shared.deviceId` hardware ID to ensure identity remains correctly synced with backend Webhooks.
- Natively exposes an `isGuestUser` property (mapped to `currentUser?.isAnonymous`) allowing features like the `SettingsView` to selectively render Authentication buttons instead of prematurely forcing "Sign Out" loops on ghost bounds.
- **Identity Resolution & Native OAuth**: Merian actively leverages standard Apple (`ASAuthorizationAppleIDProvider`) and Google (`GIDSignIn`) native iOS libraries to authenticate securely without clunky web-view boundaries.
  - When a user taps "Sign in with Apple", iOS natively acquires the raw cryptographically signed `.idToken`. Note: Because `ASAuthorizationController` holds a weak reference to its Apple Sign-In delegate natively, `SupabaseManager` must persist the controller in a strong `activeAppleAuth` class property until the delegate callback returns to explicitly avoid premature memory deallocation crashes (where the sign-in modal abruptly aborts).
  - When a user taps "Sign in with Google", iOS boots the ASWebAuthenticationSession. The application universally intercepts the callback schema securely inside `<MerianApp>.onOpenURL` via `GIDSignIn.sharedInstance.handle(url)`, protecting Google deep-links from being blindly swallowed by Supabase Magic Link handlers.
  - Merian passes the resulting `idToken`s natively through Supabase's `linkIdentityWithIdToken(credentials:)` (if the user is currently an anonymous Ghost User) or `signInWithIdToken(credentials:)` (if returning). This is a critical security step: utilizing `linkIdentityWithIdToken` perfectly merges the OAuth provider to the *existing* anonymous UUID, guaranteeing that the user's local offline queue and S3 uploads are not stranded during the account upgrade process. If `linkIdentityWithIdToken` throws (e.g. account already exists), it gracefully falls back to a standard `signInWithIdToken`. To prevent data stranding on exactly this fallback boundary, Merian explicitly caches the ephemeral Ghost UUID prior to executing the sign-in; successfully invoking a newly decoupled Edge RPC hook (`/merge-ghost-profile`) which securely transfers PostgreSQL `scans` ownership directly from the Ghost UUID into the newly verified `session.user.id`, permanently eradicating the obsolete Ghost shell natively.
  - Once the `session.user.id.uuidString` generates, `SupabaseManager` intercepts it and explicitly calls `RevenueCatManager.shared.linkWithSupabase(userId: newUserId)` and `PostHogManager.shared.identifyUser(userId: newUserId)`. This sequence securely aliases their prior native IDFV/Ghost physical tracking payload logic cleanly into their fresh permanent Cloud Identity.
  - **Account Rehydration**: Intercepting the pure initial payload from `SupabaseManager.setupAuthStateListener`, Merian specifically binds the `ScanRepository.shared.syncHistoricalScansDown` matrix executing a swift asynchronous HTTP hook returning the fully decoded history of their life list dropping securely into the local `SwiftData` structures.
  - Finally, when executing a clean `signOut()`, `SupabaseManager` explicitly triggers `Purchases.shared.logOut()` to drop the previous user's cached RevenueCat entitlements from the device entirely preventing premium account sharing exploits.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls strict Apple ecosystem bounds dictating core app functionalities intuitively.
- Initializes `.configure(withAPIKey:)` silently pulling the active iOS `ProcessInfo` values physically mapping to `.xcconfig` secure layers.
- Uses `logIn(currentAppUserID)` binding the IDFV tracking string natively.
- Evaluates `isProActive` booleans via `.customerInfo()` natively checking for active entitlements across `pro` and `7_day_pass` identifiers seamlessly updating SwiftUI.

## RevenueCat Webhook (`revenuecat-webhook`)

To ensure the Supabase PostgreSQL backend perfectly mirrors the iOS RevenueCat entitlement state, a dedicated `revenuecat-webhook` Edge Function passively listens for global subscription events (`INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`, and `UNCANCELLATION`). This endpoint strictly guards against malicious payloads by universally demanding an explicit `Bearer 
REVENUECAT_WEBHOOK_SECRET` `Authorization` header validation natively mapping to Env Vars, automatically deflecting anonymous 401s directly at the Kong Gateway via `verify_jwt = false`.

1. **Tier Syndication**: Automatically updates the `users.subscription_tier` enum to `pro` upon initialization/renewal, and securely downgrades it back to `free` on expiration. Notably, `CANCELLATION` events are completely ignored—merely turning off Auto-Renew securely lets users keep Pro features until the genuine `EXPIRATION` physical timestamp natively lapses natively.
2. **Cloudflare Data Migration**: When an arbitrary user upgrades to `pro`, the webhook queries the `scans` table utilizing a strict `while` loop bound across paginated `.range(start, end)` subsets, fully traversing beyond Supabase's strict 1,000 max row API limitation set by `config.toml` to prevent legacy data abandonment. It leverages the AWS S3 SDK to perform remote mathematical `PUT` copies, dynamically elevating the physics binary bytes natively into the permanent `public_uploads/pro/{userId}/` tier, completely protecting the payer from the Rolling Cloud Window 90-day expiration purge. It safely parses the S3 URL (stripping out any trailing AWS presigned query parameters, e.g., `?X-Amz-Signature=...`) before extracting the filename to ensure the internal R2 `targetKey` is structurally valid. It automatically destroys the original `/free/` counterpart using a subsequent `DELETE` command and updates the `scans.image_storage_urls` array transparently so iOS clients experience zero 404 dead links.

## Usage Limits (`UsageManager`)

A tightly coupled boundary enforcing the Paywall visually in frontend boundaries securely.

- Connects logically to `.canPerformScan(isProActive:)`, successfully enforcing the exact mathematical bound `return isProActive || freeScansRemaining > 0` natively, ensuring the hard paywall drops when expected limits are hit.
- **Proactive Offline Consumption & Refunds**: Free quota tokens are now strictly deducted natively via `consumeScan()` the exact millisecond the user commits to analyzing an image inside `CameraViewModel`, *prior* to Edge inference routing, preventing "Airplane Mode Hoarding". However, to ensure fairness natively, if an inference drops into an unrecoverable failure state (e.g., explicit task cancellation, or complete JSON schema breakdown from AI response), `UsageManager.shared.refundScan()` instantly intercepts the state to refund the token securely so the user is not unfairly penalized for a technical hiccup.
- Grants 3 free daily validations intrinsically via `UserDefaults` keyed explicitly against `DeviceIdentityManager.shared.deviceId`.
- Resets limits predictably across calendar bounds, actively triggering `$isPaywallOpen` sheets on strict bounds. The `evaluateDailyRefresh()` check is aggressively bridged into `AppDIContainer.handleActivePhase()` ensuring user quotas are dynamically zeroed the exact moment the app enters the foreground from an overnight suspension.

## Trust & Safety (`SocialGuardManager`)

Operates entirely decoupled from Revenue boundaries but maps fundamentally to Identity.

- Securely manages a persistent local SwiftUI `Set<String>` of blocked User UUIDs (`blockedUserIds`).
- Optimistically updates UI blocking state across Discovery feeds instantly while asynchronously flushing the UUID to the `/block-user` Edge node. 
- Automatically drops the block natively if the Edge API returns an error, self-healing the state matrix.
