# Revenue and Identity Management

Merian implements an onboarding funnel by combining Supabase Anonymous Authentication with RevenueCat SDK bindings for entitlement checking.

## Contents

- [Anonymous IDFV Strategy (`DeviceIdentityManager`)](#the-anonymous-idfv-strategy-deviceidentitymanager) — Ghost session creation, OAuth upgrade, account merging, historical sync
- [Paywalls and Entitlements (`RevenueCatManager`)](#paywalls-and-entitlements-revenuecat manager) — `isProActive`, plan display
- [RevenueCat Webhook](#revenuecat-webhook-revenuecat-webhook) — Server-side tier sync, R2 data migration on upgrade/downgrade
- [Usage Limits (`UsageManager`)](#usage-limits-usagemanager) — Daily scan quota, refund logic, paywall gate
- [Trust & Safety (`SocialGuardManager`)](#trust--safety-socialguardmanager) — Block user, optimistic UI, Edge sync

## The Anonymous IDFV Strategy (`DeviceIdentityManager`)

To maximize user conversion, Merian requires zero upfront onboarding friction:

- Boots on app launch, silently pulling `UIDevice.current.identifierForVendor` (or `WKInterfaceDevice.current().identifierForVendor` compiled for watchOS) via the Apple Keychain.
- This creates persistent tracking tied exclusively to the `.uuidString` across the ecosystem lifecycle, without volatile session cookie dependencies.
- It acts as the unified Apple Keychain fallback, solving "split-brain" tracking between databases. `SupabaseManager` intercepts Anonymous sign-ins and links the Supabase Auth UUID into both RevenueCat and PostHog, abandoning the `DeviceIdentityManager.shared.deviceId` hardware ID to ensure identity stays synced with backend Webhooks.
- Exposes an `isGuestUser` property (mapped to `currentUser?.isAnonymous`) allowing features like `ProfileTabView` to selectively render Apple Authentication loops instead of surfacing "Sign Out" buttons on ghost sessions.
- **Identity Resolution & OAuth**: Merian uses standard Apple (`ASAuthorizationAppleIDProvider`) and Google (`GIDSignIn`) iOS libraries to authenticate without web-view redirects.
  - When a user taps "Sign in with Apple", iOS acquires the raw cryptographically signed `.idToken`. Because `ASAuthorizationController` holds a weak reference to its Apple Sign-In delegate, `SupabaseManager` must persist the controller in a strong `activeAppleAuth` class property until the delegate callback returns, to avoid premature memory deallocation crashes where the sign-in modal abruptly aborts.
  - When a user taps "Sign in with Google", iOS boots the ASWebAuthenticationSession. The application intercepts the callback scheme inside `<MerianApp>.onOpenURL` via `GIDSignIn.sharedInstance.handle(url)`, preventing Google deep-links from being consumed by Supabase Magic Link handlers.
  - Merian passes the resulting `idToken`s through Supabase's `linkIdentityWithIdToken(credentials:)` (if the user is currently an anonymous Ghost User) or `signInWithIdToken(credentials:)` (if returning). Using `linkIdentityWithIdToken` merges the OAuth provider to the *existing* anonymous UUID, ensuring the user's local offline queue and S3 uploads are not stranded during the account upgrade. If `linkIdentityWithIdToken` throws (e.g. account already exists), it falls back to a standard `signInWithIdToken`. To prevent data stranding on this fallback boundary, Merian caches the ephemeral Ghost UUID before executing the sign-in, then invokes a decoupled Edge RPC hook (`/merge-ghost-profile`) which transfers PostgreSQL `scans` ownership from the Ghost UUID to the newly verified `session.user.id`, removing the obsolete Ghost shell. To prevent account hijacking (IDOR), the backend verifies `ghostUser.user.is_anonymous === true` before merging, preventing authenticated accounts from being maliciously merged or wiped by other users.
  - Once the `session.user` is generated, `SupabaseManager` pipes the raw identity payload into `linkExternalTelemetry(user:)`. This extracts GoTrue metadata (`email`, `full_name`, `avatar_url`) and maps it into `Purchases.shared.attribution` when calling `RevenueCatManager.shared.linkWithSupabase(userId: email: displayName: avatarUrl:)`. It then calls `PostHogManager.shared.identifyUser(userId: newUserId)`. This sequence aliases the prior IDFV/Ghost tracking into the permanent Cloud Identity and populates RevenueCat dashboards with cross-referenced user details.
  - **Account Rehydration**: Intercepting the initial payload from `SupabaseManager.setupAuthStateListener`, Merian calls `ScanRepository.shared.syncHistoricalScansDown`, which fetches the user's scan history and loads it into local SwiftData structures.
  - When executing `signOut()`, `SupabaseManager` calls `Purchases.shared.logOut()` to drop the previous user's cached RevenueCat entitlements from the device, preventing premium account sharing.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls Apple ecosystem entitlement bounds governing core app functionality.
- Initializes via `.configure(withAPIKey:)`, pulling the active iOS `ProcessInfo` values mapped to `.xcconfig` secure layers.
- Uses `logIn(currentAppUserID)` to bind the IDFV tracking string.
- Evaluates `isProActive` via `.customerInfo()`, checking for active entitlements across `pro` and `7_day_pass` identifiers and updating SwiftUI state. The `PlanCard` observes this property in the Profile header, redrawing the subscription tier card to reflect the current state (e.g., Naturalist UNLIMITED SCANS vs Explorer 2 SCANS DAILY) and surfacing the `PaywallView` sheet.
- **Species Insights**: `SpeciesInsightsCard` is embedded in `BiologicalView`. Enrichment loads automatically 2–3 seconds after each biological scan via `InferenceEngine.fetchAndApplyEnrichment` — no user action required. A shimmer loading skeleton is displayed while `isEnrichmentLoading` is `true`. If data fails to load, a "Retry" button re-triggers `fetchAndApplyEnrichment`.

## RevenueCat Webhook (`revenuecat-webhook`)

To keep the Supabase PostgreSQL backend in sync with iOS RevenueCat entitlement state, a dedicated `revenuecat-webhook` Edge Function listens for global subscription events (`INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`, and `UNCANCELLATION`). This endpoint requires a `Bearer REVENUECAT_WEBHOOK_SECRET` `Authorization` header, mapped to Env Vars, and deflects unauthenticated requests with a 401 at the Kong Gateway via `verify_jwt = false`.

1. **Tier Syndication**: Updates the `users.subscription_tier` enum to `pro` on initialization/renewal, and downgrades it to `free` on expiration. `CANCELLATION` events are ignored — turning off Auto-Renew lets users keep Pro features until the genuine `EXPIRATION` timestamp lapses.
2. **Cloudflare Data Migration**: When a user upgrades to `pro`, the webhook queries the `scans` table using a `while` loop over paginated `.range(start, end)` subsets, traversing past Supabase's 1,000 max-row API limit set by `config.toml`. To prevent Ghost Profile R2 migration data loss, it evaluates image URIs based on the `public_uploads/free/` prefix rather than matching the new authenticated `userId`, ensuring historical offline scans are included. It uses the AWS S3 SDK to perform remote `PUT` copies, moving the image bytes into the permanent `public_uploads/pro/{userId}/` tier, protecting the user from the Rolling Cloud Window 90-day expiration purge. It then deletes the original `/free/` object and reconstructs the public Cloudflare URL (`https://media.merian.app/public_uploads/pro/...`), saving it to the `scans.image_storage_urls` array. This prevents S3 validation failures that would cause iOS `URLSession` to receive `HTTP 400 Bad Request` errors and result in dead links.

## Usage Limits (`UsageManager`)

Enforces the paywall in frontend entry points.

- `.canPerformScan(isProActive:)` returns `isProActive || freeScansRemaining > 0`. The paywall is surfaced from two pre-scan gates only: `Capture.swift` (camera shutter) and `handlePhotoPickerSelection` (photo library picker). Network failures in `InferenceEngine` never trigger the paywall — they surface a "Network Timeout" error state and refund the token.
- **Quota Enforcement Across Live and Background Paths**: `consumeScan()` is called in two locations to cover both inference paths — at capture time (live path) and at upload-scheduling time inside `syncPendingScans` (offline queue path). This prevents free users from bypassing the daily limit by capturing scans in the foreground and processing them through the background URLSession later.
- **Refunds**: If an inference fails unrecoverably (task cancellation, JSON decoding failure, network error), `UsageManager.shared.refundScan()` restores the consumed token so the user is not penalized for a technical failure.
- **Free User Queue Cap**: `maxFreeScansPerDay` (2) is an `internal` property accessible to `OfflineQueueManager`, which uses it to cap the offline queue depth for free users. This prevents scan hoarding across multiple days.
- Grants 2 free daily scans via `UserDefaults` keyed against `DeviceIdentityManager.shared.deviceId`.
- Resets limits at calendar boundaries. The `evaluateDailyRefresh()` check is called from `AppDIContainer.handleActivePhase()`, ensuring user quotas are reset when the app enters the foreground from an overnight suspension.

## Trust & Safety (`SocialGuardManager`)

Operates independently of Revenue boundaries but is fundamentally tied to Identity.

- Manages a persistent local SwiftUI `Set<String>` of blocked User UUIDs (`blockedUserIds`).
- Updates UI blocking state across Discovery feeds immediately while asynchronously flushing the UUID to the `/block-user` Edge node.
- Automatically reverts the block if the Edge API returns an error, restoring the previous state.
