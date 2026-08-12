# Sign-out purchase handoff

`transfer-signout-purchases` preserves App Store purchase access when a linked
Merian account signs out into a fresh anonymous Supabase account. It does not
move profile data, delete the linked account, or expose the internal term
"Ghost" in product copy.

## Contract

All operations require a live Supabase session and use the caller's JWT. The
function owns authentication through `withEdgeHandler`; `verify_jwt = false` in
`config.toml` avoids gateway coupling to asymmetric JWT rollout.

### Prepare

Request under a non-anonymous account:

```json
{ "operation": "prepare" }
```

The server reads authoritative RevenueCat CustomerInfo for the caller's
canonical uppercase UUID, snapshots only active StoreKit-backed access, creates
a random 256-bit secret, and stores only its SHA-256 hash. The response is
`Cache-Control: no-store`:

```json
{
  "success": true,
  "handoff_id": "uuid",
  "handoff_secret": "43-character-base64url",
  "expires_at": "RFC3339 timestamp"
}
```

The iOS client persists the proof using `whenUnlockedThisDeviceOnly` before it
closes the linked session. If preparation or persistence fails, sign-out does
not begin.

### Bind

Request under the fresh anonymous account:

```json
{
  "operation": "bind",
  "handoff_id": "uuid",
  "handoff_secret": "43-character-base64url"
}
```

The destination is derived only from `auth.uid()`. The private database routine
requires that destination to be anonymous and created no earlier than the
prepared proof, locks both Auth identities in UUID order, and permits one
destination. It refuses to bind either identity while durable account deletion
is active. A replay by that same destination is idempotent; a different
destination cannot consume the proof. The capability expiry limits only this
first bind. Once bound, completion remains retryable after that timestamp
because the App Store receipt may already have moved. The response includes the
derived `destination_user_id`; iOS compares it with the still-active anonymous
session before linking or synchronizing RevenueCat.

### Cancel

If preparation succeeded but local sign-out did not, the restored linked source
may cancel its still-unbound proof. Cancellation derives the source from
`auth.uid()` and is idempotent. A bound or completed handoff cannot be cancelled
because receipt ownership may already have changed.

### Complete

After iOS links RevenueCat to the destination UUID and calls
`Purchases.syncPurchases()`, it submits the same proof with `operation` set to
`complete`. The server verifies authoritative destination CustomerInfo covers
the prepared StoreKit horizon before completing the handoff. If that prepared
finite horizon expired while the handoff was pending, the server refreshes the
source too: a source renewal must be present on the destination, while a source
that is now free permits the transition to finish free. It then schedules
canonical reconciliation for source and destination. Ordinarily it applies the
exact prepared horizon; after natural expiry it applies the exact current
StoreKit state attested on the destination. Detached non-subscription pass
history is excluded from this post-expiry check because a pass cannot renew and
purchase mutations remain fenced during the handoff. Completion stores both the
verified destination snapshot and that StoreKit tier/expiry. If the response is
lost, replay uses the immutable pair rather than depending on later mutable
CustomerInfo; newer provider watermarks still win.

The client deletes the Keychain proof only after server completion and a fresh
Merian entitlement read. Temporary failures retain the proof and block purchase
mutations so app relaunch can safely retry.

## Entitlement policy

- Active subscriptions and StoreKit non-renewing/lifetime purchases transfer
  under RevenueCat's required **Transfer to new App User ID** restore behavior.
- Account-issued promotional and beta grants stay on the linked source account.
  RevenueCat may list them under `subscriptions`, but their v1 record is marked
  `store: promotional`; only an explicit `store: app_store` record is eligible.
  Missing or unknown store discriminators fail closed and are not cloned.
- The source Auth user and profile remain intact. Signing back in uses the
  provider's existing-account path; this protocol performs no data merge.

## Security and operations

- `internal.signout_purchase_handoffs` is RLS-enabled and grants no direct table
  access, including to callers using the service role.
- Only hashed secrets are stored; proof responses and errors are never logged.
- Source and destination IDs are never caller-selected.
- Database routines have an empty `search_path`, explicit grants, deterministic
  locking, finite timeouts, and idempotent same-destination receipts.
- A pending prepared or bound source and a bound destination cannot enter
  account deletion. A bound destination is also ineligible for automatic
  anonymous-shell cleanup and cannot start or complete profile merge.
- RevenueCat network calls occur outside database transactions.
- The Edge Function requires `REVENUECAT_SECRET_API_KEY` (`sk_...`). Never put
  this secret in iOS configuration or logs.

Deploy the migration and this function before releasing an iOS client that calls
it. Deployment and RevenueCat project changes remain separately approved
operations.

This handoff is the compatibility path, not the target identity architecture. An
already-issued proof remains immutable if stable-principal rollout is enabled
mid-transition: iOS must link/sync/verify the exact legacy destination UUID,
clear the proof, and only then resolve a stable principal. The accepted
long-term boundary is documented in
[`purchase-principal-auth-separation.md`](../../../../docs/rfcs/purchase-principal-auth-separation.md).
Do not substitute RevenueCat V2 customer transfer: it cannot filter mixed
StoreKit and promotional subscription history by provenance and documents no
request idempotency key.
