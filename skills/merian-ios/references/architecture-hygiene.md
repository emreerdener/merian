# iOS architecture hygiene

Read this reference for folder cleanup, file splitting, component naming,
dependency extraction, DRY consolidation, or a feature/Core integration audit.
The durable repository policy is
[`docs/development-guides/19-code-ownership-and-refactoring.md`](../../../docs/development-guides/19-code-ownership-and-refactoring.md).

## Start from ownership, not line count

1. Inventory every production declaration, extension, direct dependency,
   consumer, test, route, and documentation claim in the chosen scope.
2. Define the behavior and visual-parity contract: public/internal initializer
   signatures, routes, copy, accessibility identifiers and values, layout,
   loading/error states, lifecycle callbacks, media behavior, animation,
   cancellation, focus, and persistence semantics.
3. Map each responsibility to the narrowest honest owner before moving code.
4. Record the pre-change file and production-line inventory so the handoff can
   show the affected delta rather than citing gross repository growth.

## Extract cohesive owners

- Prefer product-area-first folders. Within a sufficiently large area, use
  `Models`, `Services`, `ViewModels`, `Views`, and focused `Components` only
  where each folder expresses a real boundary.
- Views own transient selection, gallery, focus, scroll-proxy, and presentation
  timing when moving it would alter SwiftUI identity or animation. Views do not
  own networking or broad SDK resolution.
- View models own main-actor presentation and interaction state. Inject narrow
  dependency closures or existing interfaces; do not add a singleton or a
  protocol with only speculative value.
- Services own I/O and endpoint adaptation. Domain/wire models stay with their
  true contract owner.
- A shared owner is justified by multiple real consumers and neutral semantics,
  not by a generic name. Keep feature-owned code in the feature.

## Avoid extraction debt

- Do not split a file solely to satisfy a number. A review ceiling is a signal
  to find responsibilities, not a reason to create pass-through wrappers,
  one-value files, or visibility widening.
- Co-locate tightly coupled policy values and helpers when separation adds no
  independently testable boundary.
- Preserve `private` and `fileprivate` scope. If extracted mutable state would
  become module-internal, create a contained state owner or keep it with its
  lifecycle owner.
- Consolidate duplicated behavior only after proving the variants share one
  invariant. Preserve typed endpoint actions and completion callbacks around a
  normalized presentation model.
- Remove obsolete declarations and duplicate extensions only after repository-
  wide consumer searches and focused tests prove they are unused.

## Review the result

- Report production lines added and removed, files added and removed, largest
  remaining owners, and any intentionally retained exception.
- Search for newly widened access, hidden singleton resolution, direct network
  calls in views/components, duplicate formatting/policy code, stale docs, and
  test ownership drift.
- Run focused tests throughout, then the owning feature's integration audit,
  project/source membership checks for moves, XcodeGen when groups change, and
  the complete relevant target.
- Stop extracting when the remaining owner is cohesive or the next split would
  increase indirection without improving correctness, isolation, navigation, or
  testability. Record that stopping decision instead of manufacturing another
  slice.
