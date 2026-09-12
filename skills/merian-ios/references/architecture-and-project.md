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

## Local build storage

- Use
  `make ios-local-build ARGS='simulator -- build-for-testing -configuration Debug -destination "generic/platform=iOS Simulator"'`
  for simulator compilation; use `device` for unsigned device compilation. Real
  test execution requires a concrete simulator destination. The wrapper
  preserves Xcode's exit status and keeps console diagnostics visible.
- Reuse `.build/local-ios/simulator` and `.build/local-ios/device` per checkout.
  Package clones and package caches are shared within the checkout. Builds and
  cleanup use one exclusive lock; do not run raw Xcode commands against these
  managed paths or remove their lock file.
- When fresh DerivedData is necessary, put `--isolated` before the platform:
  `make ios-local-build ARGS='--isolated simulator -- build-for-testing -configuration Debug -destination "generic/platform=iOS Simulator"'`.
  Temporary build data is removed after success, failure, or handled
  interruption; result bundles remain under `.artifacts/local-ios`.
- Do not use isolated `build-for-testing` followed by `test-without-building`:
  its build products have already been removed. Use a single isolated `test`
  invocation or the reusable simulator cache for the two-step sequence.
- The wrapper warns below 50 GiB free and refuses a build below 20 GiB. Run
  `make ios-build-storage` for a manual storage report. Stop builds and quit
  Xcode before `make ios-clean-build-cache ARGS=--apply`; omit `ARGS` to
  preview. Cleanup preserves downloaded dependencies, evidence, release
  archives, and all legacy `.build` directories. It refuses removal if process
  inspection fails or any `xcodebuild` is running.
- This wrapper is local unsigned validation only. CI retains its runner-local
  paths, and Xcode Organizer remains the release/archive owner. Keep only
  reports needed for current diagnosis or explicit release evidence; review
  historical `.artifacts/local-ios` reports separately from cache cleanup.

See the canonical
[testing strategy](../../../docs/development-guides/08-testing-strategy.md) for
commands, storage ownership, and legacy cleanup.

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
