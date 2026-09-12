# Core Utilities

`Core/Utilities` is the narrow home for small, effect-free helpers that are
genuinely shared across unrelated domains and have no more specific owner.

## Owners

- `DateUtilities.swift` owns the cached standard and fractional ISO 8601
  formatters used across persistence, transport, and presentation boundaries.
- `String+Trimming.swift` owns the shared trim-to-non-empty normalization.

Both files are Foundation-only, contain no observable or mutable workflow state,
perform no I/O, and remain below 100 lines. New code belongs here only when at
least two unrelated domains need the same mechanical value operation.

## Focused owners

The Utilities-wide audit moved declarations that already had a narrower owner:

- App phase orchestration lives in
  [`App/Lifecycle`](../../App/Lifecycle/README.md).
- Intentional detached execution lives in
  [`Core/Concurrency`](../Concurrency/README.md).
- Field-note persistence reconciliation lives in
  [`Core/Data/FieldNotes`](../Data/FieldNotes/README.md).
- Background execution windows and scan connectivity classification live in
  [`Core/Data/OfflineSync`](../Data/OfflineSync/README.md).
- The app-wide error taxonomy lives in [`Core/Errors`](../Errors/README.md).
- The framework Combine bridge lives in
  [`Core/Hardware/Utilities`](../Hardware/README.md#framework-publisher-bridge).
- Bounds-safe array access lives in
  [`Core/UI/Utilities`](../UI/README.md#safe-collection-access).
- Species common-name normalization lives in
  [`Features/SpeciesReference/Models`](../../Features/SpeciesReference/README.md#common-name-presentation).

The retired `MerianConfig.swift` aggregate remains replaced by focused policy
owners beside AI, database, image, media, and Offline Sync behavior. Typed
events and routes remain in [`Core/Routing`](../Routing/README.md).

Do not add lifecycle state, persistence, network or platform effects, feature
terminology, UI, or broad configuration aggregates back to Utilities.

## Verification

`CoreUtilitiesArchitectureTests` freezes the exact two-file production
inventory, Foundation-only/effect-free boundary, 100-line ceiling, relocated
declaration and member owners, mirrored test locations, and retired paths.
`DateUtilitiesTests` and `StringTrimmingTests` cover the retained helper
behavior. Relocated behavior tests live beside their focused owners.
