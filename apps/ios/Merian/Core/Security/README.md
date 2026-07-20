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
- Unlimited scans remain enabled, so open Settings → Plan directly instead of
  waiting for a quota-triggered paywall.

RevenueCat login and offering availability are independent. `RevenueCat login
succeeded` confirms identity linking only. A complete purchase smoke test must
also load both packages, complete/restore the transaction, and verify the
server-side webhook result where applicable.

## Security invariants

- The Supabase Auth UUID remains the RevenueCat App User ID across anonymous and
  OAuth-upgraded sessions.
- Normal sign-out is device-local and clears RevenueCat/PostHog identity without
  revoking other devices.
- Client SDK keys are extractable app configuration, never service-role or
  provider secrets.
- Errors and identity values use explicit unified-log privacy annotations.

See
[`02-revenue-and-identity.md`](../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
[`05-keychain-and-secrets.md`](../../../../../docs/development-guides/05-keychain-and-secrets.md),
and
[`14-ios-release-versioning.md`](../../../../../docs/development-guides/14-ios-release-versioning.md)
for the full identity, environment, purchase-testing, and release contracts.
