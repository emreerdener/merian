# Startup Store Recovery

Naturebook must never turn a damaged local SwiftData store into account loss.
This document defines the startup recovery contract for `ModelContainer`
failures, quarantined local store files, legacy-store rescue archives,
telemetry, and verification.

## Ownership

| Area                         | File                                                                                                                                           | Responsibility                                                                                                                                                                                                                                                                                      |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App bootstrap                | `apps/ios/Merian/App/MerianApp.swift`                                                                                                          | Orchestrates startup, builds the model container, shows safe-mode/recovery notices, and emits recovery telemetry after analytics starts.                                                                                                                                                            |
| Objective-C exception bridge | `apps/ios/Merian/App/MerianObjCExceptionBridge.*`                                                                                              | Converts Objective-C `NSException`s raised by SwiftData/Core Data into Swift errors.                                                                                                                                                                                                                |
| Store recovery policy        | `apps/ios/Merian/Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift`                                                                  | Reads store metadata for migration strategy selection, detects corruption signatures, archives unrecoverable legacy stores, quarantines corrupt local store artifacts, and writes support manifests.                                                                                                |
| Tests                        | `apps/ios/MerianTests/App/ModelStoreRecoveryCoordinatorTests.swift`, `apps/ios/MerianTests/Models/MigrationPlanTests.swift`                    | Verifies store-aware migration hints, duplicate-checksum detection, corruption gating, legacy rescue, manifest writing, recent source-isolated migration plans, and isolation from auth/session managers.                                                                                           |
| Startup CI guardrails        | `.github/workflows/ios-project-guardrails.yml`, `.github/workflows/ios-startup-safety.yml`, `scripts/check-ios-migration-source-guardrails.sh` | Runs fast source/project/release-tooling checks on Ubuntu, then focused startup store-recovery and migration tests on macOS when startup inputs change.                                                                                                                                             |
| Broad compiled CI            | `.github/workflows/ios-build-and-test.yml`, `scripts/check-ios-project-source-membership.sh`, `scripts/validate-ios-critical-test-results.sh`  | Compiles both shared test bundles, executes the complete unit-test target including the startup suites, runs all four deterministic progressive-analyzing, live-to-queue, queued-retry, and queued-completion UI smokes, and independently verifies an exact-SHA unsigned Release archive and dSYM. |

Startup Safety is a focused drift and migration-diagnostic lane, not the only
compile gate. Every build-relevant startup or schema change must also pass
`iOS Build and Test / Production readiness`.

## Startup Open And Recovery Ladder

1. Inspect the on-disk SwiftData store metadata before creating the persistent
   `ModelContainer`.
2. Choose the narrowest safe startup strategy:
   - no store artifacts or current-schema store → open without a migration plan
   - known recent source store (V42, V43, V44, V45, V46, V47, V48, V49, or V50)
     → open with the matching source-isolated recent migration plan
   - unknown older store → open with the full historical `MerianMigrationPlan`
3. If SwiftData reports duplicate version checksums, retry through the
   source-isolated ladder: current-store open, then V50, V49, V48, V47, V46,
   V45, V44, V43, and V42. V50 uses an isolated one-stage lightweight plan so a
   released V50 store only validates the tombstone rename. V49 uses its
   two-stage lightweight plan to reach V51 without validating unrelated
   historical stages. The V45/V46 retry plans keep those source representatives
   isolated from each other and use direct V49 targets because V46 was a shipped
   no-op schema; V47 uses its own source-isolated V47→V49 plan with
   self-contained V47 model classes and scalar queued-scan snapshots. V48 has
   two isolated V48→V49 lanes: the known-good V48 source and the accidental
   optional-queue V48 TestFlight source. V42 and V43 use short direct V49 plans
   to avoid validating older full-historical custom stages; V42 deliberately
   skips the older V42→V43 bridge because real TestFlight V42 stores still fell
   back to safe mode there. Every selected older repair lane then applies the
   shared lightweight V49→V50 and V50→V51 stages; stores already stamped V51
   open as current stores without a plan.
4. If SwiftData/Core Data raises an Objective-C exception, the bridge converts
   it into an error so the Swift recovery path can continue.
5. Inspect the full error chain for verified SQLite/Core Data corruption
   signatures.
6. If the error is corruption and `default.store` artifacts exist, quarantine:
   - `default.store`
   - `default.store-shm`
   - `default.store-wal`
7. Retry the persistent `ModelContainer` exactly once after quarantine.
8. If the error is not corruption but the selected startup strategy was a legacy
   migration path (`recent-source-v42`...`recent-source-v49` or
   `full-historical`), archive the same store artifacts under `store-rescue/`
   and open a fresh persistent current-schema store. This breaks repeated
   SwiftData migration failures out of the safe-mode loop while preserving the
   old files for support or future import work.
9. If recovery still fails, boot an in-memory safe-mode container and show a
   startup notice.
10. If even the in-memory container fails, show the startup-blocked fallback UI.

Generic current-store startup failures must not move local store files. They
skip quarantine/rescue and go directly to safe mode.

## TestFlight Diagnostic Expectations

For a legacy V42/V43/V44/V45/V46/V47/V48/V49/V50 store that cannot migrate but
is not corrupt, the expected diagnostic shape is:

- `selectedStrategy`: the matching `recent-source-vNN` strategy, or
  `full-historical` for unknown older stores
- first failed attempt: the selected migration plan, such as `recent-v42`
- rescue attempt: `post-migration-rescue-current-store`
- `finalOutcome`: `recovered`
- `finalReason`: `legacy_store_rescued`
- `quarantineAttempted` / `quarantinePerformed`: `false`
- `rescueAttempted` / `rescuePerformed`: `true`

If the final outcome is still `safe_mode` after a legacy source migration
failure, treat that as a release-blocking regression unless the diagnostic shows
`persistent_store_rescue_failed`. Current-schema stores are different: a generic
current-store open failure should still keep the files in place and use safe
mode rather than archive user data.

## V49→V50 Release Acceptance (Historical)

The historical V50 candidate froze all eight V49 models in
`SchemaV49Snapshots.swift`, uses V49-qualified relationship endpoints, and keeps
V50 on active global models. Source guardrails reject an active-type alias and
pin the complete frozen snapshot file SHA-256, so persisted-property,
annotation, default, relationship, initializer, or helper drift cannot pass
accidentally. The disk suite creates a source store from the new snapshots,
seeds every V49 entity plus both relationship directions, and opens V50 through
the production source-isolated plan. That proves candidate-self consistency. It
does not measure or reproduce the model identity emitted by the processed
released V49 binary, and it does not turn a test-created store into release
evidence.

The disk-backed simulator fixture proves the migration implementation, emitted
store metadata, and production plan selection. It does not prove that an
installed store created by the released V49 binary survives an application
upgrade on a physical device. Before promoting a V50 candidate beyond the
bounded internal QA group, complete this install-over gate against the exact
processed candidate build:

1. Start from a clean, committed candidate SHA whose **iOS Build and Test /
   Production readiness** result and unsigned Release archive are green.
2. Use a dedicated non-production iPhone on a supported iOS version. Install a
   genuine released V49 binary and let that binary create the store; a
   test-created V49 SQLite fixture or a locally modified V49 build is not
   release evidence.
3. While running V49, create representative offline queue state: an image row, a
   video row, and a mixed-media or description-bearing row. Retain the queue
   media and scheduler state through app termination.
4. Record only sanitized pre-upgrade evidence: app/build, source identity,
   device/OS, current schema V49, and presence of store artifacts. Do not retain
   the raw store, local paths, account identifiers, scan IDs, notes,
   coordinates, or media in the release record.
5. Install the exact V50 candidate over V49 without deleting the app or its
   data, then launch it while collecting the app's public device-console output.
   `ModelContainer bootstrap diagnostics` must show `currentSchema=V50` and the
   candidate source identity; `ModelContainer store-aware migration selection`
   must show `hasStoreArtifacts=true`, `storedSchema=V49`, and
   `strategy=recent-source-v49`. Reaching the normal app UI with no recovery
   notice or safe mode is the required successful-open evidence.
6. If approved internal tooling can retrieve the locally persisted
   `StartupStoreDiagnostic`, cross-check `currentSchemaMajor: 50`,
   `store.storedSchemaMajorVersion: 49`, `selectedStrategy: recent-source-v49`,
   and an `attempts` entry with `name: recent-v49` and `outcome: success`. Do
   not require snake-case recovery telemetry: a normal successful migration does
   not emit a `StartupStoreRecovery` event.
7. Verify every representative queue row, media reference, durable retry field,
   and scheduler record survived. Existing V49 rows must have no spontaneous
   `OfflineQueuedScanGoalHint`; V49 stored no goal selection to backfill.
8. Force-quit and relaunch the V50 candidate. The second launch must select
   `current-store`, retain the migrated queue, and produce no recovery notice.
9. Separately create fresh eligible V50 queue rows and verify goal-hint
   persistence in distinct foreground- and background-completion paths, plus
   relaunch, successful progress acknowledgement, and cancellation/orphan
   cleanup.
10. Record the sanitized diagnostic outcomes and pass/fail decision against the
    exact App Store Connect build in the restricted release record.

## V50→V51 Release Acceptance

V51 is the active schema. It keeps the V50 graph frozen in
`SchemaV50Snapshots.swift`, maps `ScanCollection.isPendingDeletion` to the
released `isDeleted` column with `@Attribute(originalName:)`, and preserves the
`is_deleted` wire field. The source-isolated `MerianRecentV50MigrationPlan`
contains one lightweight V50→V51 hop; `MerianRecentV49MigrationPlan` contains
V49→V50 followed by V50→V51. The local disk fixture is candidate-self
consistency evidence, not a substitute for a genuine released-binary install
over.

For the exact processed V51 candidate build, use a dedicated non-production
device whose store was created by the released V50 binary. Record only sanitized
device/build/source identity and schema metadata, then install V51 over V50
without deleting app data. Successful evidence must show `currentSchema=V51`,
`storedSchema=V50`, `strategy=recent-source-v50`, a successful `recent-v50`
attempt, normal UI (no recovery notice or safe mode), and preservation of queued
scans, media, retry state, goal hints, collection tombstones, and relationships.
Force-quit and relaunch must select `current-store` and retain the migrated
state. Verify a true tombstone emits `is_deleted: true`, resists delayed inbound
upserts, and is purged only after the matching cloud acknowledgement. A V50
assignment that was never durable must not be inferred by migration. Preserve
failed devices and artifacts for diagnosis; do not uninstall, delete the store,
or count recovery into a fresh store as migration success.

Wrong plan selection, safe mode, rescue/quarantine, missing queue or media
state, synthesized hints, or a relaunch failure blocks promotion. Preserve the
device and evidence for diagnosis; do not uninstall the app, delete the store,
or treat recovery into a fresh store as migration success. The operator flow is
also required by the
[iOS release runbook](../development-guides/14-ios-release-versioning.md#schema-upgrade-acceptance-gate).

## Archive Manifest

Every quarantine or rescue directory includes `recovery-manifest.json`. It is
intentionally small and support-oriented:

- schema version
- timestamp
- app version and build number
- OS version
- archive reason (`corruption_quarantine` or `legacy_migration_rescue`)
- sanitized error domain/code/description/failure reason
- moved artifact filenames

The manifest must not include:

- Supabase access or refresh tokens
- Keychain values
- user IDs, usernames, or emails
- scan IDs or species names
- full local filesystem paths outside the archive directory

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

## “Archived” Terminology and Cloud-Media Boundary

`store-rescue` **archives local SQLite artifacts for support**. It does not:

- set every scan's `isLocallyArchived` flag;
- delete a Supabase scan or Explore post;
- call Cloudflare R2; or
- remove an object under `public_uploads/free/` or `public_uploads/pro/`.

Likewise, a Scan Library “Visuals archived” placeholder describes the local
record/presentation state; it is not evidence that cloud bytes were moved into
an R2 archive tier. R2 has no product “archived scan” state.

A migration rescue can still make an image problem more visible: the fresh
SwiftData store rehydrates cloud rows containing R2 URLs, so the device depends
on those URLs unless a surviving Documents file can be reconnected. If the R2
object is independently missing, the rehydrated row remains but image loading
returns 404.

`LocalScanMediaRecoveryResolver` may read preserved `store-rescue` databases
with read-only SQLite access to align the old local filename/media order with
the same current scan ID. That is a separate post-startup media-recovery lane;
it never mutates the rescued database. See
[`system-architecture/03-image-pipeline.md`](../system-architecture/03-image-pipeline.md)
and the
[July 2026 incident report](../incidents/2026-07-account-scoped-r2-image-loss.md).

## Telemetry

`MerianApp` emits `StartupStoreRecovery` after `AppTelemetry.initialize()` with
only redacted string properties:

| Property                | Examples                                                                                                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `outcome`               | `recovered`, `safe_mode`, `blocked`                                                                                                                              |
| `reason`                | `corruption_quarantined`, `legacy_store_rescued`, `persistent_store_rescue_failed`, `persistent_store_unavailable`, `persistent_and_memory_store_unavailable`    |
| `selected_strategy`     | `current-store`, `recent-source-v50`, `recent-source-v49`, `recent-source-v48`, `full-historical`                                                                |
| `current_schema_major`  | `51`                                                                                                                                                             |
| `stored_schema_major`   | `50`, `49`, `48`, `none`                                                                                                                                         |
| `attempts`              | `recent-v50:failure,post-migration-rescue-current-store:success`, `recent-v49:failure,...`, or `recent-v48-known-good:failure,recent-v48-optional-queue:success` |
| `metadata_fingerprints` | Core Data model/version metadata keys with SHA-256 value fingerprints                                                                                            |
| `first_error`           | error domain, code, and fingerprints of description/failure/debug text                                                                                           |
| `quarantine_attempted`  | `true`, `false`                                                                                                                                                  |
| `quarantine_performed`  | `true`, `false`                                                                                                                                                  |
| `rescue_attempted`      | `true`, `false`                                                                                                                                                  |
| `rescue_performed`      | `true`, `false`                                                                                                                                                  |

The latest startup diagnostic is also persisted locally and shown as a
TestFlight/debug share action on the safe-mode/recovery card. Do not attach raw
exception text, local paths, user IDs, scan IDs, scan text, media URLs, or
account state to this event or diagnostic payload.

A normal successful migration has no recovery card and does not emit
`StartupStoreRecovery` telemetry. Its minimum release evidence is therefore the
public bootstrap/selection device logs plus a normal open and relaunch. Treat
the persisted camelCase JSON as an optional cross-check only when approved
internal tooling can retrieve it without modifying the exact candidate or
exposing app data.

## Project Guardrails

`make validate-ios-project` checks that:

- markdown documentation is not bundled into iOS app resources
- `MerianObjCExceptionBridge.m` is present in the app target
- `SWIFT_OBJC_BRIDGING_HEADER` points at
  `apps/ios/Merian/Configuration/Merian-Bridging-Header.h`

`make validate-ios-migration-guardrails` checks the SwiftData migration source
contract before Xcode compiles anything. It keeps the full runtime migration
path on V42->V49 and V43->V49, keeps duplicate-prone V44/V45/V46/V47
representatives out of that full path, verifies V42/V43/V44/V45/V46/V47
source-isolated plans target V49 directly, verifies the known-good and
optional-queue V48 recovery plan source, guards the legacy migration-rescue
escape hatch, requires the isolated V49→V51 and V50→V51 plans and runtime
selection, pins the frozen V49 and V50 snapshots, and verifies the active
`isPendingDeletion`/`isDeleted` mapping plus unchanged `is_deleted` projection.
It also guards the disk-backed migration tests from unlinking SQLite files and
locks checksum retry order to current store, then V50 through V42, newest to
oldest. The exhaustive recent-source enum must remain consecutive and end at the
schema immediately before `CurrentSchema`; the app has no generic recent
fallback, so adding a future source case also requires a dedicated runtime plan
at compile time. Runtime tests separately assert that V48 required-value
validation failures are rescue-eligible because current SwiftData may reject
malformed historical V48 rows before a repair migration can run. The V49 and V50
disk fixtures invoke the same production metadata decision used at launch, prove
stored majors `49` and `50` select `.recentSource(.v49)` and
`.recentSource(.v50)`, and then open through their corresponding plans.

Run both after XcodeGen changes.

## Verification

Fast local checks:

```sh
make validate-ios-project
make validate-ios-migration-guardrails
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

The GitHub Startup Safety workflow is scoped to startup/schema/recovery/project
path changes plus a daily scheduled drift check. Workflow, Makefile, and helper
script edits still start the workflow so the cheap guardrails validate, but the
simulator lane is skipped unless the changed files touch the startup-recovery
runtime contract, the workflow is started manually, or the daily schedule runs.
Ordinary iOS UI changes keep running the cheap project guardrails, but they do
not automatically boot a macOS simulator. Startup Safety cancels stale runs on
the same ref, restores Swift package checkouts only when the simulator lane is
needed, saves newly fetched checkouts even after a simulator failure, and runs
the source migration guardrail before selecting a simulator. It then splits
Xcode into two bounded phases: `build-for-testing` compiles the app/test bundle,
then `test-without-building` runs only the startup and migration tests from the
same derived-data folder. Build failures should therefore appear as build
diagnostics, while runtime migration failures should appear as selected test
failures. On failure it prints the `.xcresult` test-failure summary when one
exists, appends build diagnostics when Xcode fails before the test phase, and
uploads the `.xcresult` bundle plus extracted JSON summary so simulator hangs or
compiler diagnostics remain inspectable without rerunning the log loop.
