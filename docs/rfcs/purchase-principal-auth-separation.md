# Purchase Principal and Authentication Identity Separation

Status: Accepted; additive implementation prepared in source, rollout defaults
to legacy/dual-read, production cutover not authorized or performed
Decision date: 2026-08-12

## Decision

Naturebook will separate the identity that authenticates an app session from
the identity that owns App Store purchase history.

- A Supabase user is an **authentication principal**. Explicit **Sign out** may
  replace it with one fresh anonymous Supabase user.
- A RevenueCat customer used for StoreKit purchases becomes a **purchase
  principal**. It is stable across ordinary authentication sign-in and sign-out
  on the same installation and is never selected from a caller-supplied user ID.
- Promotional, beta, and support-issued access is **account-scoped**. Its
  authority moves to a Supabase-owned grant ledger and does not follow a
  purchase principal to a signed-out or different account session.

The current custom-ID sign-out handoff remains a compatibility protocol until
that separation is deployed. It is fail-closed and release-gated; it is not the
long-term identity model.

Naturebook will not replace the compatibility protocol with a direct RevenueCat
V2 transfer during sign-out. The V2 transfer action can filter by app, but not by
product or purchase provenance, while RevenueCat represents promotional grants
in subscription history. It also documents no request idempotency key. A mixed
StoreKit-plus-promotion customer therefore cannot be transferred while
preserving the product rule that the promotion stays with the linked account,
and an ambiguous network result cannot be retried blindly.

## User-facing contract

The product uses **Sign out**, **Continue with Apple**, and **Continue with
Google**. Anonymous app use is presented as signed out; the internal legacy term
“Ghost” is never user-facing.

Signing out must not:

- delete or merge the linked account;
- silently lose active App Store access;
- clone an account-issued promotion;
- create more than one replacement Supabase identity; or
- report success while purchase continuity is unresolved.

## Target boundaries

```mermaid
flowchart LR
    A["Apple or Google authentication"] --> B["Supabase authentication principal"]
    C["App Store receipt and StoreKit transactions"] --> D["Stable purchase principal"]
    E["Beta, promo, or support grant"] --> F["Account grant ledger"]
    B --> G["Server-authorized active binding"]
    D --> G
    F --> H["Account-scoped entitlement projection"]
    G --> I["Store-backed entitlement projection"]
    H --> J["Effective Merian access"]
    I --> J
```

The server owns the binding between the current authentication principal and a
purchase principal. A client may present a device-held capability, but it may
not nominate either UUID. Bindings are purpose-bound, short-lived where they
authorize a transition, replay-safe for one exact destination, and revocable.

Every database path that can move, detach, or project a stable principal locks
all related principals in UUID order before Auth/public user rows. This includes
Apple/Google profile merge and account deletion as well as resolver completion,
webhooks, and reconciliation; no transition may introduce the inverse lock
order.

The additive implementation introduces a JWT-authenticated
`/resolve-purchase-principal` route. The client submits only a device-held
256-bit installation capability; Edge stores only its SHA-256 digest and
returns a server-owned principal ID, immutable RevenueCat App User ID, and
binding generation. Existing customers are adopted in place when their
canonical custom ID is unclaimed. A collision receives an opaque
`MERIAN_PP_…` identity and requires explicit App Store restore rather than an
unsafe customer claim.

Private binding and webhook evidence retains no provider body or capability.
Account deletion nulls its Auth UUID references while keeping non-identifying
transition and delivery evidence for operations.

Every request also carries a positive device-persisted binding-intent
generation that iOS advances and verifies before network I/O. The server
accepts only a newer intent and requires completion to match it. This is the
ordering authority across cancellation and delayed HTTP execution: an old Auth
request cannot become the final binding merely because it completes last.

RevenueCat webhooks and reconciliation first resolve the private stable mapping
and only then use legacy UUID fallback. StoreKit state, legacy provider state,
and account grants are separate inputs to one effective projection. Stable
StoreKit state includes a durable signed-event policy for detached non-renewing
pass history: first adoption requires an exact locked Supabase expiry match,
purchase evidence may enable it directly, and transfer destinations may inherit
it only from a resolved stable source with an enabled durable policy after an
active App Store pass appears in the destination snapshot. Destination history
alone cannot enable it; revocation/source evidence disables it, and unrelated
webhook or scheduled CustomerInfo reads preserve it. This
prevents RevenueCat's retained refunded transaction history from recreating
access. Provider `TRANSFER` observations mutate StoreKit state only;
promotional state on either side is audited but cannot move or revoke an
account-owned grant; both stable sides are durably fenced from later dual-read
promotion import. Stable customers receive no new account PII or Auth UUID attributes, and first
adoption clears legacy account attributes before paid readiness. Ordinary
same-install sign-out and Apple/Google continuation rebind the same purchase
principal and perform no receipt synchronization or customer transfer.
The global legacy switch is an adoption brake, not an identity rollback:
already active capabilities keep resolving and rebinding their exact stable
principal. A client below the minimum protocol fails closed instead of being
redirected to an Auth-UUID RevenueCat customer.
The iOS client records only a monotonic fingerprint of the capability after
first stable activation—not the provider ID as authority. Thereafter a missing
resolver route or explicit legacy response fails closed, preventing an
operational rollback from becoming a customer-identity downgrade.

## External mutation state machine

Any future migration that changes a RevenueCat customer must reserve the operation in
the database before network I/O. The durable operation records a source,
destination, purpose, attempt lease, and one of `prepared`, `in_flight`,
`outcome_unknown`, `succeeded`, or `failed_terminal`. Provider calls occur
outside database transactions.

After a timeout or lost response, a worker reconciles authoritative source and
destination provider state before deciding whether another mutation is safe.
It never assumes a failed HTTP response means the provider made no change and
never blindly replays a non-idempotent transfer. Logs and aggregate monitors
contain operation counts and ages, not customer identities or provider bodies.
This state machine remains a required future boundary; the current additive
same-install adoption path does not mutate a RevenueCat customer and therefore
does not create a dormant operation ledger.

## Migration sequence

1. **Compatibility safety (implemented in source).** The sign-out proof is
   persisted before local sign-out. The fresh anonymous destination binds before
   RevenueCat linking or receipt synchronization. Pending proof state blocks
   purchase mutations and auth-session rotation. Once bound, it also blocks
   deletion, anonymous-shell cleanup, and profile merge for the protected
   identities. A deletion that wins before binding prevents the provider
   mutation instead of stranding a device-lost proof. The same bound destination
   remains retryable across relaunch and pre-bind expiry. Completion persists
   immutable provider-attested destination StoreKit state; if a prepared finite
   horizon expires first, current source state distinguishes natural expiry
   from a renewal that has not reached the destination.
2. **Account-grant authority (prepared, disabled).** The private, audited
   `account_access_grants` ledger exists in the forward migration. The rollout
   begins in `dual_read`; provider promotions are imported only for comparison.
   `authoritative` may be selected only after an explicit cohort migration,
   projection comparison, issuance cutover, and rollback review.
3. **Purchase-principal introduction (prepared, disabled).** Server-issued
   stable principals, device-capability resolution, binding history,
   principal-aware webhooks/reconciliation, aggregate health, and the iOS
   stable branch are additive. `principal_mode` remains `legacy`, so released
   behavior stays on the compatibility handoff until the backend, minimum
   client version, and provider fixture are approved together.
   Any compatibility proof issued before that cutover remains bound to its
   exact legacy destination UUID through receipt sync and server verification;
   stable adoption begins only after the proof is cleared.
4. **Provider migration.** Use a durable reservation/reconciliation worker for
   any required provider mutation. A controlled RevenueCat sandbox fixture must
   prove active subscription, lifetime/non-renewing purchase, pass, promo-only,
   mixed promo-plus-StoreKit, timeout, duplicate request, refund, and renewal
   cases before rollout.
5. **Cutover and removal.** Webhooks, reconciliation, purchase admission, and
   cross-device restore read the purchase-principal binding. Remove sign-out
   customer transfer and the compatibility handoff only after old-client and
   rollback windows close.

## Cross-device and account switching policy

A signed-in account receives its account grants on every device. Store-backed
access follows a verified purchase principal or an explicit App Store restore;
authentication alone does not claim an unrelated device's purchase history.
The RevenueCat project must use **Transfer to new App User ID**, not legacy
alias sharing, so a restore produces distinct source/destination subjects that
the private resolver can reconcile without merging stable principal identities.
Signing into a different account does not move account grants. Shared-device
sign-out retains only store-backed access authorized for that installation and
must revoke the previous active binding when product policy requires a single
destination.

## Release gates

Source readiness is not production readiness. Static migration contracts,
focused Edge tests, an additive pgTAP fixture, iOS DTO/policy tests, route/ACL
smokes, and principal health monitoring are checked in. Release still requires
replaying the disposable database fixture, two-session lock probes, iOS
kill/relaunch/device tests, clean-device Apple and Google cycles, old-client/new-
backend compatibility, attribute-scrub review for adopted customers, and the
controlled RevenueCat sandbox matrix. Stable mode must remain disabled until
those artifacts are attached to the reviewed exact SHA. Production Supabase,
RevenueCat, TestFlight, and App Store operations remain separately authorized.
