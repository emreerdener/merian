# Core Security

The `Security` directory owns client-side identity boundaries that are shared
across features: stable device identity, Keychain-backed flags, RevenueCat
customer/entitlement state, and trust-and-safety guards. Supabase Auth session
creation and OAuth orchestration live in `Core/Network/SupabaseManager`; this
directory provides the secure local primitives and external identity bindings
used by that manager.

## Components

- `DeviceIdentityManager` persists the stable IDFV-backed device identity used
  before Supabase establishes the canonical account UUID.
- `RevenueCatManager` owns customer identity, entitlement state, offerings, and
  purchase/restore entry points.
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

## Security invariants

- The Supabase Auth UUID remains the RevenueCat App User ID across anonymous and
  OAuth-upgraded sessions.
- Normal sign-out is device-local and clears RevenueCat/PostHog identity without
  revoking other devices.
- Client SDK keys are extractable app configuration, never service-role or
  provider secrets.
- The iOS target must never contain `REVENUECAT_WEBHOOK_SECRET`,
  `REVENUECAT_WEBHOOK_SIGNING_SECRET`, or `REVENUECAT_SECRET_API_KEY`; those are
  synchronized only to Supabase Edge.
- RevenueCat-derived plan data is read durably by the backend; entitlement
  lookup failures fail closed before AI provider dispatch.
- Errors and identity values use explicit unified-log privacy annotations.

See
[`02-revenue-and-identity.md`](../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
[`05-keychain-and-secrets.md`](../../../../../docs/development-guides/05-keychain-and-secrets.md),
and
[`14-ios-release-versioning.md`](../../../../../docs/development-guides/14-ios-release-versioning.md)
for the full identity, environment, purchase-testing, and release contracts.
