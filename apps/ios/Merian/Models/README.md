## October 22 — V66 release-start storage foundation qualified

The active schema is V66. The additive V65→V66 stage adds nullable
`releaseStartData` and `releaseStartSHA256` to the existing receiving slot.
Migration leaves both nil and preserves every historical identity, phase,
revision, prepared/result byte sequence and digest. V65 was frozen and compiled
before editing the active record. Its unchanged models retain the complete
closed V64 relationship graph. No relationship or historical schema is changed.
Every applicable forward plan appends V65→V66; V65 has a dedicated recent-source
startup plan. Rescue and quarantine eligibility are unchanged.

Raw Row equality includes both fields. All current slot/phase, clean and dirty
receiving, manual release and whole-store paged audit paths reject any populated
or partial sidecar. This includes foreign/orphan rows. Storage grants no request
staging, release start, provider execution or cleanup permission. No runtime
writer creates, consumes or clears these fields. A future typed owner requires
separate binding/audit, accounting, writer-closure and recovery qualification.
Existing metadata, package and physical limits remain unchanged.

Exact independent and IC-1 reviewed shared-checkout validation passed 177
methods / 232 invocations across the 17 selected migration, recovery, model,
receiving, audit, funding, codec and purge suites on the installed simulator.
The first run retained one stale orphan-error expectation failure; its reviewed
test-only correction passed in a single-method rerun. All 2,927 source/project
hashes stayed unchanged during each run. Source guardrails and their adversarial
checks, full portable iOS CI tooling, project generation/validation and Markdown
checks passed. This does not claim device, broader matrix or full-feature
acceptance. Exact evidence:
`.artifacts/native-app-capture-handoff-20261020/v66-validation01.json`.
Activation disabled; PR116 frozen; deployment hold active; AWS unapproved.
Earlier dated sections below retain historical implementation and validation
facts; this section owns the current schema version and sidecar behavior.

## October 20 — V65 receiving-intent storage foundation

The active schema is V65. Its additive V64→V65 stage introduces one empty
package-keyed receiving-intent slot table; it does not create operations, adopt
media or activate Capture. V64 was frozen and compiled first. Existing
source-isolated plans append the new stage, and V64 has its own recent startup
plan. Destructive rescue and quarantine eligibility remain unchanged.

Raw intent rows are conservative storage liabilities, including malformed or
unanchored rows. Until the intent-aware owner is qualified, they block legacy
qualification/purge and native scoped mutation audits, including after page
suspension. The canonical codec remains a descriptive value, not a writer
capability. Typed staging, receiving, exact recovery, abandonment and Capture
handoff remain subsequent acceptance gates. Numeric limits are unchanged.

Local validation passed 185 focused methods. The complete unit target recorded
6,456 passes and one omitted purge-inventory fixture; the corrected three-suite
rerun passed 23/23 methods with runtime sources unchanged. Full-run evidence,
including a synthetic video-fixture QoS warning, remains retained. This is
shared-checkout validation, not isolated, device or integrated acceptance. See
`docs/rfcs/identification-history-alpha-readiness-2026-10-11.md` for exact
results. Activation is disabled, PR116 frozen, deployment held and AWS
unapproved.

# App Models

## October 16 — native consumer foundation locally qualified

NCI-1 adds V63 explicit legacy/shared authority, scalar consumer identity and
pending/retained accounting after compiling the frozen V62 graph. Migration
preserves existing paths, submitted snapshots and relationships without creating
bindings. Consumer state blocks unsupported legacy construction and purge;
shared-tagged queues cannot use ordinary legacy inference. Exact bounded cohort
joins and migration/reopen passed focused qualification. The complete native run
retained 6,092 passes and one stale test inventory failure; its test-only
correction passed the reviewed purge-suite rerun. Typed mutation owners,
retained accounting and producer integration remain under construction. This is
inactive local work, not completed product acceptance. PR116 remains frozen and
the deployment hold remains active.

This directory owns values and persistence declarations shared across product
features. It is not a home for feature state, networking, filesystem work, or
live dependency resolution.

The canonical persistence contract is
[Database Schema](../../../../docs/backend-and-data/04-database-schema.md), and
the migration procedure is
[SwiftData and API Gotchas](../../../../docs/development-guides/11-swiftdata-and-api-gotchas.md).

## Ownership

- `Species/` owns the platform-neutral `SpeciesData` value graph, supporting
  observation values, deterministic display and identity policy, and rich
  lookalike values. It imports Foundation only and performs no networking,
  persistence, task creation, or live dependency lookup.
- `Media/` owns the Foundation-only captured-media value graph: the
  cross-feature `ObservationContext`, storage references, the ordered Codable
  timeline, deterministic snapshots and summaries, and scalar JSON coding.
  Filesystem resolution, cloud hydration, SwiftData mirror writes, and Capture
  submission projection remain outside this value owner.
- `ActiveSchema/` owns the current SwiftData model declarations. A stored-field,
  entity, relationship, uniqueness, or migration change must follow the
  repository's SwiftData migration procedure; moving a declaration is not a
  substitute for a schema version. `ModelContext` fetch/mutation workflows
  belong to the relevant Core Data persistence owner, not beside these
  declarations.
- `Schema/` contains immutable historical schema snapshots. Do not edit a
  released snapshot to make the current model compile.
- `SchemaVersions.swift` declares schema versions and migration stages. It
  remains a single migration registry so version and stage order can be reviewed
  together; `Aliases.swift` owns the current-schema alias.
- Root `ScanQueueState`, `UserReviewState`, and `QueuedScanContext` remain
  stable cross-feature vocabulary. They are deterministic values. Offline Sync's
  main-actor persistence projection copies a live queued row while its storage
  policy supplies the queued byte estimate; Insight's media-presentation
  extension maps the resulting context to `ActiveScanMedia` and restores Capture
  focus descriptors.

AI-bound adaptation is intentionally outside this directory. Core AI
[`Models/`](../Core/AI/Models/) owns capture telemetry and the
`EdgeResponse`-to-`SpeciesData` mapping because those values depend on inference
runtime and wire declarations. Generated Identify DTOs remain in Core AI; other
endpoint wire DTOs remain under Core Network.

## Change Rules

- Keep shared value models deterministic and free of live effects.
- Preserve public and internal initializer, Codable, and presentation behavior
  when relocating declarations.
- Do not add a convenience network client, singleton, task, or model context to
  a value owner.
- Keep production files in `Models/Species` and `Models/Media` below the local
  600-line review ceiling. Prefer a cohesive owner over fragments created only
  to reduce line count.
- Mirror focused behavior and ownership tests under `MerianTests/Models`; Core
  AI model tests belong under `MerianTests/Core/AI/Models`.
- Keep Capture-specific transformations with Capture.
  `Features/Capture/Submission/Services/CaptureSubmissionTelemetry.swift` owns
  native-default zoom normalization, and `CaptureSubmissionPolicyTests` locks
  that behavior rather than the Core AI telemetry suite.

## Verification

`SpeciesModelsArchitectureTests` locks the exact species source and test
inventory, unique declaration ownership, Foundation-only imports, effect-free
model files, Core AI mapping ownership, retired aggregate paths, and the local
line ceiling. The focused Species suites preserve initializer, presentation,
identity, Codable, and lookalike behavior. Core AI's `CaptureTelemetryTests` and
`SpeciesDataEdgeResponseTests` preserve capture-context and wire-to-domain
mapping respectively. The architecture suite prevents the Capture-owned zoom
policy regression from drifting back into Core AI.

`CapturedMediaArchitectureTests` locks the captured-media declaration owners,
effect-free value layer, unchanged V51 persisted property shape, retired
aggregate path, mirrored focused tests, and the same 600-line ceiling. Behavior
coverage is split between captured-media value, resolution, active-schema
mirror, and cloud-hydration suites rather than one cross-layer test aggregate.

`ModelsIntegrationArchitectureTests` closes the boundary across root values,
`ActiveSchema`, Species, Media, and the migration registry. It freezes the root
and active-schema inventories, rejects live effects and persistence workflows in
those owners, verifies the queued-row projection plus the queued-byte,
Insight-media, and cloud-deletion adapters have one owner each, applies the
600-line guard to every nonhistorical model file, and leaves
`SchemaVersions.swift` as the explicit ordered-registry exception. The app-wide
`IOSHygieneClosureArchitectureTests` inventory independently records that file
as the only oversized Models owner, so another Models exception cannot appear
without review.

Run project generation, source membership, the focused model suites, and the
complete unit target after moving or adding Swift sources. The canonical
selector list is the Models closure matrix in the
[testing strategy](../../../../docs/development-guides/08-testing-strategy.md).

## V53 primary identification storage

`PrimaryIdentification` retains the immutable AI label and resolution separately
from dictionary and review fields. Invalid-present bytes remain distinguishable
from legacy absence. `LocalScanRecord` pairs that snapshot with its provenance
marker; a required missing snapshot cannot regain legacy species behavior. V53
adds optional primary and confirmation bytes. `ConfirmedSpeciesReview` strictly
validates the separate versioned server envelope, including revision and
nullable identity. A clear remains a stored envelope after reopening. Typed
overrides and legacy flags describe pending local intent and never manufacture
authority; a pending selection cannot borrow the previous confirmation's
identity. V52 snapshots remain frozen and hash-pinned. The complete migration
and physical install-over requirements live in the schema and startup recovery
guides; no protocol-5 producer is enabled by this native checkpoint.

## V57 analysis history storage

`LocalAnalysisRecord` is immutable, owner-private opaque result storage with
version/object/byte-limit validation. Its parent relationship cascades deletion;
future reads must use bounded child queries. V54 and V55 are independently
frozen and hash-pinned. V56 makes completion optional only for imported V3
snapshots; V1/V2 require finite completion dates. The lightweight V55→V56 stage
preserves existing completion values and exact bytes, without creating history
or inferring a missing date. The additive migration preserves current projection
and review bytes, starts with no child results or inferred owner, and marks
selection initialized so a later completion cannot replace a legacy correction.
The
[canonical schema contract](../../../../docs/backend-and-data/04-database-schema.md#native-analysis-history-storage-and-v55)
defines this foundation and the prepared account-bound admission owner under
`Core/Data/AnalysisHistory`. Live completion, enrollment and normal sync remain
activation prerequisites. Neither restoring results nor history-based reanalysis
is enabled.

V57 adds `LocalAnalysisStateRecord` for bounded owner-private authority and
immutable display bytes, separately cascade-owned by `LocalAnalysisRecord`.
`SchemaV56ScanSnapshots.swift` and `SchemaV56QueueSnapshots.swift` freeze the
outgoing nullable-completion graph. The additive V56→V57 stage creates no cache
rows and preserves all selection, correction and observation fields. Admission
and display mapping remain under `Core/Data/AnalysisHistory`, with no ordinary
sync or Restore caller. Account purge includes both child entities.
