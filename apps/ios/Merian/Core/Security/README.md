# Core Security

The `Security` directory owns client-side identity boundaries that are shared
across features: stable device identity, Keychain-backed flags, paid RevenueCat
state, server-verified complimentary entitlement, versioned adult/Terms/AI
consent, account-wide optional analytics permission, and
trust-and-safety guards. Supabase Auth session creation and OAuth orchestration
live in `Core/Network/SupabaseManager`; this directory provides the secure local
primitives and external identity bindings used by that manager.

The consent model below is the required production contract, not a release
approval. The current candidate remains blocked by the internal findings and
external owner confirmations in the
[production consent readiness record](../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

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
- `ConsentManager` owns the append-only local ledger for adult confirmation,
  Terms acceptance, every Google Gemini grant/revocation, and optional PostHog
  grant/revocation. It binds offline records to the first anonymous account,
  synchronizes immutable account-owned rows, hydrates cross-device state, and
  requires cloud-ready adult/Terms/Gemini evidence before iOS constructs an
  inference request. The database quota boundary remains the authoritative
  provider-dispatch gate.
- `SocialGuardManager` centralizes block-state checks used by social surfaces.
- `CircuitBreakerManager` stops repeated failing requests from turning poor
  connectivity into continuous foreground retries.

## RevenueCat contract

`RevenueCatManager` configures Purchases, links the RevenueCat App User ID to the
current Supabase Auth UUID, mirrors bounded support attributes, refreshes
customer information, and exposes the current offering to the Settings paywall.
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
cannot write durable backend access. The Supabase webhook independently
verifies RevenueCat's configured bearer credential and raw-body HMAC, fetches
authoritative server-side CustomerInfo, and applies each unique event through a
per-user monotonic database transaction. Duplicate or delayed deliveries and a
failed provider lookup therefore cannot roll durable access backward or cause a
backend tier mutation.

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

- The Supabase Auth UUID remains the RevenueCat App User ID across anonymous and
  OAuth-upgraded sessions.
- Normal sign-out is device-local and clears RevenueCat/PostHog identity without
  changing the durable account-wide analytics choice on other devices.
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
  different session.
- PostHog must never be configured, identified, captured, or allowed to issue a
  request before the latest active account event grants permission. Withdrawal
  and account change must opt out and close the SDK without starting another
  request, clear identity, and leave core functionality unchanged.
- Realtime account-wide analytics changes must start reliably after session
  establishment and recover after channel failure; foreground reconciliation is
  a second safety net, not the only synchronization mechanism.
- Errors and identity values use explicit unified-log privacy annotations.

See
[`02-revenue-and-identity.md`](../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
[`05-keychain-and-secrets.md`](../../../../../docs/development-guides/05-keychain-and-secrets.md),
and
[`14-ios-release-versioning.md`](../../../../../docs/development-guides/14-ios-release-versioning.md)
for the full identity, environment, purchase-testing, and release contracts.
