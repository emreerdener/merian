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
`lib/appShareContract.test.ts` also proves the prelaunch iOS app-share payload
uses the served canonical homepage rather than an unimplemented `/invite`
route, and that changes to either Swift destination source enter the web-quality
workflow. After the App Store listing is live, update the contract and iOS TODO
together to require the reviewed App Store Connect campaign link.

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

## Supabase Functions and Tooling

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

**Supabase Candidate Validation**
(`.github/workflows/supabase-candidate-validation.yml`) is the hosted,
validation-only release gate for that complete sequence. It reports on every
pull request, supports manual dispatch for an immutable candidate ref, and is
reused as the prerequisite of `.github/workflows/deploy.yml`. A lightweight,
full-history scope job reports the stable **Candidate readiness** check. The
detector covers every root read or scanned by the suite:
`.github`, `apps`, `docs`, `scripts`, `services/supabase`, and the maintained
root contracts. An unresolved comparison requires full validation rather than
silently skipping it, and a new unclassified repository root is in scope until
explicitly reviewed as build-only. Manual, merge-queue, and reusable non-PR
invocations always run the complete gate. The workflow verifies a clean exact
checkout, pins Deno `2.9.4` and Supabase CLI `2.109.1`,
checks every deployable Function graph, replays all migrations into a disposable
database, discovers every pgTAP catalog, runs the complete Deno task with
`SUPABASE_DB_TEST_URL`, and finishes with database lint plus security and
performance advisors. It declares no Production environment, receives no
production secrets, and contains no migration push, Function deployment, or
production smoke. A green candidate run is therefore database/runtime evidence,
not proof of deployment. Repository rules should require `Supabase Candidate
Validation / Candidate readiness`, not the conditionally executed validation
job.

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
unexpected `contents: write`. Its exact writer allowlist covers only the
taxonomy checklist's isolated writer. iOS distribution needs no repository
write grant because it runs through Xcode Organizer. Keep the security test in
both the complete Edge suite and the focused deployment-planner gate so
supply-chain regressions fail before any production credential or migration is
used.

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

> **Current consent candidate:** the former Terms-link compile defect and
> foreground-replay consent fixture are fixed and no longer active blockers.
> Account synchronization now also performs its identity check inside the final
> merge before any ledger or analytics mutation. Provider authorization now
> resolves the all-version stream head before disclosure compatibility, so an
> older-disclosure head revocation cannot be hidden by a current-version grant.
> Require a new hosted run on the
> unchanged candidate SHA; older totals and local runs are diagnostic history,
> not release evidence. See the
> [production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

- anything under `apps/ios/` or the embedded companion under `apps/watch/`;
- either generated Xcode project, `project.yml`, tracked build configuration,
  SwiftLint configuration, or iOS build scripts;
- every merge-queue commit and every manual dispatch.

For a release candidate whose final commits contain only backend, catalog-test,
or documentation changes after the last iOS input, manually dispatch this
workflow against the final exact SHA. Confirm the scope reason records a manual
dispatch and both macOS jobs run. A successful scope-only result is valid
changed-file reporting, but it is not compiled iOS release evidence and cannot
replace the complete unit target, both critical scan UI smokes, and
Release-archive gate.

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

A Dependabot pull request that crosses an action major is expected to stop at
this guardrail even when its commit SHA is valid. Review the upstream release,
including its runtime and runner requirements and any security changes; update
every use to one immutable commit with its matching inline release comment;
then advance the reviewed major in
`scripts/test-ios-build-and-test-workflow.sh`. Do not relax commit pinning or
accept a floating action tag to make the upgrade pass.

### Privacy Manifest Validation

The app privacy declaration has three independent evidence layers:

1. The portable project guardrail parses
   `apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy`, requires the exact
   reviewed collected-data and required-reason declarations, and proves the
   generated `Merian` target includes it exactly once in Resources.
2. The current-SHA Release archive requires
   `Merian.app/PrivacyInfo.xcprivacy` at the application-bundle root, validates
   the bundled copy, and records `privacy_manifest_valid: true` in archive
   evidence.
3. The exported-IPA validator requires exactly one
   `Payload/Merian.app/PrivacyInfo.xcprivacy`, validates the extracted plist,
   and rejects a missing, misplaced, malformed, tracking-enabled, or drifted
   declaration.

Run the source and adversarial fixtures with:

```bash
make validate-ios-privacy-manifest
make test-ios-ci-tooling
```

The fixtures cover malformed plists, unexpected keys, missing or duplicate
categories, tracking drift, wrong linking or purpose values, wrong
required-reason codes, missing archive resources, and invalid IPA placement.
These checks establish source and bundle integrity. They do not aggregate SDK
manifests or approve App Store privacy answers. Before release promotion, use
the signed Organizer archive to generate and review Xcode's aggregate privacy
report under the
[iOS App Privacy Manifest Contract](./16-ios-privacy-manifest.md).

### Transport Security Validation

Transport security has the same three evidence layers:

1. `make validate-ios-transport-security` parses the tracked main-app plist,
   rejects every broad/media/web/local/domain ATS exception, and permits only a
   credential-free HTTPS `SUPABASE_URL` or the tracked build-setting placeholder.
2. The current-SHA Release archive validator parses the final
   `Merian.app/Info.plist`, rejects unresolved settings and exceptions, and
   records `transport_security: "ats-default"` only after that check passes.
3. The exported-IPA validator repeats the check against the final
   `Payload/Merian.app/Info.plist`.

Run the source and adversarial fixtures with:

```bash
make validate-ios-transport-security
make test-ios-transport-security
```

The Swift suites independently prove `SecureTransportPolicy` rejects HTTP,
non-network schemes, credentials, and missing hosts, while preserving HTTPS and
app-owned local files. The loader fixture verifies rejection happens before an
HTTP request is dispatched. See the
[iOS App Transport Security Contract](./17-ios-transport-security.md).

1. **Full iOS unit tests** resolves only locked package versions, validates the
   generated-project source membership against `project.yml`, compiles the app
   plus both shared test bundles with `build-for-testing`, and executes the
   complete `merianTests` target with `test-without-building`. This prevents a
   newly added Swift or Objective-C file from escaping compilation when the
   committed Xcode project was not regenerated. The unit-test selector does not
   select or skip any suite. Xcode process-level parallel testing is disabled
   because several hardware, networking, and persistence suites exercise shared
   singletons. The result gate fails if Xcode returns success without a `Passed`
   result, a non-empty test run, zero skipped tests, an exact passed/total count
   match, and at least one passed test case from each critical concurrency
   boundary: `CameraManagerTests`, `InferenceEngineTests`,
   `OfflineQueueManagerTests`, and `SyncStateManagerTests`. It also fails closed
   unless the structured test tree contains exactly one matching passed suite
   for each critical boundary and reports every named scan-flow regression
   exactly once under exactly one matching passed suite as `Passed`. A duplicate
   matching suite, duplicate protected case, or failed-suite/passed-child
   contradiction is invalid evidence. The current validator protects 95 exact
   cases. Twenty-seven were added by the joined scan-reliability follow-up.
   Eleven more form the live-connectivity follow-up: nine engine-level ownership,
   presentation, and exact-generation recovery fences plus two network-client
   replay-policy controls. One additional case protects the pre-queue admission
   connectivity handoff: a path-satisfied transport failure plus local
   eligibility selects queue-only, while local ineligibility still paywalls and
   a non-connectivity preview failure still requires retry. One more protects
   automatic single-capture chrome:
   `automaticSingleCaptureNeverPresentsIdentifyBeforeSubmission` requires
   pending automatic ownership to suppress `ActiveScanToolbar`, requires a
   failed attempt to restore the staged retry toolbar, preserves the toolbar
   when explicit confirmation is enabled, and clears the suppression with the
   staged buffer. The same protected case also requires a pending required crop
   to suppress capture chrome before the crop cover is mounted. The XCTest
   gallery-flow coverage verifies that runtime ownership. The iOS workflow
   source contract separately requires native leading/trailing crop toolbar
   placements and rejects manual `GeometryProxy.safeAreaInsets.top` or
   `.safeAreaPadding(.top, ...)` positioning, whose zero-inset context caused
   controls to overlap the status bar. It also rejects a workspace-owned crop
   transition shield or persistent transition-state flag and requires the crop
   confirmation button to use the accent tint instead of an illegible white
   prominent fill. One final case
   protects pre-import admission:
   `exhaustedImageImportAdmissionBlocksBeforePickerAndCrop` requires a valid
   server denial to reach the paywall with no staged image or crop state, while
   proving the prospective single-image RPC shape remains Flash-eligible.
   Five menu/Field
   Notes regressions exposed by the
   prior failed hosted run are individually protected, two require the
   bounded/redacted offline-queue support artifact, one prevents needs-attention
   and live-path-ineligible rows
   from driving the Scan Library recovery loop while preserving staged and
   explicit-video-override eligibility, one preserves the current account by
   refreshing an invalid handler-owned session before replay, one fences
   attention rows from serialized claims, actor-owned global status selection,
   and orphan reconciliation, one proves the pending selector pages beyond
   delayed, locally blocked, and media-less rows instead of starving ready work or spending
   runnable capacity on quarantine candidates, one proves empty pending
   quarantine is state/media bound and cannot touch advanced work, one proves
   upload packing scans beyond empty/non-fitting head rows, admits later work
   that fits, and locks final constrained/expensive request policy for normal
   video, its mixed-media siblings, forced video, and standalone image
   transport, one proves the unsynced count excludes attention-only and
   non-runnable rows, one rejects empty queued staged media before upload
   signing, one rejects an empty foreground playback video before signing, one
   rejects manual retry of a legacy non-runnable import, one keeps required
   consent out of the network circuit while locking the **Approval needed** /
   **Scan saved** UX across visual and nonvisual inference, one keeps exact
   `402`/`429` provider-admission UX out of the network circuit across both
   live pipelines, one keeps exact terminal `400 observation_rejected` UX out
   of the network circuit across both live pipelines, four protect
   account-owned funded consent recovery plus lifecycle-gated onboarding
   resume, and the media-incident compatibility case exercises the actual
   network-client boundary:

   - foreground and background malformed-success rejection, required-consent
     approval UX and network-circuit isolation, provider-admission UX and
     network-circuit isolation, terminal observation-rejection UX and
     network-circuit isolation, confidence-zero
     source-media durability, retryable background HTTP-success disposition,
     process-single-flight inference replay wake coalescing, exact
     retryable-status dispatch, dual-copy durable retry-latch visibility,
     bounded inference metadata-write backlog, retry preservation through media
     re-staging, monotonic mirrored retry accounting, cloud-complete precedence,
     durable offline enqueue, bounded/redacted queue diagnostics, atomic
     queue/job completion, needs-attention library recovery quieting, serialized
     attention claim/status/reconciliation fencing,
     retry-deadline/deferred/network/media-less starvation prevention with the
     forced video override and an independent quarantine budget, atomic
     empty-pending quarantine, bounded upload-packer head-of-line starvation
     prevention with final constrained/expensive transport enforcement,
     runnable-only unsynced counting, empty queued staged-media rejection, empty
     foreground-video rejection, legacy-import retry rejection, newest-owned
     funded consent retry with account/funding fences, lifecycle-gated
     onboarding resume with a missing-account no-op, and indefinite
     privacy-erasure retry under positive server confirmation;
   - foreground request construction, Explore idempotency and contradictory
     response rejection, existing-scan recovery-payload encoding, rejection of
     recovery races with active/retryable ingestion, stable-code-first
     missing-scan classification, exact local/cloud Field Chat identity, stale
     presented-record invalidation, presentation-generation invalidation,
     monotonic reset-time request invalidation, identification-confirmation and
     override subject identity, Field Notes and preferred-name presentation
     identity, queued refresh, direct parent-presentation replacement, and
     completion-promotion identity, exact engine/record/snapshot Explore
     identity, post/request publication target capture, target-scoped sheet
     dismissal, changed-scan and stale same-scan-generation issue-report
     rejection, missing-owner stale publication reset, exact single and bulk
     scan-status response cardinality/identity validation, validated deletion
     confirmation, pre-upload restored-media budget validation, Community
     all-media recovery and response validation, exact Explore reconciliation
     validation, persisted-completion precedence over a stale same-ID queued
     navigation snapshot, queued fallback when no completed record exists, plus
     current/defensive-direct-array media-health incident decoding, actual
     network-boundary empty-array acceptance, and unknown-success-shape
     rejection; and
   - Explore-post identifier routing plus retryable, single-flight, and
     cross-subject-replacement Field Chat preparation, and rejection of stale
     chat-subject completions.

   Swift Testing reports an explicit `@Test("Display Name")` through that
   display name rather than the source function name in Xcode's structured test
   tree. A protected case with an explicit display name must therefore supply
   both its exact Swift function name and that one exact display-name alias to
   the result validator. The portable harness must model the display-name shape
   and independently prove that omitting or skipping it is rejected; never use
   substring or suite-only matching as a workaround.

   `OfflineQueueManagerTests` is explicitly serialized because its cases
   temporarily reconfigure the process-wide queue singleton, injected
   `ModelContext`, background-session state, and retained media. Main-actor
   isolation alone does not prevent async test cases from interleaving at
   suspension points.

   The actor-level starvation regression supplies deterministic expensive-path
   eligibility inputs, but it does not drive a physical `NWPathMonitor`. Release
   QA must therefore queue a playback-video scan, keep reachability satisfied
   while moving cellular → WiFi and Low Data Mode → normal, and prove each newly
   eligible transition wakes and completes the same scan UUID. While the path is
   constrained, automatic scheduler and Library wakes must make no status,
   signing, upload, or inference request; opening the Library must not keep a
   periodic refresh/kick log loop alive. During WiFi → cellular, every PUT for a
   non-forced mixed-media video scan must stop rather than transferring only
   part of its manifest on the expensive path; an explicit retry may proceed. A
   path loss while the serialized upload claim or signer is suspended must
   return both the scan and durable job to runnable state without increasing
   attempt count, and a scan must never start only a subset of its local
   manifest. This transition smoke is required in addition to the protected
   source/test result.

   Repository-source assertions must normalize runs of whitespace before
   matching control-flow token sequences, then pin both the sequence and its
   expected occurrence count. Swift indentation is not runtime behavior; an
   indentation-sensitive multiline literal can fail after formatting while all
   guarded network boundaries remain present.

   The exact protected replay case is
   `inferenceReplayReconciliationCoalescesConcurrentWakeSources()`. It proves
   simultaneous Library, scheduler, reconnect, and URLSession wakes produce one
   active reconciliation and at most one trailing pass.

   These checks live in `scripts/validate-ios-critical-test-results.sh`; their
   positive, missing-case, and skipped-case fixtures live in
   `scripts/test-validate-ios-critical-test-results.sh`; failed-suite,
   duplicate-suite, and duplicate-case fixtures prevent contradictory or
   ambiguous structured evidence from passing. Renaming a protected test
   requires updating both files in the same change.
   `scripts/test-ios-build-and-test-workflow.sh` additionally extracts all 95
   exact allowlist entries, requires every Swift function name to resolve to
   exactly one declaration bound to `@Test` in `MerianTests`, and binds the two
   explicit Swift Testing display-name aliases to their corresponding
   declarations. This prevents a duplicate declaration, helper method, or stale
   evidence name from surviving portable checks. The exact-case allowlist
   validates evidence after the complete target runs; it must never replace the
   complete-target selector with a focused test invocation. A successful
   validation is recorded as `Critical scan-flow regressions:
   passed` in the
   hosted job summary.

   After the complete unit target passes, the same checkout, simulator
   destination, locked packages, and `build-for-testing` output execute two
   deterministic runtime UI smokes:
   `testLiveInsightConnectivityFailureTransitionsToDurableQueue` and
   `testQueuedAudioScanRetainsAudioAcrossCompletionHandoff` under
   `merianUITests/merianUITests`.
   This is deliberately narrower than the complete UI suite, whose
   camera/Photos/hardware cases remain separate. The focused result must report
   exactly those two passed cases and zero failed or skipped cases. Its
   structured tree must contain that exact named set under `merianUITests`; missing, wrong,
   duplicated, malformed, empty, or contradictory evidence fails the job.
   `scripts/validate-ios-focused-test-results.sh` enforces the hosted evidence,
   and `scripts/test-validate-ios-focused-test-results.sh` provides portable
   positive and adversarial fixtures. The seed writes a valid one-second PCM WAV
   into Documents. The test must observe its filename-scoped playback control,
   which appears only after player creation and spectrogram decoding, both
   before and after completion handoff. The outer carousel-page identifier is
   insufficient because it also exists while audio is unavailable. The seed must
   not advance on a fixed sleep or countdown. After every queued-state assertion
   passes, the smoke taps `ScanningStatusBadge`; only that explicit app-private
   Debug handshake may replace the queued fixture with its completed record. The
   fixture transaction must use the exact environment `ModelContext` bound to
   the open Insight sheet and, after saving, directly invoke the existing
   production `promoteQueuedScanIfLocalRecordExists` path with that same
   context. The open destination must complete direct promotion before it sends
   `.scanLibraryChanged` for parent-library refresh; publishing the synchronous
   event first can rebuild the child from its retained queued route snapshot. A
   cross-context event merge must not control the deterministic handoff. This
   keeps slow hosted accessibility startup or a stale open context from erasing
   the state the test is required to prove. After the completed result takes
   over, the same smoke requires `FieldChatToolbarButton` and
   `InsightShareButton`, proving queue promotion reconnects the observation to
   Field Chat and sharing. Because queued and completed presentations
   intentionally reuse the same scan UUID, delayed result-toolbar and Field
   Notes tasks use `scanBoundActionGeneration` as their `.task(id:)`; an
   ID-keyed task can be canceled by queued-state invalidation and never restart
   for the result. Seed implementation is enclosed by the app target's `DEBUG`
   compilation condition. Release retains only signature-compatible no-ops with
   `UITestSeedCoordinator.isEnabled == false`; it does not compile fixture
   arguments, deterministic media, or local data-replacement logic. The portable
   workflow contract pins both branches. The current-SHA Release archive then
   extracts the main binary's strings and fails if any achievement/queued-audio
   seed argument or queued-audio fixture filename is present.

2. **Current-SHA Release archive** independently checks out `GITHUB_SHA`,
   resolves the same lockfile, and runs a generic-device Release archive with
   signing disabled. It requires production-shaped RevenueCat client
   configuration, verifies app/widget/Messages/watch embedding, checks the
   version and build against `project.yml`, requires the embedded source
   revision/fingerprint/state to match the exact clean workflow checkout, and
   requires the main app dSYM UUID to match the compiled binary. It also
   requires and validates the app-owned privacy manifest at the root of the
   application bundle, and verifies ATS defaults plus HTTPS-only app
   configuration in the final `Info.plist`. It records
   `privacy_manifest_valid: true` and
   `transport_security: "ats-default"` only after those bundled-copy checks.
   It records `ui_test_seed_markers_absent: true` only after the binary-string
   audit above passes. Signing is disabled only because
   hosted CI has no distribution identity; this is compile, link, archive,
   provenance, privacy-manifest, transport-security, dSYM, and shipping-seed exclusion
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

### Xcode Organizer Distribution Contract

Distribution is deliberately outside CI. After exact-SHA **iOS Build and Test**
passes, an operator archives the clean revision with Xcode and uploads it with
Organizer **TestFlight & App Store**. Automatic signing and **Manage version and
build number** remain enabled. Apple credentials stay in Xcode and the macOS
Keychain; no workflow receives signing certificates or App Store Connect
private keys.

`scripts/test-ios-xcode-release-workflow.sh` proves that:

- the retired GitHub TestFlight workflows and publisher/export scripts remain
  absent;
- CI's Release archive remains explicitly unsigned and validation-only;
- the Release preflight authorizes only clean automatic-signing Organizer
  archives with synchronized version values and production client config;
- no GitHub workflow contains an Apple signing or upload implementation;
- the canonical runbook keeps Xcode as the sole distribution authority; and
- the agent workflow remains a pointer to that runbook rather than a competing
  release recipe.

`scripts/test-ios-versioning.sh` supplies an isolated Git fixture for the source
fingerprint and both preflight modes. It proves that CI cannot sign or allocate
a validation build, Organizer requires automatic signing and a local team, all
resolved version values match the repository baseline before archive,
RevenueCat production configuration is present, and dirty or hidden Git source
is rejected.

Repository source tests cannot prove current Apple account access, signing
profiles, upload delivery, processing, aggregate SDK declarations, App Store
privacy answers, or physical-device behavior. Release managers collect
Organizer, Xcode privacy-report, App Store Connect, beta, and device evidence
during an authorized release. Follow the
[operator runbook](./14-ios-release-versioning.md) for setup, archive, upload,
promotion, and emergency recovery.

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
pins, exact-SHA checkout, generated-project source membership, full-target unit
selectors, merge-queue trigger, unsigned validation-only Release archive,
embedded source provenance, product/dSYM checks, automatic-signing Organizer
preflight, exact privacy-manifest declarations, project/archive/IPA manifest
placement, version-baseline synchronization, rejection of hidden
`assume-unchanged`/`skip-worktree` source state, generated release-phase
cardinality and ordering, focused-result validation, and structured failure
diagnostics. It also proves the retired GitHub signing/upload path remains
absent. The hosted project-guardrail lane runs this target on Ubuntu without
booting a simulator; it does not replace compilation, simulator execution,
Organizer upload validation, or physical-device QA.

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

| Failure                                                               | Artifact or local action                                                                                                                                |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unit compile or execution                                             | Download `ios-unit-test-failure-<run>-attempt-<attempt>` for the unit `.xcresult`, package-resolution log, and `xcodebuild` log.                        |
| Unit result is empty, skipped, incomplete, or misses a critical suite | Inspect `ios-unit-test-evidence-<run>-attempt-<attempt>` and rerun the complete target; do not weaken the critical-suite validator.                     |
| Critical scan UI smokes or focused-result validation                  | Inspect the `ios-critical-scan-ui` result, summary, tree, evidence, and log in the same evidence/failure artifacts; require the exact two protected cases. |
| Privacy manifest source or target membership                          | Run `make validate-ios-privacy-manifest` and `make validate-ios-project`; compare the declaration with the canonical privacy contract rather than weakening the validator. |
| Privacy manifest missing or invalid in the archive                    | Download `ios-release-archive-failure-<run>-attempt-<attempt>`; inspect `Merian.app/PrivacyInfo.xcprivacy` and regenerate the project if Resources membership drifted. |
| ATS exception or insecure source origin                               | Run `make validate-ios-transport-security`; remove the exception or repair the HTTP/credentialed origin rather than weakening the validator.                    |
| ATS or configured-origin drift in the archive                         | Download `ios-release-archive-failure-<run>-attempt-<attempt>` and inspect the final `Merian.app/Info.plist` plus resolved `SUPABASE_URL`.                        |
| Release archive, embedding, or dSYM                                   | Download `ios-release-archive-failure-<run>-attempt-<attempt>` and compare it with `ios-release-archive-evidence-<run>-attempt-<attempt>`.              |
| Intended release SHA was out of scope                                 | Manually dispatch **iOS Build and Test** on that ref so both macOS jobs run and produce current-SHA evidence.                                           |

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

Scan-bound Insight fixtures must reproduce the production identity topology: the
inference engine's completed `SpeciesData.scanId`, `activeLocalRecord`,
`activeLocalRecordId`, and `toolbarRecordSnapshot` must identify the same scan
before a toolbar or persisted Field Notes assertion is meaningful. Do not make
the runtime identity guard permissive to accommodate a fixture that binds only
an ID. Similarly, an Edge mock that represents a handler-owned `404` must
include `X-Merian-Handler: 1`; omit that marker only when testing the platform
route-unavailable path, which deliberately retains optimistic local state.

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
  paid/complimentary/historical-trial/free scan payload matrix.
- **`PostHogManagerTests.swift`**: Must use an observable SDK/network boundary,
  not only no-crash singleton calls. It must prove no setup, identification,
  capture, feature-flag reload, or network request before a current-disclosure
  grant at the all-version provider head and after withdrawal/account change. It
  must also lock every disabled automatic capture mode. The host-scoped
  transport gate must close before the preserved
  `reset → optOut → close` sequence so reset-time feature-flag reload is rejected
  locally.
- **`ConsentLedgerStore` failure matrix**: Inject ledger read/write, revocation
  journal read/write/cleanup, and restart failures independently. Onboarding may
  complete only after a verified atomic ledger write. A failed analytics
  withdrawal must close the in-memory gate immediately, retain the exact event
  in the Keychain journal across restart, replay it without changing immutable
  evidence, and preserve multiple account-owned withdrawals while storage is
  unavailable. Also test the independent fallback where journal write fails but
  the atomic ledger succeeds.
- **Consent lifecycle matrix**: Cover all three final-screen switch
  combinations; no Gemini request without current age plus Terms/Gemini
  evidence; optional analytics grant and withdrawal across devices; offline
  revocation; ghost-to-permanent-account merge; account switching; foreground
  synchronization; Realtime startup/failure recovery; idempotent retry; and
  immutable/timestamp-protected RLS rows. Absence of an analytics grant must
  remain off and analytics must never gate core functionality. The launch
  matrix must distinguish unresolved evidence from resolved absence: clear the
  local ledger for a completed account, verify no Ready frame appears while
  remote evidence is restored, then verify the restored-evidence path opens the
  workspace and the truly-absent path opens Ready. Also cover first-launch
  Welcome and every non-cancellation restoration failure boundary. Network-like
  and durable-ledger-write failures must keep root presentation at
  `.restoringConsent`, advance through 5-, 10-, and 20-second retry attempts,
  remain retryable after exhaustion, and route to Ready only after a later
  successful empty authoritative merge. Cover immediate manual retry, duplicate
  same-account auth without retry-budget consumption, stale retry rejection
  after account switch, and synchronization invalidation returning a canceled
  wait to `.reconciling` with a fresh budget. Cancellation during account
  replacement must remain unresolved; duplicate same-account auth after
  resolution must not reopen restoration. For both Gemini and analytics, cover
  both inverse cross-device orders: a delayed offline grant after a synchronized
  revocation is rejected, while a delayed offline revocation after a synchronized
  grant is accepted and rebased to that grant.
  Repeat the revocation case across an app upgrade: create it under the prior
  disclosure and old observed parent, append a current-version grant, then
  upload the queued revocation. Database coverage must assert that both RPCs
  rebase its stored parent to the current grant; Edge and iOS coverage must
  assert that the all-version revoked head denies even while a current-version
  grant row exists.
  Retry the latter with its originally observed parent to prove event-ID
  idempotency, assert iOS persists the server-returned accepted parent and
  revision, and retain database assertions that the account-row lock precedes
  the provider-stream advisory lock. The disposable database suite must execute
  `_tests/legalConsentConcurrencyDb.test.ts`, which blocks both provider callers
  on the account row, releases them together, and requires a revoked final head
  for both lock-acquisition orders.
  Cross-disclosure ownership is split deliberately: `legal_consent_security.sql`
  executes the stale-parent rebase and Gemini denial in PostgreSQL;
  `_shared/posthog_test.ts`, `_shared/aiQuota_test.ts`, and
  `_tests/legalConsentMigrationContract.test.ts` lock the Edge queries, denial
  mapping, and head-before-rollout source contract; and
  `SupabaseManagerTests` proves both iOS gates remain closed after merge and
  restart when an older-disclosure revocation owns the greater revision.
  Release closure additionally requires one exact-SHA new-install transaction:
  complete Ready under a new anonymous account, observe all three required rows
  upload and refetch for that same account, then complete the first ordinary
  scan with exactly one Identify/provider dispatch. A forced missing-row variant
  must return `403 ai_consent_required`, preserve scan/media across relaunch,
  consume no included-Pro or daily-Flash allowance, schedule no automatic
  inference retry while consent is invalid, and automatically resume exactly
  one eligible original scan ID only after fresh head-anchored approval. Prove
  released, deferred, mismatched, and cross-account rows stay paused. Run a real
  `402 pro_required` and
  `429 ai_quota_daily_exceeded` case separately to prove neither enters consent
  recovery. Source type-checking or an injected network-unit test cannot replace
  this account/Edge/database/device evidence. See the
  [first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md).
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
  `make validate-ios-project`, `make validate-ios-migration-guardrails`, and
  `make validate-ios-event-routing` first, so known-bad source shapes fail on
  Ubuntu before the slower macOS simulator job spends time resolving packages,
  building, or booting a simulator. Startup Safety remains path-filtered to
  startup/schema/recovery surfaces, manual dispatch, and the daily drift check;
  broad iOS changes instead enter the full compiled gate described above.
  Workflow/tooling-only changes can start the Startup Safety workflow to
  validate cheap guardrails, but its simulator steps are skipped unless startup
  runtime files changed.
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
  claimed. Its terminal replay test accepts an absent queue only for the exact
  generation's completed durable job, while rejecting nonterminal and
  mismatched-generation jobs. `SyncStateManagerTests` also locks the
  generation-fencing contract: a stale upload completion cannot clear a
  replacement batch; a completion delivered after `forceIdle()` cannot remove a
  newer inference token; a stale finalizing transition cannot advance the
  replacement's UI phase; and `GenerationTaskRegistry` rejects
  compare-before-clear and owner-cancel attempts from a replaced slot.
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
  the same ordering, after `speciesData` arrives. It also proves a lookup miss
  for a different presented scan clears stale scan-bound state and that Explore
  cannot combine mismatched engine, local-record, and toolbar-snapshot IDs. A
  direct record switch also proves the prior action generation and all
  scan-bound busy/editor state—including exact post/request, Safari, candidate,
  and delayed-toolbar presentation targets—is invalidated. Queued presentation
  regressions prove a delayed scan-A poll cannot replace scan B's context and
  completion promotion requires the exact queued subject before releasing queued
  routing. The delayed Explore-onboarding regression proves the retained timer
  is bound to scan ID plus presentation generation and is cancelled by reset.
  Field Notes tests cover the same ID-plus-generation boundary while
  preserving editing for queued/offline scans.
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
  600-character draft cap. It additionally proves a changed chat subject clears
  the private draft and rejects the old generation's completion, a
  different-subject preparation replaces obsolete work, and same-subject
  preparation remains single-flight. `MerianNetworkClientTests.swift` exercises
  the candidate-success boundary: malformed Community enums become
  `MerianError.invalidResponse`, and Field Chat rejects cross-subject,
  missing-subject, cross-conversation, unknown-role, non-UUID-message, or
  invalid-limit envelopes before the view model can apply them, including an
  otherwise valid empty thread from the wrong subject. Send cases additionally
  reject an incomplete or mismatched `client_message_id` pair, padded/empty or
  over-4,000-character message text, and a JSON body over 1 MiB; manual retry
  retains the failed send UUID. The foreground identify boundary also proves an
  exact handler-owned `403 ai_consent_required` becomes
  `MerianError.aiConsentRequired`, so the app can enter disclosure recovery
  instead of exposing a generic HTTP retry. Backend source/helper tests lock
  bounded same-UUID quota replay coalescing. Action-response cases reject
  false/mismatched answer and feature feedback, empty or internal-ID-leaking
  note summaries, and malformed, duplicate, unsafe, oversized, or
  unknown-category prompt suggestions. Safety fixtures distinguish direct action
  requests such as harvesting/handling from ordinary educational species names
  and behavior questions such as poison ivy habitat or animal foraging.
  `UserTagsMutationControllerTests.swift` verifies tag saves commit locally
  before external cloud/search side effects can run.
- **`CaptureTelemetryTests.swift`**: Directly validates that offline/historic
  captures explicitly decouple live sensor leakage (like LiDAR distance vectors
  or view-finder zoom scopes) away from EXIF bounds.
- **`ScansManagerTests.swift`**: Validates local string-index mapping (group
  name taxonomies, semantic tags, explicitly added `customTags`, and
  one-character unigram candidates). Asserts typed, main-actor `AppEvent`
  invalidation dynamically patches specific payloads
  (`testCustomTag_DynamicHotSwap`) without OOM-burst re-renders. Search and indexing assertions now
  wait on `ScansManager.SearchDebugEvent` completions instead of fixed
  `Task.sleep` windows, including explicit debounce-cancellation coverage that
  proves a superseded query never emits `searchCompleted`. Also verifies the
  indexed query path preserves substring behavior
  (`testSubstringSearchFilteringPreservesContainsSemantics`) so the candidate
  index does not regress the user-facing `contains` search contract. Advanced
  filter tests wait for `filterIndexingCompleted`, verify cached option
  dimensions refresh after a targeted mutation, confirm selected values are
  normalized without changing matching semantics, and exercise rapid targeted
  reindexes so a superseded task cannot drop another document. Batch-export
  coverage also locks the selected-ID set and selection mode while
  `isDownloading` is true, then proves normal selection teardown resumes after
  the export fence clears.
- **`AppRouteCoordinatorTests.swift`**: Locks priority/FIFO ordering, semantic
  coalescing, latest lightweight pending payload with stable identity,
  stronger-source promotion, bounded overflow, pending/deferred expiry without
  expiring an already viewed presentation, explicit initial-session restoration
  versus runtime sign-in fencing, session generations, defer/resume, exact
  presentation dismissal, duplicate/stale callback rejection, external-route
  timeout suppression, and missing-target rejection. A rejected route must
  release the in-flight slot so later work cannot stall. Deferred-resume
  regressions additionally prove that resume cannot exceed the pending bound,
  a stronger live resume evicts exactly one eligible route, and an expired
  resume cannot evict valid queued work. Capture workspace tests
  separately prove a route remains deferred during root interactive teardown
  and across a feature-local presentation until its exact `onDismiss` callback.
- **`EventDeliveryTests.swift`**: Locks synchronous and reentrant `AppEvent`
  delivery, cancellation behavior, main-actor ordering for framework publisher
  bridges, and generation-fenced media observation after player replacement and
  detach.
- **`AppDIContainerTests.swift`**: Proves preview graphs receive independent
  event publishers, route coordinators, milestone presenters, and host
  registries. The event-routing source guard separately rejects any shared
  feedback host that bypasses this isolation through `AppDIContainer.shared`.
- **`ToastPayloadTests.swift`**: Locks typed title/body splitting, severity and
  action identity, plus a fresh presentation UUID when equivalent copy replaces
  an existing toast. It also proves milestone suppression applies only when the
  ordinary and milestone surfaces share an alignment, leaving independent
  top/bottom feedback visible.
- **`AchievementToastPresenterTests.swift`**: Runs serialized because legacy
  gamification notification assertions share process UserDefaults. In addition
  to scan ordering, it locks the 32-item architecture through injectable bounds,
  stable duplicate coalescing, case-insensitive foreground/background scan-ID
  race deduplication without rewriting the resolver's caller-supplied ID,
  account/session stale-callback rejection,
  one-time haptic/accessibility claims with remaining lifetime across remounts,
  nested-host restoration, bounded stale-host retention, and stack projection
  that mounts the first payload only while forwarding the remaining queue depth
  to the two-layer decorative-backplate clamp. It also covers the race where an
  account transition occurs while a retryable progress resolver is suspended.
  That race must not create a replacement retry after session cleanup. A paired
  test proves the new session can immediately process the same canonical scan
  key while the stale resolver remains suspended. Another locks completed-scan
  deduplication across a same-account session advance. Retry tests also inject a
  two-task global bound, schedule three scan keys, and require overflow plus
  session cleanup to retain no more than the configured number of sleepers.
- **Source guardrails**: `make validate-ios-event-routing` scans production
  sources; `make test-ios-event-routing` exercises multiline, alias,
  application-name/post, duplicate-subject, singleton, allowlist, and
  test-target-exclusion fixtures. These fixtures are part of
  `make test-ios-ci-tooling`. The fast `ios-project-guardrails.yml` lane and the
  compiled iOS workflow both validate the live repository, and both are
  path-sensitive to the checker, its exact allowlist, and its fixture script.
- **Verification tiers**: A recursive `swiftc -frontend -parse` catches syntax
  errors quickly. A direct iOS module/test-target type-check can add useful
  compile evidence when CoreSimulator is unavailable, but neither runs XCTest,
  links the application, validates resources, or replaces the hosted
  `xcodebuild build-for-testing` and complete `merianTests` execution. Record an
  environment failure as such; do not reinterpret it as a passing native build.
- **`LocalImageLoaderTests.swift`**: Locks concurrent network payload boundaries
  and request coalescing to prevent multi-grid fetch flooding. The async decode
  permit tests prove concurrency remains bounded and a cancelled waiter cannot
  consume the next released slot. Recovery cases cover promoted basename
  compatibility, registered scan-ID mapping after cloud renaming,
  high-confidence timestamp groups, Explore fallback rendering from Documents,
  and rejection of unrelated/unsafe URLs.
- **`OfflineQueueManagerTests.swift`**: Mocks queue payload insertions.
  - **Temporary-store isolation**: Spins up a `@MainActor ModelContext` on a
    unique test-store URL to isolate test data from the user's real offline
    queue while preserving save/context behavior.
  - **Core Lifecycles**: Exercises `.enqueueCapture` / non-visual queue
    insertion (asserting SwiftData record counts increment correctly), canonical
    mixed-media serialization, and `.purgeSoftDeletedRecords()` (asserting
    soft-deleted items are removed while undeleted items persist).
  - **Media staging contract drift**: Loads
    `docs/contracts/media-staging-upload-manifest.json` and asserts
    `MerianConfig` matches the documented file, audio, and video budgets and
    locks the exact signed `Content-Length`/`Content-Type` response contract.
    File-mutation coverage proves a signing-time size mismatch is discarded for
    re-signing before task creation. Also
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
  - **Consent-policy response classification**: Asserts an exact
    `403 ai_consent_required` becomes `.consentRequired`, while another `403`
    remains `.needsAttention`. This keeps the policy transition out of automatic
    inference backoff while the queued media remains available for explicit
    recovery.
  - **Post-approval consent recovery**: After explicit reapproval, assert the
    queue resumes only its newest needs-attention row with stable
    `ai_consent_required`, an exact scan-ID match, the current account ID, and an
    unreleased dispatchable funding reservation. It must resume no more than one
    row and must skip unrelated, released, missing, deferred, mismatched, and
    cross-account work.
  - **Description-only manual retry
    (`testManualRetryResetsBudgetForDescriptionOnlyScan`)**: Starting from a
    needs-attention staged observation and scan job at the automatic limit,
    assert explicit retry preserves the scan UUID, resets both bounded counters,
    clears transient errors, and returns both records to runnable state without
    relying on an upload-success transition. Hosted result validation requires
    this exact regression to execute and pass.
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
    and post/media plus `needs_id` state roll back together. Reopen coverage
    must reset old publication, vote, and worker generations without deleting
    audit rows. Simulate the absent-request race and require one relational-only
    retry to return the committed request without a second moderation/provider
    call; simulate concurrent direct sharing and require the write-time trigger
    to reject its late `shared_at` update.
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
  The post-run XCResult validator additionally requires the exact critical scan,
  offline-finalization, Community/Explore, and Field Chat regressions described
  above to pass, so one unrelated passing case cannot stand in for a protected
  workflow.
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
  clears, an exhausted free quota retains the receipt while the paywall is
  mounted and through its dismissal, and Pro entitlement retries it only after
  the matching root-sheet dismissal callback. The retry case also proves a
  direct worker call cannot stage or present crop behind the paywall. An
  unreadable file is removed with terminal feedback. Confirmation and crop
  cancellation continue to be owned by the shared gallery staging tests rather
  than a second import-only pipeline.
- **Launch presentation and explicit-route precedence**: `AppDIContainerTests`
  proves `opensExploreOnLaunch` defaults off, persists an enabled value, reloads
  from external `UserDefaults`, and requires both completed onboarding and
  opt-in. The same suite locks the root matrix: incomplete onboarding presents
  onboarding, completed/current consent presents the workspace,
  completed/pending consent presents restoration, and completed/resolved
  missing consent returns to onboarding. `CaptureWorkspaceViewModelRefinementTests`
  initializes generic Explore, then verifies Photos/Files imports, Explore post
  routes, community requests, scan routes, and the Scans library replace it. The
  import case also sends the foreground timeout event and asserts the staged
  image and required crop survive. Foreground returns must never be modeled as
  another launch-policy evaluation.
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
- **`PhotoLibraryManagerTests.swift`**: Validates that the injected default-off
  `saveToCameraRoll` preference drops automatic photo and video payloads before
  Photos authorization, photos map to `.photo`, videos map to `.video`, video
  processing preserves the source file, and photo processing still removes GPS
  metadata.
- **`InsightMediaExportManagerTests.swift`**: Validates local image/video URL
  resolution, exact-host approval for HTTPS `media.merian.app` resources,
  rejection of unapproved remote video hosts, and separate mixed-media
  attempted/saved counts with partial-failure copy.

PhotoKit completion, recorded-video audio, source-file lifetime during an
actual import, and permission-denial UI require the physical-device checklist in
[Camera Roll and Captured-Media Export](../features-and-hardware/27-camera-roll-media-export.md).

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
- **`DeviceIdentityManagerTests.swift`, `EntitlementManagerTests.swift`,
  `RevenueCatManagerTests.swift`**:
  Isolates authentication loops away from live production identifiers.
  `DeviceIdentityManagerTests` reads `DeviceIdentityManager.shared.deviceId`
  (the public `@Observable` property) — it does **not** call the private
  `getOrGeneratePersistentIDFV()` method directly. The test wipes the relevant
  Keychain item via `SecItemDelete` before and after the assertion to prevent
  cross-run contamination. `RevenueCatManagerTests` also locks the required
  current-offering product set to `pro_week` plus `pro_annual` and the pure
  provider-mutation policy: matching normalized `anonymous` and `authenticated`
  identities are allowed, while missing, unknown, or mismatched account kinds
  fail closed. `MerianNetworkClientTests` separately proves that a generic `401`
  cannot rotate a Ghost UUID. This does not replace dashboard/App Store smoke
  testing or prove provider state transfers between two custom App User IDs;
  staging must verify that the compiled purchase, restore, and redemption entry
  points enforce the policy during both normal Ghost upgrade and an
  existing-account conflict. `EntitlementManagerTests` lock
  current-launch verification, buffered replay metadata, stale-version
  rejection, account isolation, balance validation, exhaustion, and the
  difference between functional access and new-scan capacity.
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
  the Scans library, including the batch-media export selection-mutation fence.
- **`BackgroundDatabaseActorTests.swift` collection projection**: Creates member
  and unrelated scans plus Favorites, then verifies `collectionSyncPayloads()`
  returns only the non-Favorites collection's direct, deterministically sorted
  membership IDs.
- **`AppDIContainerTests.swift` preferred-name coverage**: Verifies matching
  normalized cloud values and existing tombstones are converged without an
  upsert, while real conflicts retain timestamp ordering.
- **`OnboardingViewModelTests.swift`**: Validates the extracted UI state machine,
  the full inline Terms destination, final-screen required/optional switch
  combinations, returning-user direct routing, and completion persistence. It
  also proves missing evidence waits for the initial session, an expired cached
  session retains the known account on the neutral root while refresh is
  pending, authenticated
  missing evidence remains pending through authoritative merge, fetch and
  durable-write failures remain retryable, the 5-/10-/20-second budget is
  bounded, duplicate auth preserves that budget, stale account retries are
  rejected, and generation invalidation cannot orphan a canceled waiting state.
  It also verifies a resolved same-account session cannot re-enter restoration.
  Server-rejection cases additionally lock authoritative cloud-head proof,
  durable relaunch routing to `.ready`, fresh head-anchored evidence, legacy
  ledger decoding, and per-account fence isolation across restart and account
  switch. These are deterministic boundary regressions; they do not claim the
  exact-SHA new-account release transaction described above has run.
  Every throwing assertion must be declared correctly so this file cannot
  prevent the entire unit target from compiling.
- **`SupabaseManagerTests.swift` auth-adoption coverage**: Locks the three cold-
  start classifications: nil is signed out, a current session is authenticated,
  and an expired cached session is awaiting refresh rather than signed out.

## Testing Identify Requests and Activity

Identify has a three-layer contract: root navigation/mode policy, concurrent iOS
dashboard/full-feed state, and a service-only PostgreSQL Activity projection.
Do not accept one layer as evidence for another.

iOS focused coverage:

- `Features/SpeciesDictionary/SpeciesDictionaryTests.swift` locks the exact
  three root tabs, Requests/Index mode cases, species-to-Index and
  request-to-Requests deep-link policy, 12/10 preview limits, 30-row complete
  page size, independent request/Activity failure state, and current-filter
  route propagation.
- `Core/Network/MerianNetworkClientTests.swift` decodes all Activity item fields
  and verifies `limit`, shared scope/group filters, plus paired
  `(before_activity_at, before_activity_id)` payload construction.
- `Core/Utilities/MerianConfigTests.swift` verifies a temporary service failure
  uses Recent activity-specific copy rather than the generic Explore outage
  message.

Backend focused coverage:

- `get-community-identification-activity/db_test.ts` verifies the service
  adapter forwards verified viewer identity, scope, group, limit, and paired
  cursor arguments to the RPC and propagates failures.
- `_tests/communityIdentificationActivityMigrationContract.test.ts` statically
  locks internal tables, RLS, direct-role revocations, service-role grants,
  trigger sources, current-generation backfill, stable RPC signature/order, and
  configuration.
- `_tests/communityIdentificationActivityDb.test.ts` runs against PostgreSQL and
  covers the inclusive 60-minute boundary, chained/repeated suggestions,
  distinct top-three actor ordering, submission consensus folding, standalone
  consensus changes, separate resolutions, owner/group filters, equal-time
  cursor stability, blocking, shadowban, tombstone, unshare, quarantine,
  missing media, and reopened request generations.

The PostgreSQL suite may explicitly return early when no test database is
available. That is discovery/compile evidence only. Production acceptance still
requires the fully migrated disposable catalog and the complete
`make test-supabase-privileged-routines` gate.

Manual root-UI acceptance requires:

1. Exactly Observations, Field trips, and Identify in bottom navigation.
2. Requests/Index at the Identify root and no Tree/galaxy entry point.
3. **Identify requests**, banner, 12-card cap, larger section gap, then
   **Recent activity** with 10-row cap.
4. Shared filter behavior across both previews and independent outage/Retry
   presentation.
5. **See all requests** and **See all activity** preserving the filter and
   opening **Identify requests** / **Identify activity** stack titles.
6. Root tab/mode chrome hidden on pushed feeds, with native Back returning to
   the dashboard.
7. Activity rows opening existing request detail.

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
message caps, action-intent safety refusals plus educational near-miss
allowance, and the `suggest_prompts` action's safe three-prompt JSON contract.
Shared response-builder tests prove every Insight/Explore thread and action
success echoes its exact subject, while prompt-suggestion tests prove
action-intent filtering does not reject harmless species names or educational
ecology questions. Explore fixtures also cap deterministic common-name labels so
all generated chips remain within 120 characters.
`_shared/fieldChatReservation_test.ts` verifies the fail-closed RPC adapter,
exact persisted-row binding, replay projection, and stable database-error
mapping. `_tests/fieldChatReservationMigrationContract.test.ts` pins per-user
then per-conversation lock ordering, atomic cross-table limits, direct-client
revocations, and exact stale-quota recovery in
`20260729163616_reserve_field_chat_sends_atomically.sql`. It also pins
cleanup-before-validation, the retained Insight conversation's exact scan owner,
the conversation-optional feature-feedback scan owner, deferred composite
message/feedback identity, exact RLS joins, and feedback Data API revocation in
`20260730180000_bind_field_chat_rows_to_subjects.sql`. The executable
`tests/field_chat_reservation_security.sql` is the PostgreSQL authority for
runtime transaction, 19 admission/binding/ACL assertions, replay/conflict,
capacity, daily-limit, and stale recovery behavior.

The focused portable Field Chat selection uses the two shared tests, the
migration contract, and the Insight/Explore guard, eligibility, prompt, and
prompt-suggestion tests. The 2026-07-29 baseline passed 30 tests; the 2026-07-30
exact-source rerun passed 32 tests and 0 failed across the same nine files after
adding structural binding and feedback-ACL contracts, with a frozen dependency
graph. This is deterministic runtime and source-contract evidence; it does not
replace execution of `field_chat_reservation_security.sql` against the exact
deployed PostgreSQL catalog or the joined physical-device chat smoke.

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
  updates report an attempt only after persistence commits. Its diagnostics
  fixture plants private media paths, description, Field notes, location/GPS,
  raw metadata, and arbitrary persisted messages, then proves the shared JSON
  excludes every value while retaining lifecycle/error/status evidence and
  binary-provenance fields. It also plants arbitrary values in retained
  machine-token fields and proves they are omitted. A second fixture inserts 510
  jobs, scans, and events; it proves all sections cap at 500 while zero and
  `Int.max` event requests serialize exactly one and 500 event rows.
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
inspection is not PostgreSQL evidence. That revision discovered 26 fixtures
after adding atomic Explore and Community rollback coverage. The present suite
discovers 27 after adding `field_chat_reservation_security.sql`; run all 27 on
the exact remediated SHA.

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

The latest hosted replay then discovered all 26 files present on that SHA and
proved the identity fixture correction: identity merge/recovery and inline/video
recovery passed, and 24 files completed. Only the two new atomic fixtures
aborted. Each reached its first real `service_role` body call and raised
SQLSTATE `42501`, `permission denied for table explore_community_requests`;
their later bad-plan reports were secondary to that statement failure. Forward
migration `20260729044500_grant_atomic_explore_service_privileges.sql` now
provides an operation-scoped service allowlist while preserving invoker rights
and no browser-role writes. The revised Explore and Community catalogs plan 22
and 25 assertions and include live privilege checks. Static migration contracts
can pin that correction, but all 27 current catalogs must still pass on a fresh
exact-SHA database before deployment.

Field Chat regression tests separately enforce that transient owned-scan
readiness does not become permanent UI state. HTTP `404 scan_not_ready`, missing
message/conversation actions, and status `not_found` must leave
`unavailableScanId` unset and preserve a retryable toolbar action. Terminal
ownership failure, `unsupported_scan`, and unavailable Explore-post sources
remain deterministic unavailability.

Send/retry coverage must also force an ambiguous response after the user row is
saved, replay the same `client_message_id` while the provider call is in flight,
and require one persisted user/assistant pair. The 20th-send replay must run
before daily-limit rejection. A failed provider attempt must resume under that
same UUID; allocating a fresh UUID on manual retry is a duplicate-message
regression. Repeat with uppercase request UUID input and lowercase PostgreSQL
projection, reject the same UUID with different normalized text both after a
normal read and when contradictory payloads race before insert/replay
reconciliation, start a new send at 28 persisted rows, reject one at 29, and
allow an incomplete retry at 29 while rejecting one at 30. Race two
deterministic local refusals. Assistant persistence must read-after-write
reconcile an ambiguous insert and expose one deterministic UUIDv8 answer row.
Race different request UUIDs from two devices and require one unanswered request
to win. Repeat at 19 total UTC-day sends split across Insight and Explore, and
at 28 conversation rows, to prove the database admission—not an earlier Edge
count—owns both limits. Terminate after quota commit, require in-progress
behavior before ten minutes, age only the exact reservation, then require stale
recovery to prove the bound user row and missing assistant before a newly
metered retry. Completed, mismatched, and live reservations must remain closed.
Reload a UUID-bound user row without its assistant—even with a filtered orphan
assistant after it—and require the same UUID/text to return as the failed
pending bubble rather than a delivered message; orphan and duplicate bound
assistants must not enter the transcript, and hidden recovery rows must still
count against composer capacity.

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
  It also locks the joined 2026-08-03 remediation record against the canonical
  collection RPC/ACL, exact upload-header, durable funding-reservation,
  fixed-origin redirect, and raw-page taxonomy-checkpoint contracts.
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
  authorization. Eleven customer-critical scan, signing, share-state, Explore,
  Field Chat, Community, and deletion routes additionally return marked
  fail-closed `401` responses without user Authorization. Final Function
  failures classify only whether the fixed `X-Merian-Handler: 1` marker was
  present; Data API failures use separate PostgREST/RPC guidance and never
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

Before release, Ghost-profile merge evidence must cover four complementary
layers:

- `_tests/ghostProfileMergeMigrationContract.test.ts` must statically lock the
  source-controlled policy manifest, pre-mutation topology assertion,
  scan-first/derived-ledger order, guarded orchestrator rewrite, private helper
  ACLs, user-before-RevenueCat-queue order, Community collision-only
  update/delete behavior, and absence of an actor insert/upsert path.
- `_tests/mergeGhostProfile.test.ts` exercises the real Edge error mapper. It
  must map both `ghost_merge_species_ledger_mismatch` and
  `user_species_scan_count_underflow` to HTTP 503
  `merge_temporarily_unavailable` with the guest-data-unchanged message, while
  retaining terminal versus retryable Keychain semantics.
- `tests/ghost_profile_merge_security.sql` must execute provider authorization,
  replay, topology drift, collision handling, destination-only RevenueCat queue
  repair, exact species-ledger transfer, immutable attribution, and rollback
  behavior against the fully migrated disposable catalog. It must include both
  colliding and non-colliding Community actor groups and a merge-invalidated
  RevenueCat claim that cannot apply stale state.
- Two-session disposable-database probes must run merge versus RevenueCat
  reconciliation and merge versus a normal Community activity append in the
  production workflow. Neither pairing may
  deadlock, lose counts, apply a displaced claim, or leave the destination
  provider queue absent or unclaimable.

Run `bash services/supabase/scripts/require_supabase_cli_version.sh`, then a
clean `supabase --workdir services db reset`, then
`make test-supabase-privileged-routines`. Only Supabase CLI `2.109.1` produces
release-equivalent database evidence. Static/unit checks or a direct focused SQL
file do not clear the deployment hold. The complete disposable-CI matrix is in
the
[Ghost Account Merge Security Rollout](../backend-and-data/06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).

Durable account deletion has twelve complementary checks:

- `apps/web/lib/scientificRetentionContract.test.ts` keeps the public Terms,
  Privacy Policy, Privacy Choices page, iOS account-deletion confirmation,
  location-onboarding copy, and location usage description aligned on mandatory
  ownerless Scientific Data retention. The web-quality workflow includes those
  three iOS source paths so an iOS-only wording change cannot bypass the test.
- `scripts/documentation_contract_test.ts` requires the canonical retention
  contract, links it from the maintained documentation index, locks the
  mandatory/no-parallel-table and ownerless-not-necessarily-anonymous boundary,
  verifies the current migration is part of the deployment release unit, and
  rejects unresolved local links across the account-deletion documentation.

- `_shared/appleSignIn_test.ts` and
  `register-apple-revocation-token/handler_test.ts` prove form-encoded Apple
  exchange/revocation, presented-versus-returned subject binding, safe terminal
  versus retryable errors, idempotent HTTP `200`, response-body redaction,
  registration lookup before code consumption, exchange before atomic Vault
  storage, and compensating revocation after persistence failure.

- `_tests/safeDelete.test.ts` executes the actual handler/worker modules with
  injected boundaries. It proves intake precedes processing, cleanup failure
  never calls Auth, `storage_pending` releases its claim without calling Auth,
  `auth_pending` recovery repeats idempotent cleanup before Auth, stored Apple
  credentials are revoked and transactionally completed before Auth, provider
  failure preserves Auth and the Vault credential, legacy Apple intake returns
  a manual disposition, Auth failure is deferred after verified storage, and a
  lost completion response remains retryable.
- `_tests/accountDeletionCoverage.test.ts` keeps source ordering, idempotent
  Auth-not-found handling, timing-safe reaper authentication, bounded parsing,
  `config.toml`, workflow wiring, iOS authorization-code capture and deletion
  receipt, hosted secret validation, the independent monitor's separation from
  the database reaper, and the executable fixture's
  cleanup-before-storage-before-provider-before-Auth phase order present.
- `_tests/accountDeletionMigrationContract.test.ts` locks the private state
  machine, claim token, `SKIP LOCKED`, outbox-before-tombstone order, cleanup
  verification, required `storage_pending` phase, five-prefix keyset cursor,
  25-hour delayed verification, media/private-context clearing, unchanged
  scientific-field retention, upload-signing
  fence, profile-recreation guard, terminal UUID minimization, service-only
  ACLs, five-minute cron, the failed-version no-op bridge, ownerless-tombstone
  constraint, the Auth/profile foreign key, and the absence of synthetic user
  creation. It also requires the storage-claim SQL to join a matching cleaned-up
  `storage_pending` private job and to veto live profiles and owned scans, plus
  indexed identity-free aggregate health with a service-only caller check. The
  health contract must select Vault before the NULL-only app-setting fallback,
  so a blank Vault value remains unhealthy instead of being masked. The Apple
  migration contract additionally locks private credential/receipt tables,
  Vault and Auth restrictive foreign keys, provider state coherence,
  service-only allowlisting, secret destruction before provider completion, and
  terminal provider fencing.
- `tests/account_deletion_security.sql` executes the live catalog transitions:
  durable intake leaves Auth/data intact, the restrictive profile FK rejects an
  Auth-first delete, premature Auth completion is denied, all five sweep and all
  five delayed verification prefixes advance in order, cleanup commits while
  Auth still exists, retained scans are ownerless tombstones with media and
  personal fields cleared and exact scientific coordinates retained, a
  pre-existing scan-generation fence permits only that one detachment, stale
  post-detachment coordinate rewrites are rejected, a delayed individual-scan
  completion remains idempotent without deleting the retained observation, no
  all-zero profile exists, active deletion blocks profile resurrection, a
  stored Apple credential is claim-readable only in the provider phase and is
  destroyed before provider completion, a legacy Apple fixture records the
  manual disposition, Auth completion is rejected before provider completion,
  retries preserve `auth_pending`, the service role sees that retry through
  aggregate health while public roles cannot execute the health RPC, final
  completion erases the direct UUID, and duplicate completion is idempotent.
  Before deletion begins, the same fixture inserts a stale
  storage outbox row for its live owner and proves the claim RPC cannot return
  it.
- `safe-delete/storageWorker_test.ts` proves one bounded page per claim, delete
  concurrency behavior, empty-prefix advancement, delayed verification,
  idempotent 404 deletion, retry persistence, and claim-token propagation.
- The ghost-merge catalog fixture above also proves the restrictive profile/Auth
  identity key is skipped only for the source profile row. This is the shared
  identity-lifecycle boundary needed by account deletion; its broader merge
  assertions remain part of the separate Ghost release gate.
- `MerianNetworkClientTests` returns `202 Accepted` from the mock route, strictly
  requires the manual-provider disposition, and rejects a missing field.
  `SupabaseManagerTests` proves the registration retry is bounded while reusing
  one durable request. It also locks the credential-state matrix: `.authorized`
  preserves the session, revoked/not-found/transferred states clear it, and a
  lookup failure fails closed. Static source coverage requires the
  provider-specific subject lookup and stale-identity fence.
  `AppDIContainerTests` proves the manual notice survives until explicit
  resolution.
- Release evidence must separately exercise the chosen older-binary control.
  Either an old client follows a clear enforced-update path back to in-app
  deletion, or an independent server fallback durably delivers Apple's manual
  instructions despite that client ignoring the new response field. App Store
  availability of the supporting build is not evidence for this gate.
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
- `MerianNetworkClientTests.testExploreMediaIncidentsAcceptsLegacyEmptyArrayAtNetworkBoundary`
  proves the actual iOS network method maps the older deployed direct `[]`
  response to a valid empty incident list. The hosted critical-result validator
  requires this exact case in addition to typed canonical/legacy decoding and
  malformed-success rejection.
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

Authoritative AI quota and entitlement security has four complementary base
checks:

- `_shared/entitlement_test.ts` proves paid, complimentary, pre-cutover trial,
  expired, and free resolution; dual-mode protocol 2–3 enforcement/internal replay bypass;
  database errors and missing rows failing closed; and absence of isolate-local
  reuse.
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

The complimentary extension adds three required layers:

- `_tests/complimentaryProScansMigrationContract.test.ts` locks the private
  fixed-grant ledger, derived balances, protocol/mode atomicity, user-first lock
  order, completion and terminal trigger fences, quota-versus-credit
  independence, paid preservation, Ghost merge cap, functional database gates,
  admin aggregates, recovery callers, and privileged routine catalog.
- `_tests/complimentaryScansConcurrencyDb.test.ts` overlaps three real
  reservation transactions behind one user lock and proves that the fourth
  compatible scan resolves to the separate Flash fallback without a fourth
  hold. A missing local database is an explicit skip and cannot count as
  acceptance.
- `tests/complimentary_pro_scans_security.sql` exercises ACLs, three holds,
  replay linkage, fourth-scan Flash and daily separation, Pro-only rejection,
  durable and valid non-biological consumption, terminal release, ambiguous
  retention, purchase-before-completion, paid-credit preservation, direct
  completion/terminal bypass rejection, merge deduplication/cap, and monotonic
  versions against the migrated catalog.

On iOS, `EntitlementManagerTests.swift` covers launch verification, account and
snapshot validation, active-hold-versus-startable capacity, failed-verification
locking, paid-offline preservation, stale-version rejection, and the critical
cold-launch rule: stored scan metadata is buffered until
`get_my_entitlement()` establishes the current baseline, then cannot restore a
newer exhausted balance. Network, UsageManager, AI persistence, Capture,
Results, Settings, paywall, Profile, and Explore suites cover protocol headers,
Flash reconciliation, optional historical envelopes, third-result persistence,
countdowns/exhaustion, Pro-only modes, and paid-only badges. See the normative
[`complimentary scan contract`](../backend-and-data/18-complimentary-pro-scans.md#verification-map).

The reusable candidate gate—and the production workflow that requires it—apply
all migrations to a disposable database and run
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
- `species-observation-stats/db.test.ts` proves canonical RFC UUID versions
  1...8 and UUID/name binding are accepted before provider work, exact taxon
  misses are negatively cached, non-owners dispatch no provider calls, every
  fetch receives an abort signal, provider bodies are stream-bounded, failed
  empty populations resolve `unavailable` instead of `partial`, and failed
  database finalization is not retried with downgraded cache state.
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

Public-username reservation has explicit cross-layer coverage:

- `update-public-username/validation_test.ts` and
  `_tests/updatePublicUsername.test.ts` cover normalized Edge decisions,
  protected roles, exact product-role combinations in both directions, and
  allowed non-prefix community handles.
- `_tests/publicUsernamePolicyMigrationContract.test.ts` parses the PostgreSQL,
  Edge, and iOS policy groups, requires sorted duplicate-free parity, locks the
  deterministic existing-profile repair, and forbids rewriting historical
  mention tokens.
- `_tests/exploreIdentityDb.test.ts` exercises current validator behavior and
  the historical mention-token/current-profile split on disposable PostgreSQL.
- `tests/public_username_policy_security.sql` verifies the immutable catalog
  function, both validated CHECK constraints, representative allowed/denied
  values, and an actual rejected profile update.

Run the static migration suite and the complete discovered pgTAP catalog; a
passing TypeScript contract alone does not prove the PostgreSQL migration or
backfill. Mention snapshots enforce structural username shape but intentionally
do not inherit later reservation lists, because their token must continue to
match immutable comment text.

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
  `replay_exhausted` allowlist, composite dead-letter/quota/media-lifecycle
  proof for `media_reconciliation_abandoned`, retention of exact failed and
  committed recovery authority across quota pruning, completion-last media
  finalization, strict compatibility audio deletion ordering, worker
  compare-before-complete behavior, strict atomic-setup RPC decoding, the
  parent-first DwC-A generation lock, and the revocable grant/cleanup protocol.
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
  idempotent inline request-body completion, queue-owned 15-second versus
  direct-caller 90-second Identify deadlines, and owner-scoped
  `/update-scan-context` construction. It also verifies single-status recovery,
  combined Explore recovery/media restoration, and the Ask/Field Chat repair
  seams. Its route-retry coverage also cancels a replayable request after its
  first dispatch and proves no second request is issued or noncanonical
  `URLError.cancelled` escapes the task-owned transport boundary. Establish the
  first dispatch through a bounded `ContinuousClock` wait for the observable
  mock request, not a fixed number of `Task.yield()` calls: URLSession protocol
  scheduling is not coupled to executor-yield count on a loaded hosted
  simulator. The test must still assert an exact count of one immediately before
  cancellation and again after canonical `CancellationError` exits the retry
  delay. `MerianConfigTests` locks customer-facing Explore error translation;
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

**Live-to-queue transport handoff regression matrix:** A test that throws
`URLError` from consent preflight, request construction, or another pre-dispatch
hook does not cover this boundary. At least one visual and one nonvisual case
must dispatch through `MockURLProtocol` or an equivalent URLSession-level seam,
then perform this ordering deliberately:

1. create and persist the exact queued row, job generation, and deferred-upload
   hold;
2. observe the first request at the transport boundary through a bounded
   rendezvous;
3. for path-loss cases, simulate `releaseAllForegroundInferenceClaims` while
   the request is still pending; for the black-hole timeout case, prove the path
   and exact durable owner remain active instead;
4. release the matching transient transport failure to the engine; and
5. allow durable retirement/replay work to settle without directly deleting
   process-local registries in test cleanup.

The assertions must prove the exact queued presentation ID, retained durable
row, released upload hold, eventually cleared foreground generation, `.queued`
Insight mode, no `SpeciesData`, no error haptic/circuit failure, and exactly one
live transport request. The `.timedOut` branch must begin with generation
metadata still present and retire it through the handoff itself. Request-policy
and timing assertions must prove queue-backed Identify carries the 15-second
foreground bound, does not enter the generic two-second replay or a 90-second
deadline, and completes the post-error queued handoff within 1.5 seconds.
Separate controls must preserve the 90-second window and **Network timeout** for
a queue-less direct request and classify **Analysis delayed / Scan saved** as an
inference error placeholder for an exhausted queue-backed server failure.
`testInferenceErrorPresentationRoleDoesNotDependOnDisplayCopy` separately proves
that this classification comes from `SpeciesData.presentationRole`, not the
localized title: arbitrary error copy remains an error, while result-role data
cannot become an error merely by sharing legacy fallback text.
Finally, a same-ID background/status completion must replace queued content,
while a newer scan fences the delayed error.

The current source implements this matrix with the gated
`queueBackedConnectivityFailuresUseQueuedPresentationForVisualAndNonVisual`,
`queueBackedAttemptRequiresForegroundGenerationForAllMedia`, which rejects a
durable scan ID without its exact queue-generation token before either pipeline
can start,
the network-client request-count controls
`queueBackedIdentifyReturnsFirstTransportFailureWithoutInlineReplay` and
`queueLessIdentifyRetainsOneReviewedInlineTransportReplay`, the queue-less
engine presentation control, the server-failure separation test,
`retiredQueueOwnerStillPublishesQueuedAfterTransportSuccess`, and existing
background/replacement identity fences. The first engine case now retains the
owner for `.timedOut`, while the two network cases assert 15- and 90-second
request bounds respectively. All are exact protected cases in
`validate-ios-critical-test-results.sh`. The complete matrix remains a release
closure gate, not merely a compiled test; see the
[live scan connectivity handoff incident](../incidents/2026-08-live-scan-connectivity-handoff-gap.md).

The preceding pre-queue boundary has separate deterministic coverage.
`testScanAdmissionPreviewUsesBoundedFailFastTransportPolicy` locks the exact
two-second request/resource deadline, disabled connectivity wait, absent cache,
and source contract disables PostgREST retry.
`connectivityUnavailableAdmissionSelectsQueueOnlyRoute` locks every reviewed
offline/data-path URL code, bounded underlying-error recognition, TLS/auth
fail-closed exclusions at every wrapper depth, the broader post-durability
secure-connection recovery boundary, certificate-policy veto precedence over a
broad outer transport error, fail-closed over-depth handling, and the pure route
policy without mutating process-wide connectivity state.
`automaticSingleCaptureNeverPresentsIdentifyBeforeSubmission` independently
locks the adjacent presentation boundary: automatic single-capture ownership
hides `ActiveScanToolbar` before asynchronous admission begins, admission
recovery can reveal the retained staged media, and confirmation-enabled capture
continues to present **Identify** normally. It also locks the distinct pre-crop
boundary: a required crop suppresses capture chrome even before `imageToCrop`
mounts the full-screen cover. The workflow source guard requires
`ImageCropperView` to keep Close and Delete in native `.topBarLeading` and
`.topBarTrailing` toolbar placements, with deterministic accessibility IDs, and
forbids manual top positioning from `GeometryProxy.safeAreaInsets.top` or
`.safeAreaPadding(.top, ...)`. It also forbids a workspace-owned black crop
shield or persistent transition flag and locks an accent-tinted, white-label
confirmation action.
`exhaustedImageImportAdmissionBlocksBeforePickerAndCrop` locks the import entry
boundary: a valid exhausted preview receives the prospective one-image Flash
shape, opens the paywall, and leaves staging, crop state, and the admission
in-flight flag empty before `PhotosPicker` can be presented. The external-import
integration additionally requires the durable inbox receipt to survive the same
server denial without staging or crop.
`testConnectivityUnavailableAdmissionQueuesVisualAndNonVisualCaptureWithoutForegroundInference`
then drives an actual path-satisfied `.timedOut` preview through staged visual
and direct nonvisual submission and requires both durable rows, no foreground
generation, no analyzing Insight, no live engine processing, cleared staged
input, and a still-online path. `testMalformedScanAdmissionPreviewRemainsFailClosed`
proves an invalid server shape preserves the fail-closed retry path. The pure
connectivity policy and pre-import boundary cases are in the exact protected
inventory; the workflow source contract also requires their integration
declarations to remain present.

The compiled hosted UI gate adds
`testLiveInsightConnectivityFailureTransitionsToDurableQueue`. Its Debug-only
fixture commits an exact description-backed queue row, opens the standard live
Insight in analyzing mode, and waits for an explicit `ScanningStatusBadge` tap
before invoking the production queue-presentation boundary. The test requires
the Debug-only exact `QueuedPresentation_<scan-id>` marker, continued normal AI
analysis copy, absence of the removed saved/continuing explanation and **Network
timeout**, successful sheet dismissal, and the same `QueuedScanTile_<scan-id>`
in Scans. The marker exists only under the UI-test seed and contributes no
visible layout or release accessibility element. This complements rather than
replaces the URLSession regression: the unit test proves transport and ownership
ordering; the UI smoke proves the open sheet consumes the resulting exact-ID state. Sheet
dismissal must resolve the native `InsightSheetCloseButton` accessibility
identifier through the current `InsightSheetView`. A global `Close` label query
is not a valid test contract because layered SwiftUI presentations can expose
both the active Insight control and an underlying close control.

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

Retryable status recovery must also exercise deliberate drift between
`OfflineQueuedScan` and its scan-ingestion `OfflineJobRecord`.
`scheduledServerFailureMarkerIsReadFromDurableStore` erases the queue-row
marker/count while the job survives and proves a transient re-stage failure
advances to attempt two.
`testMarkScanAsStagedPreservesScheduledServerFailureRetry` passes the same
topology through upload claim and staging.
`testScheduleInferenceRetryUsesMonotonicMirroredAttempt` proves the writer uses
the maximum copy, while
`testInferenceRetryCannotOverrideCompletedCloudOwnership` proves a job-only
cloud-complete marker vetoes a late retry. All four are required named Release
results, not merely compiled tests.

Fixtures that persist a future queue or job retry deadline must not immediately
expect upload or inference claim success: that would contradict the production
backoff contract. Claim-success fixtures must either omit the deadline or
advance both mirrored deadlines to the scheduled wake before claiming.
`pausedScansCannotBeClaimedOrReconciled` owns future-deadline rejection, while
`testTryClaimForInferenceSucceedsOnStagedScan` verifies that an elapsed deadline
is accepted and cleared atomically from both durable rows.

Field trip capture guidance has focused coverage on both sides of the Edge
boundary. `_tests/fieldTripsMigrationContract.test.ts` source-locks the private
RPC grants, verified-user Edge call, filtering/order clauses, preservation of a
standard field trip after a Seasonal Challenge join, exclusion of
challenge-specific progress, the non-destructive retirement of placeholder
templates, and the evidence-free capture projection. It also locks the private
catalog/detail `completed_scan_id` projection, detail-only publication status,
owner/non-deleted join, service-role-only grants, and credited-level/count
fields in both scan-progress RPCs. The persistent-contribution contract
additionally locks the migration abort guard, private preference table,
one-credit uniqueness and scan-first indexes, preferred-goal validation/ranking,
correction invalidation, service-role-only contribution RPC, and
evidence-minimal projection. The atomic-hardening contract locks the
receipt/trigger/transactional entry point, publication-ID repair, empty
security-definer search paths, and global Field trip/Event ACL revocation. The
confidence-policy contract locks the tier-specific Possible-match boundaries,
explicit-review overrides, receipt revision/preference carryover, the
evidence-update trigger, private downgrade-reconciliation helpers, prior-credit
repair, and preservation of pending selected-goal preferences.
The starter-level and enrollment contracts lock the 2/4/4 catalog, exact Dog
criterion, active-template preflight, insert-only existing-account backfill,
`public.users` trigger, initial activity period, no-resume conflict path, empty
search path, and denied execution for every API role.
`_tests/fieldTripCaptureContextDb.test.ts` exercises those rules against local
Postgres, including trigger-driven enrollment, exactly one open starter period,
and empty results after Reset; it reports a skip when the local stack is not
available, and that skip must not be counted as database validation.
`_tests/fieldTripProgressDb.test.ts` exercises standard and challenge
credited-level responses across Backyard enrollment, explicit starts for other
outings, challenge joins, one credit per experience, several active experiences,
delayed upload after an outing/Event
ends, preferred-goal priority, deterministic fallback, advancement, unfinished
correction removal/move after deactivation, normal correction freeze after
completion, ownership isolation, concurrency, exact confidence boundaries,
weak-match confirmation, pending-preference retention, evidence-downgrade
removal/reopening after completion, and idempotent reapplication under the same
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
used by catalog/detail thumbnails, optional ordered reference-species media,
published status, optional removed-item metadata, and standard/Event
contribution decoding plus typed destinations. A
separate legacy-payload test ensures absent publication fields decode as Private
during rollout. The progress-response tests cover both the legacy shape and an
extended level- advancement shape where current counts are `0/N` but credited
counts are the completed full level. `AchievementToastPresenterTests` covers
delayed strict ordering, multiple standard/challenge destinations, common-name
fallback, progress failure, empty matches, completed-level rings,
foreground/background scan-ID deduplication, bounded overflow, typed payload
coalescing, session fencing, and foreground-host lifetime/effect ownership. The
Field Trips Deno
`referenceMedia_test.ts` suite locks all 20 current goal-to-illustrative-species
mappings, target extraction, one-per-source Naturebook/Wikipedia/GBIF ordering,
and item-scoped payload attachment; `db_test.ts` also executes the bounded
species/reference hydration projection. `InsightSheetViewModelTests` covers
contribution loading, scan-change race rejection, silent error/empty states,
queued/unauthenticated/non-biological gates, public Event rows, invalidation
reload, and root/embedded routing in addition to the dictionary eligibility
policy. `FieldTripFeaturedMediaTests` covers the standard outing hero progression:
default illustrative references; exact completed photo, video-poster, and
legacy-cover replacement; fallback for missing, archived, incomplete,
nonvisual, posterless-video, reference-only, and repeated-scan records; strict
Naturebook → Wikipedia → GBIF failure advancement; stable goal identity across
reference-to-user replacement; active-level-only checklist ordering and its
six-item cap; same-level source-exhaustion reserve refill; and mixed reference/photo/video
full-screen order with muted video. It also locks provider/user VoiceOver copy
and top-edge underlap whenever at least one featured item exists, plus the
bottom-leading Naturebook contributor and bottom-trailing provider attribution
policy, preventing empty-media detail from moving beneath transparent
navigation chrome. `ActiveCaptureGoalStoreTests` also locks the inline-tip
policy so completed, locked, guide-free, or fully completed outing states do
not expose guidance. The focused Insight suite remains paired with this suite
when the shared native pager, pagination, attribution, or top scroll-edge
treatment changes, so reuse cannot regress Insight's mixed-media handoff
behavior.
`OfflineQueuedScanDeletionTests` verifies normal cancellation removes a
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

`testQueuedAudioScanRetainsAudioAcrossCompletionHandoff` launches the seeded
queued-audio flow, opens Scans, and taps the staged tile. It requires the queued
Insight to expose native **Back** in the Scans navigation stack plus
`ScanningStatusBadge` and **Did you know?**, locking parity with foreground
scanning rather than a nested-sheet variant. It then verifies the same audio
carousel page exists before and after the seeded **Northern Cardinal** completed
record replaces queued content in place. Its seed writes a valid PCM WAV to
Documents, and the test requires the decoded filename-scoped playback control
before and after replacement; a page backed only by a missing filename cannot
pass. The fixture does not use elapsed wall-clock time to initiate replacement.
Only after native navigation, shared scanning content, audio-page, and decoded
playback assertions pass does the smoke tap `ScanningStatusBadge`, which asks
the exact Debug-only seed to perform the handoff. That transaction writes
through the same environment `ModelContext` already bound to the open sheet and
immediately calls the production queue-promotion method with that context. The
open child promotion completes before the synchronous library-update
notification refreshes the parent Scans surface, so a retained queued route
snapshot cannot win a re-entrant rebuild. On every later bind, a persisted
same-ID completed record remains authoritative over that route snapshot. If that
exact completion is already bound, the stale route rebind must be an idempotent
no-op that preserves presentation generation and visible result actions.
Production sessions and the Release coordinator remain no-ops for the request.
The badge must not contain translated SwiftUI child geometry: completed-state
glare is painted inside a fixed Canvas, label changes use an opacity-only
content transition, and the native Button receives an explicit label without
being re-composed with `.accessibilityElement(children: .ignore)` before the
composed control is fixed to intrinsic size. Hosted Run 104 proved that visually
clipping translated descendants was not sufficient to constrain the semantic
frame. Hosted Run 105 passed all 1,243 units and its exact-SHA Release archive
but proved that synthetic recomposition also prevents the caller's
`ScanningStatusBadge` identifier from being found as a Button. The portable
contract therefore rejects both animation patterns and that accessibility
modifier. Both critical scan smokes share one
`scanningStatusBadgeElement(in:)` helper containing the repository's single
`app.buttons["ScanningStatusBadge"]` query, so neither test can retain dead
native-query text while silently falling back to weaker element-class
semantics. The queued-completion smoke requires the native Button's accessibility
frame to be fully contained by the application frame before tapping and prints
both rectangles on failure. This prevents XCTest from silently substituting an
edge-of-window activation point for an invalid off-window rectangle and
reporting the resulting no-op as a promotion failure.
The completed state must also expose the identifier-scoped Field Chat and Share
toolbar buttons. Their delayed reveal and Field Notes synchronization are keyed
to the monotonic presentation generation, not the unchanged scan ID, ensuring
both tasks restart after promotion. Keep all navigation, shared-scanning,
playable-media, downstream-toolbar, and handoff assertions when extending this
regression. The exact-SHA hosted `Full iOS unit tests` job executes this case
after the complete unit target; compilation alone is not acceptance evidence.
The native-control correction is committed at
`c7eac9c8f3124437712ee72eeff49d09e6ea55b1`; a local exact-SHA generic-Simulator
`build-for-testing` compiled and linked the app, unit bundle, and UI bundle for
arm64 and x86_64, but a hosted XCUI result is still required.

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

The public Field trips release has explicit regression coverage.
`FieldTripsAvailabilityTests` locks the parent Field trips surface on for every
account and verifies Events are absent from the feature-flag registry.
`FieldTripAPIModelsTests`, `ActiveCaptureGoalStoreTests`, profile visibility
tests, `AchievementToastPresenterTests`, and `InsightSheetViewModelTests` verify
that Event sections, badges, progress, typed routes, and scan contributions are
part of the normal client path. Manually test a physical signed-in account, a
physical ghost account, and a simulator build; all must see the Events segment
and be able to exercise the server-authorized flow.

Progress-toast device QA must use the DEBUG Settings preview at compact and
large widths with long species/trip names, VoiceOver, and Reduced Motion. A live
scan matrix must confirm standard outing toasts precede Seasonal Challenge
toasts, achievements, and **New to Naturebook**; standard taps focus the first
credited goal, challenge taps open challenge detail, and progress refresh events
do not create a duplicate plain banner. Re-identify an older scan after level
advancement and confirm only rows inserted by that attempt supply destinations,
newly completed items, and credited rings.

Presentation-handoff QA must also exercise interactive and programmatic
dismissal for Candidate review, Confidence explanation, Insight Chat, and the
Explore activity sheet. Select a candidate, ask the community, start
reanalysis, trigger a Pro paywall, and open a reply-thread notification while
rapidly changing or dismissing the source sheet. The destination must mount only
after the source's real `onDismiss`; a stale scan/generation must produce no
mutation, route, toast, or sibling sheet. Replace an ordinary toast during its
three-second lifetime and mount/unmount a nested milestone host; the replacement
must survive the old timer, and the milestone must not repeat haptics or
VoiceOver or reset its remaining lifetime.
While dismissing every Explore-owned comments, activity, Insight, profile,
filter, editor, reply-thread, Field Notes, Field Chat, and paywall sheet, verify
video remains paused until the presented content disappears. Nested sheets must
not increment `resumeGeneration` until the final overlay token is released.

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
- `MerianNetworkClientTests.testDeleteScanRejectsUnconfirmedSuccessResponse`
  rejects empty, false, missing-key, and non-object 2xx bodies.
  `OfflineQueueManagerTests.cloudDeletionRequiresExplicitNetworkConfirmation`
  proves `invalidResponse`, HTTP, and transport errors all retain durable cloud
  erasure work; only a validated nil dispatch error may remove the pending task.
  `cloudDeletionRetriesNeverEnterAnUnrecoverableState` proves exhausted legacy
  and contradictory terminal job statuses are repairable, while retry delay
  progression remains numerically capped without expiring the erasure request.
  `cloudDeletionDrainIsProcessSingleFlight` proves a competing foreground wake
  cannot claim, dispatch, or mutate the same pending erasure task while one
  process-local drain owns it. The persisted `.running` state intentionally
  remains runnable after process loss, so the in-memory latch cannot strand
  privacy work across relaunch.
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
- **`scripts/revenuecat_customer_operations_test.ts`**: Covers delimiter-safe
  offline exports, conservative customer classification, canonical UUID
  formatting, exact explicit-cohort selection independent of current
  free/timed/permanent projection, permanent Auth evidence, duplicate/malformed
  and Ghost rejection, cohort hashing, finite grant expiration, zero-request
  dry-run, no-non-cohort request proof, already-active skip, successful
  get-or-create GET `201` followed by one POST `201`, rejected POST `200`,
  bounded retry, and secret-free per-customer failures.
- **`tests/revenuecat_webhook_security.sql`**: Executable pgTAP coverage for
  ACLs, direct-table isolation, duplicate delivery, a delayed expiration after
  renewal, a delayed purchase after refund, snapshot-primary ordering,
  reconciliation claim/application fencing, indexed expired-lease reclamation,
  backlog-health telemetry, event-ID/payload conflict, atomic transfer of source
  and destination, a deleted transfer source with a live destination,
  ambiguous-alias rejection, missing-user failure, and entitlement-version
  advancement. Keep this test in the disposable-database deployment gate
  alongside `privileged_routine_security.sql` and `ai_quota_security.sql`.

The source-level grant, stable-purchase-identity, and unauthorized-recovery P1
matrix above is implemented.
The canonical-ID/beta rollout remains release-evidence-blocked until one exact
revision also supplies both of the following:

1. A staged Ghost purchase plus normal OAuth link proving the UUID and Pro state
   remain stable, a generic-`401` case proving no identity rotation, and an
   existing-account conflict pair proving the configured store-transfer
   behavior. Beta promotion remains limited to the reviewed permanent cohort.
2. A complete disposable PostgreSQL replay and all catalog tests under the
   pinned Supabase CLI. Static migration contracts and green iOS/TypeScript unit
   tests do not replace this evidence.

The complete production hold and customer-path smoke matrix are in the
[RevenueCat customer identity incident](../incidents/2026-08-revenuecat-customer-identity-drift.md).

### `sync-collections/db_test.ts`

- **Atomic collection admission**: Verifies RPC errors throw and cannot trigger
  membership hydration or writes; accepted IDs continue while rejected foreign
  IDs remain skippable; duplicate input IDs use the database result rather than
  a client-side ownership guess.
- **Owner-joined membership writes**: Verifies additions call
  `insert_owned_collection_scans` with the authenticated owner, count skipped
  missing/foreign parents without failing unrelated work, and throw on RPC or
  membership-delete errors. The empty-accepted-ID path makes no membership DB
  calls.
- **Composite membership cursor**: Verifies the existing-membership reader
  advances from the final `(collection_id, scan_id)` key of a full page and
  never falls back to range/OFFSET pagination before calculating the delta.
- **Fresh-catalog security**:
  `functions/_tests/collectionOwnershipMigrationContract.test.ts` locks the
  migration shape, invoker/empty-search-path routines, ACLs, column update
  grant, owner-match trigger, cleanup, and split RLS. Executable
  `tests/collection_ownership_security.sql` proves foreign collisions, direct
  service owner-update denial, RPC/direct/RLS membership rejection, and Ghost
  merge compatibility against PostgreSQL.

### `_shared/entitlement_test.ts` and `_shared/aiQuota_test.ts`

These replace the former worker-cache tests. Entitlement tests must prove every
call observes durable database state and never upgrades a query error or missing
profile. They also lock current complimentary resolution, global protocol
cutover, and the narrowly authenticated internal replay bypass. Quota helper
tests must keep request IDs bounded to UUIDs, preserve original-analysis and
complimentary linkage, accept only route-derived fallback eligibility, protect
raw network addresses with a strong rotating HMAC, and fail closed when
configuration is missing. Database atomicity and ACL behavior belong in
`tests/ai_quota_security.sql` and
`tests/complimentary_pro_scans_security.sql`, not a mocked TypeScript client.
