---
name: merian-ios
description: "Implement and review Merian Swift, SwiftUI, iOS, watchOS, XcodeGen, dependency-injection, capture, offline-queue, hardware, thermal, memory, Debug-fixture, and UI-test work. Use for files under apps/ios or apps/watch and for project.yml changes. Use merian-swiftdata-migrations instead when the task changes a SwiftData schema version, and merian-release for external publishing or release execution."
---

# Merian iOS

Apply Merian's native architecture and resource limits without weakening the
production capture path for simulator convenience.

## Start with evidence

1. Read `AGENTS.md`, inspect `git status`, and preserve unrelated work.
2. Read `apps/ios/README.md`, the closest feature or manager README, and the
   canonical `docs/` page for the behavior being changed.
3. Trace the production path and its existing seams before introducing a new
   protocol, fixture, singleton, or build flag.
4. If the task changes a SwiftData schema version, stop and load
   `$merian-swiftdata-migrations` before editing an active model.
5. If it crosses a Supabase or wire boundary, also load `$merian-supabase` or
   `$merian-api-contracts` as applicable.

## Route detailed guidance

- Read [architecture-and-project.md](references/architecture-and-project.md)
  for XcodeGen, dependency injection, Swift concurrency, offline ownership, and
  watchOS boundaries.
- Read [capture-performance-and-fixtures.md](references/capture-performance-and-fixtures.md)
  for camera, image/audio/video processing, thermal or memory constraints,
  simulator behavior, previews, Debug seeds, and UI-test fixtures.
- Read both when a feature connects native capture to UI state or persistence.

## Implement safely

- Keep `project.yml` authoritative. Never hand-edit either generated Xcode
  project package.
- Preserve durable capture before network submission. UI code must not bypass
  the repository/queue boundary with ad-hoc networking.
- Inject heavy dependencies through the established `AppDIContainer` and
  initializer/environment seams. Do not add broad `@EnvironmentObject`
  singletons or hidden global state.
- Preserve actor isolation, cancellation, lifecycle, and idempotency contracts.
  Do not silence concurrency errors with unsafe annotations.
- Keep release-only behavior free of Debug fixtures, mock assets, fake
  coordinates, and test launch arguments.

## Verify the affected surface

Run focused tests first. Then run the applicable repository gates, including
`make xcodegen`, `make validate-ios-project`, the relevant focused `xcodebuild`
tests, and `make test-ios-ci-tooling` when CI or Xcode tooling changes. Verify
watch targets when shared sources or project settings affect them. Report any
device, simulator, SDK, signing, or dependency limitation instead of claiming
an unrun test passed.
