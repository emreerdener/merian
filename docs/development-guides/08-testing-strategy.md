# Merian Testing & Quality Assurance Strategy

Merian uses a lightweight, Swift-native testing structure built on the `Testing`
framework, isolating offline UI queues and core engine components from Apple
lifecycle dependencies.

The public web app in `apps/web/` has its own checks:

```bash
cd apps/web
npm test
npm run typecheck
npm run build
npm run audit:dependencies
```

Run these when changing Next.js routes, Mantine UI, public metadata, Supabase
web access, canonical `naturebook.earth` sharing, or legacy `merian.earth`
compatibility. Open Graph routes should remain server-rendered so link unfurlers
can read metadata without client hydration. `lib/explorePoster.test.ts` locks
detail/social spectrogram precedence and the grid-only species-reference policy.
`lib/exploreVisualMedia.test.ts` locks canonical mixed-media ordering and
deduplication. `lib/audioProxy.test.ts` locks the Boost Audio stream to public
Naturebook WAV URLs on the exact durable `media.merian.app` technical host and
rejects arbitrary hosts, staging paths, credentials, and unsupported formats.
`lib/supabaseBoundary.test.ts` locks Explore to the `server-only` client and its
two dedicated fixed-anonymous RPCs; it rejects a public-client fallback,
synthetic viewer ID, direct user-table enrichment, or native Explore RPC.
Browser verification should cover Boost → Boosted → original transitions because
Web Audio context activation cannot be proven by TypeScript alone.

The private admin app in `apps/admin/` has an independent production gate:

```bash
cd apps/admin
npm ci
npm run audit:dependencies
npm test
npm run typecheck
npm run build
```

Run the complete sequence for admin authentication, AAL2/RBAC, Server Actions,
moderation, access, reporting, or dependency changes.
`lib/admin-foundation.test.ts` scans the complete production TypeScript source
graph with the TypeScript parser, rejects executable service-role/secret-key
references, rejects computed or whole-object `process.env` access, and
enumerates every environment read against the exact public allowlist. It also
checks the active `.env.example` keys and placeholders, so a safety comment is
not mistaken for executable credential use. `lib/dependency-security.test.ts`
rejects frozen Next.js, PostCSS, or Sharp versions below the reviewed floors and
protects the CI command order. `.github/workflows/admin-quality.yml` runs the
frozen install, live high-severity audit, tests, TypeScript check, and
production build for every pull request and every affected `main` push. It
intentionally avoids pull-request path filters so a required check always
reports. A high/critical advisory or unavailable audit registry blocks this
high-sensitivity deployment. Configure the repository ruleset to require
`Naturebook Admin Quality / test`, then add the same GitHub Action as a required
Vercel Deployment Check. Checked-in workflow YAML creates the check but does not
itself prevent a direct merge or production promotion.

The complete Supabase Edge source/unit suite is the checked-in Deno task:

```bash
cd services/supabase/functions
deno task test
```

Its narrow read allowlist includes the full function tree and the repository
surfaces inspected by security contracts: migrations, Supabase config, the
complete pgTAP fixture directory, Supabase scripts, the repository workflow
directory, iOS source surfaces used by cross-boundary contracts, and the web
waitlist route. Deployment CI runs this task after the disposable database is
migrated, so database-backed cases execute rather than reporting connection
skips; its explicit `SUPABASE_DB_TEST_URL` makes an unavailable database a test
failure. CI must run the complete task rather than substituting a hand-selected
subset whose permissions happen to pass. Pure request-mapping tests, including
`sync-collections/index.test.ts`, never conditionally write to credentials
inherited from the developer shell. Live database behavior belongs to the
disposable catalog or an explicitly configured `SUPABASE_DB_TEST_URL` test that
fails when it cannot connect.

The complete repository-tooling suite is a separate discovery-based gate:

```bash
deno fmt --check services/supabase/functions services/supabase/scripts
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions services/supabase/scripts
make test-supabase-tooling
```

`test_supabase_tooling.sh` type-checks every standard TypeScript script and runs
every conventionally named `*_test.ts`, so the ghost-user audit and cleanup
tests cannot fall out of CI through list drift. It separately exercises the
frozen executable DTO contract and Swift generator, syntax-checks every shell
script, runs every `*_test.sh`, and rejects complete provider-shaped
`sb_secret_…` literals anywhere in the repository. Format-valid secret-key
fixtures must be assembled at runtime from separate fragments; diagnostics
identify only matching filenames so the gate cannot echo an accidentally
committed credential. `tooling_gate_test.ts` protects that discovery policy. The
same test locks `validate_migration_contracts.sh`, the discovery-based
source-migration entrypoint shared by `make validate-supabase-migrations` and
the production deploy lane.

`_tests/workflowSecurity.test.ts` scans every checked-in GitHub Actions
workflow. It rejects mutable third-party action tags, missing explicit
workflow-level permissions, secret references outside individual steps, and
unexpected `contents: write`. Keep it in both the complete Edge suite and the
focused deployment-planner gate so supply-chain regressions fail before any
production credential or migration is used.

Explore database fixtures must represent the canonical write model. The shared
post helper snapshots media through `refresh_explore_post_media`; disable that
step only for deliberate partial-write/no-media cases or when the test inserts
its own media rows. Scan geoprivacy does not hide a shared post, and clearing a
scan's source URL array does not erase an already published post snapshot.
Negative SQL assertions inside a transaction must use a savepoint so the
expected error does not abort later assertions. Community-resolved fixtures must
create the matching request and set `explore_published_at` before expecting the
post on normal Explore or Species Dictionary surfaces.

`lib/species.test.ts` locks canonical/native UUID URLs, versioned Edge response
mapping, 404-versus-transient failure behavior, shared attribution filtering,
and the exact AASA path list. The corresponding iOS suites cover canonical and
legacy HTTPS/custom-scheme parsing, malformed UUID rejection, share URL copy,
conflicting-route cleanup, Dictionary-tab presentation state, and survival of
the immediate foreground timeout reset.

## In-Memory Database Containers (`SwiftData`)

Test suites must not pollute the local iOS file system or SQLite databases. All
unit tests that exercise caching states and soft-deletions must use an isolated,
volatile `ModelContext`:

```swift
@MainActor
private func createIsolatedContext() throws -> ModelContainer {
    let schema = Schema(CurrentSchema.models)
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
}
```

Always use `CurrentSchema` (aliased to the latest active `MerianSchemaV{N}`).
Never pin tests to historical versioned schemas — a pinned schema silently drops
new model fields (e.g. `similarSpecies` added in `MerianSchemaV26`), causing
persistence tests to pass against the wrong shape.

> **Primitive Mapping Constraints:** Tests must explicitly apply
> `isStoredInMemoryOnly: true` as the primary isolated context configuration. Do
> **not** bind testing contexts dynamically to disk via `.sqlite` caches. Under
> iOS 17/18 Simulator configurations during concurrent execution paths,
> assigning implicit types like `[String]` primitive arrays to dynamically
> loaded disk caches triggers an unrecoverable `_KKMDBackingData`
> materialization crash. True RAM mappings fundamentally bypass cache
> serialization and safely bridge properties without needing external
> attributes.

This guarantees that:

1. Operations like `context.save()` happen strictly in RAM securely decoupling
   from native schemas mappings.
2. The user's real `Scans` and `OfflineQueuedScan` records are completely
   shielded from parallel mutations.

Fixture setup must fail loudly. Do not use `try? context.save()` or
`try? modelContext.save()` when seeding SwiftData tests; make helpers `throws`
or call `XCTFail` in non-throwing cleanup so persistence failures do not hide
broken test state.

Keep test code warning-clean. Use immutable bindings for class fixtures when the
reference itself is not reassigned, discard intentionally unused intent results
with `_ =`, and avoid redundant `#require` wrappers around non-optional fixture
values so build logs remain useful.

## Mocking the App DI Environment (`AppDIContainer`)

When previewing complex SwiftUI trees using `#Preview`, running against
`AppDIContainer.shared` will accidentally trigger live production databases,
camera hardware allocators, and background network sync loops.

**ALWAYS** use the `#if DEBUG` mock singleton injection when writing canvas
boundaries:

```swift
#Preview {
    InsightSheetView()
        .environment(AppDIContainer.preview)
}
```

## Compiled iOS CI Gate

`.github/workflows/ios-build-and-test.yml` is the authoritative compiled
verification gate for iOS changes. It reports a stable
`iOS Build and Test / Production readiness` check on every pull request so the
repository ruleset can require it without leaving unrelated pull requests
pending. A fail-closed scope job starts the macOS work for:

- anything under `apps/ios/` or the embedded companion under `apps/watch/`;
- either generated Xcode project, `project.yml`, tracked build configuration,
  SwiftLint configuration, or iOS build scripts;
- every merge-queue commit and every manual dispatch.

For a release candidate whose final commits contain only backend, catalog-test,
or documentation changes after the last iOS input, manually dispatch this
workflow against the final exact SHA. Confirm the scope reason records a manual
dispatch and both macOS jobs run. A successful scope-only result is valid
changed-file reporting, but it is not compiled iOS release evidence and cannot
replace the full unit-test plus Release-archive gate.

Do not replace that design with workflow-level pull-request path filters. GitHub
does not report a completed required check when an entire workflow is skipped by
path filtering. The in-workflow scope job also avoids GitHub's path-filter
changed-file ceiling and treats an unresolved event range as in-scope rather
than silently skipping verification.

Two independent `macos-26` jobs use the reviewed Xcode 26.6 toolchain and the
checked-in `Package.resolved` file. Checkout, Swift package caching, and
artifact retention use reviewed, immutable action commits whose current major
versions run on Node.js 24. The portable workflow contract pins those exact
commits so a downgrade cannot silently restore a deprecated action runtime.

1. **Full iOS unit tests** resolves only locked package versions, validates the
   generated-project source membership against `project.yml`, compiles the app
   plus both shared test bundles with `build-for-testing`, and executes the
   complete `merianTests` target with `test-without-building`. This prevents a
   newly added Swift or Objective-C file from escaping compilation when the
   committed Xcode project was not regenerated. It also compiles `merianUITests`
   so UI-test-only changes cannot silently break, but UI tests remain a separate
   runtime gate. The unit-test selector does not select or skip any suite. Xcode
   process-level parallel testing is disabled because several hardware,
   networking, and persistence suites exercise shared singletons. The result
   gate fails if Xcode returns success without a `Passed` result, a non-empty
   test run, and at least one passed test case from each critical concurrency
   boundary: `CameraManagerTests`, `InferenceEngineTests`,
   `OfflineQueueManagerTests`, and `SyncStateManagerTests`.
2. **Current-SHA Release archive** independently checks out `GITHUB_SHA`,
   resolves the same lockfile, and runs a generic-device Release archive with
   signing disabled. It requires production-shaped RevenueCat client
   configuration, verifies app/widget/Messages/watch embedding, checks the
   version and build against `project.yml`, and requires the main app dSYM UUID
   to match the compiled binary. Signing is disabled only because hosted CI has
   no distribution identity; this is compile, link, archive, and dSYM
   validation—not a distributable App Store artifact.

The final Production readiness job uses `if: always()` and requires both macOS
jobs to succeed whenever scope says the build is relevant. For an unrelated
change it requires both to be skipped and reports success. Repository and merge
queue rules should require only the stable final check, not either conditional
macOS job.

### Repository Rule Setup

The workflow creates status checks but does not block a merge on its own. After
the workflow has reported once for the default branch, configure the `main`
ruleset or branch protection rule to require exactly:

```text
iOS Build and Test / Production readiness
```

Apply the requirement to pull requests and the merge queue. Do not require
`Determine iOS build scope`, `Full iOS unit tests`, or
`Current-SHA Release archive`: those jobs are conditional and correctly report
skipped for unrelated pull requests. The workflow already handles `merge_group`;
keep that trigger if the merge queue is enabled. A repository administrator
should verify the rule with one unrelated pull request and one iOS pull request
after any workflow or ruleset change.

Successful `main` and manual runs retain the unsigned validation archive for
seven days. Every run retains compact SHA/toolchain/test or archive evidence for
fourteen days; failed runs also retain the raw `.xcresult`, package-resolution
log, and `xcodebuild` log. The validation archive must never be exported or
uploaded to App Store Connect.

The cheap workflow contracts run with:

```bash
make test-ios-ci-tooling
```

That portable target tests the fail-closed scope detector, immutable action
pins, exact-SHA checkout, workflow invocation of generated-project source
membership, full-target unit-test selectors, merge-queue trigger, Release
archive, embedded-product/dSYM checks, critical-result validation, structured
failure-diagnostic extraction, and the unconditional final decision. It does not
replace the macOS compile or simulator execution.

The membership implementation and its adversarial missing, unexpected, and
orphan-source fixtures run in the macOS unit job. They can also be run locally
when the Ruby `xcodeproj` gem is installed:

```bash
bash scripts/test-ios-project-source-membership.sh
bash scripts/check-ios-project-source-membership.sh
```

If the current-project check fails after a source-layout change, update
`project.yml`, run `make xcodegen`, and commit both the source-of-truth and
generated project changes.

### Evidence And Failure Triage

Start with the job summary, then use the retained artifact that matches the
failure:

| Failure                                         | Artifact or local action                                                                                                                   |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Unit compile or execution                       | Download `ios-unit-test-failure-<run>-attempt-<attempt>` for the `.xcresult`, package-resolution log, and `xcodebuild` log.                |
| Unit result is empty or misses a critical suite | Inspect `ios-unit-test-evidence-<run>-attempt-<attempt>` and rerun the complete target; do not weaken the critical-suite validator.        |
| Release archive, embedding, or dSYM             | Download `ios-release-archive-failure-<run>-attempt-<attempt>` and compare it with `ios-release-archive-evidence-<run>-attempt-<attempt>`. |
| Intended release SHA was out of scope           | Manually dispatch **iOS Build and Test** on that ref so both macOS jobs run and produce current-SHA evidence.                              |

For an executed test failure, the summary prints `testFailures` from Xcode's
structured result summary. If that is unavailable, it prints failed test cases
and descendant failure messages from the result tree; only then does it inspect
the raw build log. Do not infer the failed test from arbitrary application
messages containing `error:`. Negative-path tests intentionally exercise reply
failures, unreadable stores, cancellation, and network errors while passing.

The hosted run is authoritative for simulator and archive behavior. A local
source-contract pass cannot substitute for its exact-SHA test and archive
results.

Full-target tests must not depend on files or singleton state left by another
test. Create media fixtures under a unique temporary directory and remove them
afterward; when the behavior specifically resolves a Documents reference, create
a unique real Documents file and clean it up. A test that exercises a shared
manager must capture and restore every stateful dependency it uses, including
injected contexts, and explicitly select the durable-context or `UserDefaults`
fallback path it intends to verify. View-model fixtures must also set routing
identifiers and active media rather than relying on presentation side effects
that are absent in a unit test.

## Core Suites

Tests are organized under `apps/ios/MerianTests/Core` and
`apps/ios/MerianTests/Features`:

- `Core/<CoreArea>/` mirrors cross-feature services, managers, actors,
  infrastructure, and shared app policies from `apps/ios/Merian/Core`.
- `Features/<Feature>/<ProductArea>/` mirrors user-facing product areas from
  `apps/ios/Merian/Features`.
- If a test covers a Core manager that happens to surface in a feature screen,
  keep the test under `Core`.
- If a test covers local product-area behavior, view models, display policy, or
  feature-only helpers, keep the test under the matching feature folder.

Example:

```text
MerianTests/
  Core/Data/OfflineSync/
  Features/Capture/Describe/
  Features/Scans/Library/
  Features/Scans/Collections/
  Features/Profile/UserProfile/
  Features/Profile/Settings/Changelog/
```

### Analytics & Telemetry

- **`AppTelemetryTests.swift`**: Installs a local capture handler and calls
  `AppTelemetry.initialize()` in `setUp()` so the `isInitialized` guard passes
  without touching the live PostHog SDK. The tests cover every public signal,
  preserved event names, `event_source = "ios_client"`, and the Pro
  paid/trial/free scan payload matrix.
- **`PostHogManagerTests.swift`**: Smoke-tests `identifyUser` and `reset`
  against the shared singleton to verify the SDK binding does not crash.
- **`GamificationManagerTests.swift`**: Validates persistence, asserting correct
  math updates against user local scores so UI progression trackers do not skew
  unexpectedly.
- **`UsageManagerTests.swift`**: Validates the advisory daily capture meter
  without treating it as a live API constraint. The suite exercises the normal
  default plus DEBUG override; `FieldTripsAvailabilityTests` locks the shipped
  `.unlimitedFreeScans` default to `false`. Server authorization is covered
  separately by the Edge and database quota suites.

### AI & Data Architectures

- **`MigrationPlanTests.swift`**: Two-tier structural guard for the SwiftData
  migration plan.
  - `migrationPlanContainerInitializesWithoutCrash`: mirrors `MerianApp.init()`
    (in-memory store, no migration). Catches init-time stage validation failures
    on iOS 26.
  - `migrationFromV30ToV33DoesNotCrash`: creates a real V30 disk store then
    reopens with a short source-isolated V30→V33 test plan. On iOS 26+ this
    keeps the historical lightweight/custom hop covered without forcing the
    fixture through unrelated recent-stage validation. The separate
    `fullHistoricalEqualReferenceFailureIsLegacyRescueEligible` test covers the
    production startup contract for full-historical equal-reference failures:
    classify them as non-corrupt legacy migration failures that are eligible for
    `store-rescue/`. The V30→V33 test validates the V31 (`isFlagged`)
    lightweight addition, the V32 (`isUploaded`) lightweight addition, and the
    V33 custom `migrateV32toV33` stage (backfilling `scanStateRaw` from the old
    booleans) in a single migration pass. Update the "from" version and
    description when a new schema is added. Run both tests on an iOS 26
    simulator on every schema bump.
  - `knownGoodV48RequiredValueFailureUsesLegacyRescue` and
    `optionalQueueV48RequiredValueFailureUsesLegacyRescue`: synthesize the
    required-value validation errors seen in TestFlight and assert that
    recent-source V48 failures are archived under `store-rescue/` instead of
    returning to safe mode. The V48 migration source contract remains covered by
    source guardrails because current SwiftData can reject malformed historical
    rows before a repair migration gets a save boundary.
  - Media-schema coverage now includes reusable disk-store fixture helpers,
    `testFullMigrationV39ToV40BackfillsMediaJSON()`,
    `testFullMigrationV40ToV41BackfillsCapturedMediaEntries()`, typed
    `StoredMediaReference` round-trips, and
    `testCapturedMediaSnapshotBuildsSharedDerivedViews()`. V47→V49 coverage also
    keeps disk-based queued-scan fixtures for image, video, audio,
    description-only, and mixed-media submissions, with display video media,
    inference-only frame paths, durable retry defaults, and a
    `scan-ingestion:{id}` scheduler row so startup-safe-mode regressions are
    caught before release. The V47 fixture also guards the snapshot-backed
    scheduler-row migration shape that prevents SwiftData from casting stale V47
    queued rows as the current model during `didMigrate`. This is the preferred
    place for schema-version migration fixtures and SwiftData checksum
    regressions.
  - V49→V50 coverage verifies the lightweight migration preserves existing
    queued scans and permits a new `OfflineQueuedScanGoalHint` companion with
    the same scan ID. Queue tests must cover hint persistence through foreground
    and background completion plus deletion/orphan cleanup.
- **`ModelStoreRecoveryCoordinatorTests.swift`**: Launch-recovery guard for
  damaged and legacy-unmigratable local stores. It verifies corruption-only
  quarantine, legacy migration rescue for generic SwiftData migration failures,
  no rescue for current-store or corruption failures, duplicate-checksum
  detection, store-metadata version parsing, store-aware migration selection,
  sanitized `recovery-manifest.json` output, startup diagnostic rescue flags,
  and a source-scan boundary that prevents store recovery from referencing
  `KeychainManager`, `SupabaseManager`, sign-out flows, or current-user state.
  The focused drift lane is `.github/workflows/ios-startup-safety.yml`; it runs
  both `ModelStoreRecoveryCoordinatorTests` and `MigrationPlanTests` so startup
  safe mode and schema-upgrade failures are caught together. The cheap
  `.github/workflows/ios-project-guardrails.yml` lane runs
  `make validate-ios-project` and `make validate-ios-migration-guardrails`
  first, so known-bad source shapes fail on Ubuntu before the slower macOS
  simulator job spends time resolving packages, building, or booting a
  simulator. Startup Safety remains path-filtered to startup/schema/recovery
  surfaces, manual dispatch, and the daily drift check; broad iOS changes
  instead enter the full compiled gate described above. Workflow/tooling-only
  changes can start the Startup Safety workflow to validate cheap guardrails,
  but its simulator steps are skipped unless startup runtime files changed.
  - Source-level migration guardrails fail if `SchemaVersions.swift`
    reintroduces `try? context.save()` / `try? modelContext.save()` in custom
    stages, active/global `FetchDescriptor` types inside `MerianMigrationPlan`,
    active model convenience helpers such as `replaceCapturedMedia(...)`, or
    bare active `CapturedMediaEntry` relationship targets inside retired
    schemas. V40→V41 media-entry backfill coverage also requires new
    relationship rows to be inserted through the migration `ModelContext` before
    assignment. They also keep the duplicate-prone V44/V45/V46 recent cluster
    collapsed out of the full historical runtime migration path so SwiftData
    cannot reject startup with duplicate version checksums. Disk-backed
    migration tests should open `ModelContainer` through the Objective-C
    exception bridge so SwiftData `NSException`s are reported as test failures
    with their original reason instead of aborting the whole test runner. V47
    must reuse the V45 checksum representative for unchanged local-scan,
    captured-media, and collection models, while V45 and V46 recent plans must
    keep those sources isolated from each other and route directly to V49 before
    the shared lightweight V49→V50 stage. Disk-backed SwiftData migration tests
    should use unique temporary store URLs and must not unlink the `.sqlite`,
    `.sqlite-shm`, or `.sqlite-wal` files during the test process. Core Data may
    keep those file descriptors alive after the visible `ModelContainer` scope
    ends; deleting them in-process can surface as sqlite
    `vnode unlinked while in use` traps in later tests. The workflow's Swift
    package cache key depends on the checked-in
    `Merian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
    lockfile and runs with automatic package resolution disabled so startup
    failures are not hidden behind cold dependency resolution or silent package
    upgrades. The workflow also uploads the raw `xcodebuild` log and appends
    build diagnostics to the job summary when Xcode fails before the selected
    startup tests run, because `xcresulttool get test-results summary` reports
    those build-only failures as `unknown` with zero tests. The startup-safety
    workflow also runs on a daily schedule as a drift check, but it is separate
    from the Supabase production deploy gate.
- **`SerializedMediaItemTests.swift`**: Locks the active-schema mixed-media read
  precedence. `localScanRecordPrefersCapturedMediaJSONOverRelationshipMirror`
  and `offlineQueuedScanPrefersCapturedMediaJSONOverRelationshipMirror` seed
  divergent JSON and relationship mirrors and assert
  `serializedCapturedMediaItems` / `capturedMediaSnapshot` return the JSON
  timeline. This guards the May 12, 2026 TestFlight crash class where SwiftUI
  layout faulted `CapturedMediaEntry.kindRaw` through an invalid SwiftData
  future backing object.
- **`InferenceEngineTests.swift`**: Asserts decoding of `EdgeResponseWrapper`
  and `EnrichScanResponse` payloads via `JSONDecoder`. Also covers
  `activeScanId` lifecycle: `testPrepareForNewScanClearsActiveScanId` verifies
  the pre-scan reset clears the stale ID;
  `testActiveScanIdClearedByInferenceTaskDefer` documents the generation-fenced
  defer contract; `testCancelActiveRequestClearsActiveScanId` verifies explicit
  cancellation clears both the presentation UUID and paired scan ID, because the
  invalidated task defer no longer owns that slot.
  `staleAttemptForSameScanCannotOverwriteReplacementGeneration` fixes the ABA
  contract independently of scan ID: attempt A is rejected while replacement B
  owns the same queued scan and only B may publish result state.
  - **`/identify` response**: Validates `EdgeResponse` fields (`scan_id`,
    `common_name`, `confidence_score`, `taxonomy`, `insight_data`,
    `species_insights.habitat_description`). Asserts that `species_insights` is
    nil on cache-miss responses and non-nil on cache-hit responses. Note:
    `aiReasoning` is populated from `insight_data.ai_reasoning` (per-scan,
    always present when `insight_data` exists) — it is **not** a separate
    `premium_insights` block.
  - **`/enrich-scan` response**: Validates flat
    `similar_species: [EnrichScanResponse.SimilarSpeciesEntry]` array decoding
    with all four fields (`scientific_name`, `common_name`,
    `reference_image_url`, `iucn_red_list_status`). Asserts sparse entries (only
    `scientific_name`) decode with `nil` optional fields. Asserts absent
    `similar_species` key decodes as `nil`, not empty array.
  - **`load(from:)` path**: Asserts that
    `LocalScanRecord.similarSpecies: [String]?` strings are wrapped into
    `SimilarSpeciesEntry` instances with `nil` enrichment fields (historical
    record path). Asserts nil `similarSpecies` on the record produces `nil` (not
    an empty `SimilarSpecies` struct) on `speciesData`.
  - **Inference tier**: Validates Flash vs Pro confidence band thresholds via
    `MerianConfig.confidenceBands(forInferenceTier:)`. Asserts nil tier resolves
    to Flash for safety.
  - **Moderation Flagging**: Asserts `flagAIIdentification` seamlessly mutates
    the offline tracking property `isFlagged` purely natively ahead of
    networking attempts (`testFlagAIIdentificationMutatesLocalState`), and
    strictly restores from `LocalScanRecord` on cold boot
    (`testLoadFromRecordPopulatesIsFlagged`).
- **`SpeciesDictionaryTests.swift`**: Validates the public dictionary response
  decoder, additive `content_quality`, legacy no-`schema_version` compatibility,
  client-side quality fallback for old payloads, species-ID-preferred request
  payloads, route entry-point propagation for analytics, view-model
  success/not-found/error states, and the `MerianNetworkClient` 10-minute
  in-memory memoization path for recently opened species pages. Test setup
  resets the singleton cache whenever a mocked `URLSession` is injected so
  serialized network tests do not share stale dictionary entries.
- **`ViewfinderIntelligenceTests.swift`**: Validates real-time analysis logic,
  ensuring frames are evaluated correctly before inference is triggered.
- **`ArchiveManagerTests.swift`, `SyncStateManagerTests.swift`,
  `ScanRepositoryTests.swift`, `BackgroundDatabaseActorTests.swift`**: Verifies
  bi-directional SwiftData relationship behavior within an isolated context,
  without triggering SwiftData loop issues. `ScanRepositoryTests` includes
  `testIngestScansTimestampGuardSkipsNilAndUnparseableTimestamps` — verifies the
  `guard let parsedDate = exifDate else { continue }` path in `ingestScans` by
  replicating the exact `flatMap + ISO 8601 formatter` derivation and asserting
  nil/garbage inputs produce nil (not a fabricated `Date()`). Also includes
  `testV26SimilarSpeciesRoundTrip` — inserts a `LocalScanRecord` with
  `similarSpecies: [String]?` and verifies the array round-trips through
  SwiftData without corruption; and `testV27LookalikesDataRoundTrip` — inserts a
  `LocalScanRecord` with `lookalikesData: Data?` (JSON-encoded
  `[SimilarSpeciesEntry]`) and verifies the blob round-trips and decodes
  correctly (covering the `MerianSchemaV27` field added for rich lookalike
  persistence). `BackgroundDatabaseActorTests` uses `CurrentSchema` and a
  disk-isolated container to validate actor-boundary `Sendable` payload
  extraction across a `Task.detached` boundary. Its upload and inference
  reconciliation tests also seed rows on both sides of an `observedThrough`
  cutoff and prove the older orphan resets while newer replacement work remains
  claimed. `SyncStateManagerTests` also locks the generation-fencing contract: a
  stale upload completion cannot clear a replacement batch; a completion
  delivered after `forceIdle()` cannot remove a newer inference token; a stale
  finalizing transition cannot advance the replacement's UI phase; and
  `GenerationTaskRegistry` rejects compare-before-clear and owner-cancel
  attempts from a replaced slot.
  **`testFetchPendingScansExcludesNonPendingScans`** (V33) seeds scans in all
  five states (`.pending`, `.uploading`, `.staged`, `.inferencing`, `.failed`)
  and asserts `fetchPendingScans` returns only the `.pending` record — directly
  validating the V33 `scanStateRaw == 0` predicate that prevents re-dispatching
  in-flight or tombstoned scans. Also covers `updateScanWithOverride`,
  `updateScanAsFlagged`, and `updateScanAsUnflagged` persistence paths.
- **`FileIOActorTests.swift`**: Covers the audio persistence resolver across the
  current supported path shapes: bare Documents filename, bare temp filename,
  and absolute temp path. This is the regression suite for "audio disappears
  after identification" class bugs.
- **`InsightSheetViewModelTests.swift`**: Verifies carousel handoff integrity
  across queued/analyzing/result states, including mixed media. The key
  regression is that an audio page present during analysis remains present, with
  the same ordering, after `speciesData` arrives.
- **Insights focused model tests**: `CandidateSwipeSessionTests.swift` covers
  skip/reject/confirm/restart/exhausted transitions without SwiftUI animation
  state. `SpeciesObservationStatsViewModelTests.swift` covers actor/reducer
  aggregation plus reducer normalization and empty-bucket behavior.
  `InsightChatTests.swift` covers Field chat request/response decoding,
  feedback/summary/prompt-suggestion DTO decoding, local fallback and
  AI-generated quick prompt merging/filtering, including reserved uncertainty
  context below 70% confidence and server-provided confidence-category
  preservation, failed outgoing recovery state, deterministic unavailable-state
  hiding, identification-concern action buckets plus negative examples, and the
  600-character draft cap. `UserTagsMutationControllerTests.swift` verifies tag
  saves commit locally before external cloud/search side effects can run.
- **`CaptureTelemetryTests.swift`**: Directly validates that offline/historic
  captures explicitly decouple live sensor leakage (like LiDAR distance vectors
  or view-finder zoom scopes) away from EXIF bounds.
- **`ScansManagerTests.swift`**: Validates local string-index mapping (group
  name taxonomies, semantic tags, explicitly added `customTags`, and
  one-character unigram candidates). Asserts `NotificationCenter` routing
  dynamically patches specific payloads (`testCustomTag_DynamicHotSwap`)
  instantly without OOM-burst re-renders. Search and indexing assertions now
  wait on `ScansManager.SearchDebugEvent` completions instead of fixed
  `Task.sleep` windows, including explicit debounce-cancellation coverage that
  proves a superseded query never emits `searchCompleted`. Also verifies the
  indexed query path preserves substring behavior
  (`testSubstringSearchFilteringPreservesContainsSemantics`) so the candidate
  index does not regress the user-facing `contains` search contract. Advanced
  filter tests wait for `filterIndexingCompleted`, verify cached option
  dimensions refresh after a targeted mutation, confirm selected values are
  normalized without changing matching semantics, and exercise rapid targeted
  reindexes so a superseded task cannot drop another document.
- **`LocalImageLoaderTests.swift`**: Locks concurrent network payload boundaries
  and request coalescing to prevent multi-grid fetch flooding. The async decode
  permit tests prove concurrency remains bounded and a cancelled waiter cannot
  consume the next released slot. Recovery cases cover promoted basename
  compatibility, registered scan-ID mapping after cloud renaming,
  high-confidence timestamp groups, Explore fallback rendering from Documents,
  and rejection of unrelated/unsafe URLs.
- **`OfflineQueueManagerTests.swift`**: Mocks queue payload insertions.
  - **In-Memory Isolation**: Spins up a `@MainActor ModelContext` with
    `.isStoredInMemoryOnly = true` to isolate test data from the user's real
    offline queue.
  - **Core Lifecycles**: Exercises `.enqueueCapture` / non-visual queue
    insertion (asserting SwiftData record counts increment correctly), canonical
    mixed-media serialization, and `.purgeSoftDeletedRecords()` (asserting
    soft-deleted items are removed while undeleted items persist).
  - **Media staging contract drift**: Loads
    `docs/contracts/media-staging-upload-manifest.json` and asserts
    `MerianConfig` matches the documented file, audio, and video budgets. Also
    covers the canonical video scan upload shape: five sampled inference frame
    files plus one playback video file must fit in one signing batch.
  - **Background task identity and single-flight ownership**: Verifies current
    upload descriptions round-trip underscored scan IDs, media indices, and the
    batch UUID; verifies current `inference_v2|generation|scanId` and legacy
    `inference_scanId` parsing; and proves inference preparation rejects a
    second claimant and ignores a compare-clear from the wrong UUID. Upload
    ownership tests prove a delayed batch UUID is rejected after replacement,
    one completion callback cannot remove another callback's membership token,
    and an old batch cannot release the replacement's global latch or UI
    activity.
  - **Disk Teardown**: Confirms that sandbox files in `URL.documentsDirectory`
    are deleted during purges to prevent storage bloat.
  - **`isSyncing` Latch Safety
    (`testSyncPendingScansResetsIsSyncingOnEmptyTasks`)**: Seeds a single
    `OfflineQueuedScan` with a non-existent image path, calls
    `syncPendingScans()`, awaits the `syncTask`, and asserts
    `isSyncing == false`. Guards against the background-task expiration or
    zero-task failsafe path leaving the latch permanently locked.
  - **`replayInferenceForUploadedScans` pickup
    (`testReplayInferencePicksUpStagedScans`)** (V33): Inserts a scan with
    `scanState: .staged` and `stagedR2Keys` set, calls
    `replayInferenceForUploadedScans()` with `isOnline=true` and
    `hasReconciledStartupState=true`, then polls a fresh `ModelContext` for up
    to 8 s until the scan's `queueState == .inferencing`. The
    `.staged → .inferencing` transition is performed by `tryClaimForInference`
    before the background download task is dispatched — it is the reliable,
    network-free observable that the pipeline was triggered. Validates the
    happy-path connectivity-restore replay without any in-memory lock set.
  - **`replayInferenceForUploadedScans` skip
    (`testReplayInferenceSkipsAlreadyClaimedScans`)** (V33): Inserts a scan with
    `scanState: .inferencing` (already claimed by another pipeline). Calls
    `replayInferenceForUploadedScans()` and waits 500 ms; asserts the durable
    queue metadata remains unchanged. Guards against dispatching a second
    pipeline for a scan already in `.inferencing` state — the function only
    queries `.staged` scans.
  - **Durable retry backoff math**: Asserts `OfflineQueueRetryPolicy` floors
    short retries, clamps long retries to `maximumRetryDelay`, and stops
    scheduling automatic work once `maximumAutomaticRetryAttempts` is exhausted.
  - **Multi-file generation retry accounting**: A successful upload member must
    not clear `queueAttemptCount` or the last durable error while sibling
    outcomes remain unresolved. Retry metadata resets only in the same actor
    save that persists the exact all-member manifest and staged transition, so
    one good file plus one persistently failing file cannot loop forever at
    attempt one and a missing queue/job read, save rollback, or mismatched
    already-staged manifest cannot advance inference.
  - **Cloud-complete local recovery**: If status is `found` but exact-owner
    hydration, local promotion, or queue deletion fails, assert the queue first
    persists its completed-result recovery marker, remains `.inferencing`,
    preserves server status fields, advances retry accounting, and returns
    `waitForServer`. Pre-dispatch, watchdog, and relaunch-orphan paths must not
    move that scan to `.staged` or dispatch another provider request even when
    the next status probe is unavailable or inconsistent. Exhaustion must pause
    in needs-attention state, and manual retry must retain the durable
    owner-result marker while resuming server-result recovery.
  - **Atomic Explore publication**: Assert the final RPC revalidates exact owner
    media, preserves request-before-scan lock ordering, rejects a locked
    `needs_id` community request as conflict, and rolls back the prior post,
    media, hashtags, timestamp, and community state after a forced late failure.
  - **Atomic Ask the Community creation**: Assert taxonomy resolves before the
    final relational mutation, the RPC locks request before exact owner scan,
    and post/media plus `needs_id` state roll back together. Reopen coverage must
    reset old publication, vote, and worker generations without deleting audit
    rows. Simulate the absent-request race and require one relational-only retry
    to return the committed request without a second moderation/provider call;
    simulate concurrent direct sharing and require the write-time trigger to
    reject its late `shared_at` update.
  - **Durable queue retry policy**: `OfflineQueueRetryPolicy` tests should cover
    transient network/server failures, local-media terminal failures, persisted
    `queueNextRetryAt`, server `retry_after`, and app relaunch behavior. An
    already-stale server retry timestamp must assert a one-second recheck, not
    the maximum five-minute delay. Video cases must assert durable playback
    media remains required while image, audio, and description-only scans use
    the same scheduler. Scheduler coverage must separately prove that a future
    persisted deadline creates a real `scheduledWakeDate`, needs-attention rows
    cannot preempt it, and claiming the scan clears both `queueNextRetryAt` and
    the ingestion job's `nextRunAt`.

  For any change to offline task ownership, the minimum regression matrix is:

  1. generation A is replaced by B before A resumes from a suspension point;
  2. A attempts to clear a registry slot, global upload latch, or UI phase;
  3. A attempts to cancel URLSession work after `allTasks` enumeration;
  4. connectivity loss invalidates A, B starts after reconnect, then A
     completes;
  5. orphan reconciliation snapshots at A, work is updated at B, and the
     `observedThrough` cutoff preserves B;
  6. current and legacy task-description parsers recover the intended scan ID.

  Assertions must prove B remains registered and active, not merely that A
  reports `Task.isCancelled`. Swift task cancellation is cooperative and is not
  an ownership assertion.
- **`CompositeLibraryTests.swift`**
  (`apps/ios/MerianTests/Features/Scans/Library/`): Validates the bounding
  behaviors of the composite `ScansGrid` that renders both `OfflineQueuedScan`
  and `LocalScanRecord` items in the same `LazyVGrid`.
  - **Unique ID Guarantee**: Inserts three `OfflineQueuedScan` records and
    asserts all three `id` values are distinct, guarding against accidental
    identifier collisions inside the grid's `ForEach` key space.
  - **Thumbnail fallback safety**: Asserts queued-scan tiles can safely derive
    an empty thumbnail from the canonical media timeline when no image is
    staged, instead of depending on a dedicated `localImagePaths` column.
  - **`queueState` Default (`testQueueStateDefaultsPending`)** (V33): Asserts a
    freshly constructed `OfflineQueuedScan` has `queueState == .pending` (raw
    value 0), so new records are always picked up by the next `syncPendingScans`
    pass.
  - **`.failed` Predicate (`testFailedScansExcludedByPredicate`)** (V33):
    Mirrors the exact `#Predicate<OfflineQueuedScan> { $0.scanStateRaw < 5 }`
    used in `ScansSheetView`'s `@Query` and asserts `.failed` (raw value 5)
    records are excluded while `.pending` records are returned. Guarantees
    tombstoned uploads never resurface in the library.
  - **Selection Engine Decoupling**: Injects an `OfflineQueuedScan` ID directly
    into `ScansManager.selectedScans` (the adversarial case) and confirms
    `getSelectedLocalRecords()` returns nothing for it. Because
    `getSelectedLocalRecords()` filters from `filteredScans: [LocalScanRecord]`,
    the queued scan ID cannot reach the batch-share / batch-delete pipeline
    regardless of what is in `selectedScans`.
- **`ImageCacheTests.swift`**: Ensures the Swift RAM cache does not exceed
  maximum system allocation limits.

### Hardware & Ecosystem Integrations

- **`CameraManagerTests.swift`, `CaptureWorkspaceViewModelRefinementTests`**:
  Validates camera state routing, target-FPS debounce ownership, and the
  video-generation correlation policy. A controlled async sleeper proves the FPS
  debouncer reads the current target after its delay and rejects a replaced
  generation even when the sleeper intentionally ignores cooperative
  cancellation. Focused recording tests prove callback URLs bind to the intended
  temporary file, generation-A callbacks/actions are rejected while generation B
  is active, and cooperatively cancelled timeout/stop tasks are rejected after
  their action token is replaced. These policy tests do not require simulator
  camera hardware. `CaptureWorkspaceViewModelRefinementTests` drives
  `startRefinementScan(from:)` through the injected `PreparedStagedImageLoader`
  seam, asserting both the success path (bounded display-sized refinement
  request is committed into `stagedCapture.images`) and the failure path
  (`isStagingRefinement` drops back to `false` without appending a stale image).
  This gives deterministic coverage over refinement staging behavior without
  simulator-driven UI automation. The complete unit target, including these
  camera-generation tests plus `InferenceEngineTests`,
  `OfflineQueueManagerTests`, and `SyncStateManagerTests`, runs in
  `.github/workflows/ios-build-and-test.yml` for every relevant source change.
- **`MediaPreparationActorTests.swift`**: Pins the production still-image
  contract directly: file URL inputs return bounded inference/display payloads,
  metrics stay within byte and dimension limits, avatar/crop previews return
  bounded sendable `CGImage` values, and invalid files are rejected before any
  staged media is produced.
- **`ExternalImageImportStoreTests.swift`**: Covers the Photos document-import
  boundary without UI automation. Tests lock Google/deep-link/file/Supabase URL
  precedence, prove security scope begins before validation, verify the inbox
  survives a new store instance, recover committed orphan copies, remove
  interrupted copies, persist onboarding-safe terminal feedback, and exercise
  real ImageIO plus dictionary fixtures for date/GPS, date-only,
  coordinate-only, absent, incomplete, and malformed metadata. Telemetry tests
  prove a gallery item never falls back to the current device location.
- **`OfflineQueueManagerTests` gallery replay cases**: Persist gallery
  provenance in the existing visual-media manifest and prove offline replay
  keeps embedded dates while omitting a queue bookkeeping timestamp when the
  photo contained coordinates only or no date. Local-only provenance must remain
  absent from the edge request JSON.
- **`CaptureWorkspaceViewModelRefinementTests` external-import cases**: Inject a
  temporary `ExternalImageImportStore` and prepared-image loader to prove a
  pending image is staged with the required crop and acknowledged only after
  commit. Separate cases prove a full tray retains the receipt until capacity
  clears, an exhausted free quota retains the receipt until Pro entitlement is
  active, and an unreadable file is removed with terminal feedback. Confirmation
  and crop cancellation continue to be owned by the shared gallery staging tests
  rather than a second import-only pipeline.
- **Launch presentation and explicit-route precedence**: `AppDIContainerTests`
  proves `opensExploreOnLaunch` defaults off, persists an enabled value, reloads
  from external `UserDefaults`, and requires both completed onboarding and
  opt-in. `CaptureWorkspaceViewModelRefinementTests` initializes generic
  Explore, then verifies Photos/Files imports, Explore post routes, community
  requests, scan routes, and the Scans library replace it. The import case also
  sends the foreground timeout event and asserts the staged image and required
  crop survive. Foreground returns must never be modeled as another
  launch-policy evaluation.
- **`AppTelemetryTests.testExternalImageImportEventContainsOnlyOutcomeAndClientSource`**:
  Guards the privacy boundary by asserting the event contains only `outcome` and
  `event_source`.
- **`HardwareOrchestratorTests.swift`**: Mocks
  `ProcessInfo.processInfo.thermalState` boundaries to verify the camera
  throttles FPS dynamically without restarting instances. Verifies the
  `UserDefaults` binding (`isExpeditionModeActive`) correctly overrides OS
  thresholds to lock to 24fps and remove glass modifiers. To avoid Swift runtime
  crashes in asynchronous CI containers, calls `AppTelemetry.initialize()` at
  `HardwareOrchestratorTests.init()` using a stub `TEST_MOCK_ID` configuration.
- **`EnvironmentContextManagerTests.swift`**: Asserts safe async handling over
  simulated `CLLocationManager` outputs for offline contexts.
- **`HapticManagerTests.swift`**: Confirms safe initialization of
  `UIImpactFeedbackGenerator` buffers without stalling threads. Asserts that
  setting `UserDefaults.standard.set(false, forKey: "isHapticsEnabled")`
  prevents sequence triggers without causing hardware memory faults.
- **`PhotoLibraryManagerTests.swift`**: Validates that toggling
  `UserDefaults("saveToCameraRoll")` drops the payload without triggering
  `PHPhotoLibrary` memory allocations.

### Security, Network & Identity

- **`MerianNetworkClientTests.swift`, `SupabaseManagerTests.swift`**: Tests API
  routing, including `.401` retry cycles for Ghost User flows and JSON body
  payload serialization.
  - **MockURLProtocol Contamination & `.serialized`:** Swift Testing may execute
    suites concurrently under the current Xcode toolchain. Generic static
    closures such as `MockURLProtocol.requestHandler` can therefore race while
    intercepting requests and corrupt expectations. Mark network suites that
    share those global mocks with `@Suite(.serialized)` to keep their
    interception state isolated.
  - **`testEndpointURLPathContainsFunctionsV1Segment`**: Verifies
    `endpointURL(_:)` produces the full `/functions/v1/<endpoint>` path
    structure by capturing the outbound URL in a mock handler. Guards against
    `supabaseUrl` misconfiguration producing a silent wrong-URL path.
  - **TLS chain-walking tests
    (`testTLSChainWalkingAcceptsIntermediateCertWhenLeafIsUnknown`,
    `testTLSChainWalkingRejectsUnknownChain`)**: Documents and validates the
    `certChain.contains { ... }` refactor that replaced `certChain.first`. The
    intermediate-CA test is the key regression guard: if someone reverts to
    `certChain.first`, the intermediate CA backup hash becomes dead code and
    this test fails. `testPinnedHashesAreNonEmptyValidBase64` guards against the
    `pinnedCertHashes` set accidentally being cleared (which would silently
    disable pinning in Release builds).
- **`DeviceIdentityManagerTests.swift`, `RevenueCatManagerTests.swift`**:
  Isolates authentication loops away from live production identifiers.
  `DeviceIdentityManagerTests` reads `DeviceIdentityManager.shared.deviceId`
  (the public `@Observable` property) — it does **not** call the private
  `getOrGeneratePersistentIDFV()` method directly. The test wipes the relevant
  Keychain item via `SecItemDelete` before and after the assertion to prevent
  cross-run contamination. `RevenueCatManagerTests` also locks the required
  current-offering product set to `pro_week` plus `pro_annual`; it does not
  replace dashboard/App Store smoke testing.
- **`MerianConfigTests.swift` production-environment coverage**: Verifies that a
  Debug simulator pointed at production Supabase reports a configuration issue
  by default, remains configured so deliberate smoke tests can proceed, and
  suppresses only the warning when
  `MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1`. It also verifies that
  non-production projects and non-simulator/release contexts do not warn.
- **`SocialGuardManagerTests.swift`, `CircuitBreakerManagerTests.swift`**:
  Asserts offline logic ensuring blocked users do not re-populate the feed.

### UI & Utilities

- **`ImageDownsamplerTests.swift`**: Tests Core Graphics memory constraints by
  processing 4000x4000 payloads under safe metric limits, preventing
  Out-Of-Memory JetSam crashes.
- **`MessageScanShareCacheTests.swift`**: Verifies the Messages App Group cache,
  generated description text, field-notes opt-in behavior, public Explore URL
  inclusion, canonical `naturebook://` generation, and legacy `merian://`
  deep-link parsing.
- **`ExploreHashtagSuggestionTests.swift`**: Covers the share composer's
  AI-assisted hashtag suggestions, including
  species/taxonomy/location/field-note ranking, selected-tag exclusion, five-tag
  slot handling, optional Field trip Challenge `eventHashtags`, and
  normalization of typed hashtag input before publishing.
- **`ScansManagerTests.swift`**: Verifies text/filter-index construction,
  incremental and coalesced reindexing, sort behavior, and selection limits for
  the Scans library.
- **`BackgroundDatabaseActorTests.swift` collection projection**: Creates member
  and unrelated scans plus Favorites, then verifies `collectionSyncPayloads()`
  returns only the non-Favorites collection's direct, deterministically sorted
  membership IDs.
- **`AppDIContainerTests.swift` preferred-name coverage**: Verifies matching
  normalized cloud values and existing tombstones are converged without an
  upsert, while real conflicts retain timestamp ordering.
- **`OnboardingViewModelTests.swift`**: Validates the extracted UI state machine
  progression, ensuring hardware fallback steps prevent `Int` scalar
  out-of-bounds crashes. Tests core persistence loops simulating `@AppStorage`
  routing flags from the `.ready` boundary, fully offline.

## Testing the Species Lookalike Pipeline

The `SimilarSpecies` / `SimilarSpeciesEntry` domain model has two distinct data
paths that require separate coverage:

### 1. Rich path (live scan + `enrich-scan` response)

`EnrichScanResponse.SimilarSpeciesEntry` (Codable DTO, snake_case) is decoded
from the `/enrich-scan` JSON payload and mapped to the domain
`SimilarSpeciesEntry` (camelCase) by `InferenceEngine.fetchAndApplyEnrichment`.
Tests:

```swift
// Verify flat array decodes with all four optional fields
@Test func testEnrichScanResponseDecodesRichLookalikes() throws {
    let json = """{ "data": { "similar_species": [
        { "scientific_name": "Procyon cancrivorus", "common_name": "Crab-eating Raccoon",
          "reference_image_url": "https://...", "iucn_red_list_status": "LC" }
    ]}}"""
    let response = try JSONDecoder().decode(EnrichScanResponse.self, from: json.data(using: .utf8)!)
    // assert entries[0] fields ...
}
```

Key assertions: absent key decodes as `nil` (not `[]`); sparse entries (only
`scientific_name`) decode with `nil` optionals without crashing.

### 2. Historical path (`load(from:)`)

When opening a scan from the library, `InferenceEngine.load(from:)` reads
`LocalScanRecord.similarSpecies: [String]?` (bare scientific name strings) and
wraps each into a `SimilarSpeciesEntry` with `nil` enrichment fields:

```swift
// LocalScanRecord.similarSpecies = ["Procyon cancrivorus", "Bassariscus astutus"]
// → SimilarSpecies(entries: [
//     SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, ...),
//     SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, ...)
//   ])
```

`SimilarSpeciesGallery` falls back to `SimilarSpeciesImageFetcher` for image
lookup when `referenceImageUrl == nil`.

A historical cached `SimilarSpeciesEntry.referenceImageUrl` is also normalized
during decode. If it matches the exact external-media denylist, it becomes `nil`
and enters the same fallback path; the surrounding lookalike entry and cache
remain intact.

### Exact external reference media

The current regression fixture is iNaturalist media `605615444` from GBIF
occurrence `5938154750`. iOS coverage must prove:

- the original, resized, uppercase-host, query-string, and fragment variants
  below `inaturalist-open-data.s3.amazonaws.com/photos/605615444/` are denied;
- unrelated iNaturalist photos and unrelated URLs containing the same digits
  remain allowed;
- comma-separated normalization preserves the permitted source order;
- a blocked cached lookalike URL decodes as absent without dropping the species;
- `LocalImageLoader` performs no request when every candidate is denied;
- concurrent similar-species download results are restored to candidate order,
  so the first permitted success wins; and
- blocked-only/all-failed dictionary galleries use the leaf placeholder.

These assertions live in `LocalImageLoaderTests.swift`,
`SpeciesDataTests.swift`, and `SpeciesDictionaryTests.swift`. Do not replace
them with a brittle assertion that merely skips array index zero.

### Backwards-compat accessor

`SimilarSpecies.lookalikes: [String]` (computed) maps entries to their
scientific names. Any code that previously consumed `[String]` arrays from the
old `SimilarSpeciesData.lookalike_species` DTO uses this accessor — it must
continue returning names in the same order as `entries`.

## Mocking Apple Ecosystem Limits (`DeviceIdentityManager`)

When testing across AI boundaries, tests must not pollute real Ghost Session
tracking identities via PostHog telemetry. Tests avoid calling
`SupabaseManager.shared.initializeGhostSession()` and instead test business
logic models decoupled from live Apple ecosystem HTTP constraints.

## API & Edge Function Testing (Deno)

Merian relies on Supabase Edge Functions. Due to the rapid iteration cycle of
Gemini structures, type safety at the Identify network boundary must come from
the shared executable contract, runtime parsing, and deterministic Swift DTO
generation described below.

Dependency validation must use the same boundary as production bundling.
`sync_function_deno_configs.ts --check` verifies every deployable function has
the generated local config derived from the reviewed root manifest.
`validate_function_dependencies.ts` verifies the shared frozen lock, one exact
Supabase SDK, the explicit one-day minimum dependency age, aliased runtime
imports, and `config.toml` parity, then CI runs
`deno check --frozen --config <function>/deno.json <function>/index.ts` for all
entrypoints. `function_dependency_tools_test.ts` independently requires exact
parity between configured functions and discoverable dependency graphs, proves
explicit type-only edges do not inflate runtime deployments, then locks
deployment selection for route-local, transitive shared, config,
dependency-policy, docs, and test-only changes.
`deploy_function_batches_test.sh` uses a fake Supabase CLI to prove a failed
batch retries only its own members and rejects malformed function names.
`scripts/function_caller_contract_test.ts` scans literal iOS, web, workflow,
Function-to-Function, operator-script, and migration callers; every target must
exist in both `config.toml` and the entrypoint graph. Reviewed historical
retirements require exact later unschedule evidence instead of silently allowing
stale names. `_tests/workflowSecurity.test.ts` independently locks immutable
action SHAs, least-privilege workflow permissions, and step-scoped secrets
across the whole workflow directory. This suite exists specifically to prevent
local checks from passing against a parent config that the remote function
bundler does not discover.

JSON ingress and public error behavior have four complementary Deno checks:

- `_shared/http_test.ts` drives declared-length, chunked, oversized, invalid
  UTF-8, invalid media-type, optional-empty, object-shape, tiny-chunk
  coalescing, and cancellation-race cases through the canonical streaming
  reader.
- `_tests/edgeHandler.test.ts` proves request IDs are server generated and
  propagated through authenticated and custom-auth handlers, only
  `PublicHttpError` or a validated `publicErrorResponse(...)` can expose a
  failure, unexpected exceptions and ordinary returned `5xx` bodies are
  sanitized, and safe retry headers survive.
- `_tests/jsonEndpointSecurityCoverage.test.ts` scans deployable production
  modules and rejects direct request `.json()`/`.text()` reads, missing explicit
  body limits, and unwrapped custom-auth entrypoints. It also locks the shared
  exception boundary so arbitrary thrown messages cannot become public errors.
- `_tests/jsonEndpointSecurityMigrationContract.test.ts` locks the waitlist
  schema constraints, RLS, revocations, privileged routine grant, and
  transactional rate-check order.

`services/supabase/tests/waitlist_security.sql` runs against the disposable
local catalog and verifies direct-table isolation, service-only RPC execution,
new-row field constraints, duplicate behavior, pre-Turnstile 10-minute/daily
limits, and exact verified/global rate boundaries. The web companion tests in
`apps/web/lib/boundedJson.test.ts` and `waitlistSecurity.test.ts` cover the 4
KiB reader, tiny-chunk coalescing, conservative email normalization, trusted
proxy parsing, rotating IP HMAC, bounded Siteverify responses, and fail-closed
Turnstile verification. The suite also proves incomplete Turnstile configuration
fails before any provider fetch. Migration coverage requires both bounded
counter-retention paths to use `FOR UPDATE SKIP LOCKED`, preventing concurrent
request cleanup from becoming a lock convoy.
`apps/web/lib/dependencySecurity.test.ts` also checks every locked PostCSS and
Sharp instance against the reviewed patched floors, keeps the Next.js transitive
overrides explicit, and verifies that the dependency audit follows the frozen
install. `.github/workflows/web-quality.yml` runs the live registry-backed audit
with a high-severity failure threshold, those tests, TypeScript checking, and a
production Next.js build for affected web changes. High and critical findings,
or an unavailable audit registry, block the job.

Public-web Explore authorization has three additional layers:

- `_tests/publicWebExploreMigrationContract.test.ts` locks empty search paths,
  service-role caller checks, fixed `NULL` viewer identity, bounded feed size,
  forced anonymous engagement/viewer state, explicit browser-role revocations,
  and privileged-routine allowlist entries.
- `_tests/publicWebExploreCoverage.test.ts` locks real public-key negative
  controls and the resolved server-key positive control into the production
  workflow without allowing the credential matrices to be mixed.
- `tests/public_web_explore_security.sql` impersonates `anon`, `authenticated`,
  and `service_role`. It proves browser roles cannot execute either wrapper,
  while the server role receives a visible post with private location redacted
  and no viewer-specific state. Moderation fixture mutation runs only as the
  catalog-test owner; `service_role` observes the resulting exclusion through
  its narrow RPC and receives no direct source-table write privilege.
- The production deploy smoke sends every real anon/publishable project key
  directly to the posts RPC as a negative control, then uses the resolved server
  key as a positive control and validates the narrow response shape.

Function-local tests under `services/supabase/functions/insight-chat/` verify
the expanded text-only prompt context, raw image URL/storage-key/coordinate
exclusion, raw-image-access system instruction, supported action parsing,
message caps, deterministic safety refusals, and the `suggest_prompts` action's
safe three-prompt JSON contract.

Media-ingestion durability has focused Deno coverage as well:
`_shared/scanIngestionJobs_test.ts` locks client-safe job-state projection and
the deterministic manifest checksum; `_shared/scanIngestionIntents_test.ts`
locks sanitized replay-intent construction and inline-media redaction;
`_shared/scanIngestionCompatibility_test.ts` locks the legacy
identify/describe/audio compatibility bridge so staged media and text-only
requests replay through `/identify-multimodal` while inline media stays redacted
and non-resumable. It also verifies one atomic pre-provider setup call,
already-complete/database fail-closed outcomes, no premature finalizing
transition, and durable retryable propagation when finalization fails;
`replay-scan-ingestion/worker_test.ts` covers staged payload reconstruction,
existing complete scan and ownerless-tombstone short-circuiting, incomplete
video rows being left for repair instead of duplicate AI replay, the 120-second
downstream deadline, the 150-second minimum lease invariant, and the 8 KiB
diagnostic-response ceiling; `reconcile-scan-media-assets/worker_test.ts` covers
video repair, abandoned media cleanup, active-job waiting, ownership matching by
user plus scan id, and job completion/failure feedback;
`_tests/scanMediaIngestionContract.test.ts` is the media-type matrix that keeps
image, audio, text-only, and video replay, status, repair, and Explore-share
contracts aligned; `_shared/mediaBudgets_test.ts` and
`generate-upload-urls/storage_test.ts` keep the staged signing limits, allowed
content types, and six-file video batch in sync with the documented contract;
and `_tests/migrationMediaContract.test.ts` checks the scan-media,
reconciliation, scanless staged-row repair, video-audio metadata backfill,
ingestion-job, manifest-checksum, intent-outbox, replay-worker migrations, and
the APNs device-token constraint repair. Run the migration contract test with
`--allow-read=services/supabase/migrations` because it reads SQL files directly.

The July 28 joined scan-reliability repair adds focused coverage at every seam
that previously passed in isolation:

- `_shared/identify/media_test.ts` proves inline image/audio bytes exclude old
  destination hints while genuine staged source keys remain in the manifest.
- `_shared/scanPersistence_test.ts` classifies returned rejection, lost write
  response, delayed owner visibility, unreadable verification, and exact-owner
  scoping. Cleanup is permitted only for proven rejection plus absence.
- `_shared/scanMediaAssets_test.ts` covers lost signing-response reuse,
  retryable reactivation, terminal refusal, compatible signing-subset
  composition, and the six-key union cap.
- `generate-upload-urls/assetRegistration_test.ts` proves mixed multi-scan
  batches cannot leak a flat index or upload session across scans and assigns
  each requested scan's indexes independently.
- `share-scan-to-explore/restoredMediaValidation_test.ts` and `db_test.ts` cover
  traversal/cross-owner refusal, exact durable filename matching,
  reread-confirmed commit, definite rejection, ambiguous update preservation,
  and rollback refusal without positive absence evidence.
- `repair-scan-image/db_test.ts` and `worker_test.ts` prove a replacement is
  deleted only after exact definite rejection and is preserved for lost,
  unreadable, concurrent, or contradictory persistence outcomes.
- Route tests for `identify-multimodal`, `identify`, `identify-describe`, and
  `audio-spec` prove owner-row durability is awaited, malformed provider JSON is
  retryable HTTP 503, and unknown persistence does not refund committed usage or
  delete promoted media. The fresh multimodal request test requires successful
  finalization before its initial 200. Completed-response tests separately prove
  that a same-UUID marked replay can reconstruct from the exact owner row while
  finalization is still retryable, without provider redispatch. Compatibility
  tests permit their narrow immediate fallback only after exact-owner insertion
  while retaining a retryable ledger.
- `_tests/inlineScanManifestRecoveryMigrationContract.test.ts`,
  `_tests/stagedScanRegistrationMigrationContract.test.ts`,
  `_tests/scanUserProfileMigrationContract.test.ts`, and
  `_tests/identityMergeScanRecoveryMigrationContract.test.ts` pin migration
  ordering, function signatures, ACLs, exact owner/identity fences, canonical
  finalization, uniqueness, owner advisory locking, and target-only merge
  recovery.
- `tests/inline_scan_manifest_recovery_security.sql`,
  `tests/scan_user_profile_security.sql`, and
  `tests/identity_merge_scan_recovery_security.sql` execute the corresponding
  authorization and topology contracts against a fully migrated disposable
  PostgreSQL catalog. The inline fixture also finalizes the production video
  shape—five promoted sampled-frame captures plus one promoted playback
  capture—and requires one ready playback row with no ready standalone frame
  images.

iOS regression coverage is intentionally joined as well:

- `OfflineQueueManagerTests` validates exact server-key task handoff, complete
  signing-response validation, persisted-session owner preference, whole-batch
  sibling failure fencing, exact all-member success accumulation, relaunch
  orphan recovery, fresh staging after consumed-key failure, and that retry
  updates report an attempt only after persistence commits.
- `OfflineSyncTests` validates queue state/backoff decisions against the
  owner-safe server ledger.
- `BackgroundDatabaseActorTests` validates immediate non-visual durability and
  late optional context merge. Its staging-transition cases assert committed,
  already-advanced, retry-required, and discarded outcomes so an HTTP callback
  cannot treat a rolled-back local write as inference readiness.

Do not replace the executable SQL fixtures with source inspection. Static
migration contracts are useful when Docker is unavailable, but only a disposable
migrated database proves live function ACLs, triggers, locking, and transaction
behavior. Never run these transactional fixtures with `--linked`.

`_tests/migrationExecutionContract.test.ts` also scans every migration for
schema-qualified `SUBSTRING` calls that incorrectly use PostgreSQL's unqualified
`FROM`, `FOR`, or `SIMILAR` expression forms. Its depth-aware fixtures reject
the three keyword forms—including nested argument expressions—and accept
unqualified expressions plus qualified comma invocation. This catches the
workflow-run-1550 parser regression before Docker startup; it does not replace
fresh-catalog replay.

Workflow run 1551 supplied that fresh-catalog replay evidence: all migrations
applied before the catalog runner reached its fixtures. Two fixtures then failed
during setup because they assumed an `auth.users` insert did not create the
matching public profile, and one also proposed 26-character usernames against
the 24-character limit. The recovery fixture source contracts now pin
policy-valid usernames and a trigger-aware `ON CONFLICT (id) DO UPDATE`. Treat a
setup exception followed by `Bad plan` as one root failure; the aborted pgTAP
block did not execute a second independent assertion failure.

Workflow run 1552 repeated the full replay at
`7e54a1ade9806f40654c937fe9eaf6f7d93439e9`, then supplied a more precise
boundary: inline recovery passed assertions 1–15 and raised in the next
mixed-video recovery call. The finalizer had incorrectly required sampled
inference-frame URLs from the compatibility image array as ready standalone
images, even though the canonical refresher intentionally emits only the
playback row. Forward migration
`20260729012153_fix_video_scan_canonical_finalization.sql` now projects
structured media or the exact legacy standalone-image/video/audio set and
requires owner-matched ready rows for that projection.

`_tests/inlineScanManifestRecoveryMigrationContract.test.ts` statically pins the
projection and guarded rewrite; the existing recovery case and direct six-object
production-shape pgTAP case are the authoritative live regressions. Source
inspection is not PostgreSQL evidence. The current suite discovers 26 fixtures
after adding atomic Explore and Community rollback coverage; run all 26 on the
exact remediated SHA.

The same run showed that an outer multi-phase `DO` can still hide the useful
PostgreSQL error: the identity-merge fixture reported `planned 1, ran 0`.
`identity_merge_scan_recovery_security.sql` now catches its outer exception,
emits one bounded warning containing fixture phase, SQLSTATE, message, detail,
and hint, stores context for the TAP description, and emits its one planned
assertion. Never put credentials, raw media, provider payloads, or arbitrary
customer data in this diagnostic.

The next exact-SHA run proved why phase diagnostics matter: it reported `42702`
at `ingestion-intent setup`, where a synthetic PL/pgSQL variable named `scan_id`
appeared beside `jobs.scan_id`. The production merge and recovery routines had
not run. Catalog fixtures must use role-prefixed identities such as
`fixture_scan_id` whenever a statement also references the corresponding column,
and must qualify every table column. The source contract pins that declaration
and rejects the ambiguous variable name. A hosted warning is evidence of the
remaining root failure, not a passing fixture; correct the layer identified by
the phase and rerun until the assertion passes.

The latest hosted replay then discovered all 26 files and proved the identity
fixture correction: identity merge/recovery and inline/video recovery passed,
and 24 files completed. Only the two new atomic fixtures aborted. Each reached
its first real `service_role` body call and raised SQLSTATE `42501`,
`permission denied for table explore_community_requests`; their later bad-plan
reports were secondary to that statement failure. Forward migration
`20260729044500_grant_atomic_explore_service_privileges.sql` now provides an
operation-scoped service allowlist while preserving invoker rights and no
browser-role writes. The revised Explore and Community catalogs plan 22 and 25
assertions and include live privilege checks. Static migration contracts can
pin that correction, but all 26 catalogs must still pass on a fresh exact-SHA
database before deployment.

Field Chat regression tests separately enforce that transient owned-scan
readiness does not become permanent UI state. HTTP `404 scan_not_ready`, missing
message/conversation actions, and status `not_found` must leave
`unavailableScanId` unset and preserve a retryable toolbar action. Terminal
ownership failure, `unsupported_scan`, and unavailable Explore-post sources
remain deterministic unavailability.

Explore composer regression coverage must distinguish “request stopped” from
“publication succeeded.” The create callback returns success only after the post
ID is cached; failure keeps the draft and retry alert mounted. Tests and reviews
must reject dismissal driven solely by an `isSharingToExplore: true → false`
transition.

Explore database integration coverage must also inject a failure after the post
and media writes but before publication returns. The disposable-catalog fixture
`atomic_explore_scan_publication_security.sql` installs a transaction-local
failing hashtag trigger, retries an existing post with replacement metadata and
media, and proves the previous timestamp, metadata, media, and hashtags all
survive with no duplicate or partial rows. Static contracts separately require
the Edge route to retain only the one atomic RPC final-mutation path.

Queue recovery review must also reject clearing durable retry metadata merely
because status returned `found`. Exact-owner hydration, local promotion, and
queue-row deletion are the success boundary. If either targeted or fallback
historical sync fails, the next retry must advance the existing attempt history
instead of beginning from zero.

The normative expected behavior and source inventory are in
[`16-scan-ingestion-reliability-and-recovery.md`](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#verification-gates).

`_shared/outbound_test.ts` covers combined caller cancellation and hard
deadlines plus streamed text/JSON response ceilings.
`_tests/outboundDeadlineCoverage.test.ts` scans every production TypeScript
module, rejects direct global or injected fetch calls, and locks the complete
set of signed R2 transport adapters. It also requires the only Google GenAI
client to configure the reviewed 90-second SDK timeout.
`send-push-notification/delivery_test.ts` proves APNs requests carry a deadline,
notification collapse identifier, and bounded provider diagnostics, and maps
request exceptions to stable non-sensitive failure reasons.
`_shared/external_test.ts` also proves one oversized provider response cannot
strand a sibling body or discard valid GBIF taxonomy and vernacular names.

`_tests/migrationExecutionContract.test.ts` enumerates the complete migration
directory, strips SQL comments, and rejects executable concurrent index DDL.
This protects both `supabase db start` in CI and clean local rebuilds; a static
allowlist would miss the next migration that introduced the same failure.

Push-device registration has two complementary database checks. The static
contract prevents a PostgreSQL-incompatible bounded regex from returning, while
`services/supabase/tests/push_device_registration.sql` inserts a normal
64-character hexadecimal token and proves that short, oversized, and non-hex
tokens fail. From the repository root, run:

```bash
make validate-supabase-migrations
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/push_device_registration.sql
```

The pgTAP command requires a running local Supabase/Postgres stack. Do not run
this fixture test with `--linked`: it intentionally writes test rows inside a
transaction. CI pins Supabase CLI `2.109.1`, which owns migration transaction
and history boundaries. New migrations at or after `20260727183356` must not add
top-level transaction controls, which can split schema state from history.
Top-level timeout guards use session `SET` plus matching `RESET`, not
`SET LOCAL`, so they remain effective during fresh replay. Historical applied
migrations with explicit controls remain immutable compatibility artifacts.
Checked-in migrations also reject direct and dynamic concurrent index DDL; large
production indexes use the supervised preflight. After a hosted deployment, use
migration history plus read-only constraint inspection to verify that both
push-token constraints exist and are validated.

Privileged routine security has three complementary checks:

- `_tests/privilegedRoutineMigrationContract.test.ts` statically locks the
  global/schema default revocations, blanket definer revocation, exact
  allowlist, empty search path, caller guards, and bounds on high-impact
  maintenance routines. It also locks
  `20260727010340_fix_service_role_authorization_guard.sql`: legacy
  `auth.role()` detection, PostgREST's protected standard `role` check,
  migration/repair sessions, and direct helper revocation.
- `tests/privileged_routine_security.sql` runs against a fully migrated
  disposable catalog. It compares effective `has_function_privilege()` results
  with `internal.privileged_routine_grants`, inspects direct `pg_proc.proacl`,
  rejects API-role schema creation and allowlist reads, and creates a temporary
  definer function to prove new functions inherit owner-only execution. A second
  temporary definer probe simulates PostgREST's `authenticator` session: the
  `authenticated` role must fail `internal.require_service_role()`, while
  `service_role` must pass without depending on a JWT claim. The fixture also
  runs `plpgsql_check` against ordinary and trigger definer functions so
  ambiguous identifiers or unresolved names fail the catalog gate. Failures
  report the exact routine signature, source line, SQLSTATE, statement, query,
  detail, and hint; a later pg_prove `Bad plan` is fallout from that exception,
  not a separate test failure. Conditional expressions such as `COALESCE` are
  SQL syntax rather than catalog functions and must not be written as
  `pg_catalog.COALESCE(...)`. For an idempotent insert whose
  `RETURNING TRUE INTO flag` can return no row, prefer `flag IS NOT TRUE` to
  handle the resulting null explicitly.
- `scripts/audit_privileged_routine_acl_test.ts` exercises the fail-closed
  report evaluator. The deployment workflow then runs the read-only audit
  against production before migration in report mode and after migration in
  enforcement mode.

Run the local gates from the repository root:

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines
```

The catalog fixture must run through `supabase test db`; a Deno database test
that reports a connection skip is not evidence for this boundary. Never point
the transactional pgTAP file at production. Use
`MERIAN_DATABASE_URL=... make audit-supabase-privileged-routines` for hosted,
read-only verification instead.

Internal service-key authorization has complementary unit, static, catalog, and
production checks:

- `_tests/serviceRoleAuth.test.ts` exercises explicit, hosted named-secret,
  singular local/manual, and legacy matching; deterministic preference;
  malformed plural fallback; strict Bearer syntax; non-JWT `apikey` transport;
  conflicting-header rejection; missing configuration; and representative
  anon/publishable/authenticated mismatches. It also rejects a publishable key,
  anon/user JWT, short placeholder, incomplete HS256 signature, malformed
  dictionary entry, or opaque key placed only in the legacy variable.
  Cross-source cases prove a malformed scalar or dictionary never vetoes an
  exact key from another valid source, never becomes a candidate itself, and
  still fails configuration when no valid key matches. An exhaustive 243-state
  matrix covers every absent, valid, and malformed combination across the five
  server-key sources and locks both inbound authorization and outbound
  precedence. The publishable-key and web-admin resolver suites apply the same
  exhaustive state-combination check to their smaller source sets.
- `_shared/serviceRoleClient_test.ts` executes PostgREST, Storage, Functions,
  and Auth Admin requests through an intercepted transport. It proves
  `sb_secret_...` keys are sent only as `apikey`, legacy service-role JWTs
  retain their required Bearer header, and `fetch(Request)` metadata or
  unrelated user access tokens are not discarded. It also proves the final SDK
  transport attaches a hard request deadline. Function-invocation regressions
  prove non-2xx responses retain only status, bounded failure class, and fixed
  handler-marker presence while the body and credential stay private.
- `scripts/monitor_scan_media_health_test.ts` proves the read-only production
  monitor retries only reviewed transient Function failures, caps attempts at
  six, and uses bounded 2/4/6/8/10-second backoff.
- `_tests/serviceRoleAuthCoverage.test.ts` inventories every production
  authorization boundary, rejects database/network capability probes, permits
  direct Supabase client construction only at the reviewed public/user or
  shared-factory boundaries, and rejects any legacy-key-only admin client. It
  also prevents a caller-supplied credential from being reused for database or
  internal-function work and locks exact server-key discovery in operational
  callers.
- `scripts/resolve_project_api_keys_test.ts` proves Management API lookup always
  requests `reveal=true`, prefers the revealed current `default` secret, rejects
  masked or malformed values and loosely named legacy keys, returns every exact
  public negative-control key, and retains the exact legacy service-role
  fallback. It also proves transport, HTTP 408/425/429, and HTTP 5xx retries are
  attempt/delay bounded; numeric `Retry-After` is capped; response-body disposal
  failure cannot suppress retry; transport details are sanitized; and
  authorization or malformed-response failures remain fail-fast.
- `scripts/verify_edge_secret_digest_test.ts` proves the deploy gate accepts
  exactly one strict named SHA-256 digest, compares it to the exact classified
  local key, and rejects missing, duplicate, malformed, mismatched, or
  malformed-key input without exposing either value.
- `_tests/serviceRoleAuth.test.ts` proves the non-reserved
  `MERIAN_SUPABASE_SERVER_API_KEY` hosted fallback accepts only a complete
  classified server key, remains available during a malformed hosted-dictionary
  incident, and stays below an explicit CI/local override in key preference.
- `_tests/serviceRoleAuthMigrationContract.test.ts` locks the
  `taxonomy_import_runs` blanket revocation and least-privilege service-role
  grant.
- `_tests/serverApiKeyBoundaryMigrationContract.test.ts` locks the private SQL
  header helper, installed-routine and persisted-cron rewrite, mixed
  user/service identity dispatch, and a forward-only ban on new Bearer-only
  `pg_net` server-key construction.
- `scripts/documentation_contract_test.ts` locks the same header matrix,
  hosted-plural versus singular environment shape, migration transaction/history
  ownership, replay-safe timeout guards, default-ACL/RLS behavior, supervised
  user-FK indexes, orphan triage, run-attempt-specific operational evidence, the
  active DwC-A/public-web release-hold navigation, and local links across the
  maintained product, feature, architecture, operator, and service docs.
- `tests/privileged_routine_security.sql` verifies the same effective ACL and
  transport policy against a fully migrated disposable catalog under real
  `anon`, `authenticated`, and `service_role` database roles. It scans current
  routine/cron source and executes the mixed media-incident routine through
  simulated PostgREST role impersonation.
- The production deployment smoke retrieves the project's real legacy anon
  and/or current publishable keys and requires `401` from
  `community-taxonomy-status`. The same public keys must receive only
  `401`/`403`/`404` when sent directly to `get_public_web_explore_posts`; a
  `2xx` is an authorization regression. The workflow then prefers a real current
  secret key (falling back to the legacy service-role key) as the positive
  control. Current secret keys are sent only in `apikey`; only legacy JWT keys
  receive Bearer transport. Key retrieval uses the tested Management API
  resolver because the CLI key-list command does not reveal a callable current
  secret. Before deployment, the workflow masks and synchronizes the selected
  value to `MERIAN_SUPABASE_SERVER_API_KEY`, then verifies the stored hash
  before Function rollout; static coverage requires that ordering. Positive
  calls make six bounded retries for transient routing/deployment statuses. A
  separate graph-derived preflight probes every configured Function and requires
  `X-Merian-Handler: 1` before the rollout succeeds; unresolved routes share one
  bounded propagation window. It uses only a validated legacy anon JWT to cross
  any intentional gateway `verify_jwt = true` boundary and fails closed if that
  execution credential is unavailable; a publishable key is never sent in Bearer
  authorization. The six customer-critical scan, Explore, and Community routes
  additionally return marked fail-closed `401` responses without user
  Authorization. Final
  Function failures classify only whether the fixed `X-Merian-Handler: 1` marker
  was present; Data API failures use separate PostgREST/RPC guidance and never
  expect a Function marker. Both paths keep the body and request-ID value
  private and never print a variable header value. Do not create a production
  user merely to obtain an authenticated JWT for this smoke: exact-value
  matching is covered deterministically and the disposable catalog exercises the
  authenticated role. Use a dedicated staging user for end-to-end
  authenticated-JWT testing when a credential-transport change is under review.

Run the focused Deno tests from `services`:

```bash
deno test --frozen --config supabase/functions/deno.json \
  --allow-read \
  supabase/scripts/resolve_project_api_keys_test.ts \
  supabase/scripts/verify_edge_secret_digest_test.ts \
  supabase/functions/_shared/serviceRoleClient_test.ts \
  supabase/functions/_tests/serviceRoleAuth.test.ts \
  supabase/functions/_tests/serviceRoleAuthCoverage.test.ts \
  supabase/functions/_tests/serviceRoleAuthMigrationContract.test.ts \
  supabase/functions/_tests/serverApiKeyBoundaryMigrationContract.test.ts
```

Durable account deletion has nine complementary checks:

- `_tests/safeDelete.test.ts` executes the actual handler/worker modules with
  injected boundaries. It proves intake precedes processing, cleanup failure
  never calls Auth, `storage_pending` releases its claim without calling Auth,
  `auth_pending` recovery repeats idempotent cleanup before Auth, Auth failure
  is deferred after verified storage, and a lost completion response remains
  retryable.
- `_tests/accountDeletionCoverage.test.ts` keeps source ordering, idempotent
  Auth-not-found handling, timing-safe reaper authentication, bounded parsing,
  `config.toml`, workflow wiring, the independent monitor's separation from the
  database reaper, and the executable fixture's cleanup-before-storage phase
  order present.
- `_tests/accountDeletionMigrationContract.test.ts` locks the private state
  machine, claim token, `SKIP LOCKED`, outbox-before-tombstone order, cleanup
  verification, required `storage_pending` phase, five-prefix keyset cursor,
  25-hour delayed verification, media/location/context clearing, upload-signing
  fence, profile-recreation guard, terminal UUID minimization, service-only
  ACLs, five-minute cron, the failed-version no-op bridge, ownerless-tombstone
  constraint, the Auth/profile foreign key, and the absence of synthetic user
  creation. It also requires the storage-claim SQL to join a matching cleaned-up
  `storage_pending` private job and to veto live profiles and owned scans, plus
  indexed identity-free aggregate health with a service-only caller check. The
  health contract must select Vault before the NULL-only app-setting fallback,
  so a blank Vault value remains unhealthy instead of being masked.
- `tests/account_deletion_security.sql` executes the live catalog transitions:
  durable intake leaves Auth/data intact, the restrictive profile FK rejects an
  Auth-first delete, premature Auth completion is denied, all five sweep and all
  five delayed verification prefixes advance in order, cleanup commits while
  Auth still exists, retained scans are ownerless tombstones with media and
  personal fields cleared, no all-zero profile exists, active deletion blocks
  profile resurrection, retries preserve `auth_pending`, the service role sees
  that retry through aggregate health while public roles cannot execute the
  health RPC, final completion erases the direct UUID, and duplicate completion
  is idempotent. Before deletion begins, the same fixture inserts a stale
  storage outbox row for its live owner and proves the claim RPC cannot return
  it.
- `safe-delete/storageWorker_test.ts` proves one bounded page per claim, delete
  concurrency behavior, empty-prefix advancement, delayed verification,
  idempotent 404 deletion, retry persistence, and claim-token propagation.
- `tests/ghost_profile_merge_security.sql` runs in the same disposable-catalog
  gate and proves the restrictive profile/Auth identity key is skipped only for
  the source profile row while all real Ghost-owned references are reparented.
- `MerianNetworkClientTests.testSafeDeleteAccountEndpoint` returns
  `202 Accepted` from the mock route and proves the shared authenticated request
  boundary recognizes durable acceptance as a successful 2xx response.
- `scripts/monitor_account_deletion_health_test.ts` proves strict aggregate
  parsing/invariants, threshold ordering, cron/configuration and orphan
  criticals, retry/expired-lease warnings, fail policy, and identity-free
  operator recovery guidance, including critical severity when configuration is
  false. The migration contract statically locks the Vault-first, NULL-only
  selection order. Workflow security checks separately keep its actions
  immutable, permissions minimal, and secrets step-scoped.
- `_tests/publicSchemaSecurityMigrationContract.test.ts` and
  `tests/public_schema_security.sql` lock every migration-created public table's
  effective RLS, deny-by-default global/schema ACLs, PostgreSQL 17 privilege
  coverage, future transaction-control rules, replay-safe timeout setup/reset,
  reaction-table grants, valid schema-qualified string-function syntax, and the
  complete valid/ready leading-index inventory for user foreign keys.

Run the pgTAP fixture only against the disposable local stack. It inserts and
deletes Auth fixtures inside a transaction and rolls everything back.

Owned scan-image recovery has five complementary boundaries:

- `repair-scan-image/validation_test.ts` accepts one canonical durable source
  and one owner staging key, then rejects an unrelated host, avatar/nested/query
  source variants, traversal/nested/non-image staging keys, and a key outside
  the exact authenticated owner prefix.
- `repair-scan-image/worker_test.ts` proves inspection never touches R2 for an
  unreferenced URL, identifies a referenced 404 as missing, checks the old and
  restored objects before promotion, returns atomic update counts, and rolls
  back a new durable object after persistence failure.
- `_tests/migrationMediaContract.test.ts` statically requires exact recursive
  replacement across scan arrays, captured-media JSON, normalized assets, and
  owner Explore snapshots plus the service-only grant/allowlist boundary.
- `tests/scan_image_repair_security.sql` executes one transaction against the
  disposable catalog and proves media order preservation, exact JSON string
  replacement without substring damage, normalized storage-key repair, and
  atomic Explore snapshot repair plus health-state reset.
- iOS `LocalImageLoaderTests` and `MerianNetworkClientTests` cover safe local
  filename compatibility, rescue-store scan-ID mapping, constrained timestamp
  grouping, unsafe/unrelated URL rejection, authenticated inspection/repair
  DTOs, and request payloads.

Do not replace the timestamp tests with a nearest-file assertion. Test fixtures
must cover exact media-count matching, the 60-second one-way window, a
three-second candidate margin, contiguous `_additional_N` roles, direct/rescue
precedence, and one-to-one file use. A local render is not enough: production
acceptance separately verifies the durable object and both Scan Library and
Explore metadata after repair.

Explore media quarantine has four complementary boundaries:

- `reconcile-explore-media-health/worker_test.ts` proves direct primary `404`,
  retryable `5xx`, distinct auxiliary poster checking without hiding a healthy
  video, and one recorded result per live lease.
- `_tests/exploreMediaQuarantineMigrationContract.test.ts` locks independent
  author/system state, canonical projection gates, two spaced confirmations,
  service/owner ACLs, notification lifecycle, in-app-only restoration, repair
  reset, and snapshot health continuity.
- `tests/explore_media_quarantine_security.sql` runs the complete healthy →
  degraded → quarantined → degraded → healthy state path against disposable
  Postgres. It proves partial omission, all-surface canonical hiding,
  preservation of publication intent, continuity across media snapshot refresh,
  automatic republish after repair, notification replacement, and
  private/service authorization.
- The iOS target build plus notification/library tests must cover decoding both
  new notification types, owner incident DTOs, missing navigation to Scan
  Library, restored navigation to post detail, persistent banner copy, refresh
  after repair, and explicit scan-deletion cascade warning.

Never make a test pass by updating health directly to healthy in production.
Fixtures may drive direct states transactionally, but staging acceptance must
create/delete controlled R2 objects and observe the two leased origin checks.
The release matrix is in
[Explore Media Health and Quarantine](../backend-and-data/12-explore-media-health-and-quarantine.md).

Incremental species-count maintenance has two complementary checks:

- `_tests/speciesCountTriggerMigrationContract.test.ts` statically requires the
  explicit whole-cutover transaction around `LOCK TABLE`, private composite
  ledger, its reverse foreign-key index, RLS/revocations, empty-search-path
  definer routines, ordered user locks, and four statement-level
  transition-table triggers. It rejects any new `COUNT(DISTINCT ...)`,
  `FOR EACH ROW`, or early-commit path in the replacement migration.
- `tests/species_count_trigger_security.sql` runs on the migrated catalog. It
  checks trigger shape and transition aliases, legacy-routine removal, private
  ACLs, and exact ledger/projection behavior across bulk insert, no-op unrelated
  update, simultaneous OLD/NEW changes, last-duplicate removal, and bulk delete.
  It rejects a live-owner ledger underflow and forces the deferred dictionary
  constraint by its schema-qualified `internal` name after an
  `ON DELETE SET NULL` transition. The intentionally corrupted projection before
  the unrelated update is a regression sentinel: the value must remain
  untouched, proving that routine updates do not hide a full-history recount.

Both are wired into `make validate-supabase-migrations`,
`make test-supabase-privileged-routines`, and the deploy workflow. Run the
database file only against the disposable local stack; it writes fixtures inside
a transaction and rolls them back.

Authoritative AI quota and entitlement security has four complementary checks:

- `_shared/entitlement_test.ts` proves paid/trial/expired resolution, database
  errors and missing rows failing closed, and absence of isolate-local reuse.
- `_shared/aiQuota_test.ts` locks UUID request-key validation, trusted proxy
  address selection, daily-rotating/domain-separated HMAC behavior, optional
  server-key fallback, weak explicit-secret failure, fail-closed commit, and
  per-attempt fencing-token propagation. `_shared/audioModeration_test.ts`
  additionally proves cache hits refund while provider attempts commit the
  database-selected model before dispatch.
- `_tests/aiQuotaCoverage.test.ts` inventories every direct provider-dispatch
  file and every public paid-model route, including transitive Explore/Community
  audio-publication callers, their exact operation, model-policy propagation,
  settlement ordering, removal of the public dictionary model fallback,
  quota-guarded group-tag calls, attempt-specific server replay keys, and
  absence of webhook cache invalidation.
- `_tests/aiQuotaMigrationContract.test.ts` statically locks the private schema,
  API-role revocations, atomic conditional UPSERT, idempotency/refund semantics,
  lease fencing and stale cleanup, service-only grants, and complete 30-row
  policy matrix. It also locks the exact schema-qualified
  `hashtextextended(text, bigint)` advisory-lock call so migration replay cannot
  hide a misspelled routine or incorrectly typed seed.
  `tests/ai_quota_security.sql` then exercises the migrated catalog and actual
  reservation/replay/limit/refund/failed-retry/stale-lease/fencing/version
  transitions.

The production workflow applies all migrations to a disposable database and runs
`bash services/supabase/scripts/test_database_catalogs.sh`. That gate discovers
every `services/supabase/tests/*.sql` fixture, rejects an empty suite, and
prevents a new catalog contract from being omitted by a selected CI list. Do not
replace executable catalog coverage with source inspection alone.

Focused source-inspection lanes have a separate Deno permission contract. Every
repository root read through an explicit filesystem API must appear in that
lane's narrow `--allow-read` list, even when the test module itself loads
successfully. The focused DwC-A lane therefore includes `supabase/functions`,
`supabase/migrations`, `supabase/scripts`, `supabase/tests`, `../apps/ios`, and
`../.github/workflows` from the workflow's `services` working directory.
`services/supabase/scripts/tooling_gate_test.ts` fails earlier if the
scan-finalization/DwC-A contract remains selected while its catalog-fixture or
iOS source root is removed. A permission failure after some tests pass is still
a failed lane and must not be reported as exact-SHA release evidence.

Public species-observation stats have layered resource-abuse coverage:

- `_shared/clientAddress_test.ts` locks right-most trusted proxy selection,
  daily rotation, purpose separation, and strong server-key failure behavior.
- `_shared/mediaBudgets_test.ts` proves declared and chunked request/provider
  bodies are rejected before crossing their byte budgets.
- `species-observation-stats/db.test.ts` proves UUID/name binding happens before
  provider work, exact taxon misses are negatively cached, non-owners dispatch
  no provider calls, every fetch receives an abort signal, provider bodies are
  stream-bounded, failed empty populations resolve `unavailable` instead of
  `partial`, and failed database finalization is not retried with downgraded
  cache state.
- `species-observation-stats/security.test.ts` locks the pre-auth IP budget,
  stable HTTP mapping for database rate/identity denials, cache-race claim
  responses, and finalization token forwarding.
- `_tests/speciesObservationStatsCoverage.test.ts` prevents deletion of
  dictionary binding, rate/lease RPCs, request/response body caps, deadlines, or
  the public route's replacement security boundary. It also prevents successful
  identity-independent responses from regaining per-Authorization cache
  fragmentation.
- `_tests/speciesObservationStatsMigrationContract.test.ts` statically locks
  private counters, user/IP/global limits, service-only ACLs, negative TTLs,
  lease duration, cache-race closure, token fencing, and stale-positive
  preservation on an unavailable refresh.
- `tests/species_observation_stats_security.sql` executes pre-auth IP and
  verified-user accounting/denial, canonical denial with retained rate usage,
  concurrent claim suppression, expired-generation replacement, stale-token
  rejection, atomic cache/taxon finalization, exact 24-hour negative caching,
  failed-refresh stale-positive retention, and effective API-role ACLs against
  the fully migrated catalog.

`SpeciesDictionaryTests` additionally proves the iOS request rejects malformed
UUIDs, empty/overlong names, legacy schemas, and response identity mismatches
before either network dispatch or memoization.

Owner-level pgTAP fixtures must first create a matching transactional
`auth.users` fixture. That insert fires `handle_new_user()` and may already
create `public.users`, so customization uses a trigger-aware
`ON CONFLICT (id) DO UPDATE` or updates the exact profile instead of issuing a
second plain insert. Supply a deterministic, unique `public_username` accepted
by `public.is_valid_public_username(...)`, a non-empty `public_author_name`, and
a CHECK-valid `public_identity_source`, in addition to the fields relevant to
the behavior under test. Usernames are currently 3–24 lowercase characters,
start with a letter, end with an alphanumeric character, contain no `__`, and
cannot be reserved. Keep fixtures transactional; never drop or weaken the Auth
FK or another production constraint to accommodate stale test data.

Identification latency has focused contract coverage at each boundary:

- `identify-multimodal/index.test.ts` source-locks the Free/Pro model mapping,
  generation configuration, one `generateContent` call, exact Gemini timer stop,
  privacy-safe latency event, awaited durability boundary, customer-safe
  `400 observation_rejected`, retryable `503 scan_persistence_failed`, and
  optional-only `EdgeRuntime.waitUntil` placement.
- `_shared/identify/db_test.ts` locks duplicate-safe insertion followed by
  owner-scoped read-back. `_shared/scanRecovery_test.ts` locks the bounded
  non-media payload, derived privacy fields, cross-owner/UUID rejection, direct
  media-URL rejection, and delegation to the atomic recovery RPC.
  `dwcaDownloadAndScanFinalizationMigrationContract.test.ts` locks the shared
  current/rolling-compatibility claim and recovery generation lock, exact
  `replay_exhausted` allowlist, completion-last media finalization, strict
  compatibility audio deletion ordering, worker compare-before-complete
  behavior, strict atomic-setup RPC decoding, the parent-first DwC-A generation
  lock, and the revocable grant/cleanup protocol.
  `share-scan-to-explore/db_test.ts` locks repair-and-reload before media
  restoration and publication.
- `_tests/auth.test.ts` covers valid anonymous claims plus expired,
  malformed-issuer/audience/subject, and public service-role rejection. Internal
  replay continues to use its separate service-role/replay-user tests; never
  weaken that path to make public claims tests pass.
- `_tests/migrationMediaContract.test.ts` verifies that `begin_scan_ingestion`,
  `hydrate_identification_dictionary`, and `apply_or_stage_scan_context` are
  service-role-only and that deferred context is RLS-protected and merged at
  scan insert. `_shared/identify/latencyDb_test.ts` exercises the canonical
  `_shared/scanIngestionJobs.ts` setup client and verifies that it consumes the
  RPC's server-canonicalized upload-session ids, checksums, stage, and
  already-complete state. `dwca_download_and_scan_finalization_security.sql`
  exercises the same invariants against a fresh PostgreSQL catalog with pgTAP.
- `MerianNetworkClientTests` verifies pinned-session `OPTIONS` prewarming,
  idempotent inline request-body completion, and owner-scoped
  `/update-scan-context` construction. It also verifies single-status recovery,
  combined Explore recovery/media restoration, and the Ask/Field Chat repair
  seams. Its route-retry coverage also cancels a replayable request after its
  first dispatch and proves no second request is issued or noncanonical
  `URLError.cancelled` escapes the task-owned transport boundary.
  `MerianConfigTests` locks customer-facing Explore error translation;
  `InsightChatTests` locks retryable still-syncing feedback.

Before production percentage increases, run a device/simulator lifecycle matrix
for slow WeatherKit, reverse geocoding, awards, Field trips, Wikipedia, and
GBIF. Primary cache-miss Wikipedia/GBIF resolution and scan persistence may
extend the server `post_gemini`/end-to-end interval because they are now part of
durable success; they must stay within the Edge/client timeout and be
rebaselined separately from response-to-first-render. Analytics, group tags,
candidate enrichment, awards, and Field trips must not delay the result.
Exercise queue durability rejection, inline request failure, connectivity loss,
app background during upload, termination/relaunch, duplicate live/background
completion, and the two-second upload fail-safe. Verify specifically that
releasing the body-upload hold does not release foreground inference ownership:
staged recovery media must wait until live success, failure, cancellation, or
app backgrounding resolves that ownership. After replacement B is registered, a
delayed body-sent callback carrying A must also leave B's recovery-upload hold
intact. Cancelling the current owner must release its hold synchronously before
its now-invalidated task exits. Run the same-scan overlap case with foreground
generation A replaced by B: `BackgroundDatabaseActorTests` must reject A's
fenced save, and `OfflineQueueManagerTests` must prove A can neither release B's
durable claim nor cancel B's retry slot or delete B's queued row.
`InferenceEngineTests` must also prove that background recovery invalidates A's
presentation UUID before cancellation, so A cannot resume an error/result commit
over the recovered UI state. Exercise visual and nonvisual replacement at task
entry, after an awaited preflight operation, and immediately before provider
dispatch. Once A has been retired or B has replaced it, A must not issue a
provider request, emit failure telemetry, record a circuit-breaker failure,
trigger an error haptic, or publish an error placeholder. The terminal-error
case must also prove that the valid current owner can snapshot its full
ownership, register synchronous retirement, and publish its own error without
reopening the stale-task window.
`foregroundGenerationCannotBeStartedTwiceOrDuringRetirement` covers both
single-use boundaries: a duplicate active UUID is an idempotent no-op, and the
same UUID cannot restart between synchronous cancellation and the asynchronous
durable handoff. It also forces the first handoff to run without a model
context, proving a transient local-database failure retains the exact owner and
retries successfully after the context returns. The duplicate claim assertion
targets the manager-owned registry, so the guarantee is process-wide rather than
scoped to one `InferenceEngine` instance. The same test verifies that registry
retirement alone rejects a delayed UI result before raw durable ownership is
cleared; `staleLiveGenerationCannotPersistOverReplacementAttempt` locks the
equivalent database-persistence fence.
`confidenceZeroResponseIsTerminalWithoutPersistence` preserves the valid
no-record terminal contract without issuing a redundant provider retry, while
`confidenceZeroResponseWithWrongScanIdRemainsRecoverable` and
`generatedBackgroundResultRejectsWrongScanId` prove that no-record and
background paths still fail closed on callback identity.
`loadingPersistedScanRelinquishesExactLiveOwner` verifies navigation to a
historical record cancels the live provider task, releases only its exact
foreground owner and upload hold, and preserves the queued capture for recovery.
Queue scenarios must keep a description-only zero-byte job in `.staged`; the
user-facing submission path must create that row before online Describe provider
dispatch so its persistence is covered by the same durable fence. When recovery
takes ownership, verify its pre-dispatch status check polls a
processing/finalizing server job and accepts fractional PostgreSQL `retry_after`
timestamps. Inspect `Server-Timing` and the one-shot first-draw marker rather
than treating a successful build or state assignment as latency proof. Run one
Free and one Pro scan and verify the expected model/configuration and exactly
one primary identification model call.

Field trip capture guidance has focused coverage on both sides of the Edge
boundary. `_tests/fieldTripsMigrationContract.test.ts` source-locks the private
RPC grants, verified-user Edge call, filtering/order clauses, preservation of a
standard field trip after a Seasonal Challenge join, exclusion of
challenge-specific progress, the non-destructive retirement of placeholder
templates, and the evidence-free capture projection. It also locks the private
catalog/detail `completed_scan_id` projection, detail-only publication status,
owner/non-deleted join, service-role-only grants, and credited-level/count
fields in both scan- progress RPCs. The persistent-contribution contract
additionally locks the migration abort guard, private preference table,
one-credit uniqueness and scan-first indexes, preferred-goal validation/ranking,
correction invalidation, service-role-only contribution RPC, and
evidence-minimal projection. The atomic-hardening contract locks the
receipt/trigger/transactional entry point, publication-ID repair, empty
security-definer search paths, and global Field trip/Event ACL revocation.
`_tests/fieldTripCaptureContextDb.test.ts` exercises those rules against local
Postgres, including empty results; it reports a skip when the local stack is not
available, and that skip must not be counted as database validation.
`_tests/fieldTripProgressDb.test.ts` exercises standard and challenge
credited-level responses across explicit-start/join eligibility, one credit per
experience, several active experiences, delayed upload after an outing/Event
ends, preferred-goal priority, deterministic fallback, advancement, unfinished
correction removal/move after deactivation, completed-experience immutability,
ownership isolation, concurrency, and idempotent reapplication under the same
local-stack requirement. Its active-catalog matrix also locks the narrow goal
boundaries introduced by `20260722211636_tighten_field_trip_goal_matching.sql`:
butterfly versus moth, spider versus tick/scorpion, bee/wasp versus ant/sawfly,
animal versus plant for ecology goals, flowering/fruiting plant kingdom gates,
and meadow plant versus meadow animal. Every narrowed rule has representative
positive and negative coverage; additions or label changes must update both that
matrix and the canonical criteria table in
`docs/features-and-hardware/25-field-trips.md`.
`_tests/fieldTripAtomicProgressDb.test.ts` executes ingestion-triggered standard
and Event progress, preference and first-achievement evaluation, receipt replay,
and an injected Event failure that must roll everything back.
`_tests/fieldTripSecurityDb.test.ts` enumerates every matching
`SECURITY DEFINER` function, denies `anon` and `authenticated`, verifies an
empty search path, and requires effective `service_role` execution to match the
central reviewed allowlist exactly. Internal trigger/helpers therefore remain
non-executable rather than receiving a blanket service grant.
`_tests/fieldTripPublicationDb.test.ts` publishes a completed outing and proves
its snapshot items use the created publication ID.
`_tests/fieldTripActions.test.ts` compares the complete Edge allowlist with a
manually maintained snapshot of the actions emitted by iOS and verifies that
missing and unknown actions are rejected. It does not parse Swift source, so
review the client call sites and update both arrays whenever an action is added,
renamed, or retired. `FieldTripCaptureContextModelsTests` covers capture-context
decoding, while `FieldTripAPIModelsTests` covers the optional completing scan ID
used by catalog/detail thumbnails, published status, optional removed-item
metadata, and standard/Event contribution decoding plus typed destinations. A
separate legacy-payload test ensures absent publication fields decode as Private
during rollout. The progress-response tests cover both the legacy shape and an
extended level- advancement shape where current counts are `0/N` but credited
counts are the completed full level. `AchievementToastPresenterTests` covers
delayed strict ordering, multiple standard/challenge destinations, common-name
fallback, progress failure, empty matches, completed-level rings, and
foreground/background scan-ID deduplication. `InsightSheetViewModelTests` covers
contribution loading, scan-change race rejection, silent error/empty states,
queued/unauthenticated/ non-biological gates, Events filtering, invalidation
reload, and root/embedded routing in addition to the dictionary eligibility
policy. `OfflineQueuedScanDeletionTests` verifies normal cancellation removes a
goal hint while successful scan finalization preserves it until explicit
progress acknowledgement. `MerianNetworkClientTests` locks the nested snake-case
`preferred_goal` ingestion payload; ingestion intent/compatibility/replay Deno
tests prove the preference survives server-side background reconstruction.
`ActiveCaptureGoalStoreTests` covers the Field trip-to-`CaptureGoal` provider
mapping, server-order preservation, typed destinations, bidirectional
wraparound, completion advancement, account-isolated versioned caching,
refresh-failure retention, single-fetch coalescing for overlapping startup
freshness checks, indicator presentation/gesture policy, exact-art fallback,
user-visibility gating, and focused Explore route compatibility. The exact-art
test includes the renamed Park **Spider**, **Bird**, and **Meadow plant**
prompts while retaining aliases for historical publication snapshots. Capture
preference tests cover visible selected-goal priority across automatic,
crop-confirmed, and manual camera-still submission. `StagedCaptureTests` locks
the camera-only media gate so gallery, mixed camera/gallery, audio, video,
Describe, Record, refinement, and missing selections cannot persist a hint.
Capture startup diagnostics must also exercise the user-configurable first-mode
matrix. For each of Camera, Audio, and Description, persist that mode first,
cold-launch with `AG_PRINT_CYCLES=3`, leave the default page idle long enough
for initial tasks and sheets to settle, and require no `AttributeGraph: cycle`
output. Description-first QA must also confirm the question content scrolls, the
keyboard dismisses on drag, the table-of-contents sheet opens, and dictation
stops when leaving the mode. Preserve the lazy horizontal pager, the UIKit
Describe vertical-scroll boundary, workspace-owned lifecycle/sheet state, and
the fixed capture-bar layout reservation when extending these surfaces.
`merianUITests.testAudioFirstLaunchSelectsRecordMode` locks the reordered Audio
launch selection. `testDescribeFirstLaunchRendersAndOpensPrompts` locks the
Description-first selection, render path, and workspace-owned prompt-sheet
interaction. It also compares rendered frames: all three Describe controls must
share a centerline, and the rounded editor must end 8...32 pt above the row. The
upper bound ensures the flexible editor fills the available page height instead
of leaving a blank band above the controls. The question navigation must also
begin 8...32 pt below the mode selector; this upper bound catches a duplicated
top-safe-area reservation. Strict cycle tracing remains a separate diagnostic
requirement.

After installing the intended Debug build on a disposable booted simulator, run
each mode as a separate cold launch. Launch arguments override the stored order
for that process without changing the simulator's persistent preference:

```bash
SIMCTL_CHILD_AG_PRINT_CYCLES=3 xcrun simctl launch --terminate-running-process --console booted app.merian.Merian -captureModeOrder visual,audio,describe
SIMCTL_CHILD_AG_PRINT_CYCLES=3 xcrun simctl launch --terminate-running-process --console booted app.merian.Merian -captureModeOrder audio,visual,describe
SIMCTL_CHILD_AG_PRINT_CYCLES=3 xcrun simctl launch --terminate-running-process --console booted app.merian.Merian -captureModeOrder describe,visual,audio
```

For each run, require the selected segmented mode to match the first argument,
leave the workspace idle for startup work to settle, and fail the check on any
`AttributeGraph: cycle detected` line. Audio-first must not start camera
hardware. Description-first must render the input, open **Prompts** through
`DescribePrompts`, scroll vertically, dismiss the keyboard on drag, and stop
dictation when changing modes. It must also keep the editor clear of the prompt,
submit, and dictation row rather than letting those controls straddle its bottom
edge. `AppDIContainerTests` verifies the presentation preference defaults on and
persists an explicit opt-out. `AppTelemetryTests` locks the coarse
action/source-only event shape and prevents goal content or identifiers from
entering analytics. UI/device QA must also confirm Dynamic Type, VoiceOver
adjustable actions, Reduce Motion, light/dark appearance, idle visual-only
visibility, and that target swipes do not page capture modes. The architectural
test obligations for future sources are recorded in
`docs/rfcs/active-capture-goal-context.md`.

Explore identity database coverage lives in `_tests/exploreIdentityDb.test.ts`.
It verifies safe identity derivation, custom-avatar precedence, ownership
repair, a stable row version after a converged refresh, and execute privileges
limited to `service_role`. The shared DB helper may skip only when it is using
the absent default local stack. Set `SUPABASE_DB_TEST_URL` for CI or release
checks; an unreachable explicitly configured URL is a test failure, so a
successful run proves the test actually connected.

The split release gates have explicit regression coverage.
`FieldTripsAvailabilityTests` locks standard Field trips on for every account
and device, locks the `.fieldTripEvents` production default off until an
intentional release edit, and verifies the staged tester/simulator bypass plus
the future public path. `FieldTripAPIModelsTests`,
`ActiveCaptureGoalStoreTests`, profile visibility tests, and
`AchievementToastPresenterTests` verify that Events-disabled clients do not
fetch or expose challenge-only UI, routes, badges, cached achievement evidence,
or progress toasts. Before an Events release, manually test a physical
allowlisted account, a physical non-allowlisted account, a ghost user, and a
simulator build; also confirm DEBUG startup logs
`TODO(field-trip-events-release)`.

Progress-toast device QA must use the DEBUG Settings preview at compact and
large widths with long species/trip names, VoiceOver, and Reduced Motion. A live
scan matrix must confirm standard outing toasts precede Seasonal Challenge
toasts, achievements, and **New to Naturebook**; standard taps focus the first
credited goal, challenge taps open challenge detail, and progress refresh events
do not create a duplicate plain banner. Re-identify an older scan after level
advancement and confirm only rows inserted by that attempt supply destinations,
newly completed items, and credited rings.

Manual completion-evidence QA must use a non-leading checklist item to catch
count-based slot inference, cover photo and video-poster thumbnails, verify the
neutral border/no blue completion outline, and open the completed scan from both
catalog and detail into the embedded Insight route. Back must return to the
outing, and a locally unavailable scan must preserve the placeholder without
opening a blank Insight.

Publication-status QA must cover unstarted, in-progress,
completed-but-unpublished, published, and deleted-publication outings. Only the
published case shows the green globe badge; VoiceOver must distinguish a public
snapshot from a private outing, and long titles must wrap without compressing
the fixed-size badge.

Field Notes editor policy coverage lives in
`MerianTests/Features/Insights/FieldNotesEditPolicyTests.swift`. It locks
unchanged public/private drafts as no-ops, distinguishes content edits from
effective visibility transitions, covers clearing public notes, and keeps
content-only feedback separate from public/private transition feedback. Run the
focused suite after changing `FieldNotesSheet`, Explore detail field-note saves,
or shared field-note feedback:

```bash
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj \
  -destination 'id=<BOOTED_SIMULATOR_ID>' \
  -only-testing:merianTests/FieldNotesEditPolicyTests test
```

Manual QA must cover owned Explore posts with both Published and Private notes.
Open the editor and close it unchanged with X and with a swipe; neither path may
show a toast, invoke the public update, clear/reload detail content, or move the
detail scroll position. Editing text without changing visibility must autosave
and show `Field notes updated`; changing visibility must show only the matching
public/private transition message. Clearing notes and a failed public save must
retain their existing confirmation and inline-error behavior.

Explore audio poster coverage is split by contract seam:
`_shared/audioSpectrogram_test.ts` validates PCM WAV decoding, iOS-compatible
FFT raster dimensions, PNG decompression, deterministic R2 keys, cache reuse,
and unsupported-codec fallback; `share-scan-to-explore/db_test.ts` verifies the
generated URL is copied into the public snapshot and normalized asset;
`backfill-explore-audio-spectrograms/worker_test.ts` locks bounded historical
repair; `update-explore-field-notes/db_test.ts` verifies edit media is approved
before thumbnail attachment; and `_shared/scanMediaDeletion_test.ts` verifies
derived thumbnails are included in coordinated R2 cleanup.

iOS audio playback policy coverage lives in
`MerianTests/Features/Explore/ExploreAudioBoostTests.swift` because the focused
suite exercises the shared Core policy and both playback surfaces. The
`insightAudioPlayheadUsesLivePlayerTimeOnlyDuringPlayback` and
`exploreAudioPlayheadUsesLivePlayerTimeOnlyDuringPlayback` tests require live
player time only when UI intent and the concrete player are both playing, and
require stored progress while paused, waiting, or seeking. The same suite passes
`NaN`, infinity, non-positive dimensions, and out-of-range progress through
`AudioSpectrogramSeekingPolicy` and `ExploreDetailZoomLayoutPolicy`; every
returned frame/offset must be finite, clamped, or absent.
`boostedAudioIsFullyReadableBeforePublication` verifies every rendered frame can
be reopened and decoded; the source-handoff and failure-recovery tests lock idle
replacement and last-confirmed-position fallback.

Run the focused regression suite after changing the Explore/Insight playhead,
audio boost rendering, or source handoff:

```bash
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:merianTests/ExploreAudioBoostTests test
```

Device QA must cold-open an audio-backed Insight with boost enabled and play the
clip through its midpoint on the first attempt, then replay it. Neither pass may
stall, lose the line, jump to the end, or remain falsely playing. In Explore,
play the same short and 15-second post in both feed and detail and confirm the
line moves continuously with audible playback, remains parked during buffering
and pause, does not snap backward on pause, and reaches the end with the audio.
Also confirm the elapsed/total badge still advances at its lower cadence, the
spectrogram does not visibly rerender, feed navigation gestures are unchanged,
and detail seeking still behaves as documented.

### `validate_edge_dtos.ts`

- **Canonical executable source**:
  `services/supabase/functions/_shared/identify/contract.ts` is a
  dependency-free typed descriptor for the provider output and complete final
  `{ success, data }` response. Provider schemas, deployed TypeScript payload
  types, recursive runtime parsers, and generated Swift DTOs all consume this
  descriptor. There is no source-text inference, global identifier map,
  TypeScript symbol lookup, or Swift declaration parser to silently bind to the
  wrong declaration.
- **Typed provider seam**: `_shared/identify/googleSchema.ts` recursively adapts
  the provider-neutral projection to the pinned `@google/genai` `Schema`. Every
  SDK schema field is structurally checked at compile time; only the SDK's
  string-enum `type` representation crosses one narrow cast. The SDK import is
  type-only, so schema validation does not gain environment permissions or
  provider startup side effects.
- **Runtime assurance**: The provider result is parsed against the model
  contract immediately after JSON extraction. After name normalization, cache
  hydration, candidate enrichment, and server-added fields, the full response
  envelope is parsed again before persistence or delivery. Parsing recursively
  checks nested objects, arrays, requiredness, nullability, enums, unknown-key
  policy, string and array limits, safe integer semantics, and finite numeric
  bounds. Describe additionally enforces `is_live_capture=false` and zero image
  quality, while every successful final envelope enforces `success=true` and its
  always-emitted core fields. A final contract failure logs internal detail but
  returns only HTTP `502` with `code: "identify_response_invalid"`.
- **Generated Swift boundary**: `validate_edge_dtos.ts` deterministically
  generates the marked Identify DTO block in `InferenceEdgeDTOs.swift`.
  Generated structs own their types, nested structure, explicit `CodingKeys`,
  and explicit `init(from:)`; the gate compares that block byte-for-byte with
  the contract output. Because decoding is declared in the generated type, an
  extension cannot silently replace it. The ownership scan also gives an early,
  focused error for direct or aliased extensions and top-level generated DTO
  redeclarations anywhere under `apps/ios`. Keep wire DTOs, including
  `PetIdentificationDTO`, in the generated block and map them into domain models
  after decoding.
- **Compatibility and numbers**: The final server contract is strict. Root Swift
  response properties are intentionally generated as optional so older cached
  responses and staggered client/server rollouts continue to decode. Every
  numeric node declares bounds that are enforced in the Edge runtime; integer
  values must be safe JavaScript integers and generate signed Swift `Int`, while
  JSON numbers generate Swift `Double`. Narrow integer and floating-point DTOs
  are not inferred from spelling or nominal range. `ai_reasoning` and
  `extracted_visual_traits` are intentional server-only fields: iOS receives
  reasoning under `insight_data` and does not decode retained visual traits.
- **CI gates**: `deploy.yml` invokes the complete discovery-based
  `test_supabase_tooling.sh` suite before any migration or Edge deployment,
  while `ios-project-guardrails.yml` invokes the isolated
  `validate_edge_dto_contract.sh` lane for every iOS source change. Both run the
  adversarial generator regression tests, the exact checked-in comparison, and
  deployed runtime-contract tests. The read allowlist includes the complete
  `apps/ios` tree and asserts every current production source root is present.
  Shared-contract/tooling changes trigger both lanes; arbitrary app Swift
  changes trigger the lightweight iOS guardrail without initiating a backend
  deployment. The validator uses a separate frozen, third-party-free Deno config
  and lock.
- **Route integration coverage**: `_tests/identifyContractCoverage.test.ts`
  proves every Identify entrypoint parses the provider's unknown JSON, performs
  the final envelope parse before persistence/finalization, settles a charged
  invalid response as failed, and returns only the parsed envelope with the
  stable public error code.
- **Intentional changes**: Edit `contract.ts`, run
  `make generate-edge-dto-contract`, review the Swift code-generation diff, and
  run `make validate-edge-dto-contract`. Do not hand-edit the generated block.
  Tests must accompany any new server-only field or source-root policy change.
- **Enrich response coverage**: `EnrichData.similar_species` and
  `SimilarSpeciesEntry` are a separate endpoint contract. Their additive
  metadata and legacy decoding behavior are covered by `InferenceEngineTests`,
  `MerianNetworkClientTests`, and the focused `enrich-scan` Deno tests rather
  than this Identify schema validator.
- **Lookalike relation metadata**: Swift and Deno tests cover the additive
  `reason`, `visual_traits`, `confidence`, source/review, direction, and order
  fields. Older payloads and cached `lookalikesData` blobs without those keys
  must still decode successfully with empty/default metadata.
- **Public species projection privacy contract**:
  `_shared/publicSpeciesProjection_test.ts` builds a dictionary payload from a
  row fixture that includes scan/user/private fields and asserts those fields
  are not projected. It also verifies
  `publicSpeciesProjectionForbiddenKeys(...)` catches explicit leaks such as
  `scan_id`, `field_notes`, coordinates, and per-scan AI reasoning. This
  protects `/species-dictionary`, Explore detail similar species, and the
  shipped web species endpoint from mixing species-level dictionary data with
  scan-specific content.
- **Public species content quality**: `_shared/publicSpeciesProjection_test.ts`
  classifies dictionary rows as `complete`, `sparse`, or `needs_enrichment` from
  public reference-image, overview, habitat/distribution, and taxonomy signals.
  This keeps sparse-page UI behavior deterministic across iOS and the web
  frontend.
- **Exact external reference-media policy**:
  `_shared/externalImagePolicy_test.ts` covers original/resized/query variants
  and unrelated media; `_shared/external_test.ts` verifies live Wikipedia/GBIF
  enrichment omits the denied URL and keeps the next result;
  `_shared/publicSpeciesProjection_test.ts` covers normalized, legacy, and
  first-image promotion; and `refresh-species-content/db.test.ts` verifies
  neither cache nor normalized RPC writes receive the denied media.
- **Current-scan reference-image exclusion**: `InsightSheetViewModelTests`
  verifies Naturebook host/object-path matching, strict external URL identity,
  corrected page counts, shared inline/fullscreen ordering, preservation of
  other-scan and Wikipedia references, and `.loaded`-to-`.empty` normalization
  for all-duplicate sets. `MerianNetworkClientTests` verifies Explore reference
  attribution survives client-side filtering. On the backend,
  `_tests/migrationMediaContract.test.ts` locks the helper and unchanged RPC
  projection contract, while `_tests/explorePostDetailDb.test.ts` covers exact
  current-scan exclusion, other-scan preservation, ordered external references,
  and legacy fallback against Postgres.
- **Public web media attribution audit**:
  `_shared/publicSpeciesProjection_test.ts` covers
  `publicWebReferenceImageAttributionIssues(...)`, which the web species mapper
  runs before rendering or selecting metadata images. The audit flags every
  public image missing `license` or `attribution`.
- **Public species URL compatibility**: `apps/web/lib/species.test.ts` verifies
  lowercase ASCII slug generation, common/scientific/generic fallbacks, the
  80-character bound, canonical UUID-plus-slug paths, UUID-only and stale-slug
  redirect decisions, UUID validation, native UUID URLs, metadata, and the exact
  AASA path list. `SpeciesDictionaryTests` locks the same canonical iOS share
  URL and slug rules, while `MessageScanShareCacheTests` verifies canonical,
  UUID-only, stale-slug, legacy-host, and custom-scheme parsing all produce only
  the normalized UUID.
- **Species content provenance contract**:
  `_shared/speciesContentProvenance_test.ts` verifies source assignment and
  refresh windows for dictionary fields, group tags, and lookalikes. It should
  be updated whenever `species_content_provenance.content_key`, source defaults,
  or refresh scheduling rules change.
- **Scheduled species content refresh worker**:
  `refresh-species-content/db.test.ts` verifies request validation, queue
  grouping/skipping, selective GBIF/Wikipedia field updates, reference-image RPC
  payload mapping, and provenance writes with a mocked Supabase client. It
  should be updated whenever the worker supports a new `content_key` or changes
  refresh safety rules.
- **Scheduled species model-content worker**:
  `refresh-species-model-content/db.test.ts` verifies request validation,
  service-role job claiming, habitat/lookalike/group-tag persistence, and
  provenance/job completion behavior with a mocked Supabase client. It should be
  updated whenever the model-heavy `content_group` set or retry semantics
  change.
- **Species dictionary enrichment migration contract**:
  `_tests/speciesContentMigrationContract.test.ts` reads
  `20260707153931_species_dictionary_enrichment_queue_backfill.sql` directly and
  asserts that sparse rows and every future insert path enqueue only the missing
  `gbif_wikipedia_reference`, `habitat`, `lookalikes`, and `group_tags` jobs.
  Run it with `--allow-read=services/supabase/migrations`.
- **Exact-media migration contract and database behavior**:
  `_tests/speciesContentMigrationContract.test.ts` locks the cleanup, filtered
  projection, and trigger definitions in
  `20260719023147_suppress_european_wildcat_roadkill_image.sql`.
  `_tests/merianReferenceImagesDb.test.ts` verifies the migration removes
  normalized and legacy variants, rejects reinsertion through the write
  backstop, and promotes the next permitted SQL result. The database test needs
  a running local Supabase/Postgres instance.
- **Scheduled Merian reference-image worker**:
  `refresh-merian-reference-images/db.test.ts` verifies request validation and
  RPC invocation; `_tests/merianReferenceImagesDb.test.ts` verifies threshold
  filtering for both image quality and species confidence, all-photo candidate
  expansion, per-species caps, confirmed-species resolution, Merian-first
  ordering, source visibility removal, and preservation across external
  GBIF/Wikipedia refreshes.
- **Public dictionary cache headers**: `_shared/http_test.ts` verifies
  `jsonResponse(...)` can merge endpoint-specific cache headers without dropping
  standard JSON/CORS headers. `/species-dictionary` uses this path for cacheable
  `200 OK` public dictionary responses; error responses stay uncached.

### `export-dwca/index_test.ts`

- **Global Anonymization**: Proves global rows use deterministic, versioned HMAC
  pseudonyms while personal rows retain the owner's UUID.
- **Precision Preservation**: Validates that personal, non-protected rows honor
  the canonical precision flag.
- **Protected Species Truncation**: Validates that matching protected statuses
  (`endangered`, `vulnerable`) explicitly drops exact map coordinates down to
  single-digit resolution metrics (`Math.round(lat * 10) / 10`) regardless of
  the original `gps_lat_exact` fields, completely shielding sensitive flora and
  fauna.
- **Null `species_dictionary` handling**:
  `generateDwcARow handles null species_dictionary without throwing` and
  `produces an empty scientific_name field` — guards against the pre-fix `|| {}`
  pattern that caused `deno check` failures when `scan.species_dictionary` was
  null. Verifies the optional-chaining fix (`species?.scientific_name`) produces
  a valid CSV row (not a JS runtime error string) for scans ingested before the
  species enrichment pipeline ran.

The surrounding export suite is intentionally split by boundary:

- `_shared/dwcaReleaseState_test.ts` proves only an explicit database Boolean is
  accepted and an unavailable/malformed service-only state fails closed.
- `request-export-dwca/db_test.ts` proves the route calls only the atomic
  request RPC and strictly maps `disabled`, `rate_limited`, `already_pending`,
  and UUID-bearing `queued` responses.
- `_tests/dwcaLaunchGateCoverage.test.ts` locks the private default-off
  singleton, first BEFORE INSERT trigger, per-user advisory request lock,
  constraint-specific duplicate handling, queue terminalization, grant
  revocation, continuation removal, cleanup retention, Edge boundary checks, and
  Release iOS presentation flag.
- `tests/dwca_export_launch_gate_security.sql` executes default-off state,
  table/routine ACL, static PL/pgSQL, transactional request denial,
  direct-insert denial, continuation absence, and archive-cleanup schedule
  presence against a disposable catalog.
- `archive_test.ts` proves occurrence and multimedia rows are appended
  incrementally, each bounded output includes its exact CRC, and encoding fails
  while appending beyond the fixed output buffer.
- `crc32_test.ts` locks the standard CRC check vector, proves ordered chunk
  composition equals a direct concatenated checksum (including empty
  boundaries), verifies cached byte operators through the maximum safe
  byte-count range, and rejects unsafe durable checksum metadata.
- `db_test.ts` proves the worker uses the claim-bound source-page RPC, accepts
  only consistent row/byte metadata, recognizes the empty completion sentinel,
  recognizes a changed-revision sentinel, and rejects oversized source rows,
  arrays, or multibyte elements measured in UTF-8 bytes. It also validates
  bounded due-job discovery and fail-closed queue-health parsing.
- `drain_test.ts` proves targeted intake fan-out is limited to one job,
  sequential scheduled oldest-due waves, soft-deadline exit, bounded discovery
  responses, failed-job suppression, and age/depth/expired-claim health
  classification with deterministic clocks.
- `pseudonym_test.ts` proves HMAC determinism, domain/key-version rotation, and
  fail-closed missing/short Base64 keys.
- `zip_test.ts` opens the lazy ZIP with an independent reader, checks
  deterministic output using precomputed entry CRCs, and proves assembly fails
  closed when streamed bytes do not match the durable manifest length.
- `storage_test.ts` proves fixed-size multipart buffering, bounded provider XML,
  completion, 30-second read-only archive signing, strict archive-key deletion,
  rejection of an embedded HTTP-200 `<Error>`, and best-effort abort after a
  failed part or completion. Work-chunk reads prove exact manifest bytes both
  with a valid declared length and with no `Content-Length`; absent length is
  never coerced to zero, and the streamed byte ceiling remains authoritative.
- `_shared/aws_test.ts` and `_shared/identify/moderation_test.ts` prove
  completion-sensitive R2 deletion accepts only 2xx or idempotent 404, rejects
  provider failure, and rolls back already-promoted public objects when staging
  deletion cannot be confirmed.
- `scripts/monitor_dwca_export_queue_test.ts` proves production monitor
  thresholds, continuation and archive-cleanup aggregate-response consistency,
  independent expired-lease/stuck-delete severity, failure policy, stable
  catalog/read/shape failure classification, always-fail acquisition behavior,
  unavailable queue values, raw-detail suppression, and operator-summary
  rendering.
- `tests/dwca_export_queue_security.sql` executes the service-only health RPC
  across due, live-claim, and expired-claim states and verifies its ACL,
  privilege allowlist, and outstanding-job partial index.
- `_shared/aws_test.ts` loads `docs/r2-lifecycle.json` and requires the global
  seven-day incomplete-multipart abort rule while continuing to reject any
  expiration rule for durable avatars. Deployment smoke checks separately
  require no expiration rule for durable free uploads or Pro uploads.
- `mail_test.ts` locks the job-scoped Resend idempotency key, bounded reply
  parsing, deterministic 4xx terminality, and ambiguous/transient retry
  classification.
- `worker_test.ts` proves duplicate deliveries do no work, the database claim is
  canonical, exactly one durable phase executes per call, row/byte overflows are
  terminal, source-snapshot changes are terminal before encoding/assembly/email,
  delivery revalidates after recipient lookup, an in-flight provider acceptance
  cannot make a newly invalid export complete, invalidated objects enter durable
  cleanup, permanent delivery rejection cannot retry forever, temporary chunk
  and final archive keys include the claim token, staged archives are reused
  privately, and only the winning lease can advance/finalize.
- `_tests/exportDwcaSecurityCoverage.test.ts` rejects webhook authority creep,
  public global-export access, OFFSET/full-buffer regressions, unbounded
  invocation work, JWT-secret reuse, and fallback salts.
- `_tests/exportDwcaMigrationContract.test.ts` locks the claim/RPC/index/grant
  migration shape, immutable canonical budgets, durable phase/cursor/manifest,
  lock-safe install/validation ordering, validated source
  cardinality/element-byte constraints, claim-bound 100-row/256 KiB source
  pages, version-2 creation-time immutable occurrence/multimedia DTOs,
  authoritative confirmed identity, row-at-a-time aggregate source-byte
  enforcement, page and full-member privacy fences, durable invalidation,
  private processing capabilities, failed DTO purge, 512 KiB chunks, claim-token
  key validation, minute resume cron, sorted canonical-job fencing before chunk
  DDL, and replacement CRC-bearing advance/manifest signatures and ACLs.
- `tests/export_dwca_security.sql` executes the ACL, live-lease, stale-token,
  immutable-row/result, finite rollout cohort, old-worker overwrite rejection,
  legacy-error sanitization, post-deadline claim, validated source constraints,
  aggregate page-byte cutoff, immutable DTOs, confirmed-identity projection,
  exact-GPS omission for non-precise jobs, ordinary-edit stability, live privacy
  revocation, private delivery URL constraints, phased cursor/manifest
  transition, terminal private-capability cleanup, budget overflow, and
  idempotent-completion contract against local Postgres.
- `tests/export_dwca_snapshot_security.sql` independently proves job insertion
  freezes both phase DTOs, later scans stay excluded, live taxonomy/media edits
  cannot change stored payloads, personal geoprivacy is scope-irrelevant, a
  protected-species coordinate-policy escalation or tombstone revocation returns
  no payload, an early paged row fails the full pre-assembly fence, oversized
  aggregate projection stops without retaining partial rows, snapshot routines
  pass static PL/pgSQL validation, and a terminal failed job purges the DTOs.
  `privileged_routine_security.sql` independently runs static
  PL/pgSQL/search-path/grant validation over the new definer RPCs.
- `downloadGrant_test.ts` and `download-dwca/*_test.ts` prove 256-bit opaque
  capability generation, hash lookup, exact query shape, stable fail-closed
  states, distributed retry windows, and no-store 30-second read redirects.
- `reconcile-dwca-archive-cleanup/*_test.ts` proves bounded oldest-due claim
  waves, delete concurrency, idempotent completion, durable release, runtime
  deadline exit, malformed-row rejection, and aggregate health thresholds.
- `delete-scan/db_test.ts` distinguishes true absence from database failure and
  locks the request-before-storage/completion-after-storage RPC boundary.
- `auto-purge-nonbio/db_test.ts` proves the retention intake accepts only
  bounded integer RPC results and fails closed on database errors, malformed
  values, and local/remote limit violations.
- `reconcile-scan-deletions/*_test.ts` proves strict claim/health parsing,
  owner-fence validation, bounded multi-wave draining, compare-before-release,
  runtime-deadline exit, and warning/critical erasure-SLA thresholds.
- `scan-media-health/health_test.ts` plus `monitor_scan_media_health_test.ts`
  prove independent aggregate deletion backlog/expired-lease alerting and
  actionable privacy-erasure ownership.
- `_tests/dwcaDownloadAndScanFinalizationMigrationContract.test.ts` locks the
  private grant/rate/outbox schema, per-click full-member fence, legacy URL
  scrub, cleanup cron/ACL ledger, shared scan-generation lock, parent-row then
  advisory lock order for mixed DwC-A transitions, complete claimed-key
  disposition, completion-last canonical media invariant, and the bounded
  generation-locked non-biological retention selector with service-only ACLs. It
  also fails closed if disposable-catalog fixtures regress to a reserved
  PL/pgSQL identifier, reuse a tombstoned scan generation, omit explicit
  wire-string-to-enum casts, or validate the retired source-state-first DwC-A
  trigger routines. It also requires deletion coverage to establish eligible
  same-generation ingestion evidence before expecting owner recovery, and
  rejects completion routines embedded in composite Boolean post-state
  assertions. Its static-analysis contract requires every trigger routine to
  declare the relation OID that supplies its trigger context; ordinary routines
  alone use relation OID zero.
- `tests/dwca_download_and_scan_finalization_security.sql` executes those ACL,
  static-validation, ordering, rate-limit, capability-state, cleanup-lease, and
  health contracts against a disposable catalog. It also proves cleanup for an
  older archive generation cannot revoke the replacement grant or purge its
  source snapshot, while exact-current terminal cleanup can, and proves
  retention fences only expired non-biological controls while recent,
  biological, and account-tombstoned controls remain unfenced. Its scan ACL
  check single-sources the exact five-column rolling-client update allowlist:
  table-level API mutation and every anonymous column mutation remain denied,
  authenticated insert/reference or non-allowlisted updates remain denied, and
  every allowlisted update must exist. The matching forward migration contract
  verifies table and historical column grants are cleared before RLS-governed
  API reads, exact `service_role` CRUD, and the compatibility allowlist are
  reinstalled.

Public-web migration/DB/source-boundary coverage proves direct detail owns the
canonical anonymous card predicate and page reads use one combined statement.
Focused tests cover revocation after preparation, during staging, before
delivery, after recipient lookup, and while provider delivery is in flight.
Fresh-catalog replay remains mandatory exact-SHA base-production evidence even
while exports are disabled. Hosted maximum-shape PostgreSQL/Edge, provider,
queue-throughput, and positive capability-delivery measurements move to the
later feature-enable gate. The regression matrix and release verdict are
maintained in
[`14-dwca-and-public-web-release-hold-2026-07-27.md`](../backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

The CRC tests deliberately assert correctness and bounded algorithm shape rather
than wall-clock timing, which is unstable on shared CI runners. The development
microbenchmark comparing cached versus per-part matrix construction is audit
evidence only. Production performance assurance before feature enable comes from
the maximum-shape hosted export and Metrics/546-log gate in the Supabase
deployment runbook; it is not inferred from the launch-disabled posture.

### `revenuecat-webhook/*_test.ts`

- **`signature_test.ts`**: Proves HMAC-SHA256 is calculated over the exact
  timestamp-prefixed raw body, supports multiple `v1` values, compares the
  digest safely, and rejects tampering plus timestamps outside the five-minute
  past/future window.
- **`index_test.ts`**: Validates the durable event ID and safe-integer event
  timestamp contract. It also locks current/original/alias UUID ordering,
  deduplication, anonymous handling, tombstone exclusion, and the separate
  `transferred_from` / `transferred_to` subject contract.
- **`subscriber_test.ts`**: Covers active and expired standard entitlements,
  recurring/grace-period expiry persistence, explicit lifetime null expiry,
  exact seven-day pass expiry, pass-refund exclusion with a later purchase,
  server API authentication/URL encoding, and fail-closed CustomerInfo errors.
- **`handler_test.ts`**: Uses mocked RevenueCat and database boundaries to prove
  the order is signature verification → payload validation → durable duplicate
  lookup → authoritative lookup → one mutation transaction. A committed
  duplicate makes no provider request; replay rejection and oversized bodies
  make no external calls; a future event cannot poison the database watermark;
  subscriber-API failure makes no mutation call; purely anonymous events skip
  the provider but receive a durable ignored receipt; and both sides of a
  transfer are reconciled before one mutation call.
- **`_tests/revenueCatWebhookCoverage.test.ts`**: Source contract that keeps the
  processing order, deadline-driven reconciliation route/configuration,
  independent backlog monitor, and all three GitHub/Supabase secret bindings
  present.
- **`_tests/revenueCatWebhookMigrationContract.test.ts`**: Static SQL contract
  for the unique event ledger, per-event subject table, ordering watermark,
  snapshot-primary ordering, deterministic multi-user row locks, durable
  reconciliation queue/leases/backoff, expired-claim partial index, oldest-due
  health RPC, 15-minute cron timeout, service-only
  duplicate/mutation/reconciliation RPCs, RLS, and explicit revocations.
- **`reconcile-revenuecat-subscribers/db_test.ts`**: Validates each bounded
  claim wave and rejects malformed or inconsistent queue-health responses.
- **`reconcile-revenuecat-subscribers/worker_test.ts`**: Proves repeated waves
  drain beyond the former ten-record ceiling, stop at the monotonic cutoff,
  retain the three-fetch concurrency bound, apply newer snapshots, release
  durable failures, and prevent a background sweep from newly granting
  historical non-renewing pass history.
- **`scripts/monitor_revenuecat_reconciliation_test.ts`**: Proves the 30/60
  minute age thresholds, expired-lease warning, fail policy, response schema,
  CLI safety, and operator summary.
- **`tests/revenuecat_webhook_security.sql`**: Executable pgTAP coverage for
  ACLs, direct-table isolation, duplicate delivery, a delayed expiration after
  renewal, a delayed purchase after refund, snapshot-primary ordering,
  reconciliation claim/application fencing, indexed expired-lease reclamation,
  backlog-health telemetry, event-ID/payload conflict, atomic transfer of source
  and destination, a deleted transfer source with a live destination,
  ambiguous-alias rejection, missing-user failure, and entitlement-version
  advancement. Keep this test in the disposable-database deployment gate
  alongside `privileged_routine_security.sql` and `ai_quota_security.sql`.

### `sync-collections/db_test.ts`

- **`syncMembershipDelta` error propagation**: Verifies the function throws (not
  `console.error`-swallows) when the scan validation query fails, when a
  membership delete operation is rejected, and resolves cleanly on success. Also
  asserts the early-return path for empty `ownedIds` makes no DB calls.
- **Composite membership cursor**: Verifies the existing-membership reader
  advances from the final `(collection_id, scan_id)` key of a full page and
  never falls back to range/OFFSET pagination before calculating the delta.

### `_shared/entitlement_test.ts` and `_shared/aiQuota_test.ts`

These replace the former worker-cache tests. Entitlement tests must prove every
call observes durable database state and never upgrades a query error or missing
profile. Quota helper tests must keep request IDs bounded to UUIDs, protect raw
network addresses with a strong rotating HMAC, and fail closed when
configuration is missing. Database atomicity and ACL behavior belong in
`tests/ai_quota_security.sql`, not a mocked TypeScript client.
