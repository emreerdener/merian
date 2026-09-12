# iOS Core

`Core` contains capabilities shared by more than one product feature. Feature
workflow, screen state, copy, navigation, and one-off presentation stay under
`Features`; backend implementation stays under `services/supabase`.

The canonical inventory is the [codebase map](../../../../docs/codebase-map.md),
and the staged cleanup history and residual owners are recorded in the
[codebase cleanup RFC](../../../../docs/rfcs/codebase-cleanup.md).

## Ownership boundaries

- The Core root contains only `AppDIContainer.swift`, which composes live
  dependencies, and `MerianLog.swift`, which defines logging categories.
- Each domain directory owns its local contract in a `README.md`. New code
  belongs in the narrowest domain; a generic utility is appropriate only when
  its semantics are genuinely mechanical and cross-domain.
- `Policies` contain bounded, stateless decisions and do not resolve live
  network, SwiftData, application, preference, task, or singleton effects. A
  small exact allowlist records the established local-file, clock, and jitter
  inputs used by Offline Sync, Store Recovery, and RevenueCat access policy;
  each domain README owns those semantics.
- Reusable `UI/Components` may render injected values and actions but do not
  issue requests or read persistence directly.
- SwiftData fetch errors are not collapsed with `try?`. A persistence boundary
  distinguishes an absent row from an unreadable store and callers fail closed
  when durable authority cannot be established.
- Local paths, media filenames, raw localized errors, server failure messages,
  credentials, account state, and response bodies remain private or absent in
  unified logging.

## Residual large owners

The post-refactor integration guard intentionally tracks the remaining Core
production files above the 600-line review ceiling:

- `AI/InferenceEngine.swift`
- `Network/ExploreAPIModels.swift`
- `Network/FieldTripAPIModels.swift`
- `Network/SupabaseManager.swift`
- `Security/ConsentManager.swift`

This is a residual inventory, not an exemption for new growth. Split these
owners in behavior-preserving slices, update the inventory in the same change,
and keep wire DTOs separate from UI policy.

## Verification

`MerianTests/Core/Architecture/CoreIntegrationArchitectureTests.swift` freezes
the root/domain inventory, local README coverage, residual large owners,
stateless policy boundaries and their exact documented local inputs,
transport/persistence-free shared components, throwing SwiftData reads, and
privacy-safe diagnostics. Domain suites remain authoritative for behavior; the
Core-wide suite prevents ownership drift between those domains.
