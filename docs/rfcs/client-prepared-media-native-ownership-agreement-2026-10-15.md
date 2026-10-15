# NCO-1: native ownership agreement and P1 implementation packet

October 15, 2026. The human approved the two-hour local schema/capture/cleanup
agreement scope after `600b5ce28`. Window: 22:54:43 UTC to 00:54:43 UTC
October 16. This is a design agreement and proposed execution packet, not
implementation or test permission. Activation disabled, ordinary access nil, AWS
unapproved, existing package/storage/resource limits unchanged; auto-prompts
paused.

## Result and recommendation

Close CP-1's two design prerequisites with **P1-L1, four standalone native
ownership entities in SwiftData V59**, and a minimal additive capture handoff
owned by History. Originals remain private files. No field or relationship is
added to an existing queue/scan model, and preparation cannot create a scan job,
claim funding or invoke inference. This is an additive V58-to-V59 proposal; it
still needs actual migration and lifecycle tests before acceptance.

The next useful work is one **four-hour local implementation/validation window**
for P1, followed by exact independent and IC-1 review. It implements the
inactive photo-acquisition-to-held-package path and its cleanup/recovery
integration. It does not complete CPM server admission, version creation,
audio/video preparation, cloud reference accounting or the installed product
journey. No further transport/verifier experiment is justified.

The source review resolves the schema and code owners. No additional
architecture survey is proposed. If implementation discovers an incompatible
schema/source change or exceeds this exact file boundary, stop with that
concrete conflict; do not add a parallel writer or expand the checkpoint
automatically.

## Native persisted contract

New standalone models under `Models/ActiveSchema/`, without SwiftData
relationships or cascade links to legacy entities:

| Entity                      | Stored authority                                                                                                                                                                                                     |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PhotoPreparationRecord`    | Unique package UUID; owner UUID; fixed contract `P1-L1`; draft UUID/generation; revision; phase; bounded ordered supporting-context snapshot; derived allocation totals; retirement status.                          |
| `PhotoPreparationAsset`     | Unique asset UUID; owner UUID; immutable generation; opaque relative file token; actual supported content type; role-independent byte count and SHA-256; acquisition kind; file/cleanup state.                       |
| `PhotoPreparationReference` | Unique edge UUID; package UUID; asset UUID; owner UUID; role (`original`, `aiInput`, `display`); ordinal; revision; live/retired state.                                                                              |
| `PhotoPreparationLease`     | Unique lease UUID; package/asset/owner IDs; process epoch; purpose (`acquire`, `copy`, `read`, `retire`); fixed partial/final file tokens; reserved and allocated byte liabilities; writer state and terminal proof. |

`ownerID` always means the stable authenticated account UUID in every entity,
lease, handle and namespace; it never means a package, local reference owner or
process ID. Qualification substitutes one explicit synthetic account UUID.
Package/draft/asset IDs remain distinct; generation fencing supplements, never
replaces, account scope. Cross-account resolution fails before file access.

Use UUID, String, Int64, Bool and optional scalar metadata as appropriate;
original, AI and display media bytes never enter SwiftData. Supporting-context
metadata may use a bounded versioned encoding of existing `ObservationContext`
values, with strict decoding and the existing text/1 MiB envelope. It must
preserve ordered values exactly; no new text-only submission or replacement of
submitted text. Unknown contract/phase/role, missing referenced owner or
inconsistent counters means `needsAttention`, never ordinary queue fallback.

Allocation totals are reconstructed from distinct physical assets and unresolved
lease liabilities; stored summaries are checked caches, never a second quota
authority. A mismatch blocks new allocation until reconciliation. Integer byte
counts and revisions use checked nonnegative Int64 arithmetic.

All uniqueness constraints are on the explicit IDs. Foreign-key-like integrity
and aggregate caps are validated by the sole repository transaction under the
cross-instance lock, not assumed from scalar UUIDs. Each critical section
refetches in a fresh repository context and compares revisions after taking the
lock; a cached model/context is not authority across another owner's save. Asset
hashes alone do not merge ownership. Initial entity sets are empty on migration:
do not backfill originals from display/inference paths, infer admission from
queue state, or rewrite existing snapshots.

Phases are `acquiring`, `draftOwned`, `preparedHeld`, `needsAttention`,
`retiring`. Only draft-owned context is editable. Freeze atomically fixes
ordered references, supporting context and identity; any changed input requires
explicit new work. `preparedHeld` has no scan token, server receipt, upload
ticket or provider grant. P1 does not expose a promotion into ordinary queue
work. Later CPM integration must introduce its separately reviewed handoff and
cannot reinterpret this phase as server admission. Uncertainty remains recovery
of the original identity.

### Storage and transaction authority

A new `PhotoOriginalPreparationOwner` coordinates a main-actor SwiftData
repository and a file actor through the existing injection seams. Main-actor
code must not do hashing/copying. There is no shared singleton, TaskLocal
capability, job-metadata authority or second filesystem database.

Use `Documents/PhotoPreparation/<ownerUUID>/<packageUUID>/` with opaque file
names; reject symlinks, nonregular files, traversal and a replaced directory.
All native operations acquire stable Documents shared lock, then the P1
namespace exclusive lock, then perform their bounded repository transaction.
File locks are nonblocking; busy means retained work, not a retry loop. Keep the
namespace lock through the corresponding file/persist critical section. Do not
acquire these locks from inside an already-held database transaction. Existing
reanalysis file-store descriptor/inode fencing is a design reference, not a
license to reuse its media contracts or full-buffer reads unchanged.

Before acquisition, persist its intent/slot/reservation; before draft clear,
finalize/flush the complete file and commit its asset/reference. A crash between
filesystem and database commits is reconciled using the durable intent and exact
token/hash, never by assuming that a thrown save failed to commit. An ambiguous
save retains bytes/reservation and blocks a second operation until same-ID
readback. Freeze transfers draft ownership to the held package in one save; a
stale UI callback cannot clear a newer generation.

A cleanup transaction retires only the requested owner. Under the same lock,
zero live edges and zero unresolved leases permit terminal retirement. Recheck
revision after awaits. New references cannot acquire a retired asset. The file
actor confirms unlink and directory synchronization before the repository
releases physical-byte liability. Failed deletion remains charged and
recoverable. Process death releases OS locks; startup may resolve an old process
lease only after exclusive-lock acquisition and exact intent/file
reconciliation. Age or lease expiry alone never proves writer closure. Keep
unknown files quarantined inside the owned namespace and charged conservatively
until reconciled.

No TTL deletes draft originals, held packages or uncertain work. P1 cannot evict
its only local copy. Future server/history references must be acquired before
local ownership can be released; P1 does not claim that integrated gate closed.

## Exact schema and recovery agreement

Verified current alias is `CurrentSchema = MerianSchemaV58` in
`Models/Aliases.swift:4`. `SchemaV58.swift` currently names ten global active
models plus the already-frozen
`MerianActiveSchemaV50.OfflineQueuedScanGoalHint`. The next native version is
**59**, subject to exact pre-edit source recheck.

1. Freeze the full outgoing V58 graph into `SchemaV58ScanSnapshots.swift` and
   `SchemaV58QueueSnapshots.swift`, preserving fields/defaults/attributes and
   fully qualifying relationship types. The scan/analysis/state/collection graph
   and queued/captured-media graph must stay internally V58. Retain the existing
   frozen V50 goal-hint type. V57 snapshots are a structural example, not the
   source for V58's changed queue fields.
2. Review and compile this outgoing snapshot before adding active entities or
   changing the current alias. No historical checksum edit, model reset or
   destructive fallback is permitted.
3. Add the four standalone entities and `SchemaV59.swift` using global active
   models plus those new types. Advance the alias. Append exactly one additive
   lightweight `migrateV58toV59` stage and V59 to every
   full/recent/released-active plan in `SchemaVersions.swift`; add
   `MerianRecentV58MigrationPlan`. The lightweight choice depends on the
   additive/no-backfill/no-legacy-model-change contract and must pass a real
   disk-store migration.
4. Add `.v58` to `RecentSourceSchema` in `StoreMigrationModels.swift`. Extend
   `ModelContainerFactory`'s exhaustive recent-source switch and prepend V58 to
   its recent-checksum retry sequence. Do not alter current-store-first
   behavior, corruption classification or quarantine/rescue matching.
5. `ModelContainerBootstrapper` already derives the current major; safe mode
   already uses CurrentSchema without a plan. No new production bootstrap hook
   is needed beyond the factory/enum changes. Tests must prove this remains
   true.

All old schemas and their evidence remain immutable after the V58 freeze. A V58
fixture with existing queued/admitted/history data must migrate with those
values unchanged and an empty P1 ledger. Fresh-container, immediate-recent-plan
and full/recent/released-active plan completeness are mandatory acceptance, not
inferred from an in-memory container.

## Capture handoff: exact bytes without an unbounded extra copy

The current `ImageFileWrapper` copies the provider file to tmp with `copyItem`
before any byte check. Do not use it for P1 and then pretend a later check
bounds that allocation. Do not change the ordinary import path or replace the
picker UI.

Add **`PhotoOriginalPickerTransfer`**, an import-only FileRepresentation
selected only by the inactive P1 branch. The existing SDK interface permits an
async `ReceivedTransferredFile` callback. In that callback, inspect a regular
source file, check declared size if available, read in bounded chunks with a
hard 32 MiB plus one-byte overflow probe, and return exact Data with type
metadata. Do not make an application-owned tmp copy, use Data(contentsOf:) or
decode before the cap/type/pixel checks. Hold the callback's source access for
the read; never return a borrowed provider URL for later use. The outer caller
already holds its durable P1 acquisition reservation before calling
loadTransferable, and awaits callback completion before releasing that
reservation. No static mutable capability registry is needed.

The Data bridge is an explicit tradeoff: at most one original is acquired at a
time, and encoded bytes are released after the protected durable write.
Appending Data can have transient memory overhead; the 32 MiB byte bound is not
a claim of 32 MiB process RAM. Native memory/codec/device qualification remains
open. This avoids both an unbounded app tmp copy and a picker/UI rewrite. The
existing approved October 13 accounting boundary covers application-owned
media/copies; provider-internal materialization is separately observed, not an
exact app-disk guarantee. See the
[approved accounting decision](client-prepared-media-local-feasibility-2026-10-13.md).
A provider file already owned by the app counts physically; no exclusion based
only on being temporary.

Camera acquisition reserves before `captureImage()`, checks its returned encoded
Data against the same cap, and persists it before `prepareStill`. No
AVFoundation settings change or claim that its internal buffers are bounded by
the file cap. Picker source is exactly the delivered representation, not an
unedited master. External inbox import uses its existing file as a caller-owned
source; charge it while it belongs to P1 acquisition and do not consume the
inbox item until new ownership commits. Oversized/missing input is rejected
explicitly without consuming the inbox entry or fabricating a derivative
original.

Use the existing prepared image/camera algorithms after original ownership and
header eligibility. Keep supported formats, inference/display recipes and crop
geometry unchanged. `StagedImage` receives an optional immutable
`PhotoOriginalReference`; every replacing/crop method carries it unchanged. The
value handle is a new non-`@Model`, `Codable`, `Hashable`, `Sendable`
`PhotoOriginalReference` in `PhotoPreparationValues.swift`:
`contractVersion:
String` fixed to `P1-L1`, `ownerID`, `packageID`,
`referenceID`, `assetID`, `assetGeneration`, `draftGeneration` (UUID), and
`referenceRevision` (Int64). Its versioned keyed encoding contains only those
scalar values, with strict required-field/version/range validation. No model
instance, file token, URL, media bytes or implicit SwiftData relationship
travels in the handle. It is a lookup assertion, not authority. Only the
repository resolves it under the lock against the live original-role edge,
matching owner/package/asset IDs, asset generation, reference revision and the
current draft generation. A stale, retired or inconsistent handle blocks the
edit/freeze and preserves the draft.

A separate local `PhotoPreparationSnapshot` additionally freezes an ordered
array of these value handles and `expectedPackageRevision: Int64`; revalidate
both after asynchronous preparation before the compare-and-save freeze. Updating
derivatives/context increments the package revision without mutating the
original edge or the original handle. Discard/replacement retires that edge and
invalidates its old handle. Neither capture nor a decoded local snapshot can
mint an authoritative reference. `CaptureSubmissionPayload.swift` may build that
companion local snapshot for the P1 branch; do not add P1 fields to the existing
admission snapshot or its wire/queue projections. Neither existing struct is
currently Codable; do not make it Codable or alter downstream encoders. Only the
separate versioned P1 ledger/snapshot encoding carries these handles. Nil-access
legacy request and queued-operation byte identities/schema remain unchanged,
with an explicit regression assertion in the future capture tests. Local P1 IDs
must never leak into ordinary admission JSON, provider input or a hidden
protocol extension.

Acquisition occurs once. A later crop persists new derivative references, not a
new original. Only the separate local `PhotoPreparationSnapshot` includes these
reference identities so suspended P1 work cannot silently substitute a source.
Only physical still images count as originals, never sampled video frames or
cover images.

### Inactive composition and draft lifecycle

Add optional `photoOriginalPreparation` access to
`CaptureWorkspaceDependencies`; `.live` always supplies nil. An explicit
prepared/test factory binds one dedicated on-disk qualification container,
synthetic owner/account generation and the owner. Its file-store root is an
injected private sandbox using the same `PhotoPreparation` relative layout and
locking rules, never the installed app library. No preference, remote flag,
launch argument or production AppDI hookup enables it. The existing history
installation qualification flag remains false. No change to public wire DTOs or
backend code.

When access is nonnil, camera/import/submit take the P1 branch before legacy
funding/preview/ordinary enqueue. Require resolved current account and unblocked
library; unresolved identity preserves the draft and refuses preparation. P1
accepts only the scoped still-photo combinations with optional supporting text;
audio/video or a missing original block that branch explicitly, never fall
through to legacy admission. Normal nil-access behavior remains unchanged.

Submission freezes into `preparedHeld`, returns a typed local receipt, and
acknowledges only “saved locally,” never identification complete. Keep proposed
receipt type distinct from `onAdmission`'s accepted timeline. Existing
auto-submit may reach that local branch when explicitly composed for
qualification but cannot invoke funding/AI. No default UI entry is enabled.

Persist draft supporting context and derivative role updates through this owner
before acknowledging a P1 edit. A disk-full failure keeps the in-memory edit and
original owned bytes, exposes an unsaved state and blocks submit; it cannot be
reported durable. On reopen, show the last committed draft and any incomplete
intent as needing attention. During pure acquisition, do not claim a shutter
photo survived restart until its durable-write acknowledgement exists.

Image removal, required-crop cancellation, explicit discard and normal draft
clear call revisioned owner release; never put a P1 path into `draftOwnedFiles`
or `FileIOActor.deleteFiles`. Async release must complete or retain a durable
cleanup intent before UI reports successful discard. Background dismissal clears
presentation only for P1, preserving its durable draft. Account changes revoke
access/cancel acquisition and retain ownership until the existing authorized
library transition or purge resolves it. Same-account refresh preserves work.

The concrete Auth lifetime owner is `SupabaseManager`'s existing
`beginUnownedAccountBoundWork` / `isAccountBoundWorkLeaseCurrent` /
`finishAccountBoundWork` boundary (`SupabaseManager.swift:78-145`). Each P1
acquisition/commit holds its exact account lease and checks it after awaits.
Qualification injects equivalent closures backed by a dedicated
`AuthRuntimeState` and synthetic session, without using a live SDK session. A UI
account check is not a writer lease.

Add an optional P1 `invalidateAndAwaitForAccountTransition` closure to the
existing `awaitAccountBoundWorkQuiescenceForAuthTransition` sequence
(`SupabaseManager.swift:632-676`), after admission closes and before
`awaitAccountWorkDrain`. Its default is nil; production composition remains nil.
The owner cancels acquisition, waits for actual callback/file-writer
termination, persists reconciliation/cleanup intent, and then releases the
lease. If durable pausing cannot be established, return failure and keep
admission closed; cancellation request or elapsed time is not completion. Do not
inject P1 into queue cancellation or create a second Auth drain owner. The
prepared harness exercises these same lease/closure rules with local fakes; no
sign-in, sign-out, account deletion or SDK request runs during qualification.

Thread a separate optional P1 purge closure through
`ScanRepository.purgeAllData` (`ScanRepository.swift:580-603`) into
`ScanLibraryPurgeService.purge`, default nil. In P1 composition it is mandatory
whenever P1 rows or namespace liabilities exist; absence must fail closed, not
skip cleanup. No call-site activation is added to `MerianApp` or AppDI. On
startup/reopen, inventory plus the retained P1 barrier prevents identity reuse
until the correct owner is explicitly rebound and reconciliation succeeds. The
existing default purge must refuse nonempty P1 state if no owner was supplied,
so a later inactive-library read cannot erase its recovery authority.

`LibraryMutationInventory` must count live/incomplete P1 preparations and
unreleased liabilities as local changes, including corrupt/orphaned P1 rows (all
four entities, regardless of source account); they block identity replacement
even though no job is runnable. Do not infer readiness from a missing legacy
queue row. Full-library `ScanLibraryPurgeService` must suspend P1 admission,
drain/confirm active local writers, retire P1 owners, erase the private
namespace under exclusive root protection and then delete its ledger rows. A
failed purge retains the cleanup barrier and P1 records; never delete the only
cleanup authority before files are reconciled. Existing old-model purge ordering
need not be rewritten. P1 cleanup is no-op when its namespace and rows are
absent. No account transition may reopen admission until the same
purge/transition generation permits it.

## Limits and ownership stay fixed

32 MiB per original, two physical sources/64 MiB original total; 64 million
primary pixels; 5 MiB aggregate AI images; display 4 MiB each/8 MiB aggregate;
96 MiB complete package including bounded metadata; four pending packages and
384 MiB durable total. Temporary pool remains 192 MiB (96 acquisition/commit, 64
preparation, 32 transfer/export); 288 MiB maximum new allocation and 256 MiB
free reserve, hence 544 MiB for a completely new worst-case package. Existing
owned files count once, every physical duplicate separately; retries/restart
cannot reset accounting. A hash match alone grants no free deduplication.

Reserve and reconstruct these liabilities across P1 owner instances under the
namespace lock. Keep one active preparation; do not create network/export work.

**P1 qualification uses exclusive allocator composition.** The prepared factory
owns a dedicated test container and file root. It does not install AppDI,
ordinary queue/sync, reanalysis, transfer/export or another capture producer.
Only P1 allocators receive that root and its reservation authority. Test
acquisition and cleanup hold the composition lifetime until writers have
terminated; rejected second preparations cannot allocate. A deterministic
competing-allocation test attempts a second P1 owner/producer and proves the
shared reservation prevents overcommit. A test composition requesting any
unsupported competing allocator must fail before acquisition, not silently omit
its accounting. An actual disk-space check remains required.

This is the explicit qualification-only exclusion, not evidence of atomic
reservation with the installed product's other media allocators. P1 cannot be
installed or promoted until a later reviewed common allocation authority or
product-wide exclusion is implemented and tested. No existing non-P1 allocator
is claimed to honor the new namespace lock. The 192 MiB shared policy is
unchanged; mixed-owner product acceptance remains open. At cap or unknown free
space, preserve draft/selection/text and refuse. Optional explicit replacement
is new input, never silent compression or discarded media. No text-only
fallback; admitted historic operations retain their original meaning.

**History primary owns the additive code changes listed below.** The human's
approval here closes this preparation handoff; implementation still awaits its
own approval. `Simplify capture tools` remains a read-only planning owner and is
not assigned work. Its latest recorded plan requires later separate approval for
its visual refactor. This handoff grants no toolbar/Add details/Prompts/layout
change and does not depend on completing that later redesign. No approval from
`Scan ID History (2)` is required. Independent/IC-1 reviewers remain read-only.
All 115 pre-existing changes are preserved; implementation may touch only the
listed additive hunks in overlapping files after exact baseline review.

## Exact P1 file boundary

Paths below are relative to `apps/ios/` unless stated otherwise. Newly proposed
files do not exist yet. Source hashes and existence are in the evidence
inventory. No other implementation file may be added to this window without
reporting the specific need; historical source changes invalidate the affected
review.

- **New active entities**:
  `Merian/Models/ActiveSchema/PhotoPreparationRecord.swift`,
  `PhotoPreparationAsset.swift`, `PhotoPreparationReference.swift`,
  `PhotoPreparationLease.swift` (four new, scalar-only).
- **Schema**: `Merian/Models/Schema/SchemaV58.swift`; new
  `SchemaV58ScanSnapshots.swift`, `SchemaV58QueueSnapshots.swift`,
  `SchemaV59.swift`; `Merian/Models/Aliases.swift`,
  `Merian/Models/SchemaVersions.swift`.
- **Startup**:
  `Merian/Core/Data/StoreRecovery/Models/StoreMigrationModels.swift`;
  `Merian/Core/Data/StoreRecovery/Services/ModelContainerFactory.swift`.
  Bootstrapper/policies are verification-only.
- **New native owner**:
  `Merian/Core/Data/PhotoPreparation/PhotoOriginalPreparationOwner.swift`,
  `PhotoPreparationRepository.swift`, `PhotoPreparationFileStore.swift`,
  `PhotoPreparationValues.swift`, `PhotoPreparationPolicy.swift`, `README.md`.
- **Acquisition**: new
  `Merian/Features/Capture/Shared/Models/PhotoOriginalPickerTransfer.swift`;
  `Merian/Features/Capture/Scan/ViewModels/CaptureWorkspaceViewModel+PhotoCapture.swift`;
  `Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Imports.swift`.
  Existing transfer wrapper, media preparers, camera coordinator and
  PhotoLibraryManager unchanged.
- **Draft/role propagation**:
  `Merian/Features/Capture/Staging/Models/StagedImage.swift`;
  `Merian/Features/Capture/Submission/Models/CaptureSubmissionPayload.swift`;
  `Merian/Features/Capture/Shell/Services/CaptureWorkspaceDependencies.swift`;
  new
  `Merian/Features/Capture/Submission/Services/CapturePhotoOriginalPreparationAccess.swift`.
- **Held submit / release**:
  `Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift`;
  `Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Draft.swift`,
  `+Staging.swift`, `CaptureWorkspaceViewModel.swift`;
  `Merian/Features/Capture/Staging/Views/CropSheetModifier.swift`. Only P1
  reference, persistence, release and nil-access branches; no visual changes.
- **Library safety**:
  `Merian/Core/Data/OfflineSync/Persistence/LibraryMutationInventory.swift`;
  `Merian/Core/Data/Database/ScanLibraryPurgeService.swift`;
  `Merian/Core/Data/Database/ScanRepository.swift` (optional purge forwarding);
  `Merian/Core/Network/SupabaseManager.swift` (optional pre-drain P1 lifecycle
  hook only). AppDI/MerianApp remain untouched; no ordinary enqueue/dispatch or
  Auth protocol change.
- **Tests**: New
  `MerianTests/Core/Data/PhotoPreparation/PhotoOriginalPreparationTests.swift`,
  `PhotoPreparationPersistenceTests.swift`; existing
  `MerianTests/Models/MigrationPlanTests.swift`;
  `MerianTests/Core/Data/StoreRecovery/ModelContainerBootstrapperTests.swift`,
  `ModelStoreRecoveryCoordinatorTests.swift`;
  `MerianTests/Core/Data/ScanRepositoryPurgeTests.swift`;
  `MerianTests/Core/Data/OfflineSync/LibraryMutationInventoryTests.swift`;
  `MerianTests/Core/Network/Auth/AuthRuntimeStateTests.swift`;
  `MerianTests/Core/Network/SupabaseManagerTests.swift` (isolated lifecycle
  ordering, no live session);
  `MerianTests/Features/Capture/Shell/CaptureWorkspacePresentationAndImportTests.swift`;
  `MerianTests/Features/Capture/Submission/CaptureWorkspaceSubmissionTests.swift`;
  `MerianTests/Features/Capture/Staging/CaptureDraftSessionTests.swift`.
- **Documentation / generation**: Local Capture Submission/Staging/Shell README
  updates only for changed ownership;
  `docs/backend-and-data/04-database-schema.md`, current alpha/IC-1/acceptance
  summaries, this record. Run `make xcodegen`, review its generated project
  delta; preserve pre-existing project edits. Do not hand-edit project files. No
  project.yml change is planned.

## Proposed execution and acceptance packet

**Not authorized by this agreement run.** Request one four-hour local window;
clock includes preparation, reviews, compilation, checks and report. Stop adding
work at expiry; do not cancel or duplicate an already-running managed-cache
build. Retain failed evidence and report incomplete if gates cannot close.
History primary writes; exact independent/IC-1 review precedes execution of each
materially changed candidate and follows corrections.

1. Recheck file hashes/dirty hunk ownership, current V58, disk >=20 GiB and
   absence of conflicting compilation. Freeze V58; exact read-only review, then
   managed compilation of the unchanged outgoing shape. If freeze/compile fails,
   do not add entities or advance the alias.
2. Implement the agreed inactive ledger, acquisition, held commit, recovery and
   release path, V59 registration, inventory/purge integration and focused
   tests. Review exact source before test execution. Do not edit sources while
   compiling.
3. Run relevant source/migration/project gates and one managed simulator build,
   then focused acceptance using its products. Concrete available simulator is
   selected read-only at execution time, never generic destination for tests.
4. If focused checks pass, complete the affected native gate before any
   P1-complete claim. Reuse unchanged prior evidence where applicable; do not
   rerun a hosted transport campaign, quality experiment or optional allocator
   diagnostics.

Required new checks:

- `PhotoOriginalPreparationTests`: camera/picker byte identity, source preserved
  through crop, type/pixel/32 MiB and cap+1 checks, no app tmp copy, missing
  source, canceled provider callback, account/generation change, zero funding/AI
  calls.
- `PhotoPreparationPersistenceTests`: disk reopen at intent/file/asset/freeze/UI
  boundaries; same IDs after ambiguous save; full reservation reconstruction;
  two-owner release and acquisition in both orders; cleanup failure; concurrent
  owner instances and competing allocation/exclusion; symlink/directory
  replacement; stale-writer completion; failed purge never loses cleanup
  authority. Actual max cohort and peak physical copies stay within the
  unchanged limits; mocked free-space alone is insufficient.
- Existing capture tests: nil access unchanged; installed P1 test seam follows
  real acquisition/prepare/crop/held-submit paths, blocks unsupported cohorts
  and never ordinary enqueue. Persisted context remains immutable after freeze;
  refusal preserves original/text and draft. No layout acceptance is claimed.
- Complete `MigrationPlanTests`, outgoing V58 disk fixture and all startup plan
  assertions; `ModelContainerBootstrapperTests`,
  `ModelStoreRecoveryCoordinatorTests`; `LibraryMutationInventoryTests`,
  `ScanRepositoryPurgeTests` prove readiness and purge correctness.
  `AuthRuntimeStateTests` and isolated lifecycle-hook coverage in
  `SupabaseManagerTests` prove close-before-drain, cancellation completion,
  stale-lease rejection, failed-purge blocking, and nil-hook compatibility.
  Mocks must fail on any network/real account operation. No broadened quarantine
  or reset.

Commands must use the existing `make ios-local-build` wrapper/cache and current
XcodeGen manifest. Before compiled acceptance:
`make validate-ios-migration-guardrails`, `make xcodegen`,
`make validate-ios-project`, required source-membership checks,
privacy/transport/versioning gates. Focused selectors are
`merianTests/<suite-name>` above; final complete `merianTests` and required
native production-readiness phases remain the completion gate. No CI dispatch,
device install or hosted action is requested. A passing unit seam is not
installed camera/PhotoKit/file-protection qualification; those user-run gates
remain open.

Plan native build evidence under the established `.artifacts/local-ios`
procedure, separate from the almost-full verifier-experiment allowance. The
execution request includes at most **2 GiB new native test evidence**, leaving
at least 20 GiB free before new work; no deletion of prior
evidence/dependencies. This is an explicit proposed evidence allocation, not a
change to media/package/storage or runtime resource limits. If the first
retained result exceeds that allocation, preserve it, start no further run and
report the bound; never hide failure by removing evidence. Managed build cache
remains owned by the existing wrapper. This preparation itself retains <=64 KiB
new sanitized documents/evidence within the existing CPM allowance and cleanup
reserve.

## Review and remaining boundaries

NCO-1 closes design/ownership prerequisites only after exact independent and
IC-1 concurrence. No test, schema edit, generated project, media fixture,
account query or hosted action occurred in this preparation. Runtime feasibility
and acceptance remain unproven; any failure blocks the affected P1 claim.

P1's output is a durable inactive photo package, not a completed identification.
Later original admission/funding/result recovery, source-backed
photo/audio/video reanalysis, shared-version deletion and full native/integrated
qualification remain in approved dependency order. Later version actions/export
and redesign remain separate. Activation disabled, AWS unapproved, all existing
limits and external-operation restrictions retained.
