# Native architecture and project rules

Read this reference for application architecture, Swift concurrency, XcodeGen,
dependency injection, persistence ownership, or shared iOS/watchOS code.

## XcodeGen is authoritative

- Root `project.yml` owns targets, sources, build settings, packages, schemes,
  entitlements, and scripts. Change it, run `make xcodegen`, and review the
  generated project diff.
- Do not edit `Merian.xcodeproj` or `merian.xcodeproj` directly. Do not add an
  independent package or build manifest to work around XcodeGen.
- Source directories are globbed. Confirm the relevant target already includes a
  new file, regenerate, then build that target.
- Preserve automatic signing and established bundle identifiers. Signing and
  distribution belong to `$merian-release`, not routine implementation.

## Dependency and state ownership

- Use the existing `AppDIContainer` seams for long-lived services. Prefer
  initializer injection for feature-local dependencies and protocols for
  deterministic tests.
- Avoid a new `@EnvironmentObject` for a heavy manager. Observable UI state may
  be environment-provided only when its ownership and redraw scope are clear.
- Keep UI layers declarative. Repositories, coordinators, and managers own I/O,
  persistence, and long-running work.
- Preserve typed app-event and navigation boundaries. Do not introduce stringly
  notifications or parallel route state.

## Offline and lifecycle guarantees

- A physical capture is durably represented in SwiftData through the existing
  staging/repository/offline queue path before remote work is allowed to own it.
- Treat upload, inference, deletion, and handoff operations as retryable. Keep
  stable identifiers, generation checks, cancellation, and duplicate delivery
  handling intact.
- Views must not launch raw `URLSession` work that bypasses those owners.
- Background task completion must be called exactly once and only after the
  durable state transition required by that task.

## Swift concurrency

- Keep UI mutation on the main actor and expensive image, media, hashing, and
  network work off it.
- Preserve structured task ownership. Capture weak references where lifetime is
  not guaranteed, check cancellation around expensive boundaries, and avoid
  detached work unless the repository already establishes ownership.
- Fix isolation violations at the boundary; do not add blanket
  `nonisolated(unsafe)`, `@unchecked Sendable`, or suppressed diagnostics.

## watchOS and shared sources

- When changing `apps/ios/Shared`, verify every target that compiles the file.
- Keep watch payloads bounded and compatible with intermittent connectivity.
- Do not pull iOS-only frameworks or assumptions into watch targets through a
  shared file.

## Documentation and tests

Update the relevant `docs/` and local README when ownership, state transitions,
payloads, lifecycle behavior, or hardware constraints change. Add focused tests
at the owning layer and use generated-project guardrails for target membership
or build-setting changes.
