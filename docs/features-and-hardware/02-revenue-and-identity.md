# Revenue and Identity Management

Merian implements an onboarding funnel by combining Supabase Anonymous
Authentication with RevenueCat SDK bindings for entitlement checking.

## Contents

- [Anonymous IDFV Strategy (`DeviceIdentityManager`)](#the-anonymous-idfv-strategy-deviceidentitymanager)
  — Ghost session creation, OAuth upgrade, account merging, historical sync
- [Paywalls and Entitlements
  (`RevenueCatManager`)](#paywalls-and-entitlements-revenuecat manager) —
  `isProActive`, plan display
- [RevenueCat Webhook](#revenuecat-webhook-revenuecat-webhook) — Server-side
  tier sync, R2 data migration on upgrade/downgrade
- [Usage Limits (`UsageManager`)](#usage-limits-usagemanager) — Daily scan
  quota, refund logic, paywall gate
- [Trust & Safety (`SocialGuardManager`)](#trust--safety-socialguardmanager) —
  Block user, optimistic UI, Edge sync

## The Anonymous IDFV Strategy (`DeviceIdentityManager`)

To maximize user conversion, Merian requires zero upfront onboarding friction:

- Boots on app launch, silently pulling `UIDevice.current.identifierForVendor`
  (or `WKInterfaceDevice.current().identifierForVendor` compiled for watchOS)
  via the Apple Keychain.
- This creates persistent tracking tied exclusively to the `.uuidString` across
  the ecosystem lifecycle, without volatile session cookie dependencies.
- It acts as the unified Apple Keychain fallback, solving "split-brain" tracking
  between databases. `SupabaseManager` intercepts Anonymous sign-ins and links
  the Supabase Auth UUID into both RevenueCat and PostHog, abandoning the
  `DeviceIdentityManager.shared.deviceId` hardware ID to ensure identity stays
  synced with backend Webhooks.
- Anonymous session bootstrap is single-flight. `SupabaseManager` stores a
  `ghostSessionTask` handle so concurrent callers to `initializeGhostSession()`
  / `getValidAuthHeaders()` all await the same in-flight anonymous sign-in
  instead of racing multiple `signInAnonymously()` requests against the same
  empty state.
- Exposes an `isGuestUser` property (mapped to `currentUser?.isAnonymous`)
  allowing features like `ProfileTabView` to selectively render Apple
  Authentication loops instead of surfacing "Sign Out" buttons on ghost
  sessions.
- **Identity Resolution & OAuth**: Merian uses standard Apple
  (`ASAuthorizationAppleIDProvider`) and Google (`GIDSignIn`) iOS libraries to
  authenticate without web-view redirects.
  - When a user taps "Sign in with Apple", iOS acquires the raw
    cryptographically signed `.idToken`. Because `ASAuthorizationController`
    holds a weak reference to its Apple Sign-In delegate, `SupabaseManager` must
    persist the controller in a strong `activeAppleAuth` class property until
    the delegate callback returns, to avoid premature memory deallocation
    crashes where the sign-in modal abruptly aborts.
  - Apple Sign-In bootstrap failures are now recoverable. If the app cannot
    generate a nonce, cannot find a presentation anchor yet, or receives a
    callback after the nonce was cleared, `SupabaseManager` logs the failure and
    cancels the auth attempt instead of crashing the app.
  - When a user taps "Sign in with Google", iOS boots the
    ASWebAuthenticationSession. The application intercepts the callback scheme
    inside `<MerianApp>.onOpenURL` via `GIDSignIn.sharedInstance.handle(url)`,
    preventing Google deep-links from being consumed by Supabase Magic Link
    handlers.
  - Merian passes the resulting `idToken`s through Supabase's
    `linkIdentityWithIdToken(credentials:)` (if the user is currently an
    anonymous Ghost User) or `signInWithIdToken(credentials:)` (if returning).
    Using `linkIdentityWithIdToken` merges the OAuth provider to the _existing_
    anonymous UUID, ensuring the user's local offline queue and S3 uploads are
    not stranded during the account upgrade. If `linkIdentityWithIdToken` throws
    (e.g. account already exists), it falls back to a standard
    `signInWithIdToken`. To prevent data stranding on this fallback boundary,
    Merian caches the ephemeral Ghost UUID before executing the sign-in, then
    invokes a decoupled Edge RPC hook (`/merge-ghost-profile`) which transfers
    PostgreSQL `scans`, `collections`, Explore posts, Ask the Community request
    ownership, and follow relationships from the Ghost UUID to the newly
    verified `session.user.id`, removing the obsolete Ghost shell. To prevent
    account hijacking (IDOR), the backend verifies
    `ghostUser.user.is_anonymous === true` before merging, preventing
    authenticated accounts from being maliciously merged or wiped by other
    users.
  - Once the `session.user` is generated, `SupabaseManager` pipes the raw
    identity payload into `linkExternalTelemetry(user:)`. This extracts GoTrue
    metadata (`email`, `full_name`, `avatar_url`) and maps it into
    `Purchases.shared.attribution` when calling
    `RevenueCatManager.shared.linkWithSupabase(userId: email: displayName: avatarUrl:)`.
    It then calls `PostHogManager.shared.identifyUser(userId: newUserId)`. This
    sequence aliases the prior IDFV/Ghost tracking into the permanent Cloud
    Identity and populates RevenueCat dashboards with cross-referenced user
    details.
  - **Account Rehydration**: Intercepting the initial payload from
    `SupabaseManager.setupAuthStateListener`, Merian calls
    `ScanRepository.shared.syncHistoricalScansDown`, which fetches the user's
    scan history and loads it into local SwiftData structures.
  - When executing `signOut()`, `SupabaseManager` calls
    `Purchases.shared.logOut()` to drop the previous user's cached RevenueCat
    entitlements from the device, preventing premium account sharing.
  - The authenticated-session marker is centralized under
    `KeychainKeys.hasAuthenticatedOAuth`. Do not inline the legacy string key in
    auth or network code.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls Apple ecosystem entitlement bounds governing core app functionality.
- Initializes via `.configure(withAPIKey:)`, pulling the active iOS
  `ProcessInfo` values mapped to `.xcconfig` secure layers.
- Uses `logIn(currentAppUserID)` to bind the IDFV tracking string.
- Evaluates `isSubscribed` and `trialDaysRemaining` via `.customerInfo()`.
  - `isSubscribed` checks for active entitlements across the standard Pro
    subscription identifiers and a locally evaluated `merian_7_day_pass`
    non-subscription transaction. The 7-day pass is intentionally not a
    RevenueCat entitlement.
  - `trialDaysRemaining` computes the days since the user's `firstSeen` date in
    RevenueCat (representing app installation) and grants a dynamic 7-day trial
    of the Pro feature set for all new users.
  - `isProActive` evaluates to `true` if either the user is subscribed or their
    trial is active, triggering Pro client behavior such as 1024 px inference
    image preparation and the Pro tier badge. The `ModelTierBadge` explicitly
    highlights the trial status (e.g., "7 days of pro remaining") for new users.
    The `PlanCard` observes `isProActive` in the Profile header, redrawing the
    subscription tier card to reflect the current state and surfacing the
    `PaywallView` sheet.
  - **Backend Model Upgrades**: Edge Functions coordinate with this logic via
    `resolveTierForUser` in `_shared/tierCache.ts`. The resolver returns a raw
    `subscription_tier` from Postgres plus derived telemetry fields:
    `effective_tier` (`"pro"` or `"free"`), `plan` (`"pro_paid"`, `"pro_trial"`,
    or `"free"`), and `trial_active`. Paid users have
    `users.subscription_tier = "pro"` from RevenueCat webhook events and resolve
    to `plan = "pro_paid"`. Non-renewing 7-day pass users also carry
    `users.subscription_expires_at`; the backend expiry worker downgrades them
    after that timestamp, while the resolver treats any stale timed Pro row as
    free as a fallback. Trial users usually still have
    `users.subscription_tier = "free"`; if `created_at` is within the 7-day
    window, they resolve to `effective_tier = "pro"` and `plan = "pro_trial"`.
    Ghost users without a row are treated as trial Pro for their first scan and
    then upserted as raw `subscription_tier = "free"` so paid entitlement
    and paid-pass storage remains webhook-owned.

## RevenueCat Webhook (`revenuecat-webhook`)

To keep the Supabase PostgreSQL backend in sync with iOS RevenueCat purchase
state, a dedicated `revenuecat-webhook` Edge Function listens for global
subscription events (`INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`, and
`UNCANCELLATION`) plus the exact non-renewing `merian_7_day_pass` product. This
endpoint requires a `Bearer REVENUECAT_WEBHOOK_SECRET` `Authorization` header,
mapped to Env Vars, and deflects unauthenticated requests with a 401 at the
Kong Gateway via `verify_jwt = false`.

1. **`app_user_id` UUID validation**: After HMAC authentication,
   `event.app_user_id` is validated against a strict UUID regex before any DB
   access. A simple falsy check is insufficient — RevenueCat sends anonymous IDs
   (`$RCAnonymousID:xxx`) for un-linked purchases, which would pass a falsy
   check but fail UUID constraints in the DB layer. Anonymous-ID events are
   rejected with `HTTP 400` and a warning log.
2. **Tier Syndication**: Updates the `users.subscription_tier` enum to `pro` on
   initialization/renewal, and downgrades it to `free` on expiration. Standard
   subscriptions clear `subscription_expires_at`; the detached 7-day pass sets
   it to `purchased_at_ms + 7 days`. `CANCELLATION` events are ignored for
   standard auto-renewing subscriptions — turning off Auto-Renew lets users keep
   Pro features until the genuine `EXPIRATION` timestamp lapses. For the
   7-day pass, refund/cancellation-style events downgrade immediately.
3. **Timed Pass Expiry**: `expire-subscription-passes` runs hourly via
   `pg_cron`, finds timed Pro rows whose `subscription_expires_at` has passed,
   downgrades them to `free`, clears the expiry timestamp, and migrates storage
   back to the free bucket path. The webhook does not mark the dynamic 7-day app
   trial as paid Pro; trial access is derived at inference time from RevenueCat
   first-seen/client state and `users.created_at`.
4. **Cloudflare Data Migration**: When a user upgrades to `pro`, the webhook
   queries the `scans` table using a `while` loop over paginated
   `.range(start, end)` subsets, traversing past Supabase's 1,000 max-row API
   limit set by `config.toml`. To prevent Ghost Profile R2 migration data loss,
   it evaluates image URIs based on the `public_uploads/free/` prefix rather
   than matching the new authenticated `userId`, ensuring historical offline
  scans are included. Existing scan media remains under its original
  `public_uploads/free/` or `public_uploads/pro/` prefix when the tier changes;
  both prefixes are durable scan-media storage. This prevents S3
   validation failures that would cause iOS `URLSession` to receive
   `HTTP 400 Bad Request` errors and result in dead links.

## Usage Limits (`UsageManager`)

Enforces the paywall in frontend entry points.

- `.canPerformScan(isProActive:)` returns
  `isProActive || freeScansRemaining > 0`. The paywall is surfaced from two
  pre-scan gates only: `Capture.swift` (camera shutter) and
  `handlePhotoPickerSelection` (photo library picker). Network failures in
  `InferenceEngine` never trigger the paywall — they surface a "Network Timeout"
  error state and refund the token.
- `handlePhotoPickerSelection` snapshots the current quota once per picker batch
  before any background downsampling begins. If the batch is over quota, it
  clears the picker selection immediately, tracks the paywall impression, and
  exits before loading gallery bytes into memory.
- The current alpha/testing override is intentional:
  `MerianConfig.alphaUnlimitedFreeScansEnabled = true` bypasses the free daily
  scan limit while testing continues. Do not remove or flip this flag as part of
  telemetry or plan-tag work. When this override is later removed, Pro users
  should still bypass the cap via `isProActive`, and free users should return to
  the daily quota.
- **Quota Enforcement at Capture Time**: `consumeScan()` is called once, at
  enqueue time, inside `OfflineQueueManager.insertAndPersistRecord`. The quota
  check (`canPerformScan`) and token consumption happen before the
  `OfflineQueuedScan` record is inserted into SwiftData. `syncPendingScans` has
  no quota involvement — every scan that enters the queue is already paid for
  and uploads unconditionally. This eliminates the historical silent stall where
  `freeScansRemaining = 0` caused `syncPendingScans` to discard queued scans via
  a zero batchLimit. Successful non-biological results still count as scan
  attempts. The Non-biological collection's correction reanalysis flow bypasses
  only the Pro reanalysis feature gate for that specific correction path; when
  the user submits the replacement scan it still follows normal free-tier
  inference settings and daily scan limits.
- **Refunds**: If an inference fails unrecoverably (task cancellation, JSON
  decoding failure, network error), `UsageManager.shared.refundScan()` restores
  the consumed token so the user is not penalized for a technical failure.
- Grants 1 free daily scan via `UserDefaults` keyed against
  `DeviceIdentityManager.shared.deviceId`.
- Resets limits at calendar boundaries. The `evaluateDailyRefresh()` check is
  called from `AppDIContainer.handleActivePhase()`, ensuring user quotas are
  reset when the app enters the foreground from an overnight suspension.

## Trust & Safety (`SocialGuardManager`)

Operates independently of Revenue boundaries but is fundamentally tied to
Identity.

- Manages a persistent local SwiftUI `Set<String>` of blocked User UUIDs
  (`blockedUserIds`).
- Updates UI blocking state across Discovery feeds immediately while
  asynchronously flushing the UUID to the `/block-user` Edge node.
- Automatically reverts the block if the Edge API returns an error, restoring
  the previous state.
