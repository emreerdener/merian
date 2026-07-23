# Revenue and Identity Management

Naturebook implements an onboarding funnel by combining Supabase Anonymous
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
    not stranded during the account upgrade. Only an
    `identity_already_exists` error falls back to a standard
    `signInWithIdToken`; transient and configuration failures leave the Ghost
    session active. Before switching sessions, the live Ghost session
    requests a one-use `/merge-ghost-profile` handoff bound to the exact OAuth
    provider subject and persists its 256-bit secret in a versioned,
    foreground-accessible, device-only Keychain queue. The proof remains valid
    for 30 days. After sign-in, only the permanent account that owns that
    provider identity can consume it. PostgreSQL locks both users, resolves
    uniqueness conflicts, and re-parents all supported ownership in one
    transaction; only then does the Edge Function delete the obsolete anonymous
    Auth shell. The client retains transient failures for idempotent retries,
    and a five-minute service-role worker finishes Auth cleanup if the client
    never returns.
  - Once the `session.user` is generated, `SupabaseManager` pipes the raw
    identity payload into `linkExternalTelemetry(user:)`. This extracts GoTrue
    metadata (`email`, `full_name`, `avatar_url`), performs a best-effort read of
    the user's `public.users` row, and maps both sources into
    `Purchases.shared.attribution` when calling
    `RevenueCatManager.shared.linkWithSupabase(...)`. RevenueCat customers
    receive subscriber attributes such as `supabase_user_id`, `auth_email`,
    `public_username`, `public_author_name`, `public_identity_source`, and
    `account_kind` so test-dashboard customers can be matched back to Merian
    accounts even while the app uses the RevenueCat Test Store key. It then
    calls `PostHogManager.shared.identifyUser(userId: newUserId)`. This sequence
    aliases the prior IDFV/Ghost tracking into the permanent Cloud Identity and
    populates RevenueCat dashboards with cross-referenced user details.
  - **Account Rehydration**: Intercepting the initial payload from
    `SupabaseManager.setupAuthStateListener`, Merian calls
    `ScanRepository.shared.syncHistoricalScansDown`, which fetches the user's
    scan history and loads it into local SwiftData structures.
  - When executing `signOut()`, `SupabaseManager` signs out with Supabase
    `.local` scope so one device or simulator does not revoke every active
    session for the same account. It then calls `Purchases.shared.logOut()` to
    drop the previous user's cached RevenueCat entitlements from the current
    device, preventing premium account sharing.
  - The authenticated-session marker is centralized under
    `KeychainKeys.hasAuthenticatedOAuth`. Do not inline the legacy string key in
    auth or network code.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls Apple ecosystem entitlement bounds governing core app functionality.
- Initializes via `.configure(withAPIKey:)`, pulling the active iOS
  `ProcessInfo` values mapped to `.xcconfig` secure layers.
- Development and internal builds can continue using RevenueCat's `test_` Test
  Store key while purchase flows are being exercised. The store environment does
  not change Merian's identity contract: the RevenueCat App User ID is the
  Supabase Auth UUID, and subscriber attributes mirror the user's auth/public
  identity for manual support lookups. Production App Store export should still
  resolve to a RevenueCat iOS SDK key beginning with `appl_`.
- Uses `logIn(currentAppUserID)` to bind the Supabase Auth UUID.
- `RevenueCatOfferingPolicy` requires the current offering to contain App Store
  product identifiers `pro_week` and `pro_annual`. Offering fetches emit an
  operational error when there is no current offering, the current offering has
  no packages, or either mapping is missing. The client cannot create products
  or select a dashboard offering: App Store Connect product readiness, RevenueCat
  package mapping, and current-offering selection must be completed externally
  before release.
- Evaluates `isSubscribed` and `trialDaysRemaining` via `.customerInfo()`.
  - `isSubscribed` checks for active entitlements across the standard Pro
    subscription identifiers and a locally evaluated `pro_week`
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
  - **Backend Model Upgrades**: The client display state is not provider
    authorization. Every paid-model Edge path atomically calls
    `reserve_ai_quota`, which reads Postgres tier/creation/expiry/version,
    derives `effective_tier` and `plan`, selects the database policy model, and
    consumes quota before dispatch. Paid users have
    `users.subscription_tier = "pro"` and resolve to `pro_paid`; active
    non-renewing passes also require a future `subscription_expires_at`; raw
    free users inside the database's seven-day creation window resolve to
    `pro_trial`. A stale timed pass resolves free, and a missing user row or
    database error fails closed rather than granting a ghost trial.
    RevenueCat/webhook changes advance `users.entitlement_version` in a trigger,
    so no Edge-isolate cache invalidation is required.

### Prelaunch purchase testing

Choose one store source deliberately; do not mix Test Store products, App Store
products, and StoreKit configuration products in one diagnosis.

| Test path | SDK key | Product source | Required verification |
|---|---|---|---|
| Fast Debug/simulator purchase testing | RevenueCat `test_` key | RevenueCat Test Store products | The dashboard current offering contains Test Store products whose identifiers are exactly `pro_week` and `pro_annual`; purchases and customer identity are visible in the Test Store project. |
| Local StoreKit configuration | RevenueCat iOS `appl_` key | A `.storekit` file attached to the Xcode Run action | The file contains the same identifiers and its certificate/configuration follows RevenueCat's StoreKit testing setup. |
| Apple sandbox, physical device, or TestFlight | RevenueCat iOS `appl_` key | App Store Connect products imported and mapped in RevenueCat | Bundle ID, agreements, product readiness, package mapping, current offering, purchase, restore, and webhook behavior all pass. |

The shared `Merian` scheme does not currently attach a `.storekit` file. A
Debug simulator using the production `appl_` key therefore depends on StoreKit
being able to resolve the App Store Connect products. If the SDK reports that
none of the dashboard products could be fetched, fix the selected store setup
before changing client retry logic. Repeated errors can reflect more than one
SDK/UI request for the same unavailable offering; the first success criterion
is one valid offering, not fewer error lines.

RevenueCat identity and product loading are separate checks. A log such as
`RevenueCat login succeeded` proves that the Supabase UUID was linked; it does
not prove StoreKit returned products. A complete smoke test must:

1. Launch with the intended key/store combination.
2. Confirm the SDK product-fetch error is absent.
3. Open Settings → Plan manually and confirm both required packages render.
4. Complete and restore a purchase in the selected test environment.
5. For Apple sandbox/TestFlight, confirm the webhook updates the matching
   Supabase user and expiration semantics.

The release build keeps the advisory local scan meter enabled. A DEBUG-only
meter bypass can still prevent quota-triggered paywall presentation, but it
does not bypass the Supabase reservation; purchase QA should therefore open the
Plan surface directly. See
[RevenueCat offering troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings),
[Apple sandbox testing](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
and the
[iOS release runbook](../development-guides/14-ios-release-versioning.md).

## RevenueCat Webhook (`revenuecat-webhook`)

To keep the Supabase PostgreSQL backend in sync with iOS RevenueCat purchase
state, a dedicated `revenuecat-webhook` Edge Function listens for global
subscription events (`INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`, and
`UNCANCELLATION`) plus the exact non-renewing `pro_week` product. This
endpoint requires a `Bearer REVENUECAT_WEBHOOK_SECRET` `Authorization` header,
mapped to Env Vars. `verify_jwt = false` lets the non-Supabase webhook
credential reach Deno; the handler performs the secret comparison and returns
401 for an invalid caller.

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

Provides an advisory local paywall/capture meter. It is not the entitlement or
provider-cost enforcement boundary.

- `.canPerformScan(isProActive:)` returns
  `isProActive || freeScansRemaining > 0`. The paywall is surfaced from two
  pre-scan gates only: `Capture.swift` (camera shutter) and
  `handlePhotoPickerSelection` (photo library picker). Network failures in
  `InferenceEngine` never trigger the paywall — they surface a "Network timeout"
  error state while the already-queued scan retries in the background.
- `handlePhotoPickerSelection` snapshots the current quota once per picker batch
  before any background downsampling begins. If the batch is over quota, it
  clears the picker selection immediately, tracks the paywall impression, and
  exits before loading gallery bytes into memory.
- `FeatureFlag.unlimitedFreeScans.defaultValue` is `false`. DEBUG builds may
  bypass the local meter from Settings or `MERIAN_DISABLE_FREE_SCAN_LIMIT=1`;
  Release/TestFlight ignores persisted debug overrides. This never changes the
  database entitlement, model, or server quota.
- **Advisory reservation at capture time**: `consumeScan()` is called once, at
  enqueue time, inside `OfflineQueueManager.insertAndPersistRecord`. The quota
  check (`canPerformScan`) and token consumption happen before the
  `OfflineQueuedScan` record is inserted into SwiftData. `syncPendingScans` has
  no local-meter involvement — every accepted queue row uploads
  unconditionally. The Edge request still reserves authoritative server quota
  immediately before model work. Successful non-biological results count as scan
  attempts. The Non-biological collection's correction reanalysis flow bypasses
  only the Pro reanalysis feature gate for that specific correction path; when
  the user submits the replacement scan it still follows normal free-tier
  inference settings and daily scan limits.
- **Server authority**: `reserve_ai_quota` applies the free one-scan UTC-day
  policy and high Pro trial/paid fair-use ceilings, plus shared per-user/IP
  minute limits. Clearing/modifying `UserDefaults` does not change them. A
  database entitlement failure returns `503`; it never falls back to Pro.
- **Product language**: Pro removes the ordinary one-scan product cap but
  remains subject to documented anti-abuse/cost safety ceilings. Do not promise
  technically unbounded provider use.
- **Local refunds**: If an inference fails unrecoverably (task cancellation, JSON
  decoding failure, network error), `UsageManager.shared.refundScan()` restores
  the advisory token. This does not refund a provider attempt. Server refund is
  an explicit reservation transition used only when no provider call occurred.
- Grants 1 free daily scan via `UserDefaults` keyed against
  `DeviceIdentityManager.shared.deviceId`.
- Resets the advisory meter at device calendar boundaries. The authoritative
  free scan bucket resets at the UTC database boundary. The
  `evaluateDailyRefresh()` check is
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
