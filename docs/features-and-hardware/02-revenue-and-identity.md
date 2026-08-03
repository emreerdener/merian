# Revenue and Identity Management

Naturebook implements an onboarding funnel by combining Supabase Anonymous
Authentication with RevenueCat SDK bindings for entitlement checking.

## Contents

- [Anonymous IDFV Strategy (`DeviceIdentityManager`)](#the-anonymous-idfv-strategy-deviceidentitymanager)
  — Ghost session creation, OAuth upgrade, account merging, historical sync
- [Paywalls and Entitlements
  (`RevenueCatManager`)](#paywalls-and-entitlements-revenuecatmanager) — paid,
  functional, and new-scan capacity; current-launch `EntitlementManager`
- [RevenueCat Webhook](#revenuecat-webhook-revenuecat-webhook) — Server-side
  paid-tier and timed-pass synchronization
- [Usage Limits (`UsageManager`)](#usage-limits-usagemanager) — Daily Flash
  meter, authoritative plan reconciliation, paywall gate
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
    uniqueness conflicts, and transfers ownership in one transaction; only then
    does the Edge Function delete the obsolete anonymous Auth shell. The pending
    schema-aware contract must execute only source-controlled ownership policies
    within that transaction. The client retains transient failures for
    idempotent retries, and a five-minute service-role worker finishes Auth
    cleanup if the client never returns.
  - For this conflict fallback, client-side `Purchases.logIn` and provider
    webhooks are acceleration paths, not recovery authority. Merge completion
    must independently upsert an immediately due RevenueCat reconciliation row
    for the permanent UUID even when the anonymous source had no queue row.
    RevenueCat reconciliation and merge both lock the public user before the
    queue row, and reconciliation revalidates its lease under lock before
    applying entitlement state.
  - The schema-aware conflict fallback remains release-gated until that durable
    queue behavior, RevenueCat and Community lock ordering, both scan-ledger
    error mappings, exact-version catalog replay, and staging concurrency probes
    satisfy the
    [Ghost merge rollout matrix](../backend-and-data/06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).
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
- Local Debug and unsigned validation builds may use RevenueCat's `test_` Test
  Store key while purchase flows are being exercised. This does not include an
  internal TestFlight build. The store environment does not change Merian's
  identity contract: the RevenueCat App User ID is the Supabase Auth UUID, and
  subscriber attributes mirror the user's auth/public identity for manual
  support lookups. The Xcode Release archive preflight requires a RevenueCat
  iOS SDK key beginning with `appl_` before Organizer distribution.
- Uses `logIn(currentAppUserID)` to bind the Supabase Auth UUID.
- `RevenueCatOfferingPolicy` requires the current offering to contain App Store
  product identifiers `pro_week` and `pro_annual`. Offering fetches emit an
  operational error when there is no current offering, the current offering has
  no packages, or either mapping is missing. The client cannot create products
  or select a dashboard offering: App Store Connect product readiness, RevenueCat
  package mapping, and current-offering selection must be completed externally
  before release.
- Evaluates paid `isSubscribed` state via `.customerInfo()` and combines it
  with the current session's server-verified complimentary entitlement.
  - `isSubscribed` checks for active entitlements across the standard Pro
    subscription identifiers and a locally evaluated `pro_week`
    non-subscription transaction. The 7-day pass is intentionally not a
    RevenueCat entitlement.
  - `EntitlementManager` calls authenticated `get_my_entitlement()` on every
    launch/session and accepts complimentary access only after online
    verification for the active Supabase user. It applies snapshots and scan
    metadata monotonically by `entitlement_version`, including an account-owner
    check, so late responses cannot restore another account's stale balance.
    Scan-response metadata is buffered until that launch baseline succeeds:
    an idempotently replayed stored envelope can contain a historical snapshot
    and cannot establish current-launch proof on its own.
  - Every account receives three lifetime complimentary Pro scans with no
    calendar expiry. A credit or active hold enables the complimentary fair-use
    Pro actions. `isProActive` is paid RevenueCat access or an exactly verified
    complimentary tier; public Profile and Explore badges continue to use
    paid `isSubscribed` state only.
    `canStartProScan` is a presentation hint for new Pro-funded analyses. Actual
    admission synchronously claims an account/scan-keyed funding reservation and
    subtracts unresolved local complimentary and legacy blockers from
    `scans_available_to_start`; an active hold alone cannot fund scan four, and
    one stale remaining credit cannot admit multiple offline Pro scans.
  - Complimentary balances appear in Results and Settings, not Capture. After
    the third durable result the stored result remains fully viewable and the
    UI shows exhaustion plus an upgrade action. Ordinary compatible captures
    use the separate daily Flash policy when credits are exhausted.
  - Visible product copy calls the allowance **Pro scans**, not
    “complimentary” scans. Remaining counters use “3 Pro scans remain” and “1
    Pro scan remains”; `pro_complimentary` remains an internal server plan.
  - **Backend Model Upgrades**: The client display state is not provider
    authorization. Every paid-model Edge path atomically calls
    protocol-3 `reserve_ai_quota`, which locks the user, resolves paid Pro →
    complimentary Pro → free, acquires a lifetime-ledger hold when required,
    selects the database policy model, and consumes provider quota before
    dispatch. Paid users have
    `users.subscription_tier = "pro"` and resolve to `pro_paid`; active
    non-renewing passes also require a future `subscription_expires_at`;
    verified complimentary scans resolve to `pro_complimentary`. A stale timed
    pass resolves free, and a missing user row, malformed entitlement row, or
    database error fails closed. `pro_trial` remains a historical reporting
    value only after cutover.
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
state, the `revenuecat-webhook` Edge Function treats each global subscription
or `pro_week` event as a synchronization signal. It never trusts the event type
alone to decide access.

1. **Dual ingress authentication**: `verify_jwt = false` permits RevenueCat,
   which has no Supabase JWT, to reach the handler. The handler requires the
   configured `Authorization: Bearer REVENUECAT_WEBHOOK_SECRET` and verifies
   `X-RevenueCat-Webhook-Signature` with HMAC-SHA256 over the exact
   `<timestamp>.<raw JSON body>` using
   `REVENUECAT_WEBHOOK_SIGNING_SECRET`. Signatures outside the five-minute
   past/future window fail before JSON parsing.
2. **Durable identity**: `event.id` and `event_timestamp_ms` are required.
   Supabase UUID candidates are resolved in RevenueCat's current,
   original, then alias order. `TRANSFER` has no `app_user_id`, so its
   `transferred_from` and `transferred_to` identity groups become separate
   source and destination subjects. A purely anonymous event is durably marked
   `ignored` without mutating a user; a later alias event carries a different
   durable event ID. Billing never creates a missing `public.users` row or picks
   arbitrarily when one RevenueCat identity group maps to multiple live rows. A
   transfer source that was already deleted is omitted so it cannot block the
   live destination; missing normal/destination rows remain retryable.
3. **Authoritative reconciliation**: After signature verification, the server
   first checks its private durable receipt. A committed duplicate returns
   immediately so provider retries cannot amplify API traffic. Every new event
   calls RevenueCat `GET /v1/subscribers/{app_user_id}` for each mapped customer with
   `REVENUECAT_SECRET_API_KEY`. Active `pro` or `Naturalist Tier` entitlement
   state controls standard Pro and carries the later of recurring expiration
   and grace-period expiration. The detached `pro_week` purchase is derived from
   authoritative non-subscription transactions with a seven-day expiry;
   matching refunds/revocations are excluded. An API error or malformed
   response returns a retryable failure and leaves the database unchanged. Both
   transfer lookups finish before either side can be written.
4. **Transactional ordering**:
   `public.apply_revenuecat_customer_state(...)` stores each event ID once,
   locks every resolved user in sorted UUID order, and advances each subject
   only when the authoritative CustomerInfo `request_date_ms` is newer than that
   user's durable watermark. Provider event timestamp and event ID break only
   exact snapshot ties. Duplicate and stale deliveries are audited but cannot
   overwrite access. A newer refund therefore cannot be undone by a delayed
   purchase, and a newer renewal cannot be overwritten by a delayed expiration.
   Transfer source/destination changes share one event transaction and cannot
   partially commit.
5. **Tier and expiry projection**: Active standard entitlement state writes
   `subscription_tier = pro` with the later recurring/grace expiration.
   `NULL` is reserved for an explicitly non-expiring lifetime entitlement. An
   active `pro_week` writes its calculated expiration. No active paid state
   writes `free` and clears the expiry. The existing trigger advances
   `users.entitlement_version` only when the projected tier or expiry changes;
   all AI authorization reads that durable version.
6. **Timed-pass repair and media stability**:
   `expire-subscription-passes` remains an hourly fail-safe for any recurring,
   grace-period, or pass row that reaches its expiry. Before complimentary
   cutover, the legacy seven-day new-user trial is derived from
   `users.created_at` and is never stored as paid Pro; after cutover no current
   resolver emits it. Tier changes do not relocate scan media: both
   `public_uploads/free/` and `public_uploads/pro/` are durable prefixes.
7. **Missed-delivery repair**: A private durable queue invokes
   `reconcile-revenuecat-subscribers` every 15 minutes. It drains repeated
   six-customer lease waves until empty or a runtime cutoff, fetches with
   concurrency three, and applies only a newer authoritative snapshot under its
   claim token. Expired leases have a supporting partial index. Pro users are
   revisited every six hours and free users every 24 hours. A separate
   oldest-due-age monitor alerts at 30 minutes and becomes critical at 60. The
   sweep cannot newly grant historical `pro_week` history after a revoked/free
   watermark.

RevenueCat delivers webhooks at least once, so a `200` response may report
`applied`, `duplicate`, `stale`, `mixed`, or `ignored`, together with subject,
applied, and stale counts. Provider or
database faults return non-2xx so RevenueCat retries. Operational setup,
rotation, and smoke checks live in the
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#revenuecat-webhook-release-gate).

## Usage Limits (`UsageManager`)

Provides an advisory local paywall/capture meter. It is not the entitlement or
provider-cost enforcement boundary.

- `.canPerformScan(isProActive:)` returns
  `isProActive || freeScansRemaining > 0`. Capture passes
  `RevenueCatManager.canStartProScan` for UI presentation, but queue insertion
  uses the synchronous `EntitlementManager.claimFunding` transaction. Only
  immediate/deferred Flash funding reserves the advisory token. Network
  failures do not release an accepted reservation or turn a durable scan into a
  paywall; exact-ID recovery keeps it queued.
- `handlePhotoPickerSelection` snapshots the current quota once per picker batch
  before any background downsampling begins. If the batch is over quota, it
  clears the picker selection immediately, tracks the paywall impression, and
  exits before loading gallery bytes into memory.
- `FeatureFlag.unlimitedFreeScans.defaultValue` is `false`. DEBUG builds may
  bypass the local meter from Settings or `MERIAN_DISABLE_FREE_SCAN_LIMIT=1`;
  Release/TestFlight ignores persisted debug overrides. This never changes the
  database entitlement, model, or server quota.
- **Advisory reservation at capture time**: when paid or verified unheld
  complimentary capacity is unavailable, `consumeScan()` reserves the separate
  Flash meter at enqueue time in `insertAndPersistRecord` or
  `enqueueNonVisualCapture`. The quota check and token consumption happen before
  the `OfflineQueuedScan` record is inserted into SwiftData. `syncPendingScans`
  has no second local-meter gate—every accepted queue row uploads
  unconditionally. The Edge request still reserves authoritative server quota
  and any required lifetime hold immediately before model work. Successful
  non-biological results consume the plan that funded them. The Non-biological
  collection's correction reanalysis flow bypasses
  only the Pro reanalysis feature gate for that specific correction path; when
  the user submits the replacement scan it follows the normal paid →
  complimentary → Flash selection and applicable limits.
- **Server authority**: `reserve_ai_quota` applies the free one-scan UTC-day
  policy and high complimentary/paid Pro fair-use ceilings, plus shared
  per-user/IP minute limits. Overview, lookalike, and optional group-tag provider calls
  share their own enrichment bucket. Clearing/modifying `UserDefaults` does not
  change them. A database entitlement failure returns `503`; it never falls
  back to Pro.
- **Product language**: Pro removes the ordinary one-scan product cap but
  remains subject to documented anti-abuse/cost safety ceilings. Do not promise
  technically unbounded provider use.
- **Local reconciliation**: queue-insertion or proven pre-provider client
  failure can restore an optimistic local token. After success,
  `reconcileServerPlanUsed` refunds that token for paid/complimentary results or
  consumes it for actual Flash fallback, idempotently by scan ID. This does not
  refund a provider attempt or settle a complimentary hold. Provider quota
  remains charged after an attempted call even when terminal credit settlement
  releases the user's hold.
- Grants 1 free daily scan via `UserDefaults` keyed against
  `DeviceIdentityManager.shared.deviceId`.
- Resets the advisory meter at device calendar boundaries. The authoritative
  free scan bucket resets at the UTC database boundary. The
  `evaluateDailyRefresh()` check is
  called from `AppDIContainer.handleActivePhase()`, ensuring user quotas are
  reset when the app enters the foreground from an overnight suspension.

The complete grant, ledger, balance, fallback, settlement, protocol, offline,
merge, security, and rollout contract is
[`18-complimentary-pro-scans.md`](../backend-and-data/18-complimentary-pro-scans.md).

## Trust & Safety (`SocialGuardManager`)

Operates independently of Revenue boundaries but is fundamentally tied to
Identity.

- Manages a persistent local SwiftUI `Set<String>` of blocked User UUIDs
  (`blockedUserIds`).
- Updates UI blocking state across Discovery feeds immediately while
  asynchronously flushing the UUID to the `/block-user` Edge node.
- Automatically reverts the block if the Edge API returns an error, restoring
  the previous state.
