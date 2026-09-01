# Onboarding

Onboarding owns the first-run Welcome → Camera → Location → Ready sequence and
the returning-user Ready presentation selected by the app root. The canonical
behavior, consent, and release contract is
[Onboarding Flow](../../../../../docs/features-and-hardware/04-onboarding.md).

## Ownership

- `Shell/` composes the sequence. Its observable state owner coordinates
  progression and completion through a small injected dependency value;
  `Shell/Services` is the only Onboarding owner that resolves live app settings,
  consent, telemetry, queue recovery, or hardware-animation state.
- `Steps/` owns user-facing copy, layout, UI-only interaction state, and the
  deterministic Ready consent projection. The production shell injects camera
  and location request closures. Compatibility step initializers compose the
  feature-local live permission adapter, but step views contain no native
  permission API calls or app-manager lookup.
- `Permissions/` owns the narrow AVFoundation and Core Location adapters. The
  `@MainActor` location delegate returns nonisolated Core Location callbacks to
  the main actor before reading authorization state, retains exactly one pending
  authorization completion, and clears it before delivery.
- `MerianApp` owns root selection and injects the exact app-scoped manager
  instances into the shell.
- `Core/Security` remains the authority for durable consent evidence,
  account-scoped restoration, and provider admission. Onboarding does not own
  those contracts.

Every production Swift file in this feature remains below the 600-line review
guard. Mirrored tests under `MerianTests/Features/Onboarding` lock presentation,
state, dependency ordering, native-permission confinement, source ownership, and
the line ceiling. Consent ledger, restoration, authority, reapproval, and
lifecycle tests live with their Core owner under
`MerianTests/Core/Security/Consent`.

The Supabase Ghost merge client contract reads
`ConsentManagerAuthorityTests.swift` from that Core test owner to lock pending
consent flush before account refetch. A future test rehome must update that
cross-surface source contract in the same change.
