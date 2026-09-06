# resolve-purchase-principal

JWT-authenticated, additive purchase-identity route. Ordinary `resolve` requests
supply a 256-bit installation capability, protocol version, and device-monotonic
binding intent. Protocol-3 stable sign-out requests instead add one rotation
UUID and one 256-bit secret plus the expected binding generation for
preparation. The Edge function always derives the current Auth user from the
verified JWT, hashes the capability and rotation secret before database calls,
and never accepts a caller-selected Auth, purchase-principal, or RevenueCat
customer ID.

The protocol-3 client uses ordinary `resolve` requests for login and account
continuation. The binding intent is advanced and verified in device-only
Keychain storage before network I/O. Postgres accepts it only when newer than
the last intent for that capability, and completion must match it exactly. This
prevents an older Auth request that finishes late from rebinding the principal
over a newer session.

Stable sign-out is a separate server-owned state machine on the same route:

1. While the exact linked, non-anonymous source JWT is still live, iOS journals
   a random rotation UUID and 256-bit secret, then sends
   `prepare_signout_rotation` with the expected binding generation. Postgres
   stores only the secret hash and reserves that principal for 30 days. The
   device must persist the returned expiry before local sign-out.
2. After local sign-out, only a different anonymous Auth identity created no
   earlier than the reservation may send `claim_signout_rotation`. The claim
   atomically advances the binding and returns its exact principal receipt; it
   does not read RevenueCat or transfer receipts.
3. If the source session remains or is restored before claim, only that exact
   source may send `cancel_signout_rotation`. A write-ahead cancellation also
   tombstones a request whose prepare response was lost.

While a live reservation exists, ordinary resolution and every other binding
writer fail with `purchase_principal_signout_rotation_required`. An unrelated
permanent session therefore cannot become the destination. Completed claims
replay only for the recorded destination with the same secret; terminal rows
reject every other replay. Preparation captures the latest two-phase binding
intent; after claim, cancellation, or expiry, the terminal fence still rejects
every completion begun before preparation. Only a later ordinary begin may
advance above it. iOS retains the Keychain journal and closes all paid readiness
until the exact claim, RevenueCat identity readiness, successful entitlement
session, and the exact anonymous manager-published user, nonexpired SDK session,
current Auth generation, cancellation state, and transition context are
verified, or exact source cancellation is durably confirmed. A retry without a
transition owner becomes stale as soon as another Auth transition opens; durable
proof remains available for the correct session to resume.

The client cannot nominate an Auth UUID, purchase-principal UUID, or RevenueCat
App User ID. Existing customers are adopted in place when safe; otherwise the
server creates an opaque `MERIAN_PP_…` provider ID. StoreKit-backed state is
projected through the active binding. RevenueCat promotional state is imported
to the fixed account-grant owner and does not move during sign-out or account
switching.

An active account-deletion job rejects both database resolution phases. Cleanup
uses the same principal-first lock order, detaches the deleting Auth binding,
erases account-owned grants, and permanently freezes compatibility promotion
import. The non-identifying StoreKit principal survives for the same
installation; a later account cannot inherit the deleted account's provider
promotion.

RevenueCat retains historical non-renewing purchases after refund. First
adoption therefore enables detached `pro_week` inference only when the current
Supabase Pro projection has the exact same finite expiry; completion repeats the
comparison while holding the user row lock. Active principals return and reuse
their durable pass-policy flag. Only signed webhook purchase evidence can later
enable it directly. A transfer destination can inherit an enabled flag only from
its resolved stable source after its authoritative snapshot contains an active
App Store pass; destination history, ordinary resolver reads, and reconciliation
reads cannot enable it.

The rollout configuration returns `mode: legacy` for new or pending capabilities
until operators explicitly enable the stable lane after schema, webhook,
reconciliation, iOS, and provider sandbox gates pass. An already active
capability remains stable and rebindable if rollout returns to legacy; rollback
cannot rotate its provider identity. A below-minimum active client fails closed
with `purchase_principal_client_upgrade_required`. The legacy
`/transfer-signout-purchases` protocol remains unchanged for old clients. After
the first stable response, iOS stores a verified device-only fingerprint of the
exact installation capability. That monotonic evidence is not a provider ID
cache, but it makes any later endpoint `404` or `mode: legacy` response fail
closed instead of re-entering compatibility mode.

Stable rollout requires minimum client protocol 3. The rotation migration may
land only while `principal_mode = legacy` unless the live minimum is already 3;
operators then deploy the protocol-3 Edge/iOS surfaces and separately activate
stable mode at minimum 3. This prevents a protocol-2 stable client from silently
using the former client-only sign-out marker after the server interlock exists.

The installation capability and raw rotation secret are stored only in
device-only Keychain storage on iOS and only as SHA-256 in Postgres. Responses
never echo either secret. Logs must never include either secret or hash, the
rotation UUID, any persisted journal field, provider payload, or user identity.
Aggregate rotation counts and ages are exposed separately through the
service-only health RPC described in the
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#deno-resolve-purchase-principal-edge-node).
