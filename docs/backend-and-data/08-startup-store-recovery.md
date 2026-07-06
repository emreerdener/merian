# Startup Store Recovery

Merian must never turn a damaged local SwiftData store into account loss. This
document defines the startup recovery contract for `ModelContainer` failures,
quarantined local store files, telemetry, and verification.

## Ownership

| Area                         | File                                                                                                                        | Responsibility                                                                                                                                                                             |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| App bootstrap                | `apps/ios/Merian/App/MerianApp.swift`                                                                                       | Orchestrates startup, builds the model container, shows safe-mode notices, and emits recovery telemetry after analytics starts.                                                            |
| Objective-C exception bridge | `apps/ios/Merian/App/MerianObjCExceptionBridge.*`                                                                           | Converts Objective-C `NSException`s raised by SwiftData/Core Data into Swift errors.                                                                                                       |
| Store recovery policy        | `apps/ios/Merian/Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift`                                               | Reads store metadata for migration strategy selection, detects corruption signatures, quarantines local store artifacts, and writes support manifests.                                     |
| Tests                        | `apps/ios/MerianTests/App/ModelStoreRecoveryCoordinatorTests.swift`, `apps/ios/MerianTests/Models/MigrationPlanTests.swift` | Verifies store-aware migration hints, duplicate-checksum detection, corruption gating, manifest writing, recent source-isolated migration plans, and isolation from auth/session managers. |
| CI guardrails                | `.github/workflows/ios-startup-safety.yml`                                                                                  | Runs focused startup store-recovery tests on macOS.                                                                                                                                        |

## Startup Open And Recovery Ladder

1. Inspect the on-disk SwiftData store metadata before creating the persistent
   `ModelContainer`.
2. Choose the narrowest safe startup strategy:
   - no store artifacts or current-schema store → open without a migration plan
   - known recent source store (V44, V45, V46, or V47) → open with the matching
     source-isolated recent migration plan
   - unknown older store → open with the full historical `MerianMigrationPlan`
3. If SwiftData reports duplicate version checksums, retry through the
   source-isolated ladder: current-store open, then V47, V46, V45, and V44.
   The V45/V46 retry plans keep those source representatives isolated from each
   other and use direct V48 targets because V46 was a shipped no-op schema; V47
   also reuses the V45 representative for unchanged model classes and only
   introduces the queued-scan model change on V43/V44 paths.
4. If SwiftData/Core Data raises an Objective-C exception, the bridge converts
   it into an error so the Swift recovery path can continue.
5. Inspect the full error chain for verified SQLite/Core Data corruption
   signatures.
6. If the error is corruption and `default.store` artifacts exist, quarantine:
   - `default.store`
   - `default.store-shm`
   - `default.store-wal`
7. Retry the persistent `ModelContainer` exactly once using the same store-aware
   strategy selection.
8. If recovery still fails, boot an in-memory safe-mode container and show a
   startup notice.
9. If even the in-memory container fails, show the startup-blocked fallback UI.

Generic startup failures must not move local store files. They skip quarantine
and go directly to safe mode.

## Quarantine Manifest

Every quarantine directory includes `recovery-manifest.json`. It is
intentionally small and support-oriented:

- schema version
- timestamp
- app version and build number
- OS version
- sanitized error domain/code/description/failure reason
- moved artifact filenames

The manifest must not include:

- Supabase access or refresh tokens
- Keychain values
- user IDs, usernames, or emails
- scan IDs or species names
- full local filesystem paths outside the quarantine directory

## Identity Boundary

Store recovery is local persistence repair only. It must never call or
reference:

- `KeychainManager`
- `SupabaseManager`
- `PostHogManager.shared.reset`
- `signOut`
- `initializeGhostSession`
- `currentUser`

This boundary preserves the signed-in account and keeps public Explore ownership
attached to the cloud user even when local SwiftData needs repair.

## Telemetry

`MerianApp` emits `StartupStoreRecovery` after `AppTelemetry.initialize()` with
only coarse string properties:

| Property  | Examples                                                                                                                                 |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `outcome` | `recovered`, `safe_mode`, `blocked`                                                                                                      |
| `reason`  | `corruption_quarantined`, `persistent_store_migration_failed`, `persistent_store_unavailable`, `persistent_and_memory_store_unavailable` |

Do not attach exception text, local paths, user IDs, scan IDs, or account state
to this event.

## Project Guardrails

`make validate-ios-project` checks that:

- markdown documentation is not bundled into iOS app resources
- `MerianObjCExceptionBridge.m` is present in the app target
- `SWIFT_OBJC_BRIDGING_HEADER` points at
  `apps/ios/Merian/Configuration/Merian-Bridging-Header.h`

Run it after XcodeGen changes.

## Verification

Fast local checks:

```sh
make validate-ios-project
jq empty apps/ios/Merian/Resources/Changelog/changelog.json
swiftlint lint \
  apps/ios/Merian/App/MerianApp.swift \
  apps/ios/Merian/Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift \
  apps/ios/Merian/Core/Analytics/AppTelemetry.swift \
  apps/ios/MerianTests/App/ModelStoreRecoveryCoordinatorTests.swift \
  apps/ios/MerianTests/Models/MigrationPlanTests.swift \
  apps/ios/MerianTests/Core/Analytics/AppTelemetryTests.swift
git diff --check
```

Focused Xcode lane:

```sh
destination="$(bash scripts/select-ios-simulator-destination.sh)"
xcodebuild test \
  -scheme Merian \
  -project Merian.xcodeproj \
  -destination "$destination" \
  -only-testing:merianTests/ModelStoreRecoveryCoordinatorTests \
  -only-testing:merianTests/MigrationPlanTests
```

In sandboxed environments, Xcode may fail before source compilation if it cannot
write SwiftPM diagnostics under `~/Library/Caches/org.swift.swiftpm`. Treat that
as an environment issue, not a recovery-code failure, and run the focused lane
in a normal local or GitHub macOS runner.

`MigrationPlanTests` intentionally keep disk-backed SwiftData store files alive
for the test-process lifetime instead of deleting them in test cleanup. Core
Data can retain SQLite/WAL descriptors after the last visible `ModelContainer`
falls out of scope, and unlinking those files in-process can compromise later
fixtures with sqlite `vnode unlinked while in use` traps.

The GitHub Startup Safety workflow is scoped to iOS/project/workflow path
changes, cancels stale runs on the same ref, restores Swift package checkouts,
saves newly fetched checkouts even after a failure, and splits Xcode into two
bounded phases: `build-for-testing` compiles the app/test bundle, then
`test-without-building` runs only the startup and migration tests from the same
derived-data folder. Build failures should therefore appear as build diagnostics,
while runtime migration failures should appear as selected test failures. On
failure it prints the `.xcresult` test-failure summary when one exists, appends
build diagnostics when Xcode fails before the test phase, and uploads the
`.xcresult` bundle plus extracted JSON summary so simulator hangs or compiler
diagnostics remain inspectable without rerunning the log loop.
