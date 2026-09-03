# Revenue and Identity Management

Naturebook implements an onboarding funnel by combining Supabase Anonymous
Authentication with RevenueCat SDK bindings for entitlement checking.

## Contents

- [Anonymous IDFV Strategy (`DeviceIdentityManager`)](#the-anonymous-idfv-strategy-deviceidentitymanager)
  — Ghost session creation, OAuth upgrade, account merging, historical sync
- [Paywalls and Entitlements
  (`RevenueCatManager`)](#paywalls-and-entitlements-revenuecatmanager) — paid,
  functional, and new-scan capacity; trials, beta grants, Field Chat, and the
  current-launch `EntitlementManager`
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
- It remains an analytics/install fallback, not billing authority. In stable
  mode, `PurchasePrincipalResolver` uses a separate 256-bit device-only
  capability to obtain a server-owned RevenueCat purchase principal for the
  current Supabase session. PostHog and Supabase Auth keep their own identity
  contracts; no hardware ID selects a billing customer.
- Anonymous session bootstrap is single-flight. `SupabaseManager` stores a
  `ghostSessionTask` handle so concurrent callers to `initializeGhostSession()`
  / `getValidAuthHeaders()` all await the same in-flight anonymous sign-in
  instead of racing multiple `signInAnonymously()` requests against the same
  empty state.
- A generic Edge `401` is not account-deletion evidence and preserves the
  current Ghost UUID. Replacement is allowed only for the stable
  missing/invalid-session contract after a Supabase SDK refresh also fails. This
  prevents a failing route from creating a chain of Supabase Ghost users and
  matching RevenueCat customer shells.
- Exposes `isGuestUser` through `AccountPresentationPolicy`. It is true only
  when the active Supabase session is anonymous or no session is available. A
  linked session is always presented as linked. This is an internal state name;
  product errors and controls say signed out and never render “Ghost” or “guest
  session.”
- Apple, Google, Sign out, anonymous recovery, credential revocation, and
  account deletion share one generation-bound `AuthTransitionCoordinator`. Only
  its token may adopt a destination or mutate the SDK session. Competing
  controls disable, stale provider/controller callbacks are ignored, and every
  account-bound write rechecks the live source/destination after suspension.
  Confirmed deletion first persists `capability_preparation_pending`, then
  verifies an atomic device-only envelope with distinct recovery and
  acknowledgement capabilities before the first network suspension. It is
  intended to complete the server's non-destructive prepare, persist
  `capability_prepared_pending`, and then persist `capability_intake_pending`
  before destructive commit. It fences every other account operation and replays
  only the JWT-derived idempotent commit or account-free proof recovery after a
  lost response. `not_committed` preserves the account and retires only local
  intent; a success receipt advances through cleanup, independent
  acknowledgement, and capability retirement. Verified Keychain envelope removal
  precedes marker clearing. The blocking foreground/cold-launch recovery UI
  never stores or displays an internal user, job, provider, request, or purchase
  identity. The checked-in four-field prepare response is decoded by the
  operation-specific native receipt and locked to the handler through a shared
  fixture; see the
  [Core Network preparation contract](../../apps/ios/Merian/Core/Network/README.md#preparation-receipt-contract).
  Authorized real-session deletion remains separate release evidence.
- **Identity Resolution & OAuth**: Merian uses standard Apple
  (`ASAuthorizationAppleIDProvider`) and Google (`GIDSignIn`) iOS libraries to
  authenticate without web-view redirects.
  - When a user taps **Continue with Apple**, iOS acquires the raw
    cryptographically signed `.idToken` and the one-use authorization code.
    After Supabase installs the permanent session, the authenticated
    `register-apple-revocation-token` route verifies both Apple identity tokens,
    binds their subject to the Supabase identity, exchanges the code, and stores
    the refresh token in Vault. Registration is required for sign-in success;
    failure clears the new local session. Account deletion later revokes that
    credential before Auth, while accounts predating capture receive a durable
    server disposition that supporting clients persist as the manual
    Apple-removal fallback documented in the
    [canonical contract](../backend-and-data/20-sign-in-with-apple-account-deletion.md).
    Apple's credential-revoked notification triggers a credential-state query
    for the active provider-specific subject. The callback is discarded if the
    signed-in Apple identity changed; `.authorized` preserves the session and
    every non-authorized, unknown, or failed resolution clears the matching
    local session without claiming server revocation. The manual fallback is
    implemented only by supporting binaries, so public promotion still requires
    an enforceable minimum-supported-build control or an independent
    server-delivered fallback for older clients. Because
    `ASAuthorizationController` holds a weak reference to its Apple Sign-In
    delegate, `SupabaseManager` must persist the controller in a strong
    `activeAppleAuth` class property until the delegate callback returns, to
    avoid premature memory deallocation crashes where the sign-in modal abruptly
    aborts.
  - Apple Sign-In bootstrap failures are now recoverable. If the app cannot
    generate a nonce, cannot find a presentation anchor yet, or receives a
    callback after the nonce was cleared, `SupabaseManager` logs the failure and
    cancels the auth attempt instead of crashing the app.
  - When a user taps **Continue with Google**, iOS boots the
    ASWebAuthenticationSession. The application intercepts the callback scheme
    inside `<MerianApp>.onOpenURL` via `GIDSignIn.sharedInstance.handle(url)`,
    preventing Google deep-links from being consumed by Supabase Magic Link
    handlers.
  - Merian passes the resulting `idToken`s through Supabase's
    `linkIdentityWithIdToken(credentials:)` (if the user is currently an
    anonymous Ghost User) or `signInWithIdToken(credentials:)` (if returning).
    Using `linkIdentityWithIdToken` merges the OAuth provider to the _existing_
    anonymous UUID, ensuring the user's local offline queue and S3 uploads are
    not stranded during the account upgrade. Only an `identity_already_exists`
    error falls back to a standard `signInWithIdToken`; transient and
    configuration failures leave the Ghost session active. Before switching
    sessions, the live Ghost session requests a one-use `/merge-ghost-profile`
    handoff bound to the exact OAuth provider subject and persists its 256-bit
    secret in a versioned, foreground-accessible, device-only Keychain queue.
    The proof remains valid for 30 days. After sign-in, only the permanent
    account that owns that provider identity can consume it. PostgreSQL locks
    both users, resolves uniqueness conflicts, and transfers ownership in one
    transaction; only then does the Edge Function delete the obsolete anonymous
    Auth shell. The pending schema-aware contract must execute only
    source-controlled ownership policies within that transaction. The client
    retains transient failures for idempotent retries, and a five-minute
    service-role worker finishes Auth cleanup if the client never returns.
  - For this conflict fallback, client-side `Purchases.logIn` and provider
    webhooks are acceleration paths, not recovery authority. Merge completion
    must independently upsert an immediately due RevenueCat reconciliation row
    for the permanent UUID even when the anonymous source had no queue row.
    RevenueCat reconciliation and merge both lock the public user before the
    queue row, and reconciliation revalidates its lease under lock before
    applying entitlement state.
  - In the legacy compatibility lane, a database queue repair does not transfer
    RevenueCat provider state. The Ghost UUID and permanent UUID are both
    non-anonymous custom RevenueCat IDs, and RevenueCat documents
    custom-to-custom `logIn` as an account switch with no purchase transfer.
    This does **not** block Ghost purchases: a stable Ghost UUID is a
    first-class RevenueCat purchase identity, and the normal OAuth link
    preserves that UUID. For the existing-account conflict fallback, the Edge
    function reads source and destination CustomerInfo, mirrors and verifies the
    source's active finite or lifetime Pro horizon, and only then allows
    obsolete source Auth deletion. The iOS durable completion then calls
    `syncPurchases()` under the required **Transfer to new App User ID** project
    behavior before rebinding local evidence and removing its proof. The worker
    repeats server preservation before cleanup if the client disappears. Beta
    grants accept both verified active Ghost and linked Auth identities.
  - The schema-aware conflict fallback remains release-gated until that durable
    queue behavior, RevenueCat and Community lock ordering, both scan-ledger
    error mappings, exact-version catalog replay, and staging concurrency probes
    satisfy the
    [Ghost merge rollout matrix](../backend-and-data/06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).
  - Once `session.user` is available, `SupabaseManager` resolves purchase
    identity before paid readiness unless a protocol-3 sign-out journal owns the
    transition; that exact anonymous destination must claim its reservation
    instead. Stable mode passes only the server-returned purchase-principal ID
    and binding generation to `RevenueCatManager`; it never writes email,
    avatar, display name, username, account kind, or Auth UUID subscriber
    attributes because the same purchase principal can outlive or switch
    accounts. Identity mutations are serialized and fenced by Auth-event
    generation so a stale asynchronous `logIn` cannot overwrite a newer session.
    Every Auth-user, binding-generation, account-kind, or provider-ID change
    closes local subscription and account-grant readiness before rebind; a
    transient same-principal rebind cannot retain another account's promotion.
    Legacy mode retains the uppercase Auth-UUID link and its historical
    attributes only for supported old-client compatibility. PostHog linking is
    independent and remains governed by analytics consent.
  - Local `CustomerInfo` can open paid UI only when RevenueCat reports
    `verified` or `verifiedOnDevice` and each active product has store
    provenance allowed by the binding. Release builds accept exact Apple App
    Store provenance; Test Store is Debug-only. Stable mode rejects promotional,
    Mac App Store, Play Store, Stripe, RevenueCat Billing, External, Paddle,
    Amazon, Galaxy, missing, or unknown provenance for `pro_annual`, entitlement
    rows, and the seven-day pass even if the product identifier appears active.
    Account-owned promotions remain a separate server grant and never masquerade
    as StoreKit access on a shared purchase principal; only the temporary
    dual-read account-grant compatibility lane may admit explicit promotional
    provenance for the recorded owner.
  - **Account Rehydration**: Intercepting the initial payload from
    `SupabaseManager.setupAuthStateListener`, Merian calls
    `ScanRepository.shared.syncHistoricalScansDown`, which fetches the user's
    scan history and loads it into local SwiftData structures.
  - User-facing **Sign out** calls `transitionToGhostSession()` but displays no
    internal Ghost or guest-session terminology. Stable mode first journals a
    random rotation ID and device-only proof, then prepares a server-owned
    reservation while the exact linked source JWT and binding generation are
    still live. Only after that response is durably recorded does iOS close the
    local linked session and create one anonymous session. Postgres accepts the
    claim only when that destination is different, anonymous, and no older than
    the reservation; the atomic receipt advances the same purchase principal's
    binding. A live reservation blocks ordinary resolution, every other binding
    writer, paid readiness, provider mutations, account deletion, and Ghost
    merge. The reservation snapshots the latest two-phase resolver intent, so a
    completion begun before preparation stays stale after every terminal
    outcome. An unrelated permanent session remains fail-closed and cannot link
    RevenueCat. The restored exact source may cancel, including a write-ahead
    request whose prepare response was lost. After claim, iOS relinks RevenueCat
    to the unchanged server-owned ID, requires
    `EntitlementManager.beginSession(...)` to return `true`, verifies the same
    anonymous Auth generation, and clears the journal last. A provider or
    entitlement failure after the atomic claim retains both the journal and
    paid- operation fence for exact same-destination retry. The journal pins the
    exact local capability fingerprint and forbids replacement capability
    creation, so partial Keychain loss fails before server or provider identity
    mutation. It does not call `syncPurchases()` or a provider customer-transfer
    API. The Profile offers **Continue with Apple** and **Continue with
    Google**; those transitions resolve the same principal. Foreground
    activation retries this exact binding after transient resolver,
    account-cleanup, Keychain, or provider failure, so recovery does not depend
    on another Auth callback and never rotates the capability or provider ID.
  - While the rollout response is `mode: legacy`, sign-out retains the existing
    `/transfer-signout-purchases` compatibility flow: prepare StoreKit-only
    state, verify a device-only proof before local sign-out, bind exactly one
    fresh anonymous UUID, link its uppercase UUID customer, call
    `syncPurchases()`, obtain authoritative server verification/reconciliation,
    refresh entitlement, and remove the proof last. A restored source can cancel
    only an unbound proof. Account deletion is disabled and server-rejected
    while either stable rotation evidence or a legacy proof remains pending. An
    already-issued legacy proof is immutable across a rollout-mode change: iOS
    finishes receipt sync and server verification on its exact uppercase
    destination UUID, clears the proof, and only then permits stable-principal
    adoption.
  - Sign-out transfers only receipt-backed StoreKit access under RevenueCat's
    required **Transfer to new App User ID** behavior. Account-issued
    promotional/beta grants remain attached to the linked source and are not
    duplicated. The server requires RevenueCat v1's explicit `store: app_store`
    purchase discriminator; promotional subscription records use
    `store: promotional`, and unknown or missing stores fail closed. A mixed
    customer whose promotion wins the entitlement row still retains an active
    reviewed `pro_annual` StoreKit subscription from the authoritative
    subscription record; the promotion remains account-owned. A detached
    seven-day pass must match the database's authoritative expiry;
    stale/refunded purchase history cannot establish a handoff.
  - This custom-ID handoff is a compatibility boundary. The additive long-term
    implementation separates Supabase authentication identity, a stable StoreKit
    purchase principal, and Supabase-owned account grants; see
    [`purchase-principal-auth-separation.md`](../rfcs/purchase-principal-auth-separation.md).
    RevenueCat V2 customer transfer is not an allowed shortcut because it cannot
    isolate mixed promotional and StoreKit subscription history and has no
    documented request idempotency key.
  - The authenticated-session marker is centralized under
    `KeychainKeys.hasAuthenticatedOAuth`. Do not inline the legacy string key in
    auth or network code. The retired presentation-only marker is referenced as
    `KeychainKeys.legacyGhostModeUserID` solely so upgraded clients can delete
    it during startup.

## Paywalls and Entitlements (`RevenueCatManager`)

- Controls Apple ecosystem entitlement bounds governing core app functionality.
- Waits for an active Supabase session and a successful purchase-principal
  resolution. Stable mode initializes or logs in with the exact server-returned
  opaque App User ID; legacy mode uses the uppercase RFC 4122 Supabase UUID.
  RevenueCat IDs are case-sensitive, so neither client nor database changes the
  returned stable value.
- Local Debug and unsigned validation builds may use RevenueCat's `test_` Test
  Store key while purchase flows are being exercised. This does not include an
  internal TestFlight build. The store environment does not change Merian's
  identity contract: stable mode uses the server-issued purchase principal and
  writes no account PII to it; legacy mode keeps the Auth-UUID compatibility
  identity. The Xcode Release archive preflight requires a RevenueCat iOS SDK
  key beginning with `appl_` before Organizer distribution.
- Serializes configure/login mutations. Stable readiness requires the provider's
  current App User ID, active Supabase Auth UUID, and server binding generation
  all match; a late result for an older Auth event is discarded. Sign-out clears
  readiness but does not call RevenueCat logout, preventing `$RCAnonymousID`
  creation. Legacy custom-ID switches still require the separate verified server
  mirror and receipt-sync contract described above.
- Configures RevenueCat entitlement verification in informational mode and
  grants local paid presentation/operation readiness only for CustomerInfo
  reported as `verified` or `verifiedOnDevice`. Any unverified snapshot closes
  local paid state. The SDK log callback discards provider message bodies and
  emits fixed severity-only diagnostics without customer or account identity.
- `RevenueCatOfferingPolicy` requires the current offering to contain App Store
  product identifiers `pro_week` and `pro_annual`. Offering fetches emit an
  operational error when there is no current offering, the current offering has
  no packages, or either mapping is missing. The client cannot create products
  or select a dashboard offering: App Store Connect product readiness,
  RevenueCat package mapping, and current-offering selection must be completed
  externally before release.
- Settings Plan presentation reads the environment-owned offering and
  entitlement snapshot reactively. `PaywallDependencies` and
  `ManagePlanDependencies`, together with `PlanCardDependencies`, are the narrow
  action boundary for purchase, restore, subscription management, and code
  redemption. Their `@MainActor` view models reject purchase/restore overlap,
  serialize restore work, and prevent code redemption from competing with an
  active restore; SwiftUI views retain only package selection and presentation
  timing.
- Evaluates paid `isSubscribed` state via `.customerInfo()` and combines it with
  the current session's server-verified complimentary entitlement.
  - `isSubscribed` checks for active entitlements across the standard Pro
    subscription identifiers and a locally evaluated `pro_week` non-subscription
    transaction. The 7-day pass is intentionally not a RevenueCat entitlement.
  - `EntitlementManager` calls authenticated `get_my_entitlement()` on every
    launch/session and accepts complimentary access only after online
    verification for the active Supabase user. It applies snapshots and scan
    metadata monotonically by `entitlement_version`, including an account-owner
    check, so late responses cannot restore another account's stale balance.
    Scan-response metadata is buffered until that launch baseline succeeds: an
    idempotently replayed stored envelope can contain a historical snapshot and
    cannot establish current-launch proof on its own.
  - Every account receives three lifetime complimentary Pro scans with no
    calendar expiry. A credit or active hold enables the complimentary fair-use
    Pro actions. `isProActive` is paid RevenueCat access or an exactly verified
    complimentary tier; public Profile and Explore badges continue to use paid
    `isSubscribed` state only. `canStartProScan` is a presentation hint for new
    Pro-funded analyses. Actual admission synchronously claims an
    account/scan-keyed funding reservation and subtracts unresolved local
    complimentary and legacy blockers from `scans_available_to_start`; an active
    hold alone cannot fund scan four, and one stale remaining credit cannot
    admit multiple offline Pro scans.
  - Complimentary balances appear in Results and Settings, not Capture. After
    the third durable result the stored result remains fully viewable and the UI
    shows exhaustion plus an upgrade action. Ordinary compatible captures use
    the separate daily Flash policy when credits are exhausted.
  - Visible product copy calls the allowance **Pro scans**, not “complimentary”
    scans. Remaining counters use “3 Pro scans remain” and “1 Pro scan remains”;
    `pro_complimentary` remains an internal server plan.
  - **Backend Model Upgrades**: The client display state is not provider
    authorization. Every paid-model Edge path atomically calls protocol-3
    `reserve_ai_quota`, which locks the user, resolves paid Pro → complimentary
    Pro → free, acquires a lifetime-ledger hold when required, selects the
    database policy model, and consumes provider quota before dispatch. Paid
    users have `users.subscription_tier = "pro"` and resolve to `pro_paid`;
    active non-renewing passes also require a future `subscription_expires_at`;
    verified complimentary scans resolve to `pro_complimentary`. A stale timed
    pass resolves free, and a missing user row, malformed entitlement row, or
    database error fails closed. `pro_trial` remains a historical reporting
    value only after cutover. RevenueCat/webhook changes advance
    `users.entitlement_version` in a trigger, so no Edge-isolate cache
    invalidation is required.
  - RevenueCat project-level Pro billing is an integration plan, not a customer
    entitlement. Beta access uses an expiring promotional `pro` entitlement.
    Once its webhook or scheduled reconciliation projects
    `subscription_tier =
    pro`, it receives the same server `pro_paid`
    feature gates—including Field Chat—as store-paid Pro for the grant period. A
    manual database-only Pro edit is intentionally reverted when RevenueCat has
    no active entitlement.

### RevenueCat plan, trials, beta grants, and Field Chat

These similarly named states have different authorities:

| State                             | How it starts                                                                                                        | Customer access                                                                                                        |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| RevenueCat developer account Pro  | The developer pays RevenueCat for its project plan                                                                   | Enables project features and integrations only; it grants no app user Pro access.                                      |
| App Store introductory free trial | The user completes the normal store purchase flow and the receipt contains an introductory trial                     | RevenueCat activates the mapped `pro` entitlement automatically. There is no manual per-user RevenueCat approval step. |
| Beta promotional Pro              | A reviewed operator or server uses RevenueCat's secret-key promotional entitlement boundary with a finite expiration | Immediate provider Pro for the approved customer; it does not create or alter an App Store subscription.               |
| Three introductory Pro scans      | Supabase grants and settles the private complimentary ledger                                                         | Separate functional allowance; it is not a RevenueCat trial, purchase, or promotion.                                   |

For store trials and beta promotions, RevenueCat CustomerInfo is the Pro-state
authority and Supabase is its durable server projection. The webhook normally
projects the change immediately; the scheduled reconciler repairs a missed
delivery. After `subscription_tier = pro` is projected, the server resolves
`pro_paid`, so the customer receives Field Chat and the other paid feature gates
for the active period. Editing the database tier directly is never a grant and
will be overwritten by the next authoritative reconciliation.

The Field Chat entitlement is identical for owned Insight scans, visible Explore
posts, and canonical in-app Species Dictionary pages. Each backend route
re-resolves effective tier; a client paywall check is presentation only and
cannot grant access. Public web dictionary pages remain anonymous reference
content and do not expose Field Chat.

This describes the authorization contract, not release status. The Dictionary
surface remains release-held by the
[Species Dictionary candidate checklist](16-species-dictionary.md#candidate-release-status);
do not infer availability from an effective Pro entitlement alone.

The independent `pro_complimentary` path can also resolve `effective_tier = pro`
while an exactly verified credit or active hold remains, so it passes the Field
Chat gate without creating a RevenueCat entitlement or paid badge. That
functional allowance is not evidence about the customer's store trial or beta
membership.

Beta membership must come from an explicit reviewed UUID cohort, not from the
current tier column. A user who already reverted to `free` is still eligible if
the approved cohort says they are a beta member. The Auth audit requires a live
Auth user but accepts both Supabase-anonymous Ghost and linked accounts.
RevenueCat customer-count parity is also not expected: aliases, case variants,
test identities, deleted Merian users, and get-or-create shells can all exist in
the provider project.

The P1 source corrections for the canonical-ID and beta rollout include a grant
client that accepts successful CustomerInfo GET `200|201`, consumes an explicit
cohort independent of tier, and reports verified Ghost/linked counts. The iOS
mutation boundary accepts an exact stable Ghost or linked identity, and its
generic-`401` path preserves the current UUID instead of manufacturing another
Ghost and RevenueCat customer. The conflict fallback mirrors active Pro before
source Auth deletion and synchronizes the real store receipt before its durable
client proof is removed.

Prelaunch cleanup is permitted only through the exact
`cleanup-revenuecat-shells` plan/apply boundary. It protects the reviewed
cohort, every active Auth identity, canonical current Supabase customers by
default, purchase/promotion history, aliases, recent activity, and ambiguous
state, then revalidates live RevenueCat state before each exact delete. It never
deletes a Supabase user or app data. A later lookup can recreate an empty
provider shell, but cannot reconstruct deleted aliases, purchases, or
promotions; that is why only shells proven to have none are eligible. See the
[RevenueCat customer identity incident](../incidents/2026-08-revenuecat-customer-identity-drift.md)
and
[deployment release gate](../backend-and-data/06-supabase-deployment-runbook.md#revenuecat-webhook-release-gate).

### Prelaunch purchase testing

Choose one store source deliberately; do not mix Test Store products, App Store
products, and StoreKit configuration products in one diagnosis.

| Test path                                     | SDK key                    | Product source                                               | Required verification                                                                                                                                                                         |
| --------------------------------------------- | -------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fast Debug/simulator purchase testing         | RevenueCat `test_` key     | RevenueCat Test Store products                               | The dashboard current offering contains Test Store products whose identifiers are exactly `pro_week` and `pro_annual`; purchases and customer identity are visible in the Test Store project. |
| Local StoreKit configuration                  | RevenueCat iOS `appl_` key | A `.storekit` file attached to the Xcode Run action          | The file contains the same identifiers and its certificate/configuration follows RevenueCat's StoreKit testing setup.                                                                         |
| Apple sandbox, physical device, or TestFlight | RevenueCat iOS `appl_` key | App Store Connect products imported and mapped in RevenueCat | Bundle ID, agreements, product readiness, package mapping, current offering, purchase, restore, and webhook behavior all pass.                                                                |

The shared `Merian` scheme does not currently attach a `.storekit` file. A Debug
simulator using the production `appl_` key therefore depends on StoreKit being
able to resolve the App Store Connect products. If the SDK reports that none of
the dashboard products could be fetched, fix the selected store setup before
changing client retry logic. Repeated errors can reflect more than one SDK/UI
request for the same unavailable offering; the first success criterion is one
valid offering, not fewer error lines.

RevenueCat identity and product loading are separate checks. A log such as
`RevenueCat identity linked` proves only that the currently resolved legacy or
stable App User ID was linked; it does not prove StoreKit returned products or
that the server binding still matches after an Auth race. A complete smoke test
must:

1. Launch with the intended key/store combination.
2. Confirm the SDK product-fetch error is absent.
3. Open Settings → Plan manually and confirm both required packages render.
4. Complete and restore a purchase in the selected test environment.
5. For Apple sandbox/TestFlight, confirm the webhook updates the matching
   Supabase user and expiration semantics.

The release build keeps the advisory local scan meter enabled. A DEBUG-only
meter bypass can still prevent quota-triggered paywall presentation, but it does
not bypass the Supabase reservation; purchase QA should therefore open the Plan
surface directly. See
[RevenueCat offering troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings),
[Apple sandbox testing](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
and the
[iOS release runbook](../development-guides/14-ios-release-versioning.md).

## RevenueCat Webhook (`revenuecat-webhook`)

To keep the Supabase PostgreSQL backend in sync with iOS RevenueCat purchase
state, the `revenuecat-webhook` Edge Function treats each global subscription or
`pro_week` event as a synchronization signal. It never trusts the event type
alone to decide access.

1. **Dual ingress authentication**: `verify_jwt = false` permits RevenueCat,
   which has no Supabase JWT, to reach the handler. The handler requires the
   configured `Authorization: Bearer REVENUECAT_WEBHOOK_SECRET` and verifies
   `X-RevenueCat-Webhook-Signature` with HMAC-SHA256 over the exact
   `<timestamp>.<raw JSON body>` using `REVENUECAT_WEBHOOK_SIGNING_SECRET`.
   Signatures outside the five-minute past/future window fail before JSON
   parsing.
2. **Durable identity**: `event.id` and `event_timestamp_ms` are required.
   RevenueCat current, original, and alias identifiers resolve against active
   stable purchase principals first and uppercase Supabase UUID compatibility
   customers second. Ambiguous mixed identities fail closed. `TRANSFER` has no
   `app_user_id`, so its `transferred_from` and `transferred_to` identity groups
   become separate source and destination subjects. A purely anonymous event is
   durably marked `ignored` without mutating a user; a later alias event carries
   a different durable event ID. Billing never creates a missing `public.users`
   row or picks arbitrarily when one RevenueCat identity group maps to multiple
   live rows. A transfer source that was already deleted is omitted so it cannot
   block the live destination; missing normal/destination rows remain retryable.
3. **Authoritative reconciliation**: After signature verification, the server
   first checks its private durable receipt. A committed duplicate returns
   immediately so provider retries cannot amplify API traffic. Every new event
   calls RevenueCat `GET /v1/subscribers/{app_user_id}` for each mapped customer
   with `REVENUECAT_SECRET_API_KEY`. Active `pro` or `Naturalist Tier`
   entitlement state controls standard Pro and carries the later of recurring
   expiration and grace-period expiration. The detached `pro_week` purchase is
   derived from authoritative non-subscription transactions with a seven-day
   expiry; matching refunds/revocations are excluded. An API error or malformed
   response returns a retryable failure and leaves the database unchanged. Both
   transfer lookups finish before either side can be written. For stable
   principals, the database also stores whether detached pass history is
   eligible. Signed purchase evidence may enable it directly. A transfer
   destination inherits it only from a resolved stable source whose durable
   policy is already enabled and only after the destination snapshot contains an
   active App Store pass. Refund/revocation/transfer-source evidence disables
   it; unrelated events preserve it. CustomerInfo destination history or a
   scheduled repair cannot enable the flag on its own, and transfer propagation
   lag is retried instead of guessed. A stable `TRANSFER` never mutates
   account-owned beta/promotional grants: provider promotion state on either
   side is recorded as observation only, while StoreKit state follows the
   purchase principal. Both stable customers are then durably fenced from later
   provider-promotion imports so resolver and scheduled reconciliation cannot
   move the grant after the event.
4. **Transactional ordering**: `public.apply_revenuecat_identity_state(...)`
   stores each event ID once, locks stable principals and then every resolved
   user in sorted order, and advances each subject only when the authoritative
   CustomerInfo `request_date_ms` is newer than that user's durable watermark.
   Provider event timestamp and event ID break only exact snapshot ties.
   Duplicate and stale deliveries are audited but cannot overwrite access. A
   newer refund therefore cannot be undone by a delayed purchase, and a newer
   renewal cannot be overwritten by a delayed expiration. Transfer
   source/destination changes share one event transaction and cannot partially
   commit. The previous bundle's legacy UUID mutation and scheduler RPCs remain
   only as compatibility adapters into the identity ledger and queue. They share
   a cutover advisory lock with activation before the principal-before-user
   row-lock sequence and recheck under lock, so a completed stable adoption or
   rebind cannot be followed by a legacy state or queue write.
5. **Tier and expiry projection**: Active standard entitlement state writes
   `subscription_tier = pro` with the later recurring/grace expiration. `NULL`
   is reserved for an explicitly non-expiring lifetime entitlement. An active
   `pro_week` writes its calculated expiration. No active paid state writes
   `free` and clears the expiry. The existing trigger advances
   `users.entitlement_version` only when the projected tier or expiry changes;
   all AI authorization reads that durable version.
6. **Timed-pass repair and media stability**: `expire-subscription-passes`
   remains an hourly fail-safe for any recurring, grace-period, or pass row that
   reaches its expiry. Before complimentary cutover, the legacy seven-day
   new-user trial is derived from `users.created_at` and is never stored as paid
   Pro; after cutover no current resolver emits it. Tier changes do not relocate
   scan media: both `public_uploads/free/` and `public_uploads/pro/` are durable
   prefixes.
7. **Missed-delivery repair**: A private durable queue invokes
   `reconcile-revenuecat-subscribers` every 15 minutes. It drains repeated
   six-customer lease waves until empty or a runtime cutoff, fetches with
   concurrency three, and applies only a newer authoritative snapshot under its
   claim token. Expired leases have a supporting partial index. Pro users are
   revisited every six hours and free users every 24 hours. A separate
   oldest-due-age monitor alerts at 30 minutes and becomes critical at 60. The
   sweep cannot newly grant historical `pro_week` history after a revoked/free
   watermark. Stable-principal claims carry the durable pass-policy flag and the
   apply path preserves it.

RevenueCat delivers webhooks at least once, so a `200` response may report
`applied`, `duplicate`, `stale`, `mixed`, or `ignored`, together with subject,
applied, and stale counts. Provider or database faults return non-2xx so
RevenueCat retries. Operational setup, rotation, and smoke checks live in the
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#revenuecat-webhook-release-gate).

## Usage Limits (`UsageManager`)

Provides an advisory local paywall/capture meter. It is not the entitlement or
provider-cost enforcement boundary.

- `.canPerformScan(isProActive:)` returns
  `isProActive || freeScansRemaining > 0`. Capture passes
  `RevenueCatManager.canStartProScan` for UI presentation, but queue insertion
  uses the synchronous `EntitlementManager.claimFunding` transaction. Only
  immediate/deferred Flash funding reserves the advisory token. Network failures
  do not release an accepted reservation or turn a durable scan into a paywall;
  exact-ID recovery keeps it queued.
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
  collection's correction reanalysis flow bypasses only the Pro reanalysis
  feature gate for that specific correction path; when the user submits the
  replacement scan it follows the normal paid → complimentary → Flash selection
  and applicable limits.
- **Server authority**: `reserve_ai_quota` applies the free one-scan UTC-day
  policy and high complimentary/paid Pro fair-use ceilings, plus shared
  per-user/IP minute limits. Overview, lookalike, and optional group-tag
  provider calls share their own enrichment bucket. Clearing/modifying
  `UserDefaults` does not change them. A database entitlement failure returns
  `503`; it never falls back to Pro.
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
  `evaluateDailyRefresh()` check is called from
  `AppLifecycleManager.handleActivePhase()`, ensuring user quotas are reset when
  the app enters the foreground from an overnight suspension.

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
