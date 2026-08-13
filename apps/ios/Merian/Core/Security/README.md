# Core Security

The `Security` directory owns client-side identity boundaries that are shared
across features: stable device identity, Keychain-backed flags, paid RevenueCat
state, server-verified complimentary entitlement, versioned adult/Terms/AI
consent, account-wide optional analytics permission, and
trust-and-safety guards. Supabase Auth session creation and OAuth orchestration
live in `Core/Network/SupabaseManager`; this directory provides the secure local
primitives and external identity bindings used by that manager.

The consent model below is the required production contract, not a release
approval. All tracked consent findings are complete in source, but the current
candidate still requires hosted exact-SHA execution and the external owner
confirmations in the
[production consent readiness record](../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

The app privacy manifest is a separate disclosure and required-reason API
contract; it never grants Gemini or PostHog permission. Its source inventory and
release evidence are documented in the
[iOS App Privacy Manifest Contract](../../../../../docs/development-guides/16-ios-privacy-manifest.md).

Transport security is an independent connection boundary. The app retains ATS
defaults and uses `SecureTransportPolicy` to reject non-HTTPS or credentialed
remote URLs before network/media frameworks see them. See the
[iOS App Transport Security Contract](../../../../../docs/development-guides/17-ios-transport-security.md).

## Components

- `DeviceIdentityManager` persists the stable IDFV-backed device identity used
  before Supabase establishes the canonical account UUID.
- `RevenueCatManager` owns customer identity, paid and paid-offline access,
  offerings, and purchase/restore entry points. Its `isSubscribed` value—not
  functional complimentary access—drives public Pro badges.
- `EntitlementManager` owns the authenticated, current-launch server proof for
  complimentary and other functional entitlement. It exposes the total
  remaining grant, unheld capacity available to start, in-flight holds, and the
  monotonic entitlement version. It also serializes stable scan/account funding
  reservations on `@MainActor`; the exposed booleans are UI hints, not an
  admission transaction.
- `ScanAdmissionManager` reads the authenticated account's prospective scan
  plan and UTC-day allowance immediately before Capture starts hardware or
  submission work. Preview responses are never cached, because even a short
  cache could outlive a concurrent scan's final daily allowance. Its isolated
  ephemeral request waits at most two seconds, never waits for connectivity,
  never retries, and returns a typed distinction between a valid preview,
  classified transport unavailability, and every other failure. Only the
  transport-unavailable result may use current local eligibility to select a
  queue-only Capture route; cancellation, malformed data, authentication/TLS,
  and server failures remain fail-closed. `ScanConnectivityFailurePolicy`
  centralizes that reviewed URL-code set, recognizes bounded underlying-error
  wrappers, gives certificate/authentication/ATS policy codes veto precedence
  over broader outer transport errors, and separately defines the broader
  post-durability recovery set so the two ownership boundaries cannot drift. The
  manager never reserves quota;
  the provider-side `reserve_ai_quota(...)` transaction remains the
  authorization boundary and can still reject a concurrent race.
- `ConsentManager` owns the append-only local ledger for adult confirmation,
  Terms acceptance, every Google Gemini grant/revocation, and optional PostHog
  grant/revocation. `ConsentLedgerStore` persists that ledger as an atomically
  replaced, file-protected, read-back-verified Application Support file and
  migrates the former `UserDefaults` copy before removing it. Analytics
  withdrawal first records the exact immutable revocation event in an
  independently verified Keychain journal; a failed ledger write therefore
  remains fail-closed across restart and can be replayed without changing its
  ID or timestamp. The journal retains multiple account-owned withdrawals
  rather than overwriting one during account switching. `ConsentManager` binds
  offline records to the first anonymous account,
  synchronizes immutable account-owned rows, hydrates cross-device state, and
  requires cloud-ready adult/Terms/Gemini evidence before iOS constructs an
  inference request. After a confirmed provider-bound ghost handoff, it
  generation-cancels stale sync work, atomically rebinds all four local ledgers,
  pushes target-owned pending actions, and refetches before the durable handoff
  can be removed. Normal account restoration also activates and flushes the
  target account before remote refetch while analytics remains fail-closed.
  Synchronization preserves the order target activation → all target-owned
  pending pushes → authoritative fetch → merge. AI and analytics pending events
  name their observed provider-stream head. Their authenticated RPC serializes
  the account against ghost merge and then the provider stream, assigns a
  server-only `consentRevision`, rejects a delayed grant whose parent is stale,
  and rebases a revocation to the locked current head. Rejected grants remain
  locally marked as superseded and cannot authorize either provider; accepted
  events retain the parent returned by the server. Fetch-after-error recovery
  also compares every immutable payload field before accepting an existing ID,
  while allowing the server-rebased parent of a revocation. The authoritative
  fetch includes the all-version stream head so subsequent local actions attach
  to the actual head. Local Gemini and PostHog permissions also start from that
  same head: a revocation under any disclosure version closes the gate, and only
  an exact current-version head grant may authorize the current app. The merge
  itself performs a
  final synchronous fence over task cancellation, the observed account, the
  Supabase SDK's current session, and the synchronization generation before it
  can mutate or persist the ledger or apply analytics.
  Analytics-consent Realtime owns its subscribed account independently,
  generation-fences stale channels, and retries failures with foreground
  repair. OAuth account replacement closes analytics before session
  installation and reconciles the SDK's actual session before a
  current-disclosure grant at the all-version head may reopen capture. The
  database quota boundary remains the authoritative provider-dispatch gate.
  When that boundary returns exact `403 ai_consent_required`, the manager
  immediately closes its process-local cloud-ready gate and durably fences only
  the active account. A completed user routes through authoritative restoration
  to Ready across relaunch. Reapproval writes new adult, Terms, and Gemini
  evidence; the Gemini action extends the provider head fetched after rejection,
  and another authoritative merge is required before inference. A legacy ledger
  without the fence decodes as unfenced, and account switching cannot inherit
  another user's marker.
- `SocialGuardManager` centralizes block-state checks used by social surfaces.
- `CircuitBreakerManager` stops repeated failing requests from turning poor
  connectivity into continuous foreground retries.

## Required-consent launch restoration

`ConsentManager` exposes launch-restoration state separately from
`hasCurrentRequiredConsent`. Missing local evidence is not enough to conclude
that the user must approve again because an authenticated account may restore
the current adult, Terms, and Gemini records moments later.

| State | Meaning |
|---|---|
| `.awaitingInitialSession` | No initial auth result has been observed yet. |
| `.reconciling(userId:)` | A known account, including an expired cached session awaiting refresh, lacks current local evidence and its pending rows plus authoritative remote state are being reconciled. |
| `.waitingToRetry(userId:attempt:)` | Reconciliation failed without establishing absence; an account- and generation-fenced automatic retry is pending. |
| `.retryRequired(userId:)` | Three automatic retries were exhausted; the neutral surface offers an explicit retry. |
| `.resolved` | The initial session is unauthenticated, current local required evidence already bypasses restoration, or an identity-fenced authoritative merge has durably established a previously unknown account state. |

`isRestoringRequiredConsent` is true only while required consent is missing and
the enum has not resolved. Current required evidence always wins and makes the
computed value false. `AppRootPresentationPolicy` in `MerianApp.swift` uses that
signal to hold a completed user on a launch-matched neutral surface instead of
mounting the approval screen during an in-flight restore.

Supabase token expiry does not mean the account is absent. On cold launch, an
expired cached session contributes its user ID to this restoration state while
`SupabaseManager.isAuthenticated` remains false. A later `tokenRefreshed` event
adopts the valid session normally; a terminal Auth cleanup emits `signedOut`,
which is the event that may establish no active account.

Once missing local evidence has entered restoration, the state resolves only
after an identity-fenced authoritative merge, including a merge that proves the
evidence absent. Network, decoding, pending-row push, and persistence failures
transition to 5-, 10-, and 20-second bounded retries and expose an immediate
**Try Again** action without routing to Ready. Timers and manual retries retain
both account and synchronization-generation fences. Cancellation preserves the
pending state because an account or synchronization generation may be changing.
A duplicate auth event neither consumes the retry budget nor reopens restoration
for the same resolved session.

`invalidateSynchronizationWork()` cancels scheduled and active work, resets the
retry counter, and normalizes a retryable state for the same unresolved account
back to `.reconciling`. This prevents `.waitingToRetry` from surviving after its
timer has been cancelled and gives the replacement synchronization generation a
fresh retry budget.

See the
[Onboarding Flow](../../../../../docs/features-and-hardware/04-onboarding.md#root-presentation-gate)
for the complete root matrix and UI behavior.

## RevenueCat contract

`RevenueCatManager` remains unconfigured until Supabase has established a
session and `/resolve-purchase-principal` has selected the identity mode. In
legacy mode it uses the uppercase RFC 4122 Supabase Auth UUID. In stable mode it
uses only the server-issued immutable purchase-principal App User ID and writes
no account PII or Auth UUID attributes. RevenueCat App User IDs are
case-sensitive, so iOS and PostgreSQL must agree on the exact server-selected
value. The manager refreshes customer information and exposes the current
offering to the Settings paywall.

Merian never configures without a custom ID and never calls
`Purchases.logOut()`, both of which would generate a `$RCAnonymousID` customer.
Sign-out clears paid readiness and Auth-session fences but does not discard an
active stable purchase principal. Legacy mode retains the durable sign-out
handoff and exact UUID linkage until the cutover/rollback window closes.
Any Auth user, binding generation, account kind, or provider App User ID change
also closes subscription state and account-grant eligibility before the
asynchronous rebind begins. Reusing the same stable provider ID therefore cannot
carry the previous account's promotion through a transient resolver failure.
Offering reads, purchase, restore, redemption, and subscription management
require the exact resolved identity, current Auth session, binding generation,
and recognized `account_kind`. Missing, unknown, stale, or asynchronously
mismatched state fails closed. A generic Edge `401` never rotates purchase
identity.
`RevenueCatOfferingPolicy` requires these App Store product identifiers:

- `pro_week`
- `pro_annual`

Unit tests lock the identifier policy, but they cannot validate App Store
Connect or RevenueCat dashboard state. During prelaunch testing:

- Debug simulator tests may use the RevenueCat Test Store with a `test_` key.
- The committed shared scheme has no attached `.storekit` configuration.
- TestFlight uses an iOS production key beginning with `appl_` and products
  imported from App Store Connect.
- Release builds keep the advisory local scan meter enabled. A debug-only local
  bypass never bypasses the authoritative server quota, so purchase QA should
  open Settings → Plan directly instead of depending on a quota-triggered
  paywall.

RevenueCat login and offering availability are independent. `RevenueCat login
succeeded` confirms identity linking only. A complete purchase smoke test must
also load both packages, complete/restore the transaction, and verify the
server-side webhook result where applicable.

Client `CustomerInfo` controls local presentation and purchase UX only. It
cannot write durable backend access, and local paid access opens only when
RevenueCat reports `verified` or `verifiedOnDevice` entitlement verification.
An unverified snapshot immediately closes local paid state. Store provenance is
also part of that local decision: `pro_annual`, entitlement rows, and the
detached seven-day pass must resolve to a store allowed by the active binding.
A stable purchase principal accepts only exact Apple App Store provenance in
Release builds. Promotional provenance is admitted only by the approved
legacy/account-grant compatibility lane; Test Store is an explicit Debug-only
test path. Mac App Store, Play Store, Stripe, RevenueCat Billing, External,
Paddle, Amazon, Galaxy, and missing/unknown provenance fail closed even when
RevenueCat lists `pro_annual` as active.
RevenueCat SDK log bodies are discarded; fixed severity-only messages prevent
provider responses or identifiers from entering unified logs. The Supabase webhook independently
verifies RevenueCat's configured bearer credential and raw-body HMAC, fetches
authoritative server-side CustomerInfo, and applies each unique event through a
per-user monotonic database transaction. Duplicate or delayed deliveries and a
failed provider lookup therefore cannot roll durable access backward or cause a
backend tier mutation.

The RevenueCat project's own Pro billing plan enables RevenueCat dashboard and
integration features; it does not make any Merian customer Pro. A beta customer
must have an active `pro` entitlement. A promotional `pro` grant is projected by
the webhook and reconciler to the same `pro_paid` server plan as an active store
entitlement, including Field Chat, until its explicit expiration. Directly
editing `public.users.subscription_tier` is not a grant: authoritative
reconciliation will intentionally restore RevenueCat's state.

## Complimentary entitlement contract

RevenueCat does not calculate `firstSeen`, trial days, or a client-side
`pro_trial`. On each authenticated launch, `EntitlementManager.beginSession`
calls private `get_my_entitlement()` and validates exactly one snapshot before
unlocking complimentary-only functionality. Failed or absent verification
creates no complimentary offline access. RevenueCat's existing paid-offline
behavior remains unchanged.

The client distinguishes three questions:

- `RevenueCatManager.isSubscribed`: paid status for profile and Explore badges,
  paid offline behavior, and subscription management.
- `RevenueCatManager.isProActive`: functional Pro access from paid status or a
  current-launch server proof. An active hold can preserve this access.
- `RevenueCatManager.canStartProScan`: capacity to fund a new Pro scan. A
  complimentary account needs `scansAvailableToStart > 0`; an existing hold is
  not reusable capacity. This value is advisory until `claimFunding` reserves a
  class for the stable scan ID.

Every capture path calls `EntitlementManager.claimFunding(scanId:flashFallbackEligible:)`
synchronously before writing files or starting foreground inference. The claim
is idempotent for one active account and scan and records paid Pro, locally
reserved complimentary Pro, immediate Flash, or deferred Flash with earlier
blocker scan IDs. Locally available complimentary capacity is the verified
server availability minus every unresolved local complimentary reservation and
conservative pre-protocol-3 blocker. This is the concurrency boundary that
prevents one stale remaining credit from admitting multiple offline Pro scans.

Only exactly one image, one standalone audio clip, or one description—and no
video—is eligible for Flash. Eligible later work becomes deferred when earlier
complimentary assumptions are unresolved and cannot start foreground inference.
The scheduler reads blocker funding state in one bulk status call, refreshes
authoritative entitlement after released/absent terminal state and terminal
consumption, and persists any paid, complimentary, or immediate-Flash
reclassification before dispatch.

Funding lives in `OfflineJobRecord.metadataJSON` beside
`inference_generation`. A proven pre-dispatch failure is released only after a
durable `funding_reservation_released` marker is saved; ambiguous network
outcomes remain reserved. Relaunch restores nonterminal claims, while that
marker prevents an intentionally released legacy job from being restored as a
blocker. Manual retry of released work makes a fresh synchronous claim. A 402
invalidates complimentary proof until an authoritative refresh. Completion uses
both `plan_used` and `credit_consumed`; `pro_complimentary` with
`credit_consumed = false` releases the local assumption.

Scan response metadata cannot establish a launch baseline. If a stored or live
response arrives first, the manager buffers only the newest valid snapshot,
then reconciles it after `get_my_entitlement()`. Once verified, snapshots apply
only when `entitlementVersion` is at least the installed version, so an
out-of-order replay cannot restore a stale balance. Session changes and sign-out
clear the proof and buffer.

The accepted product, API, offline, and rollout rules are canonical in
[Three Complimentary Pro Scans](../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Required security invariants

These invariants must all be demonstrated in a clean compiled test run before
the strict server cutover or a production submission.

- Legacy mode uses the uppercase Auth UUID; stable mode uses only the exact
  server-issued purchase-principal App User ID. An active stable installation
  never downgrades to the legacy identity during rollback.
- RevenueCat purchase, restore, and offer-code redemption require the exact
  resolved provider identity, Auth session, binding generation, and one matching
  recognized account kind.
- Local paid access requires verified RevenueCat CustomerInfo. Unverified,
  failed, or stale-session results fail closed.
- An unclassified `401` preserves the active Supabase identity. Ghost replacement
  requires an explicit missing/invalid-session response and a failed SDK refresh.
- Normal sign-out is device-local, clears RevenueCat's local linked-state fence
  and PostHog identity, and never asks RevenueCat to generate an anonymous App
  User ID. It does not change the durable account-wide analytics choice on
  other devices.
- Client SDK keys are extractable app configuration, never service-role or
  provider secrets.
- The iOS target must never contain `REVENUECAT_WEBHOOK_SECRET`,
  `REVENUECAT_WEBHOOK_SIGNING_SECRET`, or `REVENUECAT_SECRET_API_KEY`; those are
  synchronized only to Supabase Edge.
- RevenueCat-derived plan data is read durably by the backend; entitlement
  lookup failures fail closed before AI provider dispatch.
- Complimentary entitlement is current-session server state, never a Keychain
  or `UserDefaults` authorization flag.
- Local consent state closes the app gate immediately, but it cannot authorize
  Gemini by itself. Current versioned adult confirmation, Terms, and Gemini
  evidence must also exist at the service-only quota boundary before provider
  dispatch.
- Unsynchronized local consent actions must follow a ghost-to-permanent-account
  merge, and a stale or cancelled account sync must never install evidence for a
  different session. Every awaited network boundary and the final synchronous
  merge must agree on the observed user, SDK session, and synchronization
  generation before evidence or analytics can change.
- A provider consent action must carry the event head observed when it was
  created. Only the causal RPC may append it, and only its returned server
  revision may order accepted state. Fetch-first synchronization by itself is
  not a concurrency control. Stale-grant rejection and deny-wins revocation
  rebasing must remain atomic with the stream-head decision.
- PostHog must never be configured, identified, captured, or allowed to issue a
  request before the latest active account event grants permission. Withdrawal
  and account change must opt out and close the SDK without starting another
  request, clear identity, and leave core functionality unchanged.
- Every user-facing consent mutation must build a candidate ledger and install
  it in memory only after the throwing storage boundary verifies the complete
  atomic write. Onboarding cannot set its completion flag after a failed write.
  The three Ready-step switch labels omit terminal periods, and new adult,
  Terms, Gemini, and analytics evidence persists that exact displayed copy;
  this punctuation-only revision does not change the policy versions.
  Analytics withdrawal closes capture before storage, writes its Keychain
  journal before the primary ledger, and remains off while either recovery or
  journal cleanup is pending.
- Realtime account-wide analytics changes must start reliably after session
  establishment and recover after channel failure; foreground reconciliation is
  a second safety net, not the only synchronization mechanism.
- Auth transition admission cancels and awaits consent synchronization before
  the SDK session can change. Entitlement baseline reads require either the
  active transition token or an exact-session account-work lease, then reject
  wrong-account, stale-generation, and non-single-row results before applying
  any functional access.
- Authentication and purchase logs contain no account, Auth, RevenueCat
  customer, purchase-principal, capability, provider-body, URL, or raw-error
  values; fixed operation/error kinds are the only diagnostic payload.

See
[`02-revenue-and-identity.md`](../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
[`05-keychain-and-secrets.md`](../../../../../docs/development-guides/05-keychain-and-secrets.md),
and
[`14-ios-release-versioning.md`](../../../../../docs/development-guides/14-ios-release-versioning.md)
for the full identity, environment, purchase-testing, and release contracts.
