# RevenueCat Ownership

This folder owns RevenueCat-related values, deterministic policy, and the
stateful identity-link coordinator. It does not configure or call the RevenueCat
SDK, resolve Supabase identity, perform provider or UIKit effects, log, or
decide server entitlement.

## Boundaries

- `Models/RevenueCatModels.swift` owns the source-compatible seven-day purchase
  value, manager error, normalized context for legacy subscriber attributes, and
  the typed registry of every legacy attribute key.
- `Policies/RevenueCatIdentityPolicies.swift` owns canonical App User IDs,
  recognized account kinds, admission for provider mutations, purchase
  admission, and reset decisions for identity rebinding. It depends only on
  Foundation.
- `Policies/RevenueCatAccessPolicies.swift` owns the exact `pro_week` and
  `pro_annual` product policy, trusted CustomerInfo verification states, and
  admitted store provenance. It imports RevenueCat only for provider value types
  and performs no SDK calls.
- `Policies/RevenueCatPrivacyPolicies.swift` owns fixed severity-only SDK log
  messages and derives the exact legacy subscriber-attribute deletion map from
  that shared key registry. It never records provider message bodies or customer
  identity.
- `Coordinators/RevenueCatIdentityCoordinator.swift` owns requested and linked
  identity state, binding-generation and account-kind fences, handoff and
  account-grant readiness, and serialized link-task lifetime. It runs injected
  link and paid-readiness-reset closures, waits for cancellation-uncooperative
  provider work before starting its replacement, rejects stale commits, and
  clears only the exact current task. A monotonic handoff generation raised
  while a provider operation is suspended overrides that older operation's
  captured account-grant permission even when the handoff clears before the
  operation resumes. A fresh exact binding begun after that fence may commit
  once the handoff is clear. The coordinator imports no RevenueCat SDK,
  Supabase, UIKit, application singleton, or logger.

`../RevenueCatManager.swift` remains the sole live iOS RevenueCat facade. It
owns SDK configuration and calls, assembles the coordinator's live closures, and
retains observable paid state, offering refresh, purchase and restore,
entitlement projection, UIKit subscription management, and logging. Supabase
purchase-principal resolution and server entitlement authority remain outside
this folder.

## Compatibility and tests

The split changes no product identifier, App User ID casing, subscriber
attribute key, user-facing error, verification decision, store-provenance
decision, SDK behavior, API payload, persistence schema, feature flag, or
release control. Manager, coordinator, and source-boundary suites live under
`MerianTests/Core/Security/RevenueCat/`. Deterministic coordinator tests cover
overlapping cancellation-uncooperative links, invalidation, exact commit
admission, same-provider Auth rebinding, handoff readiness, handoff-versus-link
overlap in both completion orders, post-fence binding admission, sign-out
retention, and manager read-through observation. The architecture guard limits
every file in this folder to 200 lines and the live manager to 600 lines.

See the [Core Security guide](../README.md),
[Core Managers](../../../../../../docs/development-guides/09-core-managers.md),
the
[Revenue and Identity contract](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
and the canonical
[purchase-principal/auth separation RFC](../../../../../../docs/rfcs/purchase-principal-auth-separation.md).
