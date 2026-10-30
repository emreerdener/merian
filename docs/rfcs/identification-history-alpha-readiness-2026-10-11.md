## October 29 — cumulative functional qualification agreement

The current functional milestone includes a bounded audit of the **complete
candidate**, after the initial/reanalysis/history journeys work and before
individual-version deletion/export or the approved redesign. This audit does not
restart implementation or create a new architecture workstream. History remains
the sole implementation/documentation writer; the existing Engine owner reviews
lifecycle/accounting, with permitted read-only security, concurrency and
contract review. Later deletion/export and redesign have their own affected
integration reviews. Replacement remains separately gated.

The audit covers photo/audio/video initial and reanalysis journeys, history
selection/review/Undo, RUX-1–RUX-6, original/derived media ownership and
retention, funding, account transitions and existing consumers. Trace durable
saves, awaits and acknowledgements across owners; exercise both orders of
completion versus cancellation/deletion, selection versus reanalysis,
shared-media cleanup and credit settlement. Include populated-store upgrades,
offline/relaunch and lost responses, real app wiring, actual selected-test
coverage, and measured memory/disk/cancellation behavior. In-memory fixtures and
component totals do not establish these integrated properties.

Extend A1–A21 with requirement-to-code-to-evidence mappings for the exact
candidate and its dependencies. Distinguish **implemented**, **inactive**,
**unqualified** and **deferred**; implementation is not validation or
deployment. Keep one findings register with severity, evidence/reproduction,
owner, fix and regression coverage. Retain deadlock/deadline, architecture, lint
and skipped coverage gaps and failed attempts. Passing reruns alone do not
establish a fix. Unresolved data-loss, authorization, duplicate
execution/charging, migration or ordinary-flow defects block acceptance.
Independent reviewers verify fixes and the final report reconciles evidence,
documentation, exclusions and release readiness. Existing C1 deadlock
disposition requirements still apply.

Reuse unchanged evidence only within its recorded input/dependency
applicability. Run final affected-surface gates and required CI on the exact
candidate; after fixes rerun affected checks rather than automatically
restarting every suite. Record audit/testing time separately from remediation
and blocked time; unknown historical durations remain unknown. The
conversational week plus contingency is provisional planning, not a deadline,
waiver or delivery promise.

The user selected the **existing beta production backend for planning** eventual
real-app qualification; no additional hosted database is required. Local
disposable databases own destructive, fault, migration and contention tests. The
[qualification environment plan](../development-guides/24-identification-history-device-review.md#planned-real-app-qualification-environment)
supersedes the separate hosted nonproduction **database requirement for real-app
qualification**. Separate nonproduction edge/storage security evidence in the
deployment runbook remains required; this does not require another hosted
database or authorize those tests. It requires reconciling the qualification
build and executable guards before use, and a separate exact operation/target
approval before any external action. It grants no deployment, installation,
hosted mutation or activation. PR116 and release holds remain. Continue
authorized local work while external approval is pending.

This is a planning amendment, not completed audit or installed evidence. The
[scan integration entry point](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#current-initial-photo-integration-entry-point--october-28)
owns current code and qualification status. Earlier dated checkpoint statements
below remain historical; the cumulative audit and environment plan above govern
current acceptance.

## October 29 — native pre-transfer reservation candidate

The inactive native owner now persists one exact reserved, not-started role with
aggregate transfer-copy accounting and held restart recovery. Engine source
review, corrected cheap preflight and focused native qualification passed (28
methods / 67 cases reconciled across the retained runs). The
[current scan contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--inactive-single-role-transfer-reservation-candidate)
owns this transition and supersedes earlier statements that reservation is
wholly unimplemented. Source access, transfer lifetime, backend
capability/closure and full journeys remain unqualified. This adds no external
or release authority and does not change the approved milestone sequence.

## October 29 — native v2 transport candidate

The inactive native owner and authenticated adapter now support explicitly
reserved v2 create/status. That owner/transport checkpoint passed Engine review
and 17 methods / 49 cases. The inactive Capture composition now selects v2 and
passed focused native qualification: 9 methods / 22 cases. Engine cleared
production; the corrected test-macro failure remains retained. The ordinary
factory remains disabled. The
[scan transport contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--native-v2-transport-integration-candidate)
owns dispatch, durable reservation, exact recovery and remaining integration.

## October 29 — native enrichment implementation candidate

The inactive reservation and receipt-enrichment writer passed focused native
qualification: 13 methods / 38 cases. The
[canonical transition contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#native-allocation-enrichment-inactive-candidate)
owns legacy byte preservation, whole-graph accounting, exact recovery and
remaining transport integration. Earlier “enrichment is next” statements below
record the preceding checkpoint. Ordinary HTTP requests remain v1; transfer and
full journey acceptance remain open. Release holds are unchanged.

## October 29 — inactive allocation role projection

The
[API contract](../backend-and-data/05-api-contracts.md#october-29--versioned-photo-allocation-role-projection-inactive)
now defines negotiated v2 metadata on the same allocation/status endpoint and an
inactive native decoder. This preserves v1 callers and persisted receipts; there
is no new transfer or execution authority. Engine source review found no
blocker. The new decoder and existing allocation regressions passed 20 methods /
46 cases. The broader selected gate retains the known unrelated Auth
architecture size failure; full native acceptance is not claimed. The next
prerequisite is bounded, monotonic receipt enrichment with metadata/revision
reservation before request and save, followed by original/AI/display transfer
and verification. The
[scan entry point](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
retains current implementation, evidence and recovery boundaries. Full photo,
reanalysis, audio/video, RUX1–6 and later deletion/export/redesign remain open.
PR116 and deployment holds are unchanged.

## October 29 — inactive outstanding-write hold candidate

The
[database schema contract](../backend-and-data/04-database-schema.md#inactive-cpm-outstanding-write-accounting--october-29)
records the new permanent attempt and conservative capacity hold through
cancellation/private erasure/account deletion. Exact recovery never renews a
clock. This database-owner-only increment has no signer, API grant or closure
settlement. Engine source review, 100 focused assertions and five concurrency
schedules passed. The subsequent private canonical encoder optimization passed
all 176 catalogs / 7,130 assertions and the five write-hold concurrency
schedules on its exact replay, with 170 differential assertions and measured
finalization cost reduction. The canonical contract retains both earlier expiry
failures and the unchanged-deadline evidence. Earlier allocation-only
restrictions remain historical. Transfer, byte verification,
admission/execution/result/history, reanalysis, audio/video, RUX and final
acceptance remain open. PR116, deployment and later-sequence controls are
unchanged.

## October 29 — Capture allocation caller qualified locally

Local checkpoint `2685d18b2` connects the inactive Capture submission caller to
explicit allocation and typed exact saved recovery. Focused validation passed 10
methods / 34 cases with unchanged native/project inputs; Engine source review
found no blocker. The
[scan-ingestion contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
owns the current behavior, evidence and retained failed attempt. This supersedes
earlier planned/pending caller and recovery statements below. The preceding
Release qualifies its earlier allocation-writer scope, not this caller change.

Next is original/AI/display transfer and verification under the existing CPM
lifetime/accounting contract, then admission/execution/result/history. The
AI-only receiving readback does not implement that complete transfer. Ordinary
installation remains disabled. Initial photo/reanalysis/full-photo, audio/video,
RUX and final acceptance remain open; the unrelated Auth architecture failure,
PR116 freeze, deployment hold and approved later sequence are unchanged.

## October 29 — bounded allocation validation complete

The native allocation writer in local checkpoint `6276b2651` now has qualified
affected runtime evidence (192 methods / 439 cases), independent source review
and a managed Release build on unchanged inputs. The
[scan-ingestion contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
owns the detailed evidence and retained failed attempts. This supersedes the
pending writer/release validation status below. The unrelated Auth architecture
size gate remains failed; full integration acceptance is not claimed.

Next is the existing Capture submission caller and exact allocation recovery,
then transfer, admission/execution and result/history under the agreed native
lifetime contract. The caller and downstream journey remain inactive. Initial
photo/reanalysis/full-photo, audio/video, RUX and the later approved sequence
remain open; all release and external-operation holds persist.

## October 28 — native allocation consuming integration candidate

The existing receiving owner now implements a durable allocation claim, bounded
authenticated create/status transport and exact positive-receipt settlement. The
[scan-ingestion contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
is the canonical home for its finite transitions, accounting, recovery and
limitations. Engine source review found no production blocker; the first
affected-surface batch passed 71 methods / 177 cases. Remaining writer/release
gates, Release and full integration acceptance are open. This local coding
checkpoint supersedes the earlier checkpoint's planned allocation-writer status,
while preserving its accepted V67 evidence below.

The candidate has no Capture caller, media transfer or execution activation.
Initial photo result/history, preserved reanalysis/recovery, full photo,
audio/video and RUX acceptance remain open. The later deletion/export/redesign
sequence, separately gated replacement follow-up and all release holds remain.

## October 28 — dormant native allocation storage qualified locally

The V67 receiving-side allocation fields and conservative release/recovery holds
are implemented and locally qualified. Combined focused Debug evidence covers
189 methods / 223 cases; the original failed run and four-method repair rerun
remain retained. Engine review and the full iOS tooling gate passed. The
canonical schema contract records exact scope and limitations:
[V67 storage and validation](../backend-and-data/04-database-schema.md). The
[scan-ingestion entry point](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
traces the current journey and owners.

Next is the existing-owner durable allocation claim, authenticated create/status
adapter and exact status-only recovery. No allocation writer or app caller is
installed. Initial photo result/history, reanalysis with preserved versions,
full photo qualification, audio/video and RUX acceptance remain open, followed
by the approved deletion/export/redesign sequence. Activation, deployment and
PR116 holds are unchanged.

## October 28 — inactive CPM allocation and recovery checkpoint

The
[photo content contract](client-prepared-photo-content-contract-2026-10-27.md)
now has an inactive SQL owner implementation for fixed assignment recovery,
distinct original/AI/display registrations, pending capacity, cancellation and
retirement. Independent source review and 61 focused SQL assertions plus
three-session capacity contention passed. No installed profile, byte IO,
verification, funding, execution or application caller is enabled.

The complete 175-file catalog gate passed with 6921 reported assertions on the
exact 494-migration local replay. Catalog validation caught and led to reviewed
repairs for owner indexing, identity-merge classification, C1/handoff child
integration, exact seal inventory and isolated test fixture lifetime/allowance;
earlier failures remain retained. The legacy 1MiB boundary still has unresolved
timing sensitivity under its unchanged limit. Full initial photo
execution/result/explicit history enrollment and reanalysis/recovery,
audio/video, RUX and the approved later milestones remain open. Release controls
are unchanged.

## October 27 — CPM consuming-contract design checkpoint

The
[photo content contract](client-prepared-photo-content-contract-2026-10-27.md)
now records Engine-reviewed composition and existing-owner lifecycle bindings,
plus the 32 MiB transfer subpool and distinction between local task drainage and
remote write closure. This is source/design agreement, not runtime or installed
qualification. The next implementation joins inactive intent allocation with
exact recovery, preserving original identity, deadlines and retirement fences;
it issues no upload, funding or execution authority. Full photo result/explicit
history and reanalysis journeys, audio/video, RUX and later milestones remain
open. No release or activation controls change.

## October 27 — Swift photo declaration mapping checkpoint

The inactive `SharedMediaNativePhotoContent` maps exact saved native V2 values
to the reviewed
[content contract](client-prepared-photo-content-contract-2026-10-27.md). It
neither reads media nor authorizes admission or dispatch. Source review and
focused native compilation/parity validation passed: seven methods / twenty
cases, with no source drift across 3,033 native/project pins and no structured
runtime warnings. This is shared-checkout Debug validation, not a new Release or
full app-journey qualification. A review caught two overflow test vectors
targeting the wrong role; they were corrected before native compilation.
Existing backend gates remain scoped to the unchanged codec. Initial submission
through execution/result and explicit history enrollment, preserved
reanalysis/recovery, audio/video, RUX-1–RUX-6 and final acceptance remain open.
No activation, replacement follow-up or release control changes follow from this
coding checkpoint.

## October 27 — photo CPM declaration implementation checkpoint

The [content contract](client-prepared-photo-content-contract-2026-10-27.md)
closes the proposed pure declaration slice needed before native initial-photo
integration. The inactive codec preserves exact text, saved recipe bits and
ordered logical original/AI/display references. Source review and local checks
are complete for the pure codec: 10 focused tests, 3416 Edge tests/598 steps
(532 ignored), static checks and composed tooling coverage. Earlier tooling
failures remain retained; the content contract records their corrections and
validation limits. Actual admission, byte verification, upload lifetime,
result/history, photo/text composition and absent inference-option semantics
remain open. No runtime authority or activation is added; media/RUX and all
final acceptance requirements remain.

## October 27 — frozen received-photo handoff implementation

The next initial-photo integration step adds read-only input recovery from the
exact received submission under the existing native owner. The
[storage contract](../../apps/ios/Merian/Core/Data/SharedMediaStorage/README.md)
defines bounded AI-byte reads and final cohort/physical seals. This cannot
schedule inference, change funding or mutate the held queue. Execution through
result/history and complete media/RUX acceptance remain open. Local focused
Debug evidence covers 43 distinct methods / 104 cases across verified passing
subsets, with 3,031 native/project inputs checked and only the corrected test
file differing across runs. Failed and incomplete attempts remain retained; this
is shared-checkout coding-checkpoint evidence, not full-target, isolated-source,
new Release or end-to-end qualification. Ordinary activation and all
external-operation holds are unchanged.

## October 27 — inactive Capture recovery host checkpoint

Capture's existing workspace and sheet router now expose a dependency-gated
Pending submissions view. Exact local identity selection lazily resolves the
existing native owner. Account, Auth generation, container, library and
presentation invalidation close or refuse the view. Closing changes presentation
only. The
[Capture contract](../../apps/ios/Merian/Features/Capture/Submission/README.md)
defines its status-only limits. The ordinary factory remains nil.

Focused Debug checks passed 27 methods / 41 cases with zero structured runtime
warnings and no drift across 3,031 source/project pins. The first compile
failure is retained. Generic Simulator Release passed after Journal's separate
rollback with zero errors, 366 warnings and no drift across 3,028 source/project
pins. The Debug result qualifies the preserved pre-rollback candidate only. Safe
generated-cache cleanup met the unchanged 25 GiB launch, 20 GiB final and 256
MiB evidence controls. Full-target and isolated-source compilation, installed
UI, actual process relaunch, accessibility, RUX-1–RUX-6 and complete
photo/audio/video initial/reanalysis journeys remain open. PR116 and all
release, activation and external-operation holds remain unchanged.

## October 27 — local received-identity recovery checkpoint

Received-candidate discovery now reuses the inactive native owner, complete
scoped audit and fresh CleanGraph facts. Explicit exact selection yields a
noneditable holding identity; absence never authorizes resubmission. The
[storage contract](../../apps/ios/Merian/Core/Data/SharedMediaStorage/README.md)
and
[Capture contract](../../apps/ios/Merian/Features/Capture/Submission/README.md)
record the boundaries and retained validation.

Local Debug coverage is 56 unique methods / 101 cases, using a reviewed
corrected retry plus unchanged passing results. Generic Simulator Release passed
with zero errors, 365 warnings and no source drift. Both earlier failed attempts
remain retained. No production Capture recovery caller is wired yet. Actual
restart UI, RUX-1–RUX-6, complete photo/audio/video initial/reanalysis,
full-target and isolated-source acceptance remain open. Ordinary factory nil,
PR116 freeze and all external-operation/deployment holds are unchanged.

## October 25 — inactive receiving terminal qualified locally

The inactive implementation adds a dedicated all-removed receiving closure
owner: two row updates and deletion of the exact held package, membership and
untouched consumer/queue/job/event quartet. It retains a canonical Released
result and seals all changed/deleted fields and persistent identities. Frozen
descriptors are checked before save; historical shared-original absence does not
fabricate a retirement identity. Uncertain attempts remain owner-held and
read-only until exact resolution or joined shutdown. Historical recovery reads
database evidence.

A separate paged terminal reader preserves raw orphan/foreign rejection, exact
row/owner/bootstrap joins, role-aware historical identity checks and checked
terminal consumption runway. Terminal payload bytes use the existing durable
physical-metadata route with zero reservation and no pending-package entry. The
final transaction compares a dedicated full successor accounting projection
against clean post-save accounting; surviving original ownership is unchanged.
Normal fresh receiving/staging and release identities consult terminal history.

October 25 local correction: each streamed historical row compares with at most
128 selected immutable values between full authority checks. Cancellation
remains checked for every comparison. The closing check must succeed before a
self-match contributes to the seen set. All deep row/live-root validation,
expected-header checks and page/suspension fences remain unchanged. No I/O,
mutation, suspension or authority issuance occurs inside the comparison batch.
The failed diagnostic measured 210.1 of 214.7 seconds in authority callbacks in
the first comparison phase. The corrected phase took 43.8 seconds, and the
pagination case passed in 546.4 seconds within its unchanged 600-second limit.

Local qualification on October 25 uses candidate06/build06: pagination03 and
focused02 passed all 11 focused methods / 21 cases. Regression02's test command
passed 146 methods / 292 cases across the 19 affected suites, with no failures,
skips or structured runtime warnings. Its wrapper exited 1 because the expected
inventory omitted six pre-existing extension methods (nine cases) in the
selected receiving-staging suite. A separately reviewed offline reconciliation
verifies the unchanged compiled extension and exact result set; it preserves
that failed wrapper record and reuses the retained XCResult without another test
run. All 3,001 source/project pins and 708 compiled products matched. These
results qualify the inactive receiving-terminal change locally; they do not
qualify performance or the complete app journey. Activation remains disabled,
PR116 frozen, deployment hold active, AWS unapproved and limits unchanged.
Full-target, isolated-source, integrated app and abrupt-exit acceptance remain
open.

## October 24 — inactive ordered-target continuation qualified locally

The inactive owner now has a separate explicit continuation entry for the next
ready photo after a nonempty removed prefix. It audits complete saved progress,
raw slot identity, owner binding, current header, survivor funding and remaining
revision capacity. Frozen descriptors must prove absent final/partial leaves for
removed originals and outputs, and present shared originals with retained
owners. Physical and authoritative checks repeat without an intervening await
before a one-use owner-local right is issued. Target zero still requires its
initial start acknowledgement.

An exact successful unused duplicate keeps the same right. Any failed admission
or retirement call burns an existing right conservatively; repairing the failure
does not restore it in that owner. Failure before any right was issued does not
create a spent grant. The right is consumed before successor mutation. Unused
rights and uncertain attempts fence unrelated native dispatch. Exact saved
before/after recovery settles the frozen continuation attempt without reminting
it; only a fresh registered owner after joined shutdown may explicitly admit the
unchanged ready predecessor again. Shared reference ownership, immutable frozen
media/text, historical operations and provider/accounting semantics are
unchanged.

Selected-target retirement, physical pair removal, original disposition and
physical original removal preserve earlier closure evidence and later ready
targets. Full-state funding replaces the selected obligation; it does not
reserve another package or subtract surviving shared liability. All targets
removed remains a releasing slot; terminal slot closure is a separate
integration.

Scoped local qualification passed on candidate04: focused 7 methods / 16 cases
and affected regression 102 methods / 190 cases across 14 suites. Both managed
runs finished with actual runner/command exits 0, exact structured coverage,
zero skips or structured runtime warnings, and unchanged source/product pins.
Evidence is retained under `.artifacts/native-app-capture-handoff-20261020/` in
next-target-focused01 and next-target-regression01 records. The failed initial
compile and all subsequent build evidence remain retained.

This qualifies the inactive ordered-target continuation only. Full-target,
isolated-source, integrated app journeys and abrupt-exit acceptance remain open;
terminal receiving-slot closure is not implemented by this checkpoint. The prior
physical-original checkpoint is `7892b597d`. No schema, wire, storage-limit, UI,
provider or activation change. Activation disabled; PR116 frozen; deployment
hold active; AWS unapproved; limits unchanged.

## October 24 — inactive held physical original cleanup qualified locally

The next inactive owner step handles only the first saved `originalRetiring`
target. It consumes the persisted retirement identity through the existing
original-file descriptor operations, with a held-specific revocable permit
spanning inspection, unlink, directory synchronization and final absence.
Shutdown revokes and joins the synchronous operation before root release. Once
absence has been observed, reappearance blocks that attempt even if the saved
identity appears to match. Every exact inspection records absence before any
authority or presence-transition rejection, including observations returned
after revocation and synchronous reinspection. Recording evidence cannot renew a
deletion permit. Immediate synchronous absence and raw-row checks run after
fault hooks and fresh predecessor validation before the metadata save.

The held seal removes six owned rows, requires the photo-preparation lease
already absent, terminalizes the acquisition receipt while preserving its
identity/fingerprint, and updates exact release/package/member/inventory facts.
Original bytes and identity liability remain charged until the save succeeds.
Same-owner uncertainty is read-only; joined shutdown can hand back the same
durable retirement to a new registered owner. Exact saved successors win before
filesystem work. Shared removals, later targets and terminal completion grant no
physical deletion through this step. Ordinary lifecycle guards remain.

Candidate05 compiled in managed build05. Focused02 passed all 12 methods / 23
cases. Affected regression01 passed all 90 methods / 167 cases in 13 full
suites. Both actual runners and commands exited 0, with zero skips and zero
structured runtime warnings. All 2,987 source/project and 708 compiled-product
pins stayed unchanged. Compiler lint/style warnings and simulator service
messages remain in the retained evidence; failed prior builds are preserved.

This is scoped local qualification. Full-target, isolated-source, integrated app
and abrupt-exit acceptance remain open. Later-target continuation and terminal
receiving-slot closure still require integration; completing this first target
does not close a whole package. Evidence:
`.artifacts/native-app-capture-handoff-20261020/original-removal-*`. No schema,
storage-limit, provider, scan-token, UI or activation change. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved; limits
unchanged.

## October 24 — inactive held original disposition qualified locally

The next inactive native owner step handles only the first selected original at
`pairGoneOriginalLive`. Shared disposition deletes its reference and edge,
decrements the authoritative count once, and preserves the physical origin and
surviving owners. Final-reference disposition records the existing canonical
retirement identity from the persisted acquisition descriptor, retires the
reference/accounting rows, and retains original bytes and charges. Neither
branch receives filesystem or provider authority. Later targets and terminal
completion remain outside this step.

A versioned shared attestation binds the clean predecessor, raw persistent row
identities, full reference-set digest and exact successor projection without
hashing its own derived result. A frozen owner-local attempt seals the changed,
deleted and preserved rows around one metadata save. Uncertain in-process saves
permit only exact readback. After joined prior-owner shutdown, a fresh
registered owner can admit a new deterministic metadata attempt from the
complete durable predecessor; saved successors take priority. Missing or mixed
evidence stays closed. Existing survivor projection and asset-owned identity
liability remain separate; locally originated shared assets retain their
physical charge, while foreign retained-only references use the existing
complete retained audit.

Candidate05 compiled in managed build05. Reviewed focused composition covers 8
methods / 20 invocations: six unchanged owner methods / 14 cases from focused01
and both corrected sharing methods / 6 cases from focused02. The focused01
aggregate remains failed evidence; its sharing results are excluded. Affected
regression02 passed 82 methods / 147 invocations in 11 full suites, with zero
skips and zero structured runtime warnings. All 2,981 source/project pins and
708 compiled-product pins remained unchanged. Simulator service messages remain
in the retained console log.

This is scoped local qualification. Full-target, isolated-source, integrated app
and abrupt-exit acceptance remain open. Physical original cleanup, later targets
and terminal completion still require integration. No schema, storage limit,
scan funding, UI routing or activation change is included. Evidence:
`.artifacts/native-app-capture-handoff-20261020/original-disposition-*`.
Activation disabled; PR116 frozen; deployment hold active; AWS unapproved;
limits unchanged.

## October 24 — inactive held pair removal qualified locally

The first saved `retiringPair` can now advance to `pairGoneOriginalLive` through
the registered native owner. Cleanup uses the saved pair identity, existing
locks and a synchronous revocable descriptor permit. Account shutdown revokes
before cancellation and joins active work before reconciliation or root release.
Exact saved successor recovery does not repeat unlink. A complete durable
retiring predecessor retains its charges and can resume the same deterministic
cleanup; a replacement path or uncertain identity keeps settlement closed.

The sealed metadata save removes only the selected pair's derivative rows and
charges. Originals, other targets, held execution and submitted media/text
remain owned. Fresh logical IDs are checked against retained release witnesses
and indexed rows. Ordinary physical-original sharing retains its existing
checks; ordinary routing still rejects held-release graphs. This step grants no
AI invocation, scan-token change, refund or replacement operation.

Candidate04 compiled in managed build05. Reviewed partitioned focused evidence
covers 12 methods / 19 invocations: 8 unchanged methods / 12 invocations from
focused01, 3 / 6 from focused03, and the corrected shutdown method / 1
invocation from focused05. The earlier aggregate failures and warning-bearing
focused04 remain failed qualification evidence; they are not relabeled as
passing runs. Regression03 passed all 61 methods / 119 invocations in six
affected suites. Selected passing evidence has zero skips and zero structured
runtime warnings. The latest focused and regression runs retained all 2,973
source/project pins and 708 compiled-product pins unchanged.

This is scoped local qualification. Full-target, isolated-source, integrated app
and abrupt-exit acceptance remain open. Original disposition/release, later
targets and terminal completion still require integration before the native
release journey is complete. Evidence:
`.artifacts/native-app-capture-handoff-20261020/pair-gone-*`. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved; limits
unchanged. No external operation is authorized.

## October 23 — inactive held pair-retirement writer qualified locally

The first held ready pair can now be recorded as retiring in one metadata save,
with its immutable physical closure and receiving Progress. This inactive path
reuses the registered native owner, coordinator locks, repository file access
and shared no-save pair-row mechanics. It does not unlink files, reduce storage
charges, change submitted media/text or invoke a provider.

Only uninterrupted normal start acknowledgement with exact readback atomically
grants the owner-local first-target right. Recovery, cold discovery and account
drain cannot grant it. The target, retirement identity, closure and physical
inspections are frozen before the save attempt. Pre-save rejection revalidates
only that same attempt; save uncertainty permits exact outcome recovery. The
joint write seal checks every raw field, persistent row identity and exact
inserted/changed set. Complete clean predecessor, existing funding/runway and
current physical inspection checks precede the save. Ordinary retirement IDs are
included in indexed collision checks.

Candidate04 compiled in managed build05. Focused01 passed all 10 methods / 17
invocations with no skips, including owned/shared originals, absent outputs,
save/readback faults, recovery denial, replacement paths, cancellation, account
drain, exact raw seals and immutable retries. Regression02 passed all 28 methods
/ 49 invocations across release start, release stage and ordinary pair
retirement. Both runs used the same 2,965 source/project pins and 708 compiled
product pins; no source or product changed during execution. Earlier
build02/build04 failures, build03 NOT RUN and regression01 HOLD remain retained
evidence.

This is scoped local qualification. Full-target, isolated, integrated app and
abrupt-exit acceptance remain open; complete release and native journeys are not
qualified by this checkpoint. The next reviewed pair-gone transition, original
release, later targets and terminal completion remain separate work. Evidence:
`.artifacts/native-app-capture-handoff-20261020/retire-writer-*`. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved; limits
unchanged. No external operations are authorized.

## October 23 — inactive release-start transaction qualified locally

The local start implementation reuses the existing stage workflow, coordinator
locks, account/work authority and repository fences. Only uninterrupted exact
stage acknowledgement atomically grants its owner a single start right. Save
fault recovery, discovery, cold reopen and account drain never grant that right.
Start audits the current staged graph, complete role-aware identities, existing
funding and aggregate revision runway; logical IDs remain unique while exact
physical originals may be shared. It freezes the initial Progress, consumes the
right before synchronous save, and changes only the receiving row and inventory
revision. Its poststate seal preserves every other raw field and persistent row.

Pending start remains in the existing dispatch and teardown guards. Recovery
requires the exact frozen initial Progress and complete live graph; a staged,
absent, partial or mismatched result cannot authorize another write or cleanup.
Account drain revokes unused rights and uses only its captured repository-fenced
read closure. Held execution rows, immutable supporting text/media, other
versions and funding are unchanged. No provider or cleanup path is added.

`SharedMediaNativeReleaseStartOwnerTests` now has scoped passing evidence for
all 9 methods / 14 invocations, assembled from reviewed partitions. Candidate05
focused02 passed 8 methods / 13 invocations; the corrected current-header method
passed separately on candidate06, XCResult
`2a2e86cf044c45f883b5732741bb0dd8.xcresult`. Only that test method changed
between candidates; production code and shared fixtures did not. Each reused
method has exact passing argument coverage and no skips. Both earlier aggregate
failures remain retained failures, not passing runs.

Coverage includes actual P2 receive, stage and start, shared originals, cold
recovery, stage/start faults, exact uncertainty, identity collisions, frozen
drift, revision exhaustion, write seals and cancellation. The counter correction
permits only validated selected originals and AI/display assets; tests prove
clean acceptance, non-asset counter rejection and restored acceptance.

The current-header test explicitly records that ordinary acquisition rejects a
staged release sidecar through the existing generic metadata fence. Its later
revision advance is test-only metadata mutation, followed by the real owner
start; it qualifies the typed release reader/start handling of an advanced
header, not concurrent ordinary acquisition. Acquisition coexistence and full
app routing remain unqualified and must be assessed at integrated acceptance.

Unchanged stage (10 methods / 12 invocations) and owner-boundary (7/7) passes
are reused only from exact focused01 suite evidence with independent/IC-1
concurrence. Source/project and product pins stayed unchanged during each run.
Evidence is under
`.artifacts/native-app-capture-handoff-20261020/start-writer-*`. Full
affected-target, isolated, integrated and abrupt-exit gates remain open. The
next held pair-retirement transaction is separate; this checkpoint does not
qualify a complete release or app journey. Activation disabled; PR116 frozen;
deployment hold active; AWS unapproved; limits unchanged.

## October 23 — dedicated native release-stage writer qualified locally

The inactive stage writer changes only the receiving sidecar pair and one
inventory revision, under existing account/work authority, canonical coordinator
locks and repository physical fences. It audits retained identities, prospective
two-save funding and aggregate revision capacity, seals the exact dirty write
set, and compares a fresh clean predecessor immediately before synchronous save.

Fresh admission is now separate from descriptive recovery. Only this owner's
actual new P2 receive save plus exact fresh readback records an entitlement to
the full received row and profile. An opaque single-use capability binds the
request and owner lifetime; its right is consumed before attempting stage save.
Receipt replay, reconstruction and cold discovery cannot mint or replenish it.
Proven pre-save rejection can retry the same unused capability. Raw requests can
only reconcile an exact saved sidecar or retained Progress association. Cold
fresh-P2 staging remains deferred until finite persistent writer closure is
qualified; missing evidence never grants fresh admission. Typed cold discovery
returns staged/Progress evidence under its retained canonical IDs, without
reconstructing a consumed historical stage header.

The owner retains an uncertain request and a repository-fenced read-only
recovery closure. Account drain invalidates unused admission, waits for active
work to terminate, reacquires the original coordinator locks, and clears
uncertainty only for matching saved evidence. The closure captures no dispatch
grant or owner and has no mutation path. Absent, partial or mismatched evidence
keeps drain closed. Original media, submitted descriptions, AI/funding and other
versions are unchanged.

The managed build and focused run passed 28 methods / 50 invocations across
stage ownership (10/12), capability boundaries (7/7) and affected existing
receiving (11/31), with zero failures or skips. Stage checks cover exact save
and replay, cold absence and receipt replay, save-boundary faults, missing or
mismatched evidence, exact write sets, retained identity collisions, cold
Progress discovery, cancellation and sealed-account reconciliation. XCResult
`61a7a2596e1f4d50b247335701ec3b09.xcresult` and candidate03/evidence are
retained under `.artifacts/native-app-capture-handoff-20261020/stage-writer-*`
and `.artifacts/local-ios`. All 2,950 source/project and 708 product pins stayed
unchanged. The earlier compiler failure remains retained; its two mechanical
corrections passed the later build. Independent/IC-1 concurrence preceded both
compile and focused execution.

Synthetic Progress is saved-state evidence, not qualification of the separate
start writer. Abrupt process-exit, complete affected-target, isolated-source and
integrated acceptance remain open. Private owner/repository boundaries and the
610/622-line ceilings remain intact. The next reviewed increment is the separate
start transaction with an atomic owner-local single-use entitlement, exact
start-outcome recovery and pending-start dispatch/drain guards. It does not
authorize cleanup, provider work or cold fresh admission. Activation disabled;
PR116 frozen; deployment hold active; AWS unapproved; limits unchanged.

## October 23 — prospective stage/start funding qualified locally

The inactive received-release reader now measures the full two-save sequence:
its future Plan uses H+1 after staging and its pair snapshots and revision
runway use H+2 after start. It binds the full caller-fixed request to the exact
clean received predecessor and keeps historical received funding unchanged. Both
sidecar data plus digest and the future release maximum must fit that funding.
Existing ordinary and saved-stage readers preserve their one-start semantics.

The managed compile and focused suite passed six methods / eighteen invocations.
Tests compare exact prediction with saved fixture state at 98/99/998/999 and for
owned/shared originals, reject stale/dirty/absent/exhausted predecessors without
writes, and retain the ordinary reader, corruption and funding-bound checks.
XCResult `952541352a9a40b78308d4a3ff329f3f.xcresult` is retained under
`.artifacts/local-ios`; candidate/evidence are in
`.artifacts/native-app-capture-handoff-20261020/stage-prospective-sizing-*`. All
2,942 source/project and 708 product pins remained unchanged. Independent and
IC-1 concurrence preceded compilation and focused execution.

This is read-only sizing qualification, not stage-writer, transaction-save or
complete feature acceptance. No synthetic staged row or dirty CleanGraph audit
was introduced. Next is the already-reviewed dedicated two-row stage writer,
including retained-identity collision checks, owner-held save uncertainty and
deterministic save-boundary/full-reopen controls. Complete affected-target,
isolated-source and integrated acceptance remain open. Activation disabled;
PR116 frozen; deployment hold active; AWS unapproved; limits unchanged.

## October 23 — physical-root reopen and metadata boundary controls qualified

The reviewed inactive profile correction passed the fresh `stage-exit-nosave08`
control: the observer positively established child process closure, and a
separate full native owner reopened the same physically bound fixture and
acknowledged exact readback. The intentionally exiting child is an expected
failed test, not a passing test. Child XCResult
`1c60ebfcdb0d43cdabc30270889e0e52.xcresult` and passing reader XCResult
`9ed5d1f2be1d45cfbf1767debcd246e4.xcresult` remain retained. This qualifies the
exercised no-save process-exit/reopen control, not transaction-save atomicity,
power-loss durability or complete feature acceptance.

The deterministic metadata gate also passed one method/two arguments. Pure
production reservation arithmetic accepts exactly 1,048,576 and rejects
1,048,577 using explicitly non-persisted synthetic accounting input. Each
independent real-file fixture found an adjacent legal-text crossing within 16
projections: 1,048,533 was admitted and replayed without a save; 1,048,619 was
rejected with unchanged draft/inventory and no receiving slot. These owner
inputs are not described as exact-cap inputs. XCResult
`724544c83d4344fbbdfe7401e14466d6.xcresult` and numeric measurements are
retained. The prior 21 profile/bootstrap methods / 69 invocations remain
unchanged passing evidence; their original whole run still records its failed
old boundary cases.

All 2,942 source/project pins and 708 compiled product pins remained unchanged
through these runs. Independent and IC-1 concurrence preceded each execution;
project/Markdown validation and diff checks passed. Evidence is under
`.artifacts/native-app-capture-handoff-20261020`. This is focused
shared-checkout qualification; complete affected-target, isolated-source and
integrated acceptance remain open. Next are the already-planned deterministic
save-boundary controls and typed release-request stage transaction. No
absence-based fresh admission or repeat AI execution is enabled. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved; limits
unchanged.

## Historical October 23 status — deterministic metadata boundary qualification in progress

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

The latest receipt-boundary run passed actual exact-cap admission and replay,
but its other fresh fixture failed before save at 1,048,523 bytes. The overall
method failed. Exact filesystem timestamp widths vary and are nested in the
encoded graph, so fixed supporting text cannot reliably target a byte-exact
persisted boundary. All prior results remain retained historical evidence.

Independent and IC-1 review cleared a test-only decomposition: the production
reservation function must accept exactly 1 MiB and reject one byte more using an
explicitly synthetic, non-persisted arithmetic input. Separately, each real-file
fixture derives its own adjacent legal-text crossing in at most 16 full
projections. The real owner must accept/replay its measured below-cap input or
reject its measured above-cap input without changing saved state. Errors abort
measurement; no file proof, saved request or production limit is rewritten. The
two fixtures are independent and are not one shared physical adjacent pair.
Actual owner byte counts will be reported; these cases do not claim exact-cap
owner inputs. The new test is implemented but not yet compiled or passed.

The prior 69 compatibility/bootstrap invocations passed and remain retained.
Fresh no-save readback, release-sidecar accounting, full affected/isolated gates
and integrated acceptance remain open. Activation disabled; PR116 frozen;
deployment hold active; AWS unapproved; production limits unchanged.

## Historical October 23 status — physical-root profile compatibility qualified; boundary and process readback open

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

The inactive native owner now selects an explicit physical-root profile for new
version-3 bootstrap journals. Legacy version-2 journals and nested snapshots
retain their original path-bound encoding and recovery rules. This addresses the
demonstrated no-save07 failure after an identity-preserving simulator container
relocation; it does not migrate an existing committed profile or relax the
store, account, directory or no-follow fences.

The focused profile/bootstrap run passed 21 methods / 69 invocations. Its two
old exact-cap arguments failed because the new explicit profile adds 42 bytes.
The later fixed V3 boundary run proved actual owner rejection at 1,048,577 bytes
with unchanged draft and inventory, but its proposed exact-cap payload measured
1,048,572 bytes and failed before saving. Eight subsequent fixed encoding
measurements reached neither the exact cap nor acceptance. All failed evidence
remains retained. The October 22 exact-cap qualification below describes the
previous profile and is not qualification of this candidate.

Exact 1,048,576-byte admission and a fresh no-save child/full-owner readback
remain open. The 69 unchanged passing cases are carried forward; diagnostic
success is not a replacement for the failed boundary assertion. Evidence is
under `.artifacts/native-app-capture-handoff-20261020` in the
`stage-profile-binding-focused01`, `stage-profile-boundary-focused01` and
`stage-profile-residues-focused01` records. No complete affected-target,
isolated-source, save-atomicity or feature acceptance is claimed. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved; all limits
unchanged.

## October 22 — clean held-release routing qualified

The scoped native audit and budget now consume the existing clean release
classifier. Exact saved release evidence supplies current and future metadata
liability; identity bytes and headroom remain charged once per asset. Live
package metadata and terminal slot caps remain distinct. Physical origins that
outlive a local reference remain counted. Every audit page rebuilds its proof in
its fresh context, and only exact validated release pair IDs are excluded from
ordinary active-preparation counting.

This change connects clean read routing only. Generic mutation facts and all
typed dirty poststate entries remain closed to releasing state. No cleanup
writer, new admission, recovery bypass, schema or storage-limit change is
introduced. Held-release writes, retained-only transitions, complete affected
gates and integrated acceptance remain open.

`release-routing-focused01` passed all 30 selected methods / 69 invocations,
with no missing, unexpected, skipped or failed tests. XCResult
`8baae9f0189847e4a52e27067ed00158.xcresult` and structured coverage are retained
under `.artifacts/native-app-capture-handoff-20261020`. All 2,920 frozen
source/project hashes and all six candidate hashes remained unchanged during
execution. The three Swift/test files remain identical in the final commit
candidate; the three documentation files were updated after the run to record
its results. Exact independent and IC-1 review preceded execution; project
validation, Markdown format validation and diff checks passed. This is focused
shared-checkout validation, not full-target, isolated-source, performance or
feature acceptance. The cleanup states are constructed fixtures, not
qualification of a cleanup writer. Activation disabled; PR116 frozen; deployment
hold active; AWS unapproved.

## October 22 — exact-cap receiving fixture qualified

The native receiving boundary now uses two fixed, legal one-original payloads:
four supporting-context fields containing 3,021 preserved U+0001 scalars each,
with 11 or 12 ASCII characters appended to the last field. Production encoding
measures 1,048,576 and 1,048,577 bytes respectively. The test requires the
maximum of current, received and abandoned projections to equal the expected
boundary before saving, then recaptures the actual persisted graph. It proves
owner staging and save-free replay at the cap, and capacity rejection with
unchanged draft/inventory at cap+1. The exhausted search and unused sizing
helper are removed. Runtime behavior, storage limits and historical operation
meaning are unchanged.

`boundary-owner-focused01` passed one method / two arguments on candidate02
`6c45b079ea18d5e5bb5110848427b392aa9ddd046c71b5c2a2d7908e1a945ba1`; XCResult
`204264cd02bc41afa29067ffd47d257c.xcresult`. All 2,920 frozen source/project
hashes were unchanged. The two preceding bounded characterization runs passed
and remain diagnostic evidence only. Exact results, failed searches, the earlier
compile failure, candidate patches and review records remain under
`.artifacts/native-app-capture-handoff-20261020`.

This supersedes the earlier **open exact-cap fixture** status below; earlier
failures remain historical evidence. Combined with unchanged prior checks, the
scoped regression evidence covers 154 methods / 382 invocations. This is shared
checkout validation, not complete affected-target, isolated-source, feature or
merge qualification. Held/releasing and retained-only survivor integration
remain open. Activation is disabled, PR116 remains frozen, the Supabase
deployment hold remains active, and AWS remains unapproved.

## October 22 — original identity enforcement checked; receiving boundary open

Original identity current bytes and reserved headroom now contribute once to
existing global Totals for appV2 admission. The twelve typed poststate seals
remain unchanged. Ordinary fully audited pending appV2 state has the reviewed
conservative bound of 357 MiB plus 4 KiB, below the existing 384 MiB durable
limit. This is not a bound for held-release unions or retained-library
occupancy. There is no new recovery bypass or free-space check on pure
settlement. The Debug-only availability clamp can only lower actual availability
and is absent from Release.

Scoped shared-checkout evidence for the enforcement source:
`identity-enforcement-focused01` passed 142 methods / 363 invocations; corrected
selector run `identity-enforcement-focused02` passed eleven additional
staging/recovery methods / seventeen invocations. These 153 fully passing
methods / 380 invocations include exact integer durable/free-space boundaries
and two saved retirements recovering at zero available space across restart and
a physical-release/save interruption. Their runtime and test sources are
unchanged in this checkpoint. This is not an isolated-source, complete
affected-target, performance, merge-readiness or feature-acceptance claim.

The receiving exact-metadata boundary remains open. The first run used a
filename as a suite selector and missed seven intended methods; the supplemental
run exposed an inherited fixture search failure before owner admission
assertions. Two test-only diagnostic edits remain outside this enforcement
checkpoint. Their narrowed retry `identity-enforcement-focused04` proved actual
persisted cap+1 rejection with unchanged state, but the exact-cap search
exhausted 9,408 evaluations, with nearest full projections 1,048,571 and
1,048,585 bytes around 1,048,576. The boundary method and overall supplemental
gates are failed, not qualified. The intervening `focused03` compile failure ran
zero tests. All failures and XCResults remain retained under
`.artifacts/native-app-capture-handoff-20261020`; all 2,920 frozen
source/project hashes were unchanged during each run. Raw simulator diagnostics
remain available. No assertion or runtime limit was weakened.

User-authorized cleanup recovered 6,425,440,256 bytes (about 5.98 GiB) from
inspected inactive global Xcode Build, Index and ModuleCache directories.
Dependencies, managed checkout caches and test evidence were preserved, and
builds resumed above the reviewed disk threshold. Cleanup evidence is
`cleanup-result01.json` in the same artifact directory.

Next: characterize legal encoding sizes before constructing a small fixed
exact-cap fixture; do not repeat the exhausted search matrices. Held/releasing
integration, retained-only survivor transitions and remaining acceptance stay
open. Activation disabled, PR116 frozen, Supabase deployment hold active, AWS
unapproved; all numeric and category limits unchanged. No push, merge,
deployment or hosted test occurred. Auto-prompts remain paused.

## October 21 — typed original identity measurements qualified locally

The candidate extends `SharedMediaNativeAcquisitionBudget.Snapshot` with
separate original identity measurements across all twelve concrete native
mutation proof families. Each proof validates its exact mutation and predecessor
revision. A fresh persisted context supplies the clean baseline under the same
store fence; only the sealed identity delta is applied. Surviving allocations
and receipts must match, and the observed pending asset cohort must equal the
expected set. Acquisition completion derives its contribution from the immutable
request and result and revalidates completion fields when consumed. Ordinary
numeric and cap-category limits remain unchanged.

Exact candidate04 passed all 107 selected methods / 272 invocations across
twelve suites in `identity-poststate-focused02`, XCResult
`a4b45d7221184cad9df52a1f8f85c7a0`. All 2,920 frozen source/project hashes
remained unchanged; no methods were missing or unexpected, and no failures,
skips or structured runtime warnings were reported. Raw simulator service,
CoreData and image-processing diagnostics remain retained. The earlier
candidate03 compilation failure executed zero tests and remains separate failed
evidence; candidate04's sole source correction added explicit actor isolation to
the nested proof enum. Both independent and IC-1 review cleared that exact
retry. Generated-project validation and changed-Markdown/diff checks passed.
This is scoped shared-checkout evidence, not isolated or complete-feature
acceptance, and is not a performance qualification.

The new lifecycle test compares mutation measurements to clean readback after
acquisition, metadata editing, sharing, nonfinal removal, final retirement and
physical release. Existing fault suites exercise all concrete proof families.
The measurement is not yet included in `Totals` or free-space admission and
provides no over-cap recovery authority. A removal leaving only retained owners
remains closed pending its own survivor proof. Held-release mutation
integration, retained terminal qualification, hostile poststate-specific cases
and proof-bound over-cap settlement remain open. The next enforcement increment
must bind saved-retirement recovery before adding this contribution to ordinary
admission. Activation disabled, PR116 frozen, deployment held, AWS unapproved;
all limits unchanged. No hosted actions or device work occurred.

## October 21 — asset-owned original identity accounting qualified locally

`SharedMediaNativeOriginalLiability` derives clean accounting inputs from the
union of pending graph allocations and held-release physical origins,
deduplicated by asset ID. Every selected completed original requires the
authoritative receipt and complete original reference/count/lease audit.
Derivatives and unmaterialized acquisition reservations keep their existing
owners. Current identity bytes and remaining headroom to the existing 512-byte
bound are separate global values; neither is charged to a package metadata cap
by this reader.

Every held target must remain in the pending union, have canonical terminal
receipt evidence, or prove a fully retained-only survivor through all surviving
references and their non-queue frozen consumers. Missing or ambiguous owners
fail closed. Retained-library occupancy remains uncapped. The reader grants no
admission, reservation, deletion, mutation or provider authority and does not
yet change Budget behavior. Proof-bound over-cap recovery and exact poststate
integration are prerequisites to enforcing this corrected global accounting.

The exact independently and IC-1 reviewed candidate01 passed four methods / six
invocations in `identity-liability-focused01`, XCResult
`5e40b14b3c6a4f7289fcac964b0bb996`. All 2,919 frozen source/project hashes
remained unchanged; there were no failures, skips or structured runtime
warnings. Raw simulator/Xcode warnings remain retained. Generated project
validation, seven-target source membership, changed-Markdown formatting and diff
checks passed. This is scoped shared-checkout validation, not full-suite or
isolated acceptance. Tests cover local/foreign origins, graph/snapshot overlap,
identity growth during retirement, physical removal, generic pending media,
missing receipt/identity, cancellation, dirty contexts and a shared original
surviving local reference removal. Valid retained-only terminal consumption and
runtime recovery remain separate gates; this candidate does not close them.
Activation disabled, PR116 frozen, deployment held, AWS unapproved; numeric and
cap-category limits unchanged.

Next integration follows `original-recovery-measurement-design04.md` and the
proof-entry inventory in `original-identity-entry-inventory01.md`, under
`.artifacts/native-app-capture-handoff-20261020/`. Independent and IC-1 design
review preserved every legacy cap: only the corrected identity contribution may
remain over aggregate capacity during a saved settlement. Ordinary admission
must add identity headroom before its existing free-space check. No unchecked
accumulator is authorized. The exact final-original mutation seal and surviving
asset values must be preserved across absence, save and readback. Runtime source
review and qualification remain required; these design records enable no route.

## October 21 — clean receiving classifier qualified locally

The separate clean-only classifier validates bounded pending membership roots
against either existing prepared/received/abandoned facts or the complete
held-release metadata snapshot. Both branches require the exact persisted row.
Dirty contexts, stale rows, corrupt ownership and duplicate execution identities
fail closed. It returns values only; generic mutation validators remain closed
to releasing states. Raw orphan/foreign slots still require the separate paged
reverse audit. This is not a complete store audit or a cleanup capability.

Exact independently and IC-1 reviewed candidate03 passed the corrected generic
phase method in `release-clean-corrected02`: one method / one invocation,
XCResult `3045d61aa62f43e1989d153a413d5844`. All 2,917 frozen source/project
hashes remained unchanged, with no failures, skips or structured runtime
warnings. The earlier `release-clean-focused01` retains the unchanged passing
one/two-original cleanup cases, including independent pair/original cleanup,
simultaneous pair retirement and stale-row rejection. Its generic case failed
because the test called ordinary staging instead of explicit restaging; that
test setup was corrected. `release-clean-corrected01` selected zero tests and is
rejected evidence. Both runs and raw simulator/Xcode warnings remain retained.
Combined scoped coverage is two methods / three invocations; no full-suite or
isolated-checkout acceptance is claimed. Evidence is under
`.artifacts/native-app-capture-handoff-20261020/`.

This classifier has no production Budget or ScopedAudit consumer yet. The next
integration must preserve global asset-lifetime identity accounting and a
proof-bound recovery path that cannot admit new work or deadlock behind fresh
capacity checks. The reviewed `release-identity-ownership-agreement02.md` keeps
retained-only occupancy uncapped and last-retained-reference deletion closed
until its separately sequenced cleanup owner is qualified. Activation disabled,
PR116 frozen, deployment held, AWS unapproved; numeric and cap-category limits
unchanged.

## October 21 — release survivor accounting qualified locally

The descriptive calculation sizes only forward states from the fully audited
current release snapshot. Current serialized components are replaced by future
component bounds, never added twice: one slot bound, exact membership, surviving
pair bounds including historical membership, and retained physical original
receipts/identities. Complete state totals are compared rather than summing
unrelated temporal peaks. Current measured usage remains distinct from possible
future growth. No policy consumes this calculation yet.

The snapshot now classifies each target by exact asset/acquisition identity:
local physical origin, foreign physical origin, or canonical stripped terminal.
Local matches are required exactly once; foreign origins contribute no local
charge but remain globally owned. Extra local origins remain charged. A shared
logical removal retains its physical charge until terminal absence. The existing
512-byte identity bound replaces, rather than supplements, the current identity.

Terminal sizing assumes one future atomic save replaces Progress with Released
and deletes package/member/consumer/execution together. It does not qualify that
writer or SQLite/WAL occupancy. The existing 1 MiB live metadata cap includes
package payload and owned original receipt payloads. Allocation identities count
only toward global storage. The terminal Released slot has its own existing
metadata cap after atomic package removal; retained shared origins remain in
global accounting. These are the existing cap categories, not a claim of
byte-for-byte equivalence to earlier phase calculations. No limit changes.

Candidate02 passed six methods / nine invocations across the projection,
metadata snapshot and live-audit suites. All 2,915 frozen source/project hashes
remained unchanged; no failures, skips or structured runtime warnings. Evidence:
`release-survivor-focused01-*` in
`.artifacts/native-app-capture-handoff-20261020/`, XCResult
`9d7c6b8c557740b08b0f0dc63a514093`. Raw simulator/Xcode warnings remain
retained.

Candidate03's receipt-only cap refinement received exact independent/IC-1
concurrence and passed three methods / four invocations in the projection suite,
including exact-limit acceptance, one-byte-over rejection and identity/terminal
cap separation. All 2,915 frozen hashes remained unchanged. Evidence:
`release-survivor-cap-focused01-*`, XCResult `96b5b79a34f942439b6c05b31e647b56`.
Unchanged snapshot/live-audit results above are reused; this is scoped
shared-checkout validation, not whole-feature acceptance. Project
generation/validation and source membership passed before the first run;
Markdown formatting and diff checks passed after synchronization.

Identity accounting here is descriptive release liability. The generic Budget
currently charges receipt encodings, not allocation identity strings. Before
Budget integration or sealed writes, the global asset-lifetime owner must cover
foreign origins and survive package/terminal-slot removal without duplicate
charges. The clean-only adapter may proceed separately; generic mutation stays
closed. Runtime budget/audit routing, sealed release writes, physical cleanup
and integrated acceptance remain open. Activation disabled, PR116 frozen,
deployment held, AWS unapproved.

## October 21 — clean release metadata measurement qualified locally

The read-only metadata snapshot measures current serialized accounting inputs
after the complete clean release audit: envelope, current membership, consumer
cohort, both execution metadata strings, Progress slot and surviving pair-state
representations. Historical closure bodies remain in surviving pair values;
deleted pairs are not reconstructed. These serializations measure the existing
accounting representation, not SQLite file occupancy.

Original receipt and allocation identity charges remain separate per asset ID,
with physical origin package ownership preserved. Logical shared-reference
removal retains the origin charge while the physical original survives. The
reader mirrors the existing paged origin traversal and receipt payload cap,
returns values only, and rejects dirty contexts or corrupted live evidence.

Exact candidate01/execution01 received independent and IC-1 concurrence. The
managed focused run passed three methods / five invocations, including one/two
originals, historical partial release, dirty/cancelled reads and shared-origin
retention followed by terminal removal. All 2,913 frozen source/project hashes
remained unchanged. No failures, skips or structured runtime warnings were
reported. Evidence: `.artifacts/native-app-capture-handoff-20261020/`
`release-metadata-focused01-*`, XCResult `74221986cdc54112b8b195e757f8eac6`. Raw
simulator image/espresso and Xcode diagnostics remain retained. Project
generation/validation, source membership, Markdown formatting and diff checks
passed.

This is scoped qualification in the shared checkout. No Totals, reservation,
admission or cleanup policy consumes this measurement. Next is a separately
reviewed survivor projection: replace current components with future bounds, key
originals by asset ID, preserve surviving shared origins, and include the atomic
terminal save shape. Global origin deduplication and persisted-state comparisons
remain required before whole-store routing. Sealed release writes, physical
cleanup and integrated acceptance remain open. Schema and limits are unchanged;
activation disabled, PR116 frozen, deployment held, AWS unapproved.

## October 21 — clean held-release live audit qualified locally

The clean-context reader binds the persisted V2 `releasing` slot to its frozen
origin, held execution quartet, exact package/member state, current membership
and media rows. Progress replaces the old slot payload copies under the existing
size contract. No schema or numeric limits changed.

Ready pairs retain their existing strict joins. Retiring pairs require a typed
slot/origin context, exact current rows and the validated historical pair proof.
Removed outputs require exact row absence. Shared removal preserves the
remaining physical owner's accounting, including its later terminal removal; it
does not require that owner to survive forever. The nested pair context is
explicitly main-actor isolated.

Candidate02 and execution02 received exact independent and IC-1 clearance. The
managed three-suite run passed 18 methods / 42 invocations: the new live audit
suite and complete paired-file retirement and recovery regression suites. This
includes one/two originals, persisted corruption, historical proof after
independent progress, orphan-lease rejection, shared removal/later terminal
absence and unchanged generic rejection. All 2,911 source/project hashes stayed
unchanged. No failures, skips or structured runtime warnings were reported.
XCResult `bff4813fc46743bca800b8fca92372ac` and exact coverage are retained
under `.artifacts/native-app-capture-handoff-20261020/release-live-focused02-*`.

The first run failed compilation before tests because the nested context lacked
main-actor isolation. Its failure and unchanged hashes remain in
`release-live-focused01-*`; no passing test result is inferred from that run.
Raw simulator image/espresso, launch-service and Xcode diagnostics remain in the
logs. Project validation, source membership, changed-Markdown checks and diff
checks passed.

This is scoped shared-checkout qualification of a descriptive per-package
reader. Synthetic persisted release fixtures do not qualify a production release
writer or physical deletion. Deleted proof bodies depend on a future sealed
writer's atomic Progress attestation; terminal receipts and database absence do
not prove fresh filesystem absence. Generic slot, budget, cleanup and execution
routing remain closed. Next: bind current serialized metadata to the clean audit
and qualify the future release projection before whole-store routing. Sealed
transitions, aggregate revision capacity, terminal paging and end-to-end
recovery remain open. Activation disabled, PR116 frozen, deployment held, AWS
unapproved and all numeric limits unchanged.

## October 21 — historical held-release pair proof qualified locally

The read-only historical proof leaf checks a saved pair-retirement closure
against one complete legal predecessor of the current release Progress.
Package/member revisions, membership and allocated bytes come from the frozen
submission. The other target may be at its current or an earlier stage on its
recorded branch; shared removal has no physical-retirement predecessor.
Unrelated inventory advances are permitted without rebasing or rewriting the
saved proof.

Frozen receiving requires ready, completed pairs. The proof binds exact target,
intent, envelope, file descriptors, retirement ID and canonical digest, and
checks before-state and successor membership hashes together. Writing/unbound
predecessors and tuples assembled from incompatible historical states fail.
Generic immediate-successor retirement validation remains unchanged.

Exact independent and IC-1 review cleared candidate03 and execution03 after the
negative tests were corrected to recompute coherent inner hashes. The focused
suite passed: 2 methods / 3 invocations, including one/two originals, 19 legal
sibling predecessor/current combinations, unrelated inventory advances and
canonical rehashed faults. All 2,908 source/project hashes remained unchanged.
No failures, skips or Xcode runtime warnings were reported. Raw simulator image,
audio-service and Xcode OS-build parsing diagnostics remain in the retained log.
XCResult `ae27d329894646c5bb503024494d2c6e` and evidence are under
`.artifacts/native-app-capture-handoff-20261020/release-history-focused01-*`.
Project validation, source membership and changed-Markdown checks passed.

This is scoped shared-checkout qualification of a pure proof-value leaf, not
complete native or isolated-source acceptance. Persisted slot/current-row joins,
sealed atomic transitions, aggregate revision capacity, terminal paging and
end-to-end recovery remain open. Once proof rows are deleted, a future sealed
writer's atomic Progress attestation plus exact absence checks must carry
recovery; the reader cannot recreate deleted physical evidence. Original
accounting remains clean-context-only. Activation disabled, PR116 frozen,
deployment held, AWS unapproved and all numeric limits unchanged.

## October 21 — exact held-release state qualified locally

The descriptive release-state leaf derives exact package membership, allocated
logical bytes and revision offsets from reconstructed Prepared/Received values
and immutable Progress. It verifies complete initial membership and byte totals.
Shared removal removes this package's original membership; physical ownership
may remain elsewhere. Original retirement retains its IDs until settlement.

The sealed-release contract preserves the frozen envelope and `preparedHeld`
phase. Every target step advances package, membership and slot revisions once,
including original retirement with unchanged membership bytes. Initial release
advances inventory and slot only. Inventory is a lower bound because unrelated
work may advance it; generic cleanup owners cannot be reused unchanged.

Independent and IC-1 review cleared the exact candidate and managed execution.
The complete release-value suite passed: 7 methods / 16 invocations, including
all 6/36 state combinations, three initial-input corruptions and four overflow
boundaries. All 2,906 source/project hashes remained unchanged. No failures,
skips or Xcode runtime warnings were reported. Raw simulator image-processing
and Xcode OS-build parsing diagnostics remain retained in the log. XCResult
`6f762bf1f69d49c1bdd7de467a984ee4` and evidence are under
`.artifacts/native-app-capture-handoff-20261020/release-state-focused01-*`.
Project validation, source membership and changed-Markdown checks passed.

This is scoped shared-checkout qualification of pure values, not a complete
native feature, physical cleanup or isolated-source acceptance result. Live
row/proof auditing, sealed atomic transitions, aggregate revision capacity,
terminal paging and end-to-end recovery remain open. The next live proof audit
must match a complete legal historical predecessor, then validate current state
separately; generic immediate-successor checks stay strict. Activation disabled,
PR116 frozen, deployment held, AWS unapproved and all numeric limits unchanged.
Prior receipt-accounting evidence is committed at
`f9ec2d385bdbf3f3e9e10e70aa36353084903c4a`.

## October 21 — shared original receipt accounting qualified locally

The pending-storage budget charges a completed original receipt once when its
physical origin package is absent or retained but a pending destination still
references the asset. The bounded pending graph supplies the assets; exact
receipt, owner, origin and inventory joins are required. Native derivative
outputs keep their existing accounting. No destination acquires the receipt as
logical metadata, and entirely retained-library assets remain excluded.

Independent and IC-1 review cleared the exact candidate and managed execution.
All three suites passed: acquisition graph, app original lifecycle and native
pair files, totaling 41 methods / 126 invocations. All seven new accounting
scenarios and eight corruption cases executed. All 2,905 source/project hashes
remained unchanged. No failures, skips or Xcode runtime warnings were reported;
raw simulator image-processing diagnostics and compiler/lint output remain in
the retained log. XCResult `da966c05776142c5a03c5aea397cdbe1` and evidence are
under
`.artifacts/native-app-capture-handoff-20261020/external-receipt-focused01-*`.
Project validation, the changed-Markdown gate and diff checks passed.

This is scoped qualification in the shared checkout, not a complete native
feature or isolated-source acceptance result. The arithmetic cap probe is not
end-to-end storage qualification. Held-release transitions, receiving-terminal
paging and complete recovery acceptance remain open. No schema, provider or
cleanup authority changed. Activation disabled, PR116 frozen, deployment held,
AWS unapproved and every numeric limit unchanged. Previous origin-reconstruction
evidence is committed at `cd311a4b243bcb0bc92e322f799ef65ce8ed58c9`.

## October 21 — release origin reconstruction qualified locally

The read-only `SharedMediaNativeReleaseOrigin` leaf reconstructs the exact
Prepared/Received/Transaction from the saved Plan, unchanged frozen envelope,
consumer cohort and persisted queue timestamp. It checks all original request
hashes and the complete held consumer/queue/job/event set without requiring
current package/member scalars to equal their historical snapshot. No clock, new
request, provider invocation, file operation or save is involved.

This leaf is not wired into release dispatch. Current ownership, acquisition
identity, cleanup assertions, membership transitions, revision runway and
terminal accounting remain the sealed release owner's responsibility. Generic
received-state validation remains strict. Synthetic partial-row test cases
exercise the separation of origin and current-state validation only; they do not
qualify a cleanup transition or restart recovery.

Exact independent and IC-1 review cleared candidate01. The managed focused suite
passed two methods / four invocations, with both one- and two-original
arguments. All 2,905 source/project hashes stayed unchanged; no failures, skips
or Xcode runtime warnings were reported. Compiler/lint and raw simulator
diagnostics are retained. XCResult `c6d1b31edee44900a291ed23bd5a90cb` and
evidence are under
`.artifacts/native-app-capture-handoff-20261020/release-origin-focused01-*`. The
initial sandbox report-extraction failure is retained; only report extraction
was repeated with the required cache access, not the test run.

Existing progress/projection evidence remains valid at local commit
`56c12bc9298f204966fe731367cba6a4e16a33e6`. Persisted release transitions,
current-state audit, shared receipt accounting, terminal paging, revision runway
and end-to-end recovery remain open. Activation disabled, PR116 frozen,
deployment held, AWS unapproved and numeric limits unchanged.

## October 21 — held-release progress and projection qualified locally

A new unconsumed `nativeReceivingReleasingProgressV1` payload retains ordered
per-target pair and original assertions across cleanup stages. Strict forward
transitions preserve existing assertions, and Released can be constructed only
from completed Progress when using the new progress-bound initializer. Existing
Plan/Released encoding meanings remain unchanged; these values still grant no
mutation or physical absence authority. Runtime slot readers reject release
phases until the sealed integration is reviewed.

The descriptive projection now includes every intermediate payload, existing
pair closure liabilities, canonical membership changes and original retirement
proofs. Each surviving pair is bounded against the union of initial membership
and possible retirement additions, covering closures that retain earlier larger
membership after other targets disappear. The unchanged envelope, receipt and
execution charges remain conservatively retained until final deletion. Progress
embeds Plan and is charged once. Terminal Released remains separately charged
outside pending membership in the intended integration; that runtime audit is
not implemented here.

The proposed atomic transition graph derives 4/3/2/1/0 remaining target saves,
plus final Released and consumption. The per-value arithmetic helper is not a
global reservation: runtime integration must still validate all affected slot,
package, membership, reference/count and aggregate inventory revision capacity
at every writer. Shared removal is an authoritative historical transition, not a
promise that surviving references never change. Original assertion preimages
must be minted by the sealed live-row owner before rows disappear.

Exact independent and IC-1 review cleared candidate01 before execution. The
managed suite passed all four methods / seven invocations, including arguments 1
and 2 for every parameterized method. All 2,903 source/project hashes remained
unchanged. No skips or Xcode runtime warnings were reported; compiler/lint and
raw simulator diagnostics remain retained. XCResult
`7eb195072f8e4558b3bd9406e52b7f09` and complete evidence are under
`.artifacts/native-app-capture-handoff-20261020/release-progress-focused01-*`.

All 6/36 progress shapes fit the slot bound. With empty support, the composed
intermediate upper bound is 71,279 bytes versus 80,046 already charged for one
original, and 168,845 versus 184,749 for two. Escaped support and scalar-width
checks also pass. The arithmetic metadata boundary remains distinct from
persisted cap and end-to-end acceptance. Persisted cap boundaries, physical
cleanup, restart recovery, terminal paging and complete affected gates remain
open. Activation disabled; PR116 frozen; deployment held; AWS unapproved; all
numeric limits unchanged.

## October 21 — held-release codec qualification

The descriptive ReleasingV1 and ReleasedV1 codecs passed two methods / three
invocations, including one/two originals and wide scalar/escaped-support inputs.
Both successor payloads are individually bounded by the existing metadata cap.
The one-original maximum terminal payload is 4,127 bytes versus 13,030 replaced
bytes; two originals use 5,851 versus 23,315. All 2,902 source/project hashes
remained unchanged. XCResult `2cf26c4f3f204cbab16485028a27b351` and complete
case evidence are retained under
`.artifacts/native-app-capture-handoff-20261020/release-values-focused01-*`. No
skips or Xcode runtime warnings were reported; raw simulator diagnostics are
retained. This is scoped shared-checkout codec evidence only.

The proposed slot mapping clears preparedData, preserves preparedSHA256 and
stores one explicitly versioned phase payload in resultData. Released binds the
original plan digest. No production slot reader, phase graph, budget or mutation
owner accepts these phases yet. Existing P2/historical meanings are unchanged.

Full release integration still requires the composed intermediate accounting,
original/pair closure retention, cold-recovery revision runway, terminal-row
paging/physical charging and end-to-end qualification. Pair membership growth
must be evaluated for every surviving pair; existing closure reservations are
not charged twice. The slot-size result alone grants no deletion, save,
admission or execution authority. Activation disabled; PR116 frozen; deployment
held; AWS unapproved; limits unchanged.

## October 21 — native receiving increment qualified locally

The reviewed P2 receiving integration now has passing scoped evidence for its
behavior and architecture. Candidate03 ran all 84 methods in twelve suites; 83
passed and only the stale architecture inventory failed. Both required metadata
boundary arguments and all recovery methods executed. Candidate04 changed only
architecture tests and documentation; the narrow rerun passed all nine methods
in both architecture suites. Each run preserved all 2,900 source/project hashes.
No skips or Xcode runtime warnings were reported; raw simulator diagnostics and
prior failures remain retained.

Evidence is under `.artifacts/native-app-capture-handoff-20261020/`:
`phase-focused03-result.json`, `phase-focused03-coverage.json`, and
`phase-focused04-result.json`. Final XCResult:
`ecf98e83628a4d99b7b466716db6c84e`. This proves the scoped shared-checkout
increment, not full-target, isolated-source, device, hosted or integrated
acceptance. Final selective local-commit review remains required.

Fresh P2 staging/receiving, saved-operation recovery, explicit abandonment and
restaging are connected under native ownership. Queue/job rows remain held.
Typed consumer release/completion, Capture handoff, broader affected gates and
integrated acceptance remain next. Two explicit architecture exceptions preserve
private capability construction, capped at the current 610/622 physical lines;
no runtime/storage limit changed. Activation disabled; PR116 frozen; deployment
held; AWS unapproved. No external operation is authorized by this result.

## October 21 — receiving behavior verified; bounded architecture correction

The exact reviewed receiving candidate03 completed all 84 methods in twelve
suites: **83 passed, one architecture inventory failure**, with no skips or
Xcode runtime warnings. All 2,900 source/project hashes stayed unchanged.
XCResult `2441e43812bb49b185c1681480ae11e8` and raw diagnostics are retained in
`.artifacts/native-app-capture-handoff-20261020/phase-focused03-result.json`.
The complete suite selection executed both metadata boundary arguments (cap and
cap-plus-one) and every required recovery method. The previous mixed-consumer
and metadata fixture failures now pass. Raw simulator diagnostics remain in the
log; this is scoped shared-checkout evidence, not integrated acceptance.

The sole failure was the stale oversized-owner inventory. Independent review
supports keeping private capability minting and validation fences together, with
explicit non-growth caps of 610 lines for the native original owner and 622 for
its repository. Both architecture inventories and canonical guides now record
these narrow exceptions; the general 600-line review ceiling and all
runtime/storage limits remain unchanged. The correction awaits exact review and
a narrow architecture rerun. No runtime source changed after candidate03.

Typed consumer lifecycle, Capture handoff, broader affected gates and integrated
acceptance remain open. Activation disabled; PR116 frozen; deployment held; AWS
unapproved. Historical failures and successful checks remain retained.

## October 21 — mixed-consumer correction and persisted recovery validation

The first complete receiving-owner run finished with **74 of 76 methods
passing** across eight suites. The two failures were an unchanged existing
consumer entering a clean-context validator during staging, and the old exact
cap-plus-two fixture target. All **2,900 source/project hashes** remained
unchanged. XCResult `6e79f31df5574c3d8f149d511cdf8bb5` and diagnostics remain
retained under `.artifacts/native-app-capture-handoff-20261020/`. This is failed
scoped shared-checkout evidence, not acceptance closure.

The corrected candidate carries the sealed staging proof through budget
accounting and validates unchanged consumers against captured facts.
Clean-context validation remains strict. Obsolete fresh-V1 mutation poststates
are removed; descriptive request values now live beside the versioned receiving
codec and use its canonical reconstruction. Historical V1 recovery remains
separate from fresh P2 admission. The exact metadata cap is unchanged; the
current fixture targets cap and cap-plus-one, subject to full persisted
projection verification. Receiving recovery tests reopen a new ModelContainer
against the same SQLite store.

These corrections await exact independent/IC-1 review and a focused rerun. No
passing result is claimed for them yet. Current valid slots remain bounded by
four pending packages, below the 128-row audit page size; retained-terminal
multi-page qualification belongs to the later typed lifecycle. Typed consumer
lifecycle, Capture handoff, broader affected gates and integrated acceptance
remain open. Activation disabled; PR116 frozen; deployment held; AWS unapproved;
all numeric limits unchanged.

## October 21 — receiving owner integration candidate under review

The local candidate connects P2 staging, atomic held receiving, explicit
abandonment and explicit restaging. Exact saved outcomes recover from database
facts without another media read or save. Old unstaged V1 requests are now
recovery-only; saved V1 prepared slots remain readable and explicitly
abandonable. Optional restaging provenance preserves historical codec bytes but
is mandatory for owner-created positive-revision P2 receiving. Pending facts and
accounting are phase-aware, and the raw intent audit checks reverse links.
Generic deletion cannot orphan a terminal slot. Shared originals remain under
the existing reference owner.

This candidate is **not yet compiled or qualified**. Independent review found
and prompted closure of the alternate fresh-V1 path and positive-revision P2
received provenance checks. Focused persisted tests cover acknowledgement loss,
corruption, cancellation, final file/CAS seals, sharing and restaging. Exact
candidate review must precede managed execution. Prior terminal-value evidence
below remains historical. Typed consumer lifecycle, Capture handoff, retained
multi-page integration, broader affected gates and integrated acceptance remain
open. Activation disabled; PR116 frozen; deployment held; AWS unapproved; limits
unchanged.

## October 21 — terminal values and reservation qualified locally

Compact AbandonedV1/V2 values now retain source-version meaning, the saved
operation/header and exact successor package/member identities without copying
media or supporting descriptions. A descriptive leaf decoder rejects
inconsistent phase, version, revision and blob combinations. P2 reserves the
larger received or abandoned successor; V1 reservation semantics and numeric
limits are unchanged. Runtime abandonment, restaging and P2 receiving are not
connected by this change.

Exact terminal candidate01 / execution01 passed **12 tests in three suites**,
with zero failures, skips or XCResult runtime warnings. All **2,898
source/project hashes** remained unchanged. Evidence lives in
`.artifacts/native-app-capture-handoff-20261020/`, XCResult
`b4bf297504264184a180aa337bfa4867`. Independent and IC-1 review preceded
execution. Simulator image-processing diagnostics are retained. This is focused
shared-checkout evidence, not full-target, isolated, device, hosted or
integrated acceptance.

The next coherent owner integration has independent and IC-1 design concurrence:
phase-aware facts/accounting, P2 staging/receiving, explicit abandonment and
fresh-only restaging with exact mutation proofs and acknowledgement recovery.
Typed consumer lifecycle, Capture handoff and integrated acceptance remain open.
Activation stays disabled, PR116 frozen, deployment held and AWS unapproved.

## October 21 — versioned receiving values and legacy exclusion verified

Prepared V2 and Received V2 now preserve a digest-bound package/operation/slot
revision, distinct consumer/queue/job/event markers and exact saved-header
reconstruction. V1 bytes and meaning remain unchanged. These are descriptive
values only: current staging still writes V1, and P2 cannot enter legacy
consumer or prepared-intent graphs, ordinary queue mutation or execution. Review
caught and corrected a prepared-row decode gap before execution; a persisted P2
payload in a V1 row now fails audit, discovery and staging recovery without
changing draft, inventory or intent facts.

Exact candidate02 / execution02 passed **56 methods across seven suites, 115
invocations**, with zero failures, skips or XCResult runtime warnings. All
**2,895 source/project hashes** stayed unchanged. Evidence is retained under
`.artifacts/native-app-capture-handoff-20261020/`, XCResult
`5fb54cfcae964dde94371d4eed6f49e4`. Independent and IC-1 concurrence preceded
the managed run. This is scoped shared-checkout evidence, not new full-target,
isolated, device, hosted or integrated acceptance. Simulator diagnostics remain
retained. Numeric storage limits are unchanged; the codebase map now correctly
names the already active V65 schema.

P2 staging/receiving, explicit abandonment/restaging, typed consumer lifecycle,
Capture handoff and integrated acceptance remain open. The next abandonment
design has independent and IC-1 concurrence: exact terminal proofs, full-slot
and target CAS, and every fresh restage using P2 even after V1 abandonment. It
is not implemented or qualified yet. Activation stays disabled, PR116 frozen,
deployment held and AWS unapproved. No external-operation authority changes.

## October 20 — persisted receiving admission boundary verified

The real owner now has persisted-fixture coverage at the unchanged
1,048,576-byte metadata cap and at the nearest discovered over-limit fixture,
1,048,578 bytes. Exact-cap staging and saved-slot recovery pass. The over-limit
draft is saved through the metadata owner, then staging rejects it without
changing its facts, inventory revision or intent rows. Neither case creates a
receiving queue, consumer, job or event. Originals and submitted supporting
content stay intact.

Candidate04 / execution05 passed **one parameterized method with both cases**,
with zero failures, skips or XCResult runtime warnings. All **2,895 source and
project hashes** remained unchanged. Evidence is retained under
`.artifacts/native-app-capture-handoff-20261020/`; XCResult
`fc5373174b834e14b12a0098722a41a2`. Exact independent and IC-1 concurrence
preceded execution. This is focused shared-checkout evidence; unchanged broader
staging and codec results are reused, not represented as a new full-target,
isolated, device, hosted or integrated acceptance run.

The acceptance method separately retains the production numeric guard's exact
one-byte-over unit proof in
`fullTwoPhotoReservationCountsEveryEnvelopeCopyAndRetainsOrder`, from
codec-focused02 / XCResult `7bb0f938407b465b9099f05dbb66a933`. The bounded
canonical search did not represent a persisted cap-plus-one draft; no global
unreachability or persisted-plus-one success is claimed. Independent and IC-1
review approved this method refinement. Failed searches, the corrected compile
failure and simulator/compiler diagnostics remain retained. This closes the
staging resource-admission behavior gate under that method without changing
runtime code or numeric limits.

Receiving/abandonment, typed consumer lifecycle, Capture handoff and integrated
acceptance remain open. The next reviewed design uses fresh-only P2/R2 receipts
with digest-bound intent provenance and matching consumer/queue/job/event
markers; V1 bytes retain their original meaning. This design is not implemented
or qualified yet. Activation stays disabled, PR116 frozen, deployment held and
AWS unapproved; external-operation restrictions remain.

## October 20 — durable prepared-intent staging locally verified

The inactive owner discovers saved identities before generating new ones, then
stages under retained account/native ownership and queue/observation locks.
Fresh staging seals the complete ready media cohort and saves one prepared slot
plus one inventory increment. Package/member bytes stay unchanged. Exact
saved-slot recovery never saves again, including cold reopen and missing
original media.

Prepared-only graph validation, exact intent facts and reservation accounting
protect competing target edits and cleanup while unrelated drafts remain usable.
Prepared bytes are materialized; future receiving headroom is reserved once.
Malformed/foreign/partial slots and identity collisions stay closed. No queue,
job, event, consumer, provider call or execution authority is created. Existing
numeric limits and submitted-content semantics are unchanged.

Exact candidate02 passed **76/76 methods across seven suites**, **166
invocations**, with **zero failures, skips or XCResult runtime warnings**. All
**2,895 source and project hashes** stayed unchanged. Evidence is retained in
`.artifacts/native-app-capture-handoff-20261020/`, including XCResult
`cecf08b059f04bf284015dfc420f5976`. Parser, generated-project, Markdown-format
and diff checks passed. Exact independent and IC-1 concurrence preceded
execution. This is scoped shared-checkout validation, not a new full-target,
isolated, device, hosted or integrated acceptance result. Compiler and simulator
diagnostics remain retained.

The run proves actual free-space threshold accounting and real persisted
over-cap draft preservation. **Exact persisted aggregate metadata-cap and
cap-plus-one fixtures remain open**, distinct from that free-space test.
Receiving/abandonment, typed consumer lifecycle, Capture handoff and integrated
acceptance remain next. Activation is disabled, PR116 frozen, deployment held
and AWS unapproved; external-operation restrictions remain.

## October 20 — V65 receiving-intent foundation locally verified

V65 adds an empty package-keyed receiving-intent table through a lightweight
V64-to-V65 migration. The outgoing V64 relationship graph and acquisition
receipt were frozen and compiled before active-model changes. All applicable
full/recent migration plans append the new stage; startup has a dedicated V64
plan. Disk migration and cold reopen preserve prior ownership, receipt bytes,
relationships and optional fields without fabricating an intent. Destructive
rescue and quarantine eligibility remain unchanged.

Every raw intent phase remains a storage liability and blocks legacy admission,
purge and native scoped mutations, including after page suspension. Storage is
not receiving or execution authority. Typed staging, receiving, exact recovery,
abandonment and Capture handoff remain next under reviewed design03. Existing
numeric limits and immutable submitted-content contracts are unchanged.

Candidate01 passed all **185 focused methods across 15 suites**. Its complete
`merianTests` run recorded **6,456 passed, one failed and zero skipped**. The
sole failure was a missed test inventory entry for the new record in
`ScanRepositoryPurgeTests`; runtime purge already blocked it. Candidate02 adds
that record to the saved/unsaved blocker fixture and corrects four stale
migration-guardrail diagnostic strings. Its **23/23 methods across three
suites** passed, covering the corrected inventory and saved/unsaved purge
denial. Runtime Swift and the generated project are unchanged between these
runs; unchanged passing full-target evidence is reused. This is corrected
shared-checkout validation, not a fresh all-green full run or
isolated/device/hosted acceptance.

All three runs retained all **2,892 source/project hashes**. The focused and
correction runs have no XCResult runtime warnings. Full01 retains one
priority-inversion warning in the unchanged synthetic `VideoAudioFixture`;
compiler/lint, simulator and fixture diagnostics remain retained. No performance
or device-quality claim follows from these functional checks. Migration source
guardrails, negative fixtures, startup selectors, generated-project validation
and complete iOS CI-tooling tests passed; the corrected diagnostic strings
passed the migration guardrail and negative fixtures again.

Evidence: `.artifacts/native-app-capture-handoff-20261020/`; focused XCResult
`4e0d7145c97b47ec87021fc8bbd1c175`, failed full XCResult
`974896fc26314e34b75990276c8910a9`, corrected XCResult
`0b5d69c9d4834963b07a62526e34b847`. Exact independent and IC-1 review preceded
each execution. Persisted metadata-cap boundaries, consumer lifecycle, native
journeys and integrated acceptance remain open before version deletion/export
and redesign. Activation is disabled, PR116 frozen, deployment held and AWS
unapproved; external-operation restrictions remain.

## October 20 — durable receiving codec and reservation locally verified

The inactive receiving values preserve exact timestamp bits, ordered media,
submitted supporting content and the complete saved transaction header. Exact
reconstruction retains nativeFreezeV3 semantics and returns only a descriptive
transaction value. No receiving writer accepts that type; its request
constructor remains file-local. The codec grants no save or execution
capability.

Reservation replaces both the draft envelope and every ready pair's future
cleanup projection with their complete frozen successor sizes. Prepared,
received, consumer and both job/event metadata copies count within the existing
aggregate metadata allowance. The input is audited pre-intent metadata; the
charge is the larger of current and maximum successor totals, reserving only the
difference. Existing numeric limits remain unchanged.

Candidate04 has **27/27 focused methods across four suites**, combining the
corrected two-suite rerun's 10/10 with 17 unchanged passing methods from the
initial run. Both retained all **2,886** source/project hashes. The final rerun
has no failures, skips or XCResult runtime warnings; compiler/lint and simulator
diagnostics remain retained. Exact reconstruction, tampering, complete reversed
cohorts, audited graph accounting, maximum two-photo wire sizes and escaped
context are covered. This is focused shared-checkout validation, not
full-target, isolated, device, hosted or integrated acceptance.

The synthetic maximum-photo metadata successor is **477,864 bytes** with one
8,192-quote context field. Four 8,000-quote fields reach **1,328,184 bytes**,
exceeding the unchanged **1,048,576-byte** aggregate cap: reservation rejects
this valid draft without trimming its context or altering media. These are
serialized-size fixtures, not physical maximum-file qualification. The exact-cap
and one-byte-over tests are arithmetic-only; a persisted graph at the cap and
actual staging/recovery accounting remain V65 integration gates.

Failed evidence is retained. Initial focused01 passed 26/27; its sole failure
was a stale source assertion predating the reviewed saved-original-retirement
exception. Candidate04 corrects the assertion while retaining qualification,
nonready, lease, cleanup and default-false checks. Runtime code is unchanged
between runs. The prior lifecycle checkpoint's reused boundary-suite evidence is
superseded by this fresh rerun. An earlier unrun review hold also closed by
restoring the sealed request constructor and returning a descriptive codec
value.

Evidence: `.artifacts/native-app-capture-handoff-20261020/`; final XCResult
`7bb0f938407b465b9099f05dbb66a933`, reused initial XCResult
`0dc60b84a5ea43b788f310b0f4667431`. V65 persistence, typed staging/receiving and
Capture handoff remain next under reviewed design03. Consumer lifecycle, full
affected gates, native journeys and integrated acceptance remain open before
version deletion/export and redesign. Activation is disabled, PR116 frozen,
deployment held and AWS unapproved; external-operation restrictions remain.

## October 20 — app original sharing and retirement locally verified

Consumer-less app drafts can now share a ready original without copying its
physical bytes. Logical removal preserves surviving references and their media.
The final removal saves the exact retirement before disposal; cold recovery
requires complete reverse accounting, synced absence and a final synchronous
absence check before releasing storage. Submitted supporting content and other
photos’ presentation remain exact. Prepared pairs must be explicitly retired
before removing their original. Old removal requests become stale after release.

Fresh app acquisition may coexist with a fully saved original retirement only on
a clean context with exact zero-live accounting and no derivative pair/work.
Preparation and dirty poststate guards remain strict. Unrelated inventory
progress cannot change the target’s local identity or authorize another
deletion. This increment does not upload media, change receiving consumers, fund
or enqueue work, or invoke a remote AI provider. Existing local Vision
preparation remains unchanged.

Candidate04 has **88/88 focused methods across 10 suites**: focused03 passed
37/37 lifecycle, acquisition and preparation methods; seven unchanged suites
contribute 51 passing methods from focused01. Both retained all **2,882** source
and project hashes. The final run has no failures, skips or XCResult runtime
warnings. Compiler/lint and simulator diagnostics remain in the logs.

Failed evidence is retained: focused01 passed 54/65 and exposed a V1 JSON
re-encoding comparison; focused02 passed 13/15 after that correction, exposing
the overly broad idle-file guard and a test’s historical global-revision
comparison. The corrections preserve V1 submitted bytes, strictly audit the
saved retirement, and compare all local plan fields while separately checking
global progress. Earlier candidate01’s unrun test-compilation review hold also
remains recorded. This is focused shared-checkout validation, not full-target,
isolated, device, hosted or integrated acceptance.

Evidence: `.artifacts/native-app-original-lifecycle-20261020/`, with final
XCResult `e03048fef8784e898ec1b5ae0b1f0ae6` and reused seven-suite XCResult
`e3d472ec437b447c984150db39a9466a`. Next is the reviewed durable
receiving-intent codec and complete metadata-reservation proof before V65
migration and Capture handoff; design03 concurrence is retained in
`.artifacts/native-app-capture-handoff-20261020/design-review03.json`. Consumer
lifecycle, full affected gates, native journeys and integrated acceptance remain
open before version deletion/export and redesign. Activation is disabled, PR116
frozen, the Supabase deployment hold active and AWS unapproved. Schema, numeric
limits and external-operation restrictions remain.

## October 20 — app pending-original cleanup locally verified

The inactive app owner now supports explicit abandonment and cold recovery of
reserved or held originals in consumer-less drafts. Saved physical closure
precedes disposal; synced absence and a final synchronous absence check precede
reservation release. The stripped terminal receipt permits read-only recovery
without another loader, reservation or AI execution. Active or unsettled writers
block entry, and raw unknown reservations are never automatically deleted.

Each transition retains the app account/namespace fences, full scoped audit,
complete pending-original reverse accounting and an exact typed write set. Other
originals, ready output pairs, receiving consumers and ordinary drafts remain
protected. V1 qualification behavior is unchanged.

Independent and IC-1 reviewed candidate04 has combined focused evidence for
**88/88 methods across 10 suites**. The initial completed run passed 87/88; its
sole failing method used an inconsistent reserved fixture package phase. The
fixture now uses the graph’s derived `acquiring` phase. The corrected cleanup
suite passed **13/13**; the nine unchanged passing suites are reused. Runtime
code did not change between these runs. Both preserved all **2,877** source and
project hashes; the rerun has no failures, skips or XCResult runtime warnings.
Compiler/lint and simulator diagnostics remain in the logs. Earlier focused02
failed during test compilation before running any methods; its evidence remains
retained. This is focused shared-checkout validation, not a new full-target,
isolated, device, hosted or integrated pass.

Evidence: `.artifacts/native-app-pending-cleanup-20261020/focused03-result.json`
and `focused04-result.json`; XCResults `6184199fac954f528f48220fd968d7c6` and
`eebc4545d392462fbffee3aec89e758d`. Next is ready-original sharing, removal and
exact final retirement/release, with its design reviewed independently and by
IC-1 in `.artifacts/native-app-original-lifecycle-20261020/design-review.json`.
Capture durable receiving handoff, consumer lifecycle, native journeys and
integrated acceptance remain open before version deletion/export and redesign.
Activation stays disabled, PR116 frozen, the Supabase deployment hold active and
AWS unapproved. Schema, numeric limits and external restrictions are unchanged.

## October 20 — ordinary native photo receiving locally verified

The inactive app owner now atomically freezes an ordinary photo cohort and
creates its consumer, queue, held job and event. Fixed identities, generation,
timestamp and metadata are retained across exact recovery. Queue and observation
locks precede the account-bound owner; the sealed lock remains checked
throughout the operation. A typed poststate permits only two updates and four
inserts. Fresh ownership/reference checks and physical seals precede the single
save. Partial or changed saved sets stay blocked, never repaired or reminted.

The queue requires attention and its job has no retry time. Neither grants
legacy execution, uploads, funding or provider calls. Submitted supporting text
and exact originals remain immutable. Later exact recovery tolerates unrelated
package progress without requiring a historical global revision. V1 behavior and
clean-context public audits remain unchanged.

Independent and IC-1 reviewed candidate05 has combined focused evidence for
**98/98 methods across 12 suites**. The initial run passed 97/98; its sole
failure was a test helper selecting an arbitrary membership row in a
multi-package fixture. The corrected receiving verifier selects the exact
request package. Its focused rerun passed **10/10**; the other 11 unchanged
suites are reused. Both runs preserved all **2,873** source/project hashes. The
rerun has no failures, skips or XCResult runtime warnings; compiler/lint and
simulator diagnostics stay in the logs. Retained evidence:
`.artifacts/native-app-receiving-20261020/focused01-result.json` and
`focused02-result.json`; XCResults `23f2f8bf0ba5485f90b6ea2a24d9a0e6` and
`d9754d29ef3940f88cba7e3591754daf`. This is combined focused shared-checkout
validation, not a new full-target, isolated, device, hosted or integrated pass.

This increment is ordinary initial photos only. Reanalysis retains its distinct
job and bound intent codec. The caller must retain the exact receiving request;
Capture's durable UI handoff, lifecycle/result transfer and removal are still
unfinished. Next is app-scoped abandonment/recovery of consumer-less pending
original acquisitions, with its independently and IC-1 reviewed design in
`.artifacts/native-app-pending-cleanup-20261020/design.md`. Existing physical
closure encoding and limits remain unchanged; terminal receipts are retained,
and final synced absence must precede reservation release.

Activation stays disabled, PR116 frozen, the Supabase deployment hold active and
AWS unapproved. No schema or limit change. Full affected gates and remaining
integrated acceptance still precede version deletion/export and redesign.

## October 20 — V2 exact output retirement locally verified

The inactive app owner now retires writing/interrupted and ready output pairs.
It persists and exactly acknowledges the deletion record before unlinking, then
requires two absence proofs and final namespace checks before releasing rows and
accounting. Shared-reference liabilities block disposal. Originals, other output
pairs, receiving consumers and unrelated drafts remain protected. Qualification
and app paths share the focused retirement mechanics while their sealed
authorities remain separate.

Independent and IC-1 reviewed candidate02 passed **116/116 methods across 16
suites**, with no failures, skips or Xcode runtime warnings. All **2,868**
source/project hashes and candidate hashes stayed unchanged. Evidence:
`.artifacts/native-app-pair-retirement-20261020/focused03-result.json`; XCResult
`86d1ab9c3d42471d9e73f1800f849dee`. The earlier focused02 attempt was refused
before compilation because another build was active; its evidence is retained.
This is focused shared-checkout validation, not full-target, isolated-source,
device, hosted or integrated acceptance. Compiler/lint warnings and simulator
diagnostics remain in the log.

Tests cover ready, absent, empty, short, missing and mixed output states;
interruption after either unlink; cold reconciliation; save/readback
uncertainty; late files and physical/metadata drift; additional references;
preservation of other originals, pairs and receiving consumers; and cancellation
at release entry. Uncertain release never authorizes a repeated deletion. A
fully released old request is stale and grants no I/O; no permanent proof rows
or capacity charges are added.

Next is atomic inactive receiving: freeze the exact cohort and create its
consumer, queue, held job and event in one save. Its design has independent and
IC-1 concurrence, with exact implementation review still required. Lifecycle,
Capture/Auth, RUX recovery and integrated acceptance remain before version
deletion/export and redesign. Activation stays disabled, PR116 frozen, the
Supabase deployment hold active and AWS unapproved. Schema and limits remain
unchanged.

## October 20 — V2 exact cold output recovery locally verified

The inactive app owner can recover an already-bound complete partial or exact
existing final after restart, then publish only the exact pair. Its sealed cold
capability cannot reserve outputs, create partials, accept replacement bytes or
run preparation. Saved work epochs stay unchanged; physical proofs use the
current held namespace binding. Incomplete, missing and unbound work stays held;
conflicting files fail closed. Already-ready recovery is read-only.

Independent and IC-1 reviewed candidate01 passed **45/45 methods across six
suites**, with no failures, skips or Xcode runtime warnings. All **2,866**
source/project hashes and candidate hashes stayed unchanged. Evidence:
`.artifacts/native-app-pair-recovery-20261020/focused01-result.json`; XCResult
`c1aee0b14f664a8bac04abef6b0e7c6f`. Nine unchanged suites from the prior
delivery 100/100-method, 14-suite result remain reused. This is focused
shared-checkout validation, not full-target, isolated-source, device, hosted or
integrated acceptance. Compiler and lint warnings remain in the log.

Tests cover cold epochs, exact retained bytes, missing/short/conflicting files,
save acknowledgement and readback loss, final-boundary replacements, receiving
preservation and cancellation at actual actor entry before rename. Uncertainty
never authorizes another processor call or substitute media.

Next is exact cold retirement: persist and acknowledge the closure before
unlink, prove both absences before final atomic accounting release, and reject
an already-released old request without I/O. No permanent proof rows or capacity
charges are required. Atomic inert receiving, lifecycle/Capture/Auth
integration, RUX recovery and integrated acceptance still precede version
deletion/export and redesign. Activation stays disabled, PR116 frozen, the
Supabase deployment hold active and AWS unapproved. Schema and limits remain
unchanged.

## October 20 — V2 fresh paired-file delivery locally verified

The inactive app owner now retains fresh processed outputs through file
reservation, partial identity persistence, both output completions and paired
publication in one held operation. A saved plan cannot supply replacement bytes
or authorize another processor call. The shared transaction core uses sealed app
actions, exact per-action poststates and full pending/receiving accounting.
Available space is rechecked at reservation save; original, output and directory
identities are synchronously rechecked immediately before publication.

Independent and IC-1 reviewed candidate02 passed **100/100 methods across 14
suites**, with no failures, skips or Xcode runtime warnings. All **2,864**
source/project hashes and candidate hashes stayed unchanged. Evidence:
`.artifacts/native-app-pair-delivery-20261020/focused02-result.json`; XCResult
`b042c93ff75842a99090fc310c49a4b2`. This is focused shared-checkout validation,
not full-target, isolated-source, device, hosted or integrated acceptance.
Compiler/lint warnings, synthetic-image diagnostics and a simulator Photos
service connection diagnostic remain in the log.

Candidate01 was held without execution: review found cancellation could reach
file creation during an actor hop. Candidate02 checks cancellation at actual
actor entry and before namespace creation; its deterministic regression proves
both final and partial paths stay absent while reserved liabilities remain.
Tests also cover interrupted writes, exact save acknowledgement, readback loss,
receiving preservation, low space, physical replacement and owner drainage.

Cold output completion and retirement remain closed pending their next reviewed
integration. Exact recovery may finish only already-bound bytes; retirement must
persist and acknowledge its closure before unlink, prove both absences before
final accounting release, and treat an already-released old request as stale
without further I/O. No permanent proof rows or capacity charges are required.

Next are cold recovery/retirement, atomic inert receiving,
lifecycle/Capture/Auth integration, RUX recovery and integrated acceptance, then
version deletion/export and redesign. Activation stays disabled, PR116 frozen,
the Supabase deployment hold active and AWS unapproved. Schema and storage
limits remain unchanged.

## October 20 — V2 no-file plan closure locally verified

The inactive app owner can close one exact never-started photo plan, including
after restart. A sealed cold-closure witness is separate from fresh processing:
a saved file epoch permits only closure, never renewed processing or output
creation. Both destinations must lack final and partial files, including empty
partials. Exact directory and leaf observations are rechecked synchronously
immediately before the single save. No file is unlinked.

The typed post-state permits exactly inventory/package/membership updates and
deletion of the pair and its two work rows. It preserves original media, other
intents, ordinary drafts and receiving-consumer facts, with complete scoped
budget validation before release. Save uncertainty allows exact read-only
acknowledgement and never another delete. The tests cover warm/cold closure,
receiving preservation, unowned files, late partial creation, parent
replacement, membership drift and before/after-save/readback faults.

Independently and IC-1 reviewed candidate01 passed **61/61 methods in ten
suites**, with no failures, skips or Xcode runtime warnings. All **2,863**
source/project hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-app-plan-closure-20261020/focused01-result.json`; XCResult
`3954e04975164e328ff4466204157ea0`. Compiler/lint warnings and the existing tiny
synthetic-image Vision diagnostics remain in the retained log; this is focused
shared-checkout evidence, not full-target, isolated-source, device, hosted or
integrated acceptance.

Next are paired-file persistence, exact output recovery/retirement, atomic inert
receiving, lifecycle/Capture/Auth integration and RUX recovery, followed by
integrated acceptance, version deletion/export and redesign. Activation remains
disabled, PR116 frozen, the Supabase deployment hold active and AWS unapproved.
Schema and storage limits remain unchanged.

## October 20 — V2 photo processing and durable planning locally verified

The inactive app owner now retains one operation across fresh preparation
reservation, exact acknowledgement, one concrete photo-processing call and a
single durable plan save. Saved attempts never authorize processor replay.
Account transition and cancellation drain the processor before ownership exits.
Original bytes are verified across processing and immediately before save.

The shared typed plan core preserves V1 qualification and pins the exact V2
three-update/three-insert post-state, all pending-package and receiving-consumer
charges, and separate original/AI-input/display identities. Preparation attempts
retain the app-operation epoch; pair/work rows retain the independently verified
file-namespace epoch. Uncertain saves permit only exact read-only
acknowledgement. Cold plan inspection grants no file-writing or dispatch
authority.

Candidate04 passed **4/4 methods** in the corrected app-plan suite, with no
failures, skips or Xcode runtime warnings; all **2,861** source/project hashes
and candidate hashes stayed unchanged. XCResult
`d7a53e29bcd9422cb56d50723f011e12`; evidence
`.artifacts/native-app-plan-20261020/focused04-result.json`. Composite coverage
reuses five unchanged passing suites from candidate03 and eight from
candidate02. This is focused shared-checkout evidence, not full-target,
isolated-source, device, hosted or integrated acceptance.

Failed evidence remains retained: candidate01 failed test compilation before
execution; candidate02 passed 91/93 methods and exposed conflated epochs;
candidate03 passed 29/30 methods after the runtime correction and exposed an
unscoped test-fixture membership lookup. Candidate04 changes only that lookup to
the exact target package. Runtime is unchanged from candidate03.

Next are physically proven no-file plan closure, paired-file persistence, atomic
inert receiving, lifecycle/Capture/Auth integration and RUX recovery, followed
by integrated acceptance, version deletion/export and redesign. This checkpoint
creates no output files and does not freeze, enqueue, fund or invoke a remote AI
provider. Activation stays disabled, PR116 frozen, the Supabase deployment hold
active and AWS unapproved. Schema and numeric limits remain unchanged.

## October 20 — V2 preparation reservations locally verified

The inactive app owner now has an envelope-only preparation path through the
shared typed mutation core. An audited, sealed action permits inspection,
reservation or explicit closure of one exact saved attempt. Reservation pins the
current writer epoch; cold closure accepts the saved epoch only for that exact
attempt after the serial owner has drained. Neither action processes media,
creates derivative files, freezes a submission or invokes AI.

The dirty-state proof permits exactly the inventory revision and target package
envelope/phase/revision to change. Membership, independent bootstrap revision,
other pending packages and receiving-consumer bytes stay pinned. Original
reference, asset and completed acquisition receipt facts are rechecked before
save and acknowledgement. Fresh scoped idle-file, pair/work and budget checks
run after the pre-save boundary; the exact dirty-state budget is then rechecked.
Uncertain saves permit exact read-only acknowledgement; the operation cannot
repeat its write. Full scoped pending and receiving charges remain included,
with unchanged storage limits. Ordinary unanchored drafts stay outside the
native graph; the existing V1 qualification path remains separate.

Independently and IC-1 reviewed candidate04 passed **97/97 methods in thirteen
suites**, with zero failures, skips or Xcode runtime warnings. All **2,860**
source/project hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-app-preparation-20261020/focused04-result.json`; XCResult
`f62dd0a664ed471aa116f1ea7ad39f20`; candidate SHA256
`54c446a85e64d239f173b636d8358dd83c844b45f5b1a88aa53f473589e0b5d5`. Candidate01
remains HOLD/unrun; candidate02 was superseded without execution. Candidate03's
compile-before-tests failure is retained. Candidate04 only splits two throwing
test assertions; runtime code is unchanged from candidate03. Simulator
diagnostics from tiny synthetic images remain in the log. This is scoped
shared-checkout validation, not full-target, isolated-source, device, hosted or
integrated acceptance.

Next are derivative preparation and atomic inert freeze/consumer/queue/job/event
receiving, lifecycle and Capture/Auth integration, RUX recovery, integrated
acceptance, version deletion/export and redesign. Activation disabled, PR116
frozen, Supabase deployment hold active, AWS unapproved; schema and numeric
limits unchanged.

## October 20 — V2 original acquisition locally verified

The inactive app owner now retains exact selected original bytes through the
shared typed reservation/completion core. Fixed identities and exact saved
reservation acknowledgement precede the single fresh loader/copy. Completed
replay is read-only; cold reserved/held requests never repeat acquisition. A
private dirty-state proof covers only the exact typed row changes and target
membership successor, preserving other pending packages and receiving-consumer
facts. Both inventory and independent bootstrap revisions remain pinned.

A separate owner-minted settlement grant is usable only after the actual writer
returns. It can acknowledge an exact saved result or hold an existing
reservation after cancellation; it cannot load, copy, reserve, complete, release
storage or invoke AI. Exact target package/member facts and the returned copy
proof bind settlement. Unknown outcomes retain the fences. Cancellation is
checked at actual I/O entry; fresh reservation checks include inventory-bound
unfinished pairs and bounded pending work. V1 behavior stays behind its original
sealed authority and separate settlement entry.

Independently and IC-1 reviewed candidate03 passed **138/138 methods in sixteen
suites**, with zero failures, skips or Xcode runtime warnings. All **2,857**
source/project hashes and candidate hashes stayed unchanged. Evidence:
`.artifacts/native-app-acquisition-20261019/focused03-result.json`; XCResult
`3a6cf78162f44a6dbfbeea8befee2cb5`; candidate SHA256
`9d362f8a3c785ccf0182aa7ea54ceba0e51126fea4d53f90156dda9c99292ab7`. Candidate01
remains HOLD/unrun. Candidate02's compile-before-tests failure is retained;
candidate03 adds the required private method actor isolation and removes an
unnecessary `try`. This is scoped shared-checkout validation, not full-target,
isolated-source, device, hosted or integrated acceptance.

Next port native preparation and atomic inert freeze/consumer/queue/job/event
receiving through the same owner, then lifecycle and Capture/Auth integration,
RUX recovery and integrated media acceptance. Version deletion/export and
redesign remain open. Activation disabled, PR116 frozen, Supabase deployment
hold active, AWS unapproved; schema and numeric limits unchanged.

## October 19 — same-owner V2 metadata saves locally verified

Existing native pending drafts now support metadata-only edits through the same
registered app owner. Each operation audits the native graph under the account
lease and retained file/store fences. A sealed witness pins the inventory and
independent bootstrap headers. The transaction changes exactly the package
envelope/revision and inventory revision; membership, media, other pending
packages and exact receiving-consumer bytes remain unchanged. Frozen, retiring,
consumer-bound and unfinished targets are refused. Ordinary unanchored drafts
remain untouched. Uncertain saves allow exact read-only recovery, never another
write within the consumed operation.

Candidate03 passed all 11 methods in the two correction suites, with no
failures, skips or Xcode runtime warnings; all 2,852 source/project hashes and
candidate hashes remained unchanged. Evidence:
`.artifacts/native-app-metadata-20261019/focused03-result.json`; XCResult
`ffba1db786634971b04d76878d982e44`; candidate SHA256
`aaf201c0b12a78009356ee750cede34e960dafa28e4e58d613b2e56ffa23239e`. The earlier
121/123 result across fifteen suites remains retained. Its failures were a test
fixture topology mismatch and a source-boundary assertion that needed to follow
the extracted V1 settlement helper. The correction changed only those two tests;
thirteen unchanged passing suites are reused. This is scoped shared-checkout
validation, not a new full-target, isolated-source, device, hosted or integrated
acceptance result.

V1 metadata and settlement orchestration remain behind their original sealed
authorities. No schema, limit, file mutation, funding or provider change is
introduced. Next port acquisition through a shared profiled transaction core,
with exact reservation acknowledgement before loading and separate post-writer
settlement. Native preparation/receiving, lifecycle and Capture/Auth
integration, RUX recovery, integrated acceptance, deletion/export and redesign
remain open. Activation disabled, PR116 frozen, Supabase deployment hold active
and AWS unapproved.

## October 19 — populated V2 opener locally verified

The same registered native owner/repository can now reopen an exact populated V2
profile for scoped inspection. It requires complete original bootstrap receipts,
directory identities, markers, account lease and store fences; missing or
substituted evidence is held without repair or conversion. Paged reads pin both
independent inventory and bootstrap revisions. Pending memberships and retained
consumers anchor reads; unrelated ordinary drafts remain untouched, including
unfinished preparation. This does not admit mutations or prove physical media
availability, and cannot detect wholly unanchored corruption.

The reviewed candidate04 passed 53/53 methods in seven correction suites, with
zero failures, skips or runtime warnings. All 2,847 source/project hashes and
candidate hashes stayed unchanged. Evidence:
`.artifacts/native-app-dispatch-20261019/focused04-result.json`, XCResult
`a6339e010414431d8a8ac61bc54848c1`; candidate SHA256
`b73e7822fb807c6384246bf35354fb3f8591804942bedefac5aa3836409bef86`. The prior
127/128 result across fifteen suites remains retained with its sole architecture
size failure. Pure bootstrap database checks and DEBUG controls were extracted
without moving sealed capability constructors or changing the 600-line limit.
The eight unchanged passing suites are reused, not reported as a new full run.
This is scoped shared-checkout validation, not isolated-source, full-target,
hosted, device or activation acceptance.

Next close legacy queue flush/soft-delete/quarantine and startup fixture reset
against native ownership before adding same-owner V2 writes/preparation and
atomic inert receiving. A private operation audit witness must preserve both
header revisions, serialized writes and exact post-save readback; avoid
synchronous uncapped retained-library scans at every save. Native
result/cleanup, Capture/Auth composition, RUX-1–RUX-6 and integrated media
acceptance remain open, followed by version deletion/export and redesign.
Activation disabled, PR116 frozen, deployment hold active, AWS unapproved and
numeric limits unchanged.

## October 19 — native V2 initialization locally verified

The existing registered owner/repository now initializes and exactly reopens an
empty V2 app-container profile. A create-only intent, five directory/parent
progress receipts and final identity receipt precede ownership markers and one
atomic inventory/bootstrap save. Interrupted or substituted evidence is held
without adoption or repair; ordinary drafts are preserved. Directory URL
semantics are explicit before and after creation, and locked descriptors
transfer without releasing their locks.

The independently and IC-1 reviewed candidate05 passed all 64 methods in eight
focused suites, with zero failures, skips or Xcode runtime warnings. All 2,844
source/project hashes and candidate hashes stayed unchanged. Evidence:
`.artifacts/native-app-bootstrap-20261019/focused05-result.json`, XCResult
`e5608cd4eea047e8a54ff8355d79bc96`; candidate SHA256
`c72cf5d0e2f6745ca564a7e259f4ec8d61e84dec795d44ef75a19b5e37d9e9cb`. The
compile-before-tests failure in focused03 and the 60/64 focused04 result remain
retained. Corrections added explicit actor isolation to the test fixture and
explicit directory URL semantics at locked descriptor handoff; identity checks
were preserved. This is focused shared-checkout verification, not full-target,
isolated-source, device, hosted or activation acceptance.

Continue the same-owner populated V2 opener and scoped write/preparation leaves,
then atomic freeze/consumer/queue/job/event local receiving admission. Local
receiving stays non-executable and does not mutate funding or invoke AI. Native
result/cleanup transitions, Capture/Auth composition, RUX-1–RUX-6 and integrated
media acceptance remain open before version deletion/export and redesign.
Activation disabled, PR116 frozen, deployment hold active, AWS unapproved and
numeric limits unchanged.

## October 19 — scoped native inspection locally verified

The existing registered native owner and repository now support inactive,
read-only inspection of an exact existing app-container profile. Missing roots,
bindings, backup exclusion, namespaces or fence fail closed without repair or
conversion. Inventory-anchored joins, shared originals, pending membership and
retained receiving facts are validated; ordinary unanchored app data is
untouched. Account drain retains the owner and fences until inspection actually
returns.

The independently and IC-1 reviewed candidate01 passed all 126 methods in
fifteen focused suites, with no failures, skips or Xcode runtime warnings. All
2,842 source/project hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-scoped-inspection-20261019/focused01-result.json`, XCResult
`61a5c783bea541d492fd1de25370c299`; candidate SHA256
`7425151624d927ebf2af35269ec8d4be94c2dccab36be7f054a5cc8e0e3e12a8`. This is
focused shared-checkout validation, not full-target, isolated-source, device,
hosted or activation acceptance. Paged reads do not establish bounded
whole-library latency or memory, detection of wholly unanchored corruption, or
physical file availability.

Continue the reviewed same-owner V2 initialization design: durable intent before
root creation, a final receipt binding exact directory identities, create-only
markers and an atomic inventory/bootstrap pair. V1 stays read-only. Profile
control metadata uses existing codec and free-space limits without charging a
user's package or adding a retained-library cap. Scoped write leaves and atomic
freeze/consumer/queue/job/event admission, retained transitions, Capture/Auth
and RUX-1–RUX-6 remain required before integrated acceptance. Replacement
remains a separate gated follow-up after deletion/export and redesign.
Activation remains disabled, PR116 frozen, deployment hold active, AWS
unapproved and limits unchanged.

## October 19 — native owner capabilities locally verified

The registered native owner and repository now have separate sealed dispatch and
settlement capabilities. Ordinary work requires the current account lease and
active operation. Recovery can only reconcile its exact saved acquisition after
the writer returns; missing evidence preserves the file, reservation and owner
fence without replaying the loader. No additional owner, container, activation
path, persisted format or numeric limit was introduced.

The exact reviewed candidate02 passed all 112 methods in eleven focused suites,
with zero failures, skips or Xcode runtime warnings. All 2,838 source/project
hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-owner-capabilities-20261019/focused02-result.json`, XCResult
`49eaa7c7223f49bfa27d2fd12a7c2fbe`; candidate02 SHA256
`72e4306e15e96026a0bf543a4a976379f7d44d671c6d5b7ecbb845e6c862a8ea`. Candidate01
was held before execution for a throwing test expression; candidate02 corrected
that expression without a runtime delta. The prior complete-target legacy
partition evidence and focused correction remain historical; this run was
focused shared-checkout validation, not a complete-target rerun,
isolated-source, device, hosted or activation acceptance.

Continue with the same repository and owner for strict scoped inspection of an
existing app-container profile, then native receiving admission, retained
transitions/cleanup and Capture/Auth integration. Scoped inspection must verify
pre-existing bindings, reject profile conversion and mutations, and audit only
inventory-anchored records with exact joins. It cannot claim detection of fully
unanchored corruption or physical availability. The remaining integrated media
acceptance, version actions and redesign remain required. PR116 stays frozen;
activation disabled, deployment hold active and AWS unapproved.

## October 19 — legacy/native ownership boundary locally verified

The existing queue, job reset, deletion, funding and background writers now
refuse native receiving ownership, reserved markers and ambiguous metadata.
Fresh ownership is checked across suspension points; background mutations share
the canonical per-scan lock. Missing queues cannot recreate scan-ingestion jobs.
Native admission, result settlement and cleanup still require their dedicated
owner; these guards do not activate them or authorize another AI request.

The full shared-checkout target ran 6,309 methods: 6,307 passed and two failed.
Both failures identified the same silent upload-candidate fetch. The correction
adds private error logging and preserves the early fail-closed return. All 34
methods in the five reviewed corrective suites then passed, with zero skips or
runtime warnings. All 2,836 source/project hashes and candidate hashes remained
unchanged during each run. This is retained full-target evidence plus focused
corrective validation, not a green full-target rerun. Earlier compiler and
assertion failures remain retained.

Evidence: `.artifacts/native-legacy-partition-20261019/full06-result.json`
(XCResult `a000c3584a3a49a5aec166ce1a8d19f8`) and `focused07-result.json`
(XCResult `3576b46a2905490e825b286e86b1da16`). Candidate07 SHA256:
`a856e1dd339a1a13f57d98cc387bb90ca5bf735f0e3ba60a6e4c3adaa83277d4`. Independent
and IC-1 reviews cleared the exact correction and execution scope. This is local
shared-checkout validation, not isolated-source, device, hosted or activation
acceptance.

Continue with the same registered native owner, scoped app-container validation,
atomic receiving admission, retained transitions/cleanup and Capture/Auth
composition, then integrated media acceptance and approved version actions and
redesign. The scoped audit must validate inventory-anchored rows and exact
joins; it must not claim detection of completely unanchored corruption or
physical availability. Qualification behavior and limits remain unchanged.
Activation stays disabled, PR116 frozen, the deployment hold active and AWS
unapproved. No routine proceed prompt is required.

## October 19 — receiving validation committed; legacy guards in review

Native receiving fact validation is committed locally as `7d1c455d7`, after
independent and IC-1 review and the 40-method focused pass recorded below. The
next implementation partitions legacy queue/job/deletion/funding helpers from
native receiving ownership. It is not yet runtime-qualified. The canonical
helper contract is in the
[offline pipeline](../backend-and-data/01-offline-sync-pipeline.md#native-receiving-ownership-and-legacy-helpers).
Typed native admission, retained transitions, cleanup and Capture/Auth
composition remain next; then integrated acceptance and the approved version
actions/redesign. Activation stays disabled, PR116 frozen, deployment hold
active, AWS unapproved and limits unchanged.

## October 18 — native receiving immutable facts verified locally

The composition/freeze milestone is committed locally as `06cc8c9cf`; its
complete-target evidence remains below. The reviewed local implementation
introduces `nativeReceivingV1`, a distinct canonical receiving assertion
containing exact `nativeFreezeV3` bytes, historical membership bytes,
binding/queue/observation identity and execution kind/generation. A
domain-separated digest binds all of these facts. Existing consumer V1 and
legacy authority retain their meanings.

Pending readback requires the actual matching membership row. Retained readback
requires its absence and exactly one package revision beyond freeze for the tier
promotion. Later ownership transfer does not alter the frozen package. Current
original reverse references and derivative joins are checked separately from
historical membership; no membership row is fabricated and no physical-file
availability is inferred. The receiving readback cap includes the context, live
membership and receiving payload. It does not replace full admission accounting
for acquisition receipts, cleanup projections and result headroom. Canonical
lowercase UUID queue/observation identities apply to fresh native receiving
only; legacy V1 identities are unchanged. Qualification remains closed to
receiving rows.

This candidate is read-only fact validation, with synthetic receiving fixtures.
It does not implement or accept atomic queue admission, promotion, terminal
cleanup, executor use or Capture/Auth composition. Those remain next under the
single-session agreement, followed by integrated media acceptance and the
approved version actions/redesign. Mutable routing still requires a typed
queue/job/result transition witness; the immutable digest alone cannot authorize
a transfer.

The exact reviewed candidate02 passed all 40 methods in five focused suites,
with zero failures, skips or Xcode runtime warnings. All 2,834 source/project
hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-receiving-20261018/focused02-result.json`, XCResult
`e816a251145443f587fb021b7ae83c81`; candidate02 SHA256
`446c4646600d58d2e8f7d90ad00642a29e3b5b792254c2e25a31b21354ddd613`. The failed
focused01 test-helper compilation is retained. The prior complete 6,286-method
target belongs to the preceding freeze checkpoint; it was not repeated for this
read-only increment. These are shared-checkout local checks, not
isolated-source, device, hosted or activation acceptance.

Next are the reviewed legacy/native queue and funding guards, then typed
admission, retained transitions, cleanup and Capture/Auth integration.
Activation stays disabled, PR116 frozen, deployment hold active, AWS unapproved
and limits unchanged.

## October 18 — two-original composition and native freeze verified locally

The combined composition/freeze candidate passed the complete `merianTests`
target: 6,286 methods, 10,130 parameter-expanded executions, zero failures, zero
skips and zero Xcode runtime warnings. All 2,831 source/project hashes and all
candidate hashes stayed unchanged. Focused03 also passed all 30 expected
methods, including all 14 freeze methods. This is shared-checkout local
evidence, not isolated-source, device, hosted or activation acceptance.

Exact source candidate03:
`e619e3985dde6aab1f4ac835eb0cf2518f0dfef5aa3eed057dcc3b5a80711d26`. Evidence:
`.artifacts/native-freeze-20261018/full03-result.json` and retained XCResult
`2b1fbc3d398a4ae38f417d523c4a55e9`. Independent and IC-1 reviews cleared this
exact source and execution scope before the runs. The earlier multipair
compiler/assertion failures remain in `.artifacts/native-multipair-20261018/`;
corrected focused05 and the complete current target passed. Earlier dated
entries below remain historical evidence.

The native owner now supports two distinct prepared originals and a terminal
`nativeFreezeV3` save binding their explicit order, immutable supporting bytes,
previous envelope/membership hashes and exact revision transition. Original,
AI-input and display identities stay separate. Frozen packages permit
independent new drafts while rejecting metadata or pair retirement changes to
the frozen package. Exact saved acknowledgement is recoverable without new
preparation; it does not promise current physical availability. Current file
identity and hash verification remain mandatory before new use. Historical V2
codecs retain their prior meaning. Freeze creates no consumer, queue or
inference authority.

Next is native receiving ownership and Capture/Auth integration. The reviewed
composition uses the existing app container and one native session/fence, with
one account-work lease per operation and registration before opening awaits. A
failed drain remains sealed. Admission must save freeze, consumer, queue,
deterministic job and event together; legacy enqueue/job-reset/deletion helpers
cannot provide this transaction. Retained consumers preserve exact historical
membership bytes, while current references and file availability are checked
independently. Reanalysis shares into a fresh pending package; existing retained
versions remain immutable. Retirement precedes drain and last-reference cleanup.
The detailed read-only review map is
`.artifacts/native-freeze-20261018/receiving-integration-map.json`.

Integrated photo/audio/video acceptance, individual-version deletion and exact
original export, then the approved Identification/History redesign remain
required in that order. The capture-tools visual refactor remains separately
owned. Activation is disabled, PR116 is frozen, the deployment hold is active,
AWS is unapproved and numeric limits are unchanged. Local work continues without
routine proceed prompts; no push, merge, deployment or hosted test is
authorized.

## October 18 — native two-original composition candidate

Paired-file recovery/retirement was committed locally as `0b38d560e`; its
passing full-target evidence and two disclosed test-fixture QoS warnings remain
below. The next candidate supports two distinct originals with one ready
derivative pair each. Recovery and retirement select an explicit pair; ambiguous
package-only selection fails. The first pair's immutable intent, work facts,
file identities, published revision and bytes survive preparing, abandoning or
removing the second. Only one preparation attempt or unfinished pair may own
processing at a time.

Original acquisition may follow a ready pair. Admission counts original
references against the existing two-original cap, while the complete graph
retains its six reference bound. Package phase reflects active preparation,
unfinished pairs or outstanding original acquisition; a ready survivor does not
hide held work. Acquisition and preparation exclude each other in both
directions. Fresh metadata, sharing, original removal and ready-pair retirement
cannot mutate unfinished work; exact recovery remains available. Prepared
originals require explicit pair retirement before original removal.

Accounting charges all ready-pair cleanup projections and each physical
allocation and logical reference once, plus the one active reservation. Full
encoded metadata must fit the unchanged allowance before processing or file
ownership. Drafts and survivors remain intact on capacity failure. No schema,
numeric limit, activation, legacy reader or provider-dispatch authority changes.
Membership rebuilding uses a narrow ready-pair proof only during transition;
complete aggregate validation and exact readback still precede successful
saves/results.

Evidence: `.artifacts/native-multipair-20261018/`. Source parsing, generation
and project validation are complete; exact independent/IC-1 review and focused
runtime qualification are pending. Tests cover late acquisition, two-ready
reopening, second-pair interruption/retirement, held acquisition cleanup,
active-work exclusion, capacity denial and cross-pair identity collisions. This
entry does not claim runtime acceptance. Freeze, receiving consumers, Capture
composition, integrated acceptance, version deletion/export and the approved
redesign remain next. Activation disabled, PR116 frozen, deployment hold active,
AWS unapproved; local work continues without routine proceed prompts.

## October 18 — native paired files locally verified

The inactive native owner now reserves both outputs atomically, creates
exclusive partials, saves their descriptors before writing, completes exact
bytes and publishes the pair. Recovery may finish only the saved bytes;
reopening inspects without repeating preparation. Original bytes and supporting
text remain intact. One pair is supported at this checkpoint. Multi-original
composition, freeze, receiving consumers and live Capture integration remain
pending.

Retirement saves one canonical closure on the AI lease and an exact digest
marker on its display sibling. It binds the prior state, immutable intent,
envelope, prior/successor membership, writer epoch, retirement identity and both
file identities. Both liabilities remain until both absence proofs pass in one
fenced transaction. Cleanup retries cannot adopt replacement bytes or delete
originals. Maximum closure/state encodings stay reserved within the existing
metadata allowance; retirement releases processing scratch while retaining
unfinished output reservations. No numeric limits or activation gates changed.

Evidence: `.artifacts/native-pair-files-20261018/`. Candidate06
(`497f4d194e1469c637ec08f7cc812506a79c470cbe4d0e96965dd2dfb33753bc`) passed 35
focused methods plus two explicitly verified method selectors. Full06 passed all
6,264 methods (10,090 executions), with no failures or skips. All 2,826
source/project hashes and all candidate hashes stayed unchanged. The result is
`a414c6ef15384c46ad15eb124b9f83ce`. Two runtime priority-inversion warnings were
recorded in unchanged `TestSupport/VideoAudioFixture.swift:163`, both in
`ObservationRetainedVideoTests.nonSquareTransformedDurationBoundaries(audio:)`;
these are retained in `full06-summary.json`, `full06-object.json` and
`full06-result.json`. This is a passing shared-checkout test result with those
fixture warnings, not a warning-free or isolated-source claim.

Exact independent and IC-1 reviews cleared candidate06 and the execution
packets. XcodeGen, project validation, parse, scoped diff checks and Markdown
formatting passed. Failed compiler/runtime candidates and the selector shell
failure remain retained. Full05 passed 6,262 methods and failed only the two
600-line architecture guards; candidate06 moved pure admission checks and
descriptor-relative empty traversal to existing helpers while retaining owner
identity checks, the root lock, namespace unlink and root fsync. No allowlist or
limit was weakened. Full05 result `ca3232477f1a40ecadbb3084b9fd4904` remains
historical failed evidence.

Continue automatically through the reviewed local commit, native two-original
composition and freeze, receiving ownership, integrated acceptance, individual
version deletion/source export and the approved redesign. The next composition
must preserve ready survivors, select pairs explicitly, account for all paired
metadata, and exclude new acquisition/preparation in both directions while work
is unfinished. Exact replay and recovery remain available. Activation disabled,
PR116 frozen, deployment hold active, AWS unapproved; no external operations or
device installation.

## October 18 — native pair plans locally verified

The inactive native owner now durably transfers an exact preparation attempt
into an immutable output plan, with both child work rows, bounded metadata
reservation, exact save-acknowledgement recovery and explicit no-file
abandonment. Draft text, original bytes and sequence survive abandonment; stale
plans cannot release newer work. Global unfinished-work admission and
bidirectional row audits remain closed to output files and ready/retained pairs.

Candidate03 (`a2e48e0b3e03d115a0c3e9cbfa065674b3fc2756a0a20f165b7ccf0effaf3265`)
passed six focused suites: 52 methods, no failures, skips or runtime warnings.
All 2,820 source/project hashes remained unchanged. Exact independent and IC-1
reviews cleared execution. Failed candidate02 is preserved; its duplicate
package registration was corrected by ordering the existing preparation charge
after package registration, with no amount or limit changes. Evidence:
`.artifacts/native-pair-plan-20261018/`, result
`3c71ef9df01c47d0b6609375802deda5`. This is scoped shared-checkout validation.

Continue native paired-file reservation/write/retirement/recovery and ready
publication, then freeze, receiving consumer ownership, live composition and
required acceptance. Version deletion/source export and the approved redesign
remain required afterward. Activation disabled, PR116 frozen, deployment hold
active, AWS unapproved; local work only. No routine proceed approval is needed.

## October 18 — native preparation reservation and worker cleanup locally verified

The inactive native owner now reserves output and metadata capacity before photo
processing, retains an exact V2 attempt, and preserves unfinished work for
explicit recovery. Compact prepared identities avoid recursively retaining old
draft envelopes. The concrete processor uses the existing image pipeline under
the original-file owner; processing results remain in memory until native paired
file publication is implemented. Core focus detection now separately tracks its
visible deadline and actual worker termination, so account transition waits for
actual drain.

The complete gate exposed video cleanup and preview-test readiness races. Video
join/timeout paths now drain children and explicitly discard late owned outputs;
audio extraction retains intermediates across the actual detached result and
cleans them before return. Borrowed originals survive. Explicit lease discard is
idempotent; failed unlink remains nonaccepting and retryable. The preview
fixture now awaits initial player readiness before measuring position. Failed
full12 evidence remains retained; the corrected candidate14 has independent and
IC-1 concurrence.

Candidate14 SHA-256:
`87b6aaefdf1cc93b45d535df5c97a6122ee5c4293f9d6e6cba9e16dcc18d9f26`. Five focused
suites passed 28 methods / 31 executions, then the complete `merianTests` target
passed 6,246 methods / 10,047 executions. Finalized results
`41c54f27b342403fb8a70f999d75cd8a` and `9a4fa521b94c4355936171e7b6a44779` have
zero failures, skips and runtime warnings. All 2,815 source/project hashes
stayed unchanged during verification. Compiler and test-fixture diagnostics
remain preserved in logs; this is shared checkout validation, not
isolated-source or live-composition acceptance.

Native paired-file admission/recovery/freeze, receiving consumer ownership,
Capture/Auth/queue/history composition and integrated acceptance remain open.
The reviewed next transition design requires exact state witnesses,
counter-aware retirement and identity-bound cleanup. Pending graph bounds must
not cap the retained library: audit all retained pages and both directions of
every join. No fresh identification or reanalysis may proceed without actual
photo, audio or video; historical admitted recovery semantics remain unchanged.
After required acceptance, continue individual-version deletion/source export
and the approved redesign. Separate capture visual ownership is unchanged.

Evidence: `.artifacts/native-preparation-integration-20261018/`. Activation
disabled, PR116 frozen, deployment hold active, AWS unapproved. Local work only;
no push or external action. Earlier entries are historical.

## October 18 — native explicit pending abandonment locally verified

The next inactive native integration adds exact-request abandonment of reserved
or held acquisitions. Reopening, inspection and generic recovery preserve raw
unfinished files and their full reservation; they never infer abandonment,
repeat a loader or invoke AI. Explicit abandonment requires the registered
owner's serial operation and exclusive file fences after prior work has drained.
It saves a strict, bounded cleanup proof before file work. The proof binds the
original request fingerprint, namespace and optional parent identities, and the
exact absent, partial or final file descriptor. A current-lifetime sealed
capability permits only matching unlink, directory sync and absence recheck.

Saved abandonment is recoverable across process epochs. Changed files or parents
block recovery; missing rows, age or cancellation do not prove release. Atomic
release removes only the pending work/allocation/lease, records the existing
terminal receipt and exact membership successor, and preserves other originals,
supporting text and the empty draft. Recovery queries one fresh saved intent at
a time. Proof bytes consume the existing result-encoding reservation; no schema
or numeric limit changes. Legacy validators remain closed to this native-only
substate. Typed lifecycle orchestration and sealed disposal values move
together; raw admission, controller and native authority constructors stay
co-located, with private file descriptors retained by the original file owner.

Independent and IC-1 review cleared the implementation and exact execution
packets. The first focused run exposed a test expectation error: cancellation
leaves pending settlement closed until uncancelled drain finishes the held
transition. Candidate02 corrected only that test to require drain and reopen;
the runtime was unchanged. The failed result and both packet-review corrections
remain retained. Thirteen focused suites passed 116 methods / 289 executions;
the complete native target passed 6,215 methods / 10,005 executions. Both
results have zero failures, skips and runtime warnings. Existing compile
warnings in unchanged code remain in the logs.

Finalized results are `5db93abacc964e77b34198a6d46bd86a` and
`adf9c90bd2414d6b8ceb0e53e2df5536`. Candidate sources and all 102 unrelated
baseline states remained unchanged through both runs. Each run removed only its
100 emitted synthetic fixture directories after host exit. This is local
shared-checkout qualification of inactive native sharing/removal/recovery; final
live Capture/Auth/queue/history composition and end-to-end acceptance remain
pending. Separate capture visual ownership stays unchanged. Evidence:
`.artifacts/shared-media-native-pending-cleanup-20261018/`. Activation is
disabled, PR116 frozen, Supabase deployment hold active and AWS unapproved.
Earlier entries are historical.

## October 18 — native sharing, removal and retirement recovery locally verified

The inactive registered native owner now supports sharing into a new
same-account pending draft, reference removal, and completed-original retirement
recovery. Sharing updates paired references, pending membership and the physical
reference counter in one save without copying bytes or changing the source
membership. Existing destinations are rejected. Both counter value and revision
are frozen with the inventory and source package/reference preconditions.

Removal preserves supporting text and stable original ordinals. Removing the
last photo leaves an empty pending draft; fresh identification still requires
media. Explicit whole-draft discard remains separate. Nonfinal removal preserves
survivor bytes. Final removal saves the existing V2 retirement and keeps its
physical charge until exact descriptor-bound unlink, directory sync and absence
proof permit atomic accounting release. Lost acknowledgements use exact saved
state. Later mutation or missing rows alone cannot prove logical success or
recreate references. Dedicated recovery accepts saved retirement while ordinary
mutations remain blocked. Reserved/held acquisition cleanup requires its
separate writer-closure proof and remains held; recovery never repeats a loader
or AI call.

The registered controller, raw admission and sealed capability constructors stay
co-located. Read-only eligibility and namespace inspection move to typed
helpers. No active schema, numeric limit, provider or live composition changes.
Independent and IC-1 reviews cleared exact candidate02 after correcting two
review findings: lost-acknowledgement checks now require the exact canonical
membership successor, and recovery queries one fresh retirement at a time until
none remain. Candidate01 is retained as unrun review-hold evidence.

Twelve focused suites passed 103 methods / 254 executions; the complete native
target passed 6,202 methods / 9,970 executions. Both finalized results report
zero failures, skips and runtime warnings: `1da84328952a472dba6e9657963b5939`
and `22ecb952812e49c6b14fe92696a17ae4`. Source and all 102 unrelated baseline
hashes remained unchanged. Each run removed only its 65 emitted synthetic
fixture directories after the compiler and test host exited.

This is shared-checkout native qualification, not isolated-source or live
Capture/Auth/queue/history acceptance. Continue the independently and IC-1
reviewed explicit abandonment/cleanup of unfinished native acquisitions: raw
reserved/held items stay retained and charged until an exact explicit
abandonment saves cleanup intent; cold recovery may finish only saved intent.
Draft text and other originals remain intact. Final composition remains pending.
Evidence: `.artifacts/shared-media-native-lifecycle-20261018/`. Activation
disabled, PR116 frozen, Supabase deployment hold active, AWS unapproved. Earlier
entries retain historical evidence.

## October 18 — native draft metadata locally verified

The inactive registered native owner now prepares metadata-only draft edits.
Requests bind the inventory, account, package/draft generation, prior revisions,
exact prior envelope and unchanged membership tuple. Desired validated envelope
bytes are produced once and retained across retries. Inventory and package
advance once; membership bytes and revision do not change. Exact post-save
readback precedes old-state CAS; later edits are stale even when their text
matches. Fresh ownership and exact old-state checks run immediately before save.

Presentation entries must resolve to live same-package/same-owner originals and
their paired shared references. Existing geometry/duplicate bounds remain. The
native graph audit now validates these entries instead of rejecting all nonempty
presentation. Metadata, membership and receipt headroom share the unchanged
budget; positive envelope growth adds free-space demand, with no advance credit
for shrinkage. Readback queries return only values under repository-minted
authority; contexts, constructors, account drain and file authority remain
sealed.

Independent review found and corrected repeated full-graph auditing in the
extracted paged reader before execution. A separate sealed inspection authority
now checks the expected header/account lease per page; each receipt must belong
to the current owner. Mutation authority remains unchanged. A 257-receipt test
proves one three-page snapshot performs only its two boundary full audits.

Independent and IC-1 review cleared exact candidate04. Ten focused suites passed
81 methods / 224 executions; the complete native target passed 6,187 methods /
9,947 executions, with zero failures or skips and no recorded runtime warnings.
Finalized results are `605c37a7e42b48c5a94c65aae3918b8a` and
`21e915d769f845deb0298fc328b82024`. Source and all 102 unrelated baseline hashes
remained unchanged. Each run removed only its 42 emitted synthetic fixture
directories after the test host exited. Earlier review holds remain retained.

No saved submission, file, provider, sharing, deletion, schema or numeric limit
changes. Evidence: `.artifacts/shared-media-native-metadata-20261017/`. This is
shared-checkout native qualification, not isolated-source or live
Capture/Auth/queue/history acceptance. Native sharing/removal/recovery and final
composition remain pending in the documented order. Activation stays disabled,
PR116 frozen, Supabase hold active and AWS unapproved. Earlier entries retain
historical evidence.

## October 17 — native atomic acquisition locally verified

The inactive registered fixture controller now prepares atomic original
reservation, completion and held settlement. A sealed capability minted only by
the fenced repository validates current account dispatch and store/root identity
immediately before the sole save. Completion consumes an unforgeable file
inspection, with separate exact byte identity and full descriptor facts. Private
transaction contexts retain the pristine full-graph audit, assert exact
changed-row postconditions, and jointly save receipt, package, membership,
allocation, lease and reference accounting. Hold preserves membership bytes and
revision and the full reservation. Any unresolved acquisition or retirement
intentionally blocks fresh acquisition until a separately qualified recovery
owner resolves it; no capacity is released here.

Exact completed replay returns the original saved result. Reserved/held cold
requests cannot restart a loader. Uncertain save/readback can only reconcile the
same operation. Account shutdown waits for actual callback/file termination.
Verified durable held settlement preserves liability while permitting process
fence release; unknown settlement keeps fences and admission sealed. An explicit
failed-drain retry may reconcile the exact saved state without dispatching work.

Independent and IC-1 review cleared exact candidate08. The nine focused suites
passed 67 methods / 199 executions; the complete native target then passed 6,173
methods / 9,922 executions, with zero failures or skips. Finalized results are
`4349aedd71094fbe98e7ac9ae653040e` and `48036d6b2b7f41f58da8a6fcd30f714c`. Exact
candidate and 102 unrelated baseline hashes stayed unchanged. Each run removed
only its 17 emitted synthetic fixture directories after the test host exited.
Full-target evidence retains Xcode's 600-second simulator-diagnostics collection
timeout and two VideoAudioFixture QoS warnings; neither caused a test failure.

Earlier compiler failures and the interrupted candidate06 run are retained. The
user explicitly authorized stopping that failed, stuck run. Its partial result
is unfinalized and contributes no passing coverage. The correction reuses the
single captured draft encoding, wakes a test gate when acquisition fails before
loading, and avoids unlinking live SwiftData databases. The failure regression
and previously stuck account-drain case pass in both corrected runs.

Evidence: `.artifacts/shared-media-native-acquisition-owner-20261017/`. This is
shared-checkout native qualification; isolated-source acceptance and live
Capture/Auth/queue/history composition remain pending. Continue native draft
metadata, sharing/removal/recovery and final composition in the documented
order. This does not close photo-storage or whole-feature acceptance. Activation
stays disabled, PR116 frozen, deployment hold active, AWS unapproved and all
limits unchanged. Earlier entries retain their historical scope.

## October 17 — registered native original admission locally verified

The inactive Debug fixture controller now registers its mandatory account drain
before asynchronous admission. It holds the existing store/root/namespace
fences, rejects overlapping opens and waits for actual audit termination on
cancellation. A dedicated I/O actor verifies completed bytes and saved directory
identities; retiring absence requires the exact saved directories and no final
or partial. The final complete namespace stream rejects unjoined or replaced
leaves after awaited reverse checks. This is fenced cooperative-owner
validation, not an atomic snapshot against arbitrary external filesystem
mutation.

The original empty-only factory keeps its restrictions. The new read-only
controller can inspect complete native original graphs, including retained
sharing after physical-origin deletion; reserved/held/retiring work remains
recovery-only. It grants no mutation, loader restart or cleanup capability. Live
Auth installation, atomic acquisition transitions, complete-target and
isolated-source qualification remain pending. Independent and IC-1 review
cleared candidate03 after correcting account binding and lease-release ordering
before execution. Its eight-suite run passed 55 methods / 181 executions and
failed one retained-sharing fixture whose draft identity differed from its
package identity. Candidate04 changed only that fixture; the admission suite
then passed all 9 methods / 35 executions with zero failures/skips. The other
seven passing suites are reused unchanged: composite focused coverage is 56
methods / 182 executions, not a clean eight-suite rerun.

Failed XCResult `93c06d249aa54786a39a1ccdeb6afe4a` and passing XCResult
`a8a1d4f8694f4a8da97db8f6bbff2c80` are retained. Xcode's failed-run simulator
diagnostic collection timed out after 600 seconds; no managed build was
cancelled or duplicated. Candidate and 102 unrelated baseline hashes remained
unchanged through each run. Project and Markdown gates passed. Evidence:
`.artifacts/shared-media-native-admission-20261017/`. Continue the
already-reviewed atomic reserve/commit/held integration, then full native and
isolated-source acceptance before live queue/history composition. Activation
stays disabled, PR116 frozen, Supabase hold active, AWS unapproved and existing
limits unchanged. Earlier entries below retain historical scope.

> October 17 inspection continuation: native namespace observations now await
> their owning actor while retaining and rechecking ancestor/leaf descriptors.
> Cancellation cannot detach a suspended observer. Independent/IC-1-reviewed
> candidate02 passed six focused suites (42 methods / 87 executions, no
> failures/skips), after retaining candidate01's pre-test SwiftLint failure.
> Evidence: `.artifacts/shared-media-native-async-inspection-20261017/`. This is
> scoped shared-checkout qualification only. Native admission remains
> empty-only; the registered admission controller, complete file audit, atomic
> transitions and full-target acceptance remain pending. Activation stays
> disabled, PR116 frozen, Supabase hold active, AWS unapproved and limits
> unchanged.

## October 17 — native acquisition graph and metadata locally verified

The inactive native acquisition prerequisite now checks receipt/work/asset/lease
and reference joins in both directions, including orphan and terminal conflicts.
Surviving original references preserve submitted provenance; completed results
remain immutable after distinct sharing references replace the original owner.
Only the exact native inventory mode, ready phase and empty cursor qualify.

Pending accounting pages physical-origin receipt charges and projects every
combination of the existing two originals completing. Receipt result headroom
and membership growth remain inside the existing 1 MiB metadata allowance and
contribute to outstanding free-space reservations. Retained-library occupancy
has no new count limit and does not consume pending slots.

Independent and IC-1 review cleared candidate02 after source-review corrections
before execution. All seven focused suites passed: 54 test methods, 215
parameterized executions, zero failures/skips. Exact source and 102 unrelated
baseline hashes stayed unchanged. Project and Markdown checks passed. Evidence:
`.artifacts/shared-media-native-transactions-20261017/`; XCResult
`.artifacts/local-ios/2e21d6f843a74d608d71f0e5a2ecd579.xcresult`. This is scoped
shared-checkout qualification, not complete-owner or isolated-source acceptance.

The helpers grant no admission or file authority. The constructor stays
empty-only until complete off-main-actor namespace/hash qualification and the
closed atomic reserve/commit controller qualify. Continue that integration, then
the complete native target and atomic queue/history ownership. Activation
remains disabled, PR116 frozen, the Supabase hold active, AWS unapproved and
existing limits unchanged. Later version-actions/redesign remain required.

## October 17 — native photo namespace traversal locally verified

The native read-only traversal now streams fixed-depth canonical directories and
original/partial leaves without a retained-library count cap or whole-library
token set. It holds ancestor descriptors, checks named/opened identity around
recursion and observers, rejects partial/final collisions and unsafe entries,
and distinguishes cancellation and enumeration errors from success. Final files
must be positive; empty partials remain structural recovery observations only.
Legacy inventory limits and all product limits are unchanged.

Independent and IC-1 review cleared candidate02 after correcting zero-final
rejection before execution. All six focused suites passed: 41 test methods, 84
parameterized executions, zero failures/skips. Exact source and 102 unrelated
baseline hashes remained unchanged. Project and Markdown checks passed.
Evidence: `.artifacts/shared-media-native-namespace-20261017/`; result
`.artifacts/local-ios/a72483178e4b48bd890a42ebcc799079.xcresult`. This is
focused shared-checkout evidence, not full-target or isolated-source
qualification.

The traversal is not a globally atomic filesystem snapshot. The native owner
must exclude cooperating writers, join exact receipt/graph ownership, reverse-
audit missing files and revalidate bytes before use. No callback may commit
partial authority. Native admission remains empty-only. Continue the reviewed
closed acquisition transaction integration, then atomic queue/history ownership
and the later approved version-actions/redesign. Activation remains disabled,
PR116 frozen, Supabase hold active and AWS unapproved; no external action
occurred.

## October 17 — native acquisition receipt codec locally qualified

The V64 receipt now has a closed, versioned codec for immutable picker/camera
original requests, exact completion results, held work and terminal replay
witnesses. Cold recovery starts from the persisted row, including terminal rows
that retain no request. A separate expected-intent check rejects substitutions.
Canonical encodings reject unknown or duplicate fields and preserve historical
UTI values without asking the current OS to decode media. The internal 8 KiB
completion headroom stays within the existing 1 MiB metadata allowance.

Independent and IC-1 review cleared the exact candidates. The initial five-suite
run passed 36 test methods and failed one because its changed-size fixture used
the original value. The corrected codec-only run passed all 13 methods with zero
failures or skips; the other four unchanged suites remain passing. Failed result
`37907a7d09fc47de8be932c74fbd17e6.xcresult` and passing correction
`1ada1289441f4b368d313c16da2c28d1.xcresult` remain under
`.artifacts/local-ios/`. Candidate and 102 unrelated baseline hashes stayed
unchanged during execution. Project and Markdown validation passed. This is
composite local shared-checkout codec evidence, not an integrated native owner,
a fresh full-target run or isolated-source acceptance. Exact candidates, review
and results: `.artifacts/shared-media-acquisition-codec-20261017/`.

Continue native reserve/commit, complete streaming namespace and reverse-receipt
audits, combined package metadata accounting, and atomic queue/history
ownership. The codec alone grants no writer restart, file, cleanup or admission
capability. Activation remains disabled, PR116 frozen, Supabase deployment hold
active, AWS unapproved and limits unchanged. Later version-actions/redesign
remain required.

## October 17 — V64 acquisition receipt foundation validated locally

The outgoing V63 schema was frozen and compiled before the additive V64
acquisition receipt model was introduced. The receipt stores immutable request
identity and supports full result retention and a minimal terminal replay
witness. Migration preserves existing native ownership and historical text-only
records and creates no receipts. Legacy and empty-native fixture owners reject
all receipt rows; the model grants no writer, media, cleanup or live authority.

Independent and IC-1 review cleared the exact candidates and the correction.
Focused migration/recovery/storage verification passed 140 tests. The complete
native run passed 6,118 and failed two architecture inventories because the
storage repository reached 601 lines. Consolidating its identical guards in the
existing lookup owner preserved behavior and reduced it to 587 lines; all 43
tests in the five affected storage/purge/architecture suites then passed. No
tests were skipped. These are composite shared-checkout results, not a clean
full run of the corrected candidate or isolated-source acceptance. Static
migration, project, CI-tooling and Markdown checks passed. Candidate and the 102
hashed unrelated baseline paths remained unchanged during validation. Evidence:
`.artifacts/shared-media-native-receipt-20261017/`; failed full result
`bbf6648481124cc0a687569f711c3263.xcresult` and correction result
`dd3c0c6e22674ef79185224f29477ca8.xcresult` remain under
`.artifacts/local-ios/`.

Continue the closed receipt codec and native reserve/commit owner, full
namespace and reverse-receipt audits, and atomic queue/history ownership. The
codec design preserves exact bounded ImageIO UTI values without later OS decoder
dependence; completion headroom and projected memberships share the existing 1
MiB metadata allowance. Held work cannot restart or acquire cleanup authority
from a receipt. The schema foundation does not close native integration or later
approved version-actions/redesign acceptance. Activation remains disabled, PR116
frozen, Supabase deployment hold active, AWS unapproved and product limits
unchanged. No push, merge, deployment or hosted action occurred.

## October 17 — native empty-store owner and exact namespace reopen verified

The Debug-only native fixture owner now admits only pristine or exactly reopened
empty stores. It fences eligibility and binding work, saves the native inventory
and bootstrap together, and rejects partial initialization, mismatched metadata,
legacy graph adoption and real Documents/Application Support roots, including
resolved aliases. Shared photo and inbox reopen no longer recreate missing
namespaces; standalone photo creation remains unchanged. Held directory
replacements fail closed. This empty-only owner grants no media mutation,
cleanup or live composition authority; cold empty-directory inode continuity is
not claimed.

Independent and IC-1 review cleared candidate02. All four focused suites passed
65 tests; the complete native target passed 6,118 tests with zero failures or
skips. Candidate and unrelated baseline hashes stayed unchanged. Evidence:
`.artifacts/shared-media-native-owner-20261017/`; full result
`.artifacts/local-ios/5cf61ea06144431d842a5d1e4332904f.xcresult`. The first
unexecuted candidate's resolved-path admission gap and its correction remain
recorded. This is shared-checkout validation, not isolated-source or live
acceptance.

Continue the closed native reserve/commit owner and complete namespace audit.
Review found that existing P1 reservation rows do not preserve the full
immutable native request. Independent and IC-1 design review concur on an
additive versioned acquisition receipt, exact same-operation recovery, terminal
replay rejection, an explicit partial/final presence matrix and single-save
descriptor-bound absence settlement. The outgoing schema must be frozen and
compiled before the additive model change. Receipt encoding, migration and
transaction implementation remain unqualified; no existing operation is
converted or replayed. Pending accounting limits stay unchanged and retained
physical ownership remains separate.

Activation remains disabled, PR116 frozen, the Supabase deployment hold active
and AWS unapproved. No push, merge, deployment, hosted action or numeric-limit
change occurred. Native queue/history ownership and the later approved
follow-ups remain unfinished.

## October 17 — native original reverse-reference audit locally verified

The read-only original audit checks saved reverse counts independently against
both complete reference directions, including retained packages and missing
physical-origin packages. It rejects orphan or substituted edges, missing
counters, inconsistent owner/generation/lease facts and dirty contexts. Zero
requires positive retirement revision, the exact V2 descriptor byte count and
one final retired pair. The caller must hold an unchanged native store fence;
this snapshot grants no mutation, media or cleanup authority. Pages bound row
materialization, not total database work or measured memory.

Independent and IC-1 review cleared accounting candidate03. Focused coverage
passed 51 tests; the complete native target passed 6,109 tests with zero
failures or skips. Candidate and unrelated baseline hashes stayed unchanged.
Evidence: `.artifacts/shared-media-native-accounting-20261017/`; full result
`.artifacts/local-ios/461182f8231345f1b58f86a6259af1fd.xcresult`. The initial
unexecuted candidate's zero-state gaps and the later paging-offset compilation
failure remain recorded. This is shared-checkout validation, not isolated-source
or live acceptance.

Continue the closed native owner, paired writes, exact memberships, whole-store
and namespace validation, and atomic queue/history ownership. The next private
fixture factory uses distinct native bindings and preserves legacy refusal;
shared reopen must reject missing namespaces without recreating them. These
remain implementation work, not completed native composition. Activation stays
disabled, PR116 frozen, the deployment hold active, AWS unapproved and numeric
limits unchanged. No push, merge, deployment or hosted action occurred.

## October 17 — pending graph and native retirement format locally verified

The bounded pending graph follows logical package references, reservation work,
handoffs and derivative pairs independently of an allocation's physical-origin
package. Exact membership checks reject missing, stale or over-budget saved
assertions. The native-only V2 retirement format binds the stable retirement,
asset/generation, inventory/generation, account and descriptor facts within the
unchanged 512-byte allowance. Qualification V1 remains separate and unchanged.
Neither helper grants mutation, file access, cleanup or provider authority.

Independent and IC-1 review cleared candidate03. Pending-graph focused coverage
passed 40 tests; the codec passed five methods and the separately selected real
filesystem roundtrip/release case passed. The complete native target then passed
6,103 tests with zero failures or skips. Candidate and recorded shared-baseline
hashes remained unchanged. This is shared-checkout validation, not
isolated-source or live acceptance. Evidence:
`.artifacts/shared-media-pending-20261016/`; full result
`.artifacts/local-ios/4e832e68b3c54a8fad056b966735301c.xcresult`. The earlier
actor-isolation compile failure, simulator no-launch failure, omitted-method
coverage gap and shell-selector failure remain retained.

Continue the reviewed closed native accounting operations, paired reference and
count updates, exact pending memberships, complete native audit and atomic
queue/history ownership. A dedicated native validator must preserve legacy
qualification rejection of retained/V2 states. Native composition remains closed
until these owners and their acceptance gates are complete. Activation stays
disabled, PR116 frozen, the deployment hold active, AWS unapproved and numeric
limits unchanged. No push, merge, deployment or hosted action occurred.

## October 16 — V63 consumer ownership foundation locally verified

V63 freezes V62 and adds explicit consumer authority, pending membership,
inventory bootstrap and reverse-reference metadata. Legacy rows retain their
semantics. Canonical, bounded cohort joins bind exact originals, AI inputs,
previews and supporting context; they grant no file, cleanup or provider
authority. Nonempty native metadata blocks the old qualification owners.

Independent and IC-1 review cleared foundation candidate08. The focused run
passed 115 tests with zero failures or skips, including disk migration/cold
reopen, lexical keyset pagination, malformed ownership, exact pending membership
and orphan cleanup barriers. Sources remained unchanged through the run.
Evidence: `.artifacts/shared-media-consumers-20261016/`; result
`.artifacts/local-ios/105372ecfbee4974aef38d9c34da8fae.xcresult`. The complete
native target on candidate09 passed 6,092 tests and failed one stale
purge-inventory assertion, with zero skips and unchanged pinned sources.
Candidate10 added the four new entities to the existing saved/unsaved purge
barrier fixtures without changing runtime code. Independent and IC-1 review
cleared the targeted rerun: all five tests passed with unchanged sources. Reuse
the 6,092 unaffected passes; the failed full result remains failed evidence, not
a clean full rerun. Earlier failures and corrections are retained. This is
shared-checkout qualification, not isolated or live acceptance.

Continue the reviewed pending-membership transaction owner, retained accounting,
atomic queue/result ownership, native composition and remaining acceptance.
Pending slots begin at package creation; retained packages do not consume those
slots. Shared asset release must consider all surviving consumers. New initial
and reanalysis requests still require photo/audio/video media, with optional
supporting text; historical records and admitted recovery retain their meaning.
The later version actions and redesign remain authorized follow-ups. Activation
stays disabled, PR116 frozen, the deployment hold active, AWS unapproved and
numeric limits unchanged. No external action is authorized by this foundation.

## October 16 — durable shared-library cleanup locally validated

The isolated shared inbox owner now has an explicit whole-library purge path. It
saves a versioned, stable reset intent before cancellation, drains its tracked
work, then uses sealed cleanup authority for exact retirement and release.
Restart accepts only the same purge ID through the cleanup constructor. Normal
construction and preparation remain closed. Cleanup orders detached liabilities
and unheld sources before abandoning the remaining handoff, preserving the
unchanged 96 MiB acquisition bound without a new reservation.

Prepared-held envelopes remain immutable. Per-package `purging` is valid only
inside the durable inventory purge. Originals are unlinked after the last local
reference; interrupted release reconciles only saved exact identities.
Completion requires empty shared/P1 graphs and physical namespaces, while
retaining the closed inventory and root bindings. The ordinary liability barrier
stays broad. A typed purge-service seam verifies the same container and terminal
state; legacy P1 namespace presence still blocks ordinary erasure. Reset
projections are deferred until the complete library purge succeeds. No live
composition or automatic reopening is added.

Independent and IC-1 review cleared candidate07. Its purge rerun passed 15
methods / 31 parameterized cases; the complete native target passed 6,081 tests
with zero failures or skips. Source hashes stayed unchanged during both
successful runs. XcodeGen/source membership, Markdown and scoped diff checks
passed. Evidence: `.artifacts/shared-media-purge-20261016/`; full result
`.artifacts/local-ios/1d56d47ebb38427d9d196391e703da42.xcresult`.

Earlier compilation failures and focused03's incorrect lost-ack expectation are
retained. The latter test correction occurred after its compiler/test host had
exited while Xcode still collected diagnostics; the execution-time source pins
and post-execution edit disclosure are retained. No
unchanged-through-finalization claim is made for that failed run. Review also
corrected the legacy namespace bypass and rejected a wrong target before any
destructive work.

This is shared-checkout qualification, not isolated-source or live product
acceptance. Continue native consumer/producer integration, retained accounting,
cloud retention and integrated acceptance. Read-only integration review confirms
atomic freeze/queue/job ownership, version-specific final bindings and separate
pending/retained accounting; no new schema or live composition is claimed here.
Activation remains disabled, PR116 frozen, the deployment hold active, AWS
unapproved and numeric limits unchanged. No push, merge or hosted action
occurred.

## October 16 — shared metadata and local freeze locally validated

L6 uses the same inbox coordinator and fenced store for bounded supporting
metadata and exact local freeze. Positive metadata growth reserves additional
free-space headroom; shrinking adds no reservation. Freeze verifies the entire
saved envelope, ordered originals, both derivative roles and every exact file
identity. Prepared-held packages reject draft mutations. Lost-ack/restart
recovery requires the retained exact request; no server admission or provider
invocation is added.

Independent and IC-1 review cleared candidate03. Eight focused suites passed 109
cases; the complete native target passed 6,066 cases, zero failures or skips.
Source hashes stayed unchanged through both runs. XcodeGen, source membership,
Markdown and scoped diff checks passed. Evidence:
`.artifacts/shared-media-freeze-20261016/`; full result
`.artifacts/local-ios/16c5efaf0b4c484c9393459fa7c298c5.xcresult`. This is local
shared-checkout qualification, not isolated-source or live product acceptance.

Continue durable shared-owner library cleanup, then real producer composition,
cloud retention and integrated acceptance under existing local authorization.
The cleanup contract preserves a closed terminal inventory/root binding and
requires exact physical release before ordinary library deletion. Its agreement
is `.artifacts/shared-media-purge-20261016/agreement.md`; independent/IC-1
concurrence is recorded there. No production composition is enabled.

The approved future cloud-backed LRU direction has no age-only expiry; final
original/preview cache budgets remain undecided. Current numeric limits are
unchanged. Activation remains disabled, PR116 frozen, Supabase hold active and
AWS unapproved. No push, hosted action or deployment occurred.

## October 16 — paired derivative runtime locally validated

L5 now owns paired AI-input/display files through the existing isolated inbox
coordinator, repository, account lease and destination actor. Originals remain
separately owned. Replacement retires the old pair before reserving the new
pair; publication requires both verified completions. Recovery reads saved
complete files only, and cleanup retains charges until both exact file
identities are absent and synchronized. Account validity is rechecked after
normal and lost-ack save returns before further file work or acknowledgement.

Independent and IC-1 review cleared candidate04. Its four focused suites passed
all 44 cases with zero failures/skips. Full01 retained 6,055 passing cases, two
file-size guard failures and no skips; the reviewed lookup extraction fixed both
failures, and the four-suite rerun passed. Unchanged full-run passes are reused;
this is not a claim of a new all-green full-target run. Earlier failed compile,
account-boundary and formatting evidence remains retained. XcodeGen, source
membership, Markdown and scoped diff checks passed. Evidence lives in
`.artifacts/shared-media-derivatives-20261016/`; final focused result is
`.artifacts/local-ios/1fdbde7fd30a480291de5eea21d8788f.xcresult`.

This is scoped shared-checkout qualification, not isolated-source or live
product acceptance. Continue the reviewed L6 metadata/local-freeze agreement
without a new proceed prompt. Live composition, cloud retention and integrated
acceptance remain open, followed by version actions and redesign. Numeric limits
are unchanged; activation disabled, PR116 frozen, Supabase hold active and AWS
unapproved. No hosted action, push or deployment occurred.

## October 16 — derivative schema prerequisite locally validated

L5 uses the existing isolated inbox coordinator for paired AI-input/display
ownership. V61 was frozen and compiled before adding V62's scalar pair/work
entities. Migration adds empty tables without adopting files or replaying work;
all retained inbox/handoff fields keep their meaning. Startup plans, purge
barriers and schema inventories include both entities. Until the paired runtime
is implemented and qualified, derivative rows block fresh qualification. This is
a schema prerequisite, not derivative or whole-product acceptance.

Independent and IC-1 reviews cleared schema candidate03. Its two affected suites
passed all 82 tests, including persistent V61→V62 ownership preservation; the
other six focused suites passed in focused02 and remain unchanged. The first
compile failure and the four fixture failures in focused02 are retained with
their reviewed corrections. XcodeGen/source membership, migration guard and its
mutation regressions, startup selector, remaining iOS CI-tooling commands,
project resources and Markdown checks passed.

Evidence: `.artifacts/shared-media-derivatives-20261016/`; successful rerun
`.artifacts/local-ios/257a242f02dd4d768aa20e10fe7027f2.xcresult`. This is scoped
shared-checkout validation, not a new full-target or isolated-source pass. An
unrelated Explore edit was observed and preserved; none of the unrelated work is
included in this scope. Continue paired runtime implementation automatically.
Numeric limits stay unchanged; activation is disabled, PR116 frozen, Supabase
hold active and AWS unapproved.

## October 16 — joint inbox/P1 handoff locally validated

The inactive joint handoff now uses one coordinator and fenced repository for
source holds, exact destination copies, original-account recovery and cleanup.
Abandonment preserves the source and account-owned draft phase/revision; it can
release liabilities under low disk while unchanged S+H+A caps remain enforced.
Saved irreversible intents and exact inode/directory proofs govern source and
detached-destination release. Surviving originals and destination references
remain owned. Empty-directory cleanup preserves all live and pending tokens.

Candidate04 passed 94 focused tests across six suites and the complete native
target: 6,038 XCResult cases, zero failures or skips (4,580 Swift Testing tests
across 669 suites). Independent and IC-1 pre-execution review concurred. The
initial compile failure from an extracted helper's missing actor annotation is
retained; the corrected helper restores its original main-actor isolation.
Project generation/membership, migration guardrails, Markdown and diff checks
passed. Evidence: `.artifacts/shared-media-handoff-20261016/`; full result
`.artifacts/local-ios/3c0cc00700dd4a4abf6c64e3cc23e1ae.xcresult`.

This validates the isolated handoff in the shared checkout, with 102 unrelated
paths and their generated-project delta preserved. It does not close isolated-
source, live capture, device, hosted or whole-product acceptance. Continue the
shared derivative lifecycle under existing local authorization, retaining the
approved retire-old-first/incomplete-needs-attention behavior. Activation stays
disabled, PR116 frozen, Supabase hold active, AWS unapproved and limits
unchanged. No push, merge, deployment or hosted action occurred.

## October 16 — proposed cloud-cache policy retained for later review

The cloud-retention integration milestone must consider the
[unadopted cache proposal](shared-media-allocation-ownership-2026-10-16.md#cloud-backed-local-cache-policy-proposal--not-adopted)
before final acceptance. The proposed 256 MiB/seven-day defaults are not current
limits or eviction authority. Current local handoff implementation continues
under the existing agreement, with activation disabled and PR116 frozen.

## October 16 — typed source inbox locally validated

SMA-1 L4 now has an inactive durable source-inbox foundation on V61. Exact
selected original bytes, prepared identities and partial inode ownership survive
reopen without repeating the source callback. Closed-writer occupancy separates
occupied bytes from unwritten reservations without reducing the total charge.
Explicit discard persists exact irreversible intent before namespace-owned
unlink, synchronization, absence proof and joint row reclamation. Legacy inbox
owners reject the bound namespace before mutation. No live routing or file
adoption exists. Handoff records remain rejected until the joint destination
extension is implemented; L4 and whole-product acceptance remain open.

V60 was frozen and compiled before V61 changes. Schema validation passed 116
cases, including disk migration and startup recovery. Source-focused validation
passed 94 tests, then 31 tests after the occupancy correction. The full shared
checkout run retained 6,021 passing and four failing cases, zero skipped. Three
failures were factory-size guards (two oversized-owner inventories and one
direct line-count assertion); one was the purge schema inventory. The reviewed
formatting-only factory correction and two additional purge blocker fixtures
passed all 50 affected architecture, purge and startup checks. Migration and
startup guardrails passed. Unchanged runtime evidence is carried forward with
independent and IC-1 concurrence; no exact-final-candidate full-green or
isolated-source claim is made.

Evidence: `.artifacts/shared-media-inbox-20261016/`, including
source-candidate05, source-full01-summary and source-correction-summary.
Continue the adopted joint inbox/P1 handoff, recovery and cleanup agreement
automatically. Numeric limits, activation disabled, PR116 freeze, deployment
hold and AWS unapproved remain unchanged. No push, merge, deployment, hosted
test or device action occurred.

## October 16 — shared-photo lifecycle locally validated

SMA-1 L3 extends the inactive isolated photo adapter with same-account sharing,
exact reference retirement, restart-safe physical release and bounded
row/directory reclamation. Surviving references preserve the original bytes and
their charge. Retained share requests cannot resurrect reclaimed references.
Saved retirement binds exact file and directory identities; absence
reconciliation proves current absence, never acquisition or AI closure. Pending
acquisition remains charged. Numeric limits and V60 fields are unchanged.

Independent and IC-1 review concurred on exact candidate03 manifest
`ef3abced1ba2cbfd5dc0906e31159a09b789bbe7521808e7a4bf21b70751f6a8`. The focused
gate passed 66 tests across four suites. The complete native target passed 6,009
XCResult cases (4,551 Swift Testing tests across 667 suites), with zero failures
or skips. Project generation/membership, migration guardrails, Markdown and diff
checks passed. Review-held candidates01/02 remain retained; candidate03 only
corrects an EOF blank line after candidate02 source concurrence. Final
documentation and scoped staging receive carry-forward review before the local
commit.

Evidence: `.artifacts/shared-media-lifecycle-20261016/`, with full result
`.artifacts/local-ios/c567429f8f9d48dd98e6c8a20b4b7888.xcresult`. Validation ran
in the shared checkout with 102 unrelated paths preserved, including a
separately retained generated-project delta. This closes the isolated reference
and release checkpoint, not isolated-source, device, hosted or whole-product
acceptance. Inbox/source handoff, derivatives and shared live composition remain
open. Canonical behavior is in
`apps/ios/Merian/Core/Data/SharedMediaStorage/README.md`. Activation stays
disabled, PR116 frozen, Supabase hold active and AWS unapproved. No external
action occurred.

## October 16 — isolated P1/shared-storage adapter locally validated

The local adapter adds `SharedMediaPhotoAcquisitionOwner` for exact
original-byte acquisition in a dedicated persistent fixture. It uses one joint
P1/shared save before the provider and one joint completion save. Exact readback
resolves lost acknowledgements without another provider invocation. A pending or
interrupted write retains its maximum reservation and fixed destinations; only
jointly committed handles can be recovered. Missing or changed originals block
use without replacement or regeneration.

Standalone P1 repositories hold a shared lifetime lock on the zero-byte
`.merian-media-fence` control file in the SQLite parent and reject shared ledger
rows. Every shared-storage mode takes that fence exclusively before the existing
parent-directory, authority and P1 locks. The fence is never removed or
upgraded; its held/named identity, zero length and single link are revalidated.
This keeps co-located standalone purge compatible without opening an
allocator-admission gap. It excludes participating owners, not arbitrary
external filesystem mutation; replacement invalidates the owner without repair.
A persistent P1-root marker also excludes standalone access through another
database after the adapter closes. First binding accepts only empty P1 rows and
namespace. Existing unbound P1 fixtures keep their behavior.

One physical destination contributes once to filesystem reservation and to the
durable budget. Its paired P1 lease also contributes to acquisition/temporary
budgets; each package's bounded empty envelope contributes once to logical
durable totals. Limits and V60 fields are unchanged. No source/inbox handoff,
derivatives, freeze, sharing, deletion, physical release, ordinary capture,
network or AI admission is enabled. Generic L1 mutations reject adapter mode.

Exact candidate05 passed all four focused suites (52 tests) and the complete
`merianTests` target (5,995 XCResult cases; 4,537 Swift Testing tests across 667
suites), with zero failures or skips. Independent and IC-1 source review
preceded execution. Project generation/membership, migration guardrails and
Markdown checks passed. The retained candidate02 compilation failure and
candidate03 legacy-purge failure led to the reviewed corrections; they are not
erased or counted as passes. Candidate04 was held at review for an EEXIST
durability race; candidate05 closes it with unconditional file/parent
synchronization and identity revalidation before admission.

Evidence is under `.artifacts/shared-media-p1-adapter-20261016/`. The native
gate ran in the shared checkout with 102 unrelated paths preserved; this is
local checkpoint validation, not isolated-source, device, hosted or
whole-product acceptance. Next is a separately reviewed source-owner/inbox
handoff and cleanup increment; no live producer, derivative or release authority
is inferred. PR116 remains frozen, activation disabled, Supabase hold active and
AWS unapproved. The L1 validation record below remains historical evidence for
that earlier scope.

## October 16 — inactive SMA-1 L1 foundation locally validated

The local implementation freezes V59 and adds four scalar V60 storage entities,
explicit fixture ownership, durable reservations/references/leases, and a
fail-closed identity/purge guard. The SQLite parent and authority directories
provide lifetime exclusion; SQLite file locking remains with Core Data. There is
no live composition, file writer, physical-release acknowledgement or AI
admission. Legacy observations remain advisory, with no completeness or
promotion claim.

The V59 disk migration and startup recovery passed. Candidate09 passed all 16
focused storage tests; its full shared-checkout execution ran 5,972 tests and
retained four failures (three size inventories and an outdated purge inventory).
Candidate10 changed production code only by formatting and corrected purge
coverage; all 23 targeted checks passed, including each new row blocking purge
before callbacks in saved and unsaved states. Independent and IC-1 review concur
with reuse of unchanged passing results. This is combined local evidence, not a
green full rerun on candidate10 or isolated-source qualification. Receipts and
failed runs remain in `.artifacts/shared-media-foundation-20261016/`.

The next dependency is an isolated P1/shared-storage handoff with explicit
ownership links, joint durable transitions, and enforced producer exclusion.
Whole-product allocation, source import, physical release and mixed-producer
qualification remain open; this is not overall acceptance closure. Limits stay
unchanged. PR116 remains frozen at `135555d66`, activation and ordinary P1
access disabled, Supabase hold active and AWS unapproved. Local continuation
needs no routine proceed prompt; push, merge, deployment and hosted tests remain
barred.

## October 16 — shared native allocation agreement reviewed

[SMA-1](shared-media-allocation-ownership-2026-10-16.md) recommends additive V60
ownership in the existing store, non-destructive legacy inventory, explicit
accountless inbox ownership, and reference-directed cleanup. The 384 MiB cap
remains pending CPM packages only; retained history occupies real disk but
receives no new quota or eviction policy. Legacy observations confer no write,
cleanup or fresh-admission authority.

This is a proposed agreement, not implementation or mixed-producer
qualification. G1–G4 and A2/A3/A5/A14/A16/A17 remain open. The next bounded
dependency is the exact inactive foundation file/lock/migration packet after
independent and IC-1 review, followed by producer integration and required
acceptance. Existing media-required submission and exact admitted recovery
remain unchanged. Unknown AI execution permits neither another invocation nor a
refund.

PR116 stays frozen at `135555d66`; activation and ordinary P1 access disabled,
Supabase hold active, AWS unapproved, limits unchanged. No push, merge,
deployment, hosted test, device operation or capture visual refactor is
included.

## October 16 — C1 observer correction validated locally; PR116 still frozen

The retained exact-source diagnostic reproduced CI's `ZX452` with only the
unknown-cancellation count predicate failing. The owner-delete fence now erases
private cancellation records before the old test observer ran. Funding and the
protected accounting projection were unchanged. The correction changes only the
account-batch test: preserve its full original assertion before the real fence,
then independently verify private erasure and unchanged accounting after it.
Enabled trigger order/function and exactly-once observations are checked. No
production migration, runtime behavior, API or activation change is needed.

Exact independent and IC-1 execution review preceded the corrected candidate.
The complete affected account-batch and admitted-expiry suites passed 9 and 12
checks on separate fresh owned local databases. Expiry waited 292.165 seconds
for the original deadline, without timeline edits. All three diagnostic/test
databases were reconciled and disposed; failed evidence remains retained.
Recursive formatting/lint and Python syntax passed. The complete tooling gate's
TypeScript, evaluation and DTO checks passed; a sandboxed synthetic terminal
fixture stopped its shell phase. That failure is retained, and the failed plus
remaining ten mock-only shell tests passed with terminal access. Passing prefix
checks were reused rather than repeated. No hosted credential or provider call
was made.

Evidence and exact review/commit receipts:
`.artifacts/c1-account-batch-diagnostic-20261016/` and
`.artifacts/c1-account-batch-correction-20261016/`. This is scoped
shared-checkout local evidence, not a new full candidate/remote CI verdict.
PR116 remains frozen at `135555d66`, with its failed CI result unchanged until
separately authorized publication. All unrelated edits are preserved. Activation
stays disabled, ordinary P1 access nil, Supabase hold active, AWS unapproved and
limits unchanged. No push, merge, deployment, hosted test or schedule change
occurred.

The next feature dependency remains durable shared allocation/inventory and
cleanup ownership, then original-media integration and remaining acceptance,
followed by approved version deletion/export and redesign. Existing
media-required submission, immutable descriptions and exact admitted recovery
rules remain; unknown execution grants neither another AI invocation nor a
refund. The capture visual refactor and broader engine work retain their
separate ownership.

## October 16 — separate local continuation; PR116 remains frozen

The user authorized local feature continuation on
`codex/history-original-media-followup`, based on
`135555d66434dbd6cdf812849745295f6db4f760`, with reviewed local commits. PR116
remains frozen at that exact head. This supersedes earlier instructions to wait
for integration before local follow-up construction; no push, merge, deployment
or hosted test is authorized. Activation stays disabled, ordinary P1 access nil,
Supabase integration hold active, AWS unapproved and all limits unchanged.

The first reviewed scope confines legacy FileIO operations so paths cannot
bypass the private PhotoPreparation, ReanalysisQueue or inbox owner. It also
removes absolute-source basename substitution. This is an ownership
prerequisite, not common allocation or product-wide lifetime qualification. The
durable shared allocator/inventory agreement, remaining media and integrated
acceptance, then version deletion/export and redesign remain in their approved
order. No capture visual refactor or broader engine ownership is absorbed.

The ownership correction passed 47 focused tests and the complete native unit
run: 5,955 expanded cases, zero failures or skips (4,497 test declarations in
665 suites). The required critical-suite result validator also passed. These are
shared-checkout simulator results, not isolated-source or device qualification.
The earlier full run, with ten failing replay declarations, remains retained:
the replay fixture had injected its Documents root but still used global
cleanup. Explicit FileIO owner injection corrected that mismatch without
broadening cleanup authority; success, cancellation and error paths now use the
same owner.

Independent and IC-1 exact-source concurrence preceded the corrected execution.
Scope and failed/passing results are retained in
`.artifacts/history-media-confinement-20261016/`. A local commit requires
separate final result review; review and commit receipts must identify the exact
candidate in that directory. All 102 unrelated paths are preserved. Auto-prompts
remain paused.

PR116's iOS Build/Test and Startup Safety checks passed. Supabase Candidate
Validation run `38864594630` failed C1 `account-batch` at
`actual_two_item_account_tombstone_rollback`, SQLSTATE `ZX452`. Its compound
pre-user-delete accounting assertion did not reveal the failed predicate at this
checkpoint. The disabled-gate restoration passed. That unresolved assessment and
proposed diagnostic are superseded by the later October 16 C1 observer
correction recorded at the top of the alpha-readiness RFC. The original CI
failure remains historical evidence; remote CI has not been rerun. See
`pr116-ci-blocker.json` in the evidence directory. PR116 remains frozen and is
not merge-ready.

## October 16 — PR116 feature scope frozen; merge-readiness proposal

The human requested a feature freeze and exact merge-readiness proposal with
independent/IC-1 review. The frozen implementation is
`ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`; its local evidence checkpoint is
`fdddf66198f0fbfd568534c62fa4b3a7e18e3254`. The 102 unrelated working-tree paths
are excluded. No further feature additions belong in PR116. This current
direction supersedes the immediate common-allocation next-step recommendation
below and the historical October 13 integration cut; existing evidence and
remaining acceptance requirements are preserved.

Proposal:
`docs/rfcs/identification-history-pr116-merge-readiness-2026-10-16.md`. ISQ-1
closes only isolated local NCO/BI qualification. Cumulative PR safety, exact
final CI and live deployment containment remain open. The local active history
hold blocks the entire Supabase production job, but does not protect old jobs or
external Vercel hooks. Remote PR116 remains draft at `878932268`; its checks do
not qualify the 101 newer local commits. No push, merge, hosted qualification,
deployment, device installation or activation is authorized.

The proposed next checkpoint is a two-hour read-only readiness audit, at most
128 MiB evidence and the 20 GiB disk floor; execution awaits approval. Exact
proposal review receipts are retained in
`.artifacts/pr116-merge-readiness-20261016/`. Proposal concurrence is not
whole-PR acceptance or release approval. Common-allocation/original-photo
integration continues in the next feature PR after the integration boundary;
later version deletion/export and redesign retain their sequence and ownership.
No acceptance gate is waived. Activation disabled, ordinary P1 access nil, AWS
unapproved, limits unchanged; automatic scheduling remains stopped.

## October 15 local / October 16 UTC — ISQ-1 isolated execution passed

The approved XcodeGen 2.45.4 selection correction resumed ISQ-1 within its
original 03:07:08–07:07:08 UTC window and unchanged bounds. The clean managed
worktree at `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f` passed generation with
identical project bytes, project/migration/CI-tooling/source-membership checks,
managed Debug build, 561 acceptance tests, all 27 UI cases, all ten report-only
performance workloads, all 5,923 unit tests, the actual critical-result
validator and unsigned generic Release compilation. No failures or skips were
reported. The unit XCResult's 9,363 per-device executions are a separate count;
BI-1's earlier 5,945 total remains shared-checkout evidence.

Source and pinned hashes remain unchanged; all 102 unrelated primary file
identities are preserved. Storage accounting normalizes only the reviewed
simulator-container relocation, charges new/grown files including 23 new fixture
roots, and preserves raw alarms. Working allocation/evidence/free-space checks
remain within the original bounds. No performance baseline was adopted; high
variance and missing hitch samples remain explicit limitations.

Result: `docs/rfcs/client-prepared-media-isq1-isolated-result-2026-10-16.md`.
Evidence: `.artifacts/local-ios/isq1-20261015/result-resumed.json`; final exact
independent/IC-1 disposition belongs in `result-review-02.json` in that
directory. Closure is limited to the isolated local NCO/BI portion of A19 after
that concurrence. P1 common-allocation/photo and device, audio/video quality,
server admission/shared references, integrated history, external/CI and later
version deletion/export/redesign gates remain open. The next recommendation is a
bounded common-allocation/original-photo ownership and integration proposal.

Activation disabled, ordinary P1 access nil, AWS unapproved, existing limits
unchanged. No push, merge, deployment, hosted test or device installation. Stop
at this local checkpoint; automatic scheduling remains stopped. Earlier stopped
attempts and proposal states below are historical and retain their evidence.

## October 15 local / October 16 UTC — ISQ-1 stopped at tool prerequisite

The human approved ISQ-1 for 03:07:08–07:07:08 UTC. Exact independent and IC-1
execution concurrence preceded the first qualification command. The clean
managed worktree at `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f` selected XcodeGen
2.45.2; the project requires 2.45.4. The primary checkout had selected the
installed 2.45.4 executable, so its preliminary tool inventory did not establish
the clean worktree's command lookup. Generation failed before changing files.

Stopped without retry or repair. No package downloads, builds, runtime tests or
later qualification gates ran. Worktree remains clean; all 106 primary file
identities (102 unrelated plus four proposal/status paths) were preserved before
this owned reporting update. Source qualification and all remaining product
gates stay open. Result and proposed environment-only correction:
`docs/rfcs/client-prepared-media-isq1-qualification-result-2026-10-15.md`.
Evidence: `.artifacts/local-ios/isq1-20261015/`. Independent and IC-1 concur
with this stopped disposition; exact receipts are in
`.artifacts/local-ios/isq1-20261015/final-review.json`.

Activation disabled, ordinary P1 access nil, AWS unapproved, existing limits
unchanged. No push, merge, deployment, hosted action or device installation;
automatic continuation remains stopped. Earlier proposal/active statements below
are historical; human approval does not erase this failed preflight.

## October 15 local / October 16 UTC — ISQ-1 proposed; execution awaits approval

BI-1 is committed locally as `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`. Its
passing validation is shared-checkout evidence; 102 unrelated dirty paths remain
preserved. Earlier pending-commit or active-window statements below are
historical. Automatic continuation stopped at BI-1 completion.

The next proposal is
`docs/rfcs/client-prepared-media-isolated-qualification-proposal-2026-10-15.md`:
one four-hour local window, one clean managed worktree at the exact commit,
explicit locked package downloads, managed native qualification, 16 GiB new
working allocation and 2 GiB retained evidence, with the 20 GiB disk floor.
Independent and IC-1 concur on proposal SHA-256
`8043861c9d55968175a9123ca944e891f622b63e88779f029b70a54458957862`; receipts are
in `.artifacts/local-ios/isq1-proposal-20261015/review.json`. Human execution
approval remains pending. No execution or implementation is authorized by this
entry. The proposal separates isolated-source evidence from
common-allocation/device, audio/video, server admission, integrated history,
external/CI and later deletion/export/redesign acceptance; those remain open.

Fresh initial/reanalysis requires photo/audio/video, with optional immutable
supporting text; retained originals suffice, missing media blocks, historical
records and exact admitted recovery remain preserved. No new Supabase project is
required: the later human shared-alpha-target decision supersedes historical
nonproduction-only wording, without granting any current hosted operation.
Activation disabled, ordinary P1 access nil, AWS unapproved, existing product
and runtime limits unchanged. No push, merge, deployment, device or hosted work;
automation remains stopped. Prior evidence and failures remain unchanged below.

## October 15 local / October 16 UTC — BI-1 validation passed; inactive integration checkpoint

BI-1 completed its planned local validation within the approved
01:56:04–03:56:04 UTC window and 1 GiB additional evidence allowance. Candidate
02 passed managed Debug compilation, 96 focused tests, all 5,945 unit tests, all
six critical UI smokes, unsigned generic Release compilation, full CI tooling,
project validation and the actual critical-result validator. Raw XCResult
per-device counts are retained separately. These are shared-checkout results,
not isolated selected-source qualification or P1/alpha acceptance.

Final staging exposed two whitespace diagnostics in newly added files. The
frozen V58 snapshot retains its exact inherited bytes; the test file loses only
one terminal blank line (candidate 03). The staged audit permits only the known
frozen-line diagnostic. Final review must concur with evidence reuse for this
formatting-only correction; candidate-02 runtime results remain accurately
labeled in the result and raw artifacts.

Independent and IC-1 source-selection review concurred on the 59-file NCO/BI
source/configuration/project selection. Local commit requires final exact
combined-patch review; receipts and commit identity are retained in
`.artifacts/local-ios/bi1-20261015/`. Unrelated working-tree edits remain
intact. BI-1 automatic continuation ends at this checkpoint and does not advance
the broader roadmap. Earlier active/paused/proposal status below is historical.

Activation disabled, ordinary P1 access nil, AWS unapproved, existing limits
unchanged. No hosted action, push, merge, deployment, device installation or
distribution occurred. Installed/mixed-allocator, audio/video, server admission,
integrated history and later deletion/export/redesign acceptance remain open.
Result: `docs/rfcs/client-prepared-media-bi1-integration-result-2026-10-15.md`.

## October 15 local / October 16 UTC — BI-1 approved; bounded validation active

The human approved automatic continuation for BI-1 only, from 01:56:04 through
03:56:04 UTC, with at most 1 GiB additional retained evidence. Candidate 02 has
exact independent and IC-1 concurrence, a passing managed simulator build, all
96 focused tests passed and a passing full CI-tooling gate. Complete unit
validation and selected-tree/final evidence review are in progress. These are
shared-checkout results; no clean-source acceptance claim. No runtime source
change beyond the reviewed Auth consolidation was added by BI-1.

The BI-1 follow-up is active only within this fixed window and stops at
completion or a genuine blocker. Earlier paused/proposal-only status is
historical. Activation disabled, ordinary P1 access nil, AWS unapproved and
existing limits unchanged. No push, merge, deployment, hosted or device actions
are authorized. Evidence: `.artifacts/local-ios/bi1-20261015/`. Proposal
boundary:
`docs/rfcs/client-prepared-media-bounded-integration-proposal-2026-10-15.md`.

## October 15 local / October 16 UTC — BI-1 integration proposal; execution gated

The human requested a bounded proposal for the remaining Auth guard, stale
capture CI selector and baseline dependency. BI-1 proposes a fresh two-hour
local window with at most 1 GiB additional evidence: consolidate existing Auth
helpers without changing caps or fences; prove pending-video interruption and
late-result cleanup before replacing the critical selector; and explicitly
integrate the account-bound capture baseline hunks needed by NCO. The dependency
includes admission fields, account-change hooks and cleanup, not just
CaptureDraftSession.

Independent and IC-1 re-review concur on proposal SHA
`4125ea97f243d0b6d6d03ef19500bfc2cac60308f7b226f40c6ef845adc2e15a`. The
corrected critical test targets pending startup cancellation and preserves
started-recording stop/completion. Human implementation approval remains
pending. Review receipt: `.artifacts/local-ios/bi1-20261015/review.json`. No new
runtime change, build or test is authorized by this proposal. NCO's existing
shared-checkout evidence and open full/UI/Release/installed/integrated gates
remain unchanged. Activation disabled, production P1 access nil, AWS unapproved,
all existing limits unchanged, auto-prompts paused. Unrelated visual/backend
work remains outside the handoff. Canonical proposal:
`docs/rfcs/client-prepared-media-bounded-integration-proposal-2026-10-15.md`.
Earlier entries remain historical.

## October 16, 2026 — NCO-1 local checkpoint; shared acceptance blocked

The approved local implementation and four-script validation extension are
implemented. Candidate 07 passed 103 focused native tests; its complete unit
target had 5,939 passed and four failed. Candidate 08 fixes the V59 factory's
three architecture failures and passes its managed build plus all 18 affected
architecture tests. The unchanged Auth budget failure and pre-existing capture
critical-selector mismatch remain open; the full gate is not green.

Evidence is for the shared checkout. P1 depends on uncommitted baseline
CaptureDraftSession account APIs, so no standalone NCO commit was made or
unrelated changes absorbed. The bounded patch and exact source snapshot are
retained. Further baseline/CI ownership reconciliation is required; UI/Release
runs are held, and P1/integrated acceptance remains open. Activation disabled,
production access nil, AWS unapproved, limits unchanged, auto-prompts paused. No
hosted action, push, merge, deployment or device installation occurred. Current
result: `docs/rfcs/client-prepared-media-nco1-local-result-2026-10-15.md`.
Earlier entries remain historical and do not supersede this checkpoint.

## October 15, 2026 — NCO-1 implementation authorized; validation in progress

The human approved a four-hour local implementation and validation window from
23:17:59 UTC through October 16 03:17:59 UTC, including up to 2 GiB of new
native evidence. The outgoing V58 model freeze passed independent/IC-1 review
and managed build-for-testing. The V59 ledger, inactive capture ownership seams
and cleanup integration are now under exact-candidate review; they have not
passed runtime acceptance. Earlier proposal-only status below is historical.

No P1 completion or integrated qualification is claimed. Production access stays
nil, activation disabled, AWS unapproved, package/storage limits unchanged and
auto-prompts paused. No hosted action, push, merge, deployment or device
installation is authorized. Current local evidence:
`.artifacts/local-ios/nco1-20261015/`. The native ownership agreement remains
the scope authority; capture-tools/redesign work remains separate.

## October 15, 2026 — NCO-1 native agreement; P1 execution awaits approval

The authorized two-hour local agreement scope after `600b5ce28` prepares P1-L1:
freeze V58, add four standalone V59 ownership entities, retain exact original
bytes before draft release, and bind capture/cleanup to account-work leases and
fail-closed purge. The canonical NCO-1 packet records the concrete file boundary
and acceptance plan. Exact independent/IC-1 review is required for closure; its
evidence is retained with this candidate. The next request is one four-hour
local implementation/validation window, including up to 2 GiB new native test
evidence under the existing managed-build procedure. It is not authorized yet.
Qualification excludes competing non-P1 allocators; installed mixed-allocator
and integrated product gates remain open. No tests, builds, runtime edits or
hosted actions occurred. No transport rerun is justified. Activation disabled,
ordinary access nil, AWS unapproved, existing limits unchanged, auto-prompts
paused. Canonical packet:
`docs/rfcs/client-prepared-media-native-ownership-agreement-2026-10-15.md`.
Earlier entries remain historical and exactly recoverable.

## October 15, 2026 — CP-1 reviewed source boundary; native ownership agreement required

CP-1 preparation was authorized after `cae2329a1`. Its twelve-file source review
finds that original-photo retention needs durable draft/package ownership,
separate from ordinary queue funding and dispatch. Proposed P1-L1 typed native
ledger and the exact schema/capture/cleanup handoff remain unadopted;
implementation is not ready. Next proposed scope is at most two hours to close
those two named agreements and return the exact four-hour P1 packet. No tests,
builds, runtime changes or hosted actions occurred. No new transport test is
justified. Activation disabled, AWS unapproved, limits unchanged, auto-prompts
paused. Current result:
`docs/rfcs/client-prepared-media-original-photo-cp1-result-2026-10-15.md`.
Earlier entries remain historical and exactly recoverable.

> Current October 15 GAC-1 local result: the loader fix and validation passed;
> one offline package, denial control and 20-read serial campaign completed. All
> 20 media reads verified and closed on one worker; teardown/removal passed.
> GAC-1 passed with case-4 warning retained. Peak partial proxy: 38.796025 MiB;
> cross-cohort Q increase: 7.8125 MiB, close to the unchanged 8 MiB gate. This
> closes only the finite local checkpoint, not hosted, whole-worker/native/CPU
> or product acceptance. Exact result and limits:
> docs/rfcs/client-prepared-media-gac1-local-result-2026-10-15.md. Activation
> disabled, AWS/160 MiB unapproved, all other limits unchanged, auto-prompts
> paused. The single package/control/campaign allowances are consumed. Earlier
> entries below are historical and remain exactly recoverable.

---

> Current October 15 GAC-1 continuation result: the corrected explicit-file type
> gate passed, reusing 54 unchanged passing tests. Staged/main lint then found
> unsafe throws in both local bundle loaders; the first-failure stop closed this
> window before packaging, control or campaign. The concrete cleanup-error
> preservation proposal requires a new implementation decision:
> docs/rfcs/client-prepared-media-gac1-loader-lint-result-2026-10-15.md.
> Activation disabled, AWS/160 MiB unapproved, all other limits unchanged,
> auto-prompts paused. Product/native/integrated gates remain open. Entries
> below are historical; their exact source bytes remain recoverable.

---

> Current October 15 GAC-1 precheck result: the approved local scope stopped
> when pinned Deno 2.9.4 rejected the recursive type-check command before
> checking source. Formatting/lint and 54 tests passed; recursive typing and
> staged lint remain unqualified. No packaging, control or campaign ran.
> Independent and IC-1 review recommend a command-only correction; another
> execution requires a new decision. Canonical result and continuation proposal:
> docs/rfcs/client-prepared-media-gac1-precheck-result-2026-10-15.md. Activation
> disabled, AWS/160 MiB unapproved, all other limits unchanged, auto-prompts
> paused. Product/native/integrated gates remain open. Entries below are
> historical; their exact source bytes remain recoverable.

---

> Current October 15 GAC-1 adoption: the user approved the revised local
> acceptance contract and bounded implementation preparation. Exact independent
> and IC-1 source review is required; no tests, packaging, control or campaign
> execution is authorized yet. Canonical adoption and execution proposal:
> docs/rfcs/client-prepared-media-gac1-implementation-2026-10-15.md. The old
> four-point stop becomes a reported warning only for the explicit GAC-1
> candidate; the 8 MiB comparison tolerance and other limits stay fixed. Prior
> failures retain their original classifications. Activation disabled, AWS/160
> MiB unapproved, auto-prompts paused. Product/native/integrated gates and
> follow-up sequencing remain open. All entries below are historical.

---

> Current October 15 result: the denial control passed; the four-read prefix
> stopped at the unchanged 8 MiB growth gate (10.278900 MiB increase). All four
> media bodies closed; teardown and removal passed. Original-call bins localized
> rises/falls within verified reading/hashing; stopped case4 remains
> unclassified. No leak/GC/idle conclusion or qualification pass. Both
> allowances consumed, no retry. Canonical result:
> docs/rfcs/client-prepared-media-memory-bins-result-2026-10-15.md. Activation
> disabled, AWS/160 MiB unapproved, all limits unchanged, auto-prompts paused.
> Product/native/integrated gates and follow-up order remain open. Earlier
> entries below are historical; no hosted or credential action occurred.

---

> Current October 15 approved scope: local fixed-bin diagnostics in the fresh
> 16:37:22–18:37:22 UTC window. No new memory call or timer; unchanged gates and
> limits. One denial control and conditional four-read prefix each require exact
> independent/IC-1 concurrence; current candidate is not yet execution-approved.
> Scope and evidence: .artifacts/client-prepared-media/memory-bins/scope.md.
> Activation disabled, AWS/160 MiB unapproved, auto-prompts paused. Prior
> results remain historical; product/native/integrated acceptance and follow-up
> order remain open. No hosted, credential, deployment, push, merge or device
> action.

# Identification history alpha readiness

> Current October 15 memory review: retained data shows phase-varying external
> memory and a valid 8 MiB growth stop, without establishing a leak or
> reclamation mechanism. A bounded proposal would expose existing samples in
> fixed bins and run only the original four-read prefix, after human approval
> and exact independent/IC-1 concurrence. No additional memory calls, idle
> timers or gate changes are proposed. Packaging must fit existing storage caps;
> feasibility remains conditional. Canonical proposal:
> docs/rfcs/client-prepared-media-memory-growth-review-2026-10-15.md. This turn
> performs no construction or runtime test. Prior failures and exact evidence
> remain preserved; activation disabled, AWS/160 MiB unapproved, limits
> unchanged, auto-prompts paused. Product gates and follow-up order remain open.
> Earlier status entries are historical.

> Current October 15 result: the baseline reproduced the retained pool error;
> the proposed control and campaign teardown passed with no runtime errors and
> confirmed removal. The campaign workload FAILED the unchanged 8 MiB growth
> gate after 42.235 seconds: one worker, five requests, four media
> reads/closures, three verified and 13.654 MiB four-point growth. Sustained
> reuse remains unqualified. Both controls and the single campaign are consumed;
> no retry. Canonical result:
> docs/rfcs/client-prepared-media-pool-retirement-result-2026-10-15.md. Executed
> candidate af9802a14a9833e1ef8e2eb9f7c5b6f65a2549cef3351347dff5f607b3e4e147
> received separate exact independent/IC-1 concurrence before controls and
> campaign. Both reviewers concurred with the result and stop disposition; final
> review receipts are retained under
> .artifacts/client-prepared-media/pool-retirement/. Source and prior evidence
> remain preserved with status snapshots. Activation disabled, AWS/160 MiB
> unapproved, all limits unchanged, auto-prompts paused.
> Product/native/integrated gates and approved follow-up order remain open. No
> hosted/credential action or cleanup obligation. Earlier status entries are
> historical.

> User approved bounded pool-retirement construction and local execution in a
> fresh October 15 window,15:48:12–17:48:12UTC. Exact independent/IC-1
> executable concurrence is required before two one-shot controls, and
> separately before the conditional unchanged campaign. Scope:
> .artifacts/client-prepared-media/pool-retirement/scope.md. No new
> clock/watchdog controls; reuse qualified unchanged sources only after review.
> Earlier failures remain preserved. Activation disabled, AWS/160MiB unapproved,
> all limits unchanged, auto-prompts paused. No hosted or credential operation.
> Product gates and follow-up sequencing remain unchanged; earlier status
> entries are historical.

> Current October 15 proposal: read-only pinned-runtime review identifies a
> pool-channel teardown ordering issue. A bounded post-terminal idle retirement
> request plus positive empty-registry observation is proposed as a hypothesis,
> preserving zero grace and every existing limit. See the
> [retirement proposal](client-prepared-media-pool-retirement-proposal-2026-10-15.md).
> Proposal review does not authorize construction or another run; human approval
> and exact independent/IC-1 executable concurrence remain required. Prior
> lifecycle failure stands. Activation disabled, AWS/160 MiB unapproved,
> auto-prompts paused; earlier status notes are historical.

> Current October 15 result: shared-clock qualification and the independent
> stalled-parent watchdog passed. Replacement baseline reproduced the original
> failure; proposed listener retention still produced the pool shutdown-send
> error. Complete receipt ordering and cleanup do not override lifecycle
> failure. The conditional campaign did not run; no retry is authorized. See the
> [exact result](client-prepared-media-clock-qualification-result-2026-10-15.md).
> Activation disabled, AWS/160 MiB unapproved, all limits unchanged,
> auto-prompts paused. Earlier states below are historical; product gates remain
> open.

> User approved the reviewed clock-method amendment in a fresh October 15 local
> window, 14:57:29–16:57:29 UTC. Construction and focused tests are complete;
> exact independent and IC-1 review is pending before execution. One
> delayed-child clock check, one inert watchdog control and two replacement
> case-26 controls are allowed; campaign remains conditional on successful
> controls and separate exact concurrence. Scope:
> .artifacts/client-prepared-media/clock-qualification/scope.md. Prior failed
> baseline and candidate evidence remain historical and preserved. Activation
> disabled, AWS/160 MiB unapproved, all limits unchanged, auto-prompts paused.
> No hosted or credential actions. Product gates and follow-up order remain
> unchanged. Earlier approval requirements below are historical for this new
> scope.

> Current October 15: the approved first shutdown control reproduced both
> runtime errors and exit 1; EOF and external cleanup are confirmed. Python
> 3.9.6/macOS clock origins invalidate cross-process ordering and transferred
> absolute-deadline qualification. Independent and IC-1 review concur with
> stopping; the second control and campaign remain unused. See the
> [clock finding and bounded next-method recommendation](client-prepared-media-shutdown-clock-finding-2026-10-15.md).
> No runtime change or further execution follows without explicit amendment and
> exact review. Activation disabled, AWS/160 MiB unapproved, all limits
> unchanged, auto-prompts paused. Earlier status text is historical; product
> gates remain open.

> Current October 14: the approved request-boundary campaign completed all 20
> media reads on one worker in 682.342 seconds, but failed runtime shutdown
> qualification after a worker-pool shutdown error (exit 1). External container
> removal is confirmed. See the
> [exact result](client-prepared-media-request-boundary-result-2026-10-14.md).
> The single campaign is consumed; no retry or limit change. Activation
> disabled, AWS unapproved, auto-prompts paused. Earlier preparation/proposal
> states below are historical; product acceptance remains open.

> Current October 14: the user approved local preparation, but independent and
> IC-1 review found an unproven parent-to-worker idle-timer cancellation path.
> Two inert controls are complete; no bundle or verifier campaign ran. See the
> [prelaunch finding and proposed method amendment](client-prepared-media-allocation-diagnostics-preflight-2026-10-14.md).
> Launch remains blocked pending explicit scope resolution and exact-candidate
> review. Activation disabled, AWS unapproved, limits unchanged. Earlier
> approval/status text below is historical.

> Current October 14 follow-up: local allocation diagnostics and harness
> shutdown correction are proposed in the
> [bounded approval scope](client-prepared-media-allocation-diagnostics-proposal-2026-10-14.md).
> Draft/review only; human approval is required before construction, controls or
> another run, followed by exact-candidate independent/IC-1 concurrence before
> execution. Previous failed campaign and cleanup evidence remain valid.
> Activation disabled, AWS unapproved, all limits unchanged. Earlier status
> entries below remain historical.

> Current October 14: the approved local campaign ran after exact independent
> and IC-1 concurrence, then stopped at the unchanged 8 MiB growth gate after
> approximately 42 seconds. One worker, five attempts, three verified reads; all
> four opened bodies closed and the container was removed. No retry. See the
> [exact result](client-prepared-media-controlled-worker-result-2026-10-14.md).
> Post-run independent/IC-1 review concurs with the corrected report, including
> its shutdown defect. Sustained reuse and product acceptance remain open.
> Activation disabled, AWS/160 MiB unapproved, all other limits unchanged.
> Earlier status/approval statements below are historical.

> Current October 14 prelaunch finding: the user approved local preparation and
> execution only after exact-candidate review. The pinned runtime's default
> supervisor retires at half the configured lifetime, so the 900-second setting
> conflicts with the 682-second schedule. No campaign launched; allowance
> unused. See the
> [prelaunch finding and unapproved amendment](client-prepared-media-controlled-worker-preflight-2026-10-14.md).
> Existing limits remain unchanged, activation disabled, AWS unapproved. Earlier
> approval/status notes below are historical.

> Current October 14 controlled-reuse proposal: the attended v1.77.0 run
> completed all 26 checks and cleanup, but all 25 reads reported different
> worker aliases. Hosted warm reuse, growth and physical read overlap remain
> unobserved. The user authorized only the
> [local controlled-worker proposal](client-prepared-media-controlled-worker-reuse-proposal-2026-10-14.md)
> and independent/IC-1 review; construction and execution await approval.
> Activation disabled, AWS and 160 MiB unapproved, credentials retained,
> auto-prompts paused. Earlier status entries below are historical. No product
> acceptance, ownership or follow-up sequencing changes.

> Current October 14 v1.77.0 qualification: the reviewed startup correction
> passed the hosted denial and two closed controls, then stopped at the runtime
> version gate. Cleanup completed; both credentials are retained by explicit
> user decision. Old control closure is reconciled; its private object remains
> untouched. Local v1.77.0 compatibility and independent/IC-1 review are covered
> by the
> [current packet](client-prepared-media-runtime-177-hosted-packet-2026-10-14.md).
> No new hosted action is authorized. Activation disabled, AWS and 160 MiB
> unapproved, auto-prompts paused. Earlier current-state entries below are
> historical; product acceptance and follow-up sequencing are unchanged.

> Current October 14 runtime correction: the approved test-auth attempt stopped
> at case 26; route/settings were removed. Both R2 keys remain active per the
> user's corrected statement, and the old private control object remains
> unresolved. Local pinned-runtime reproduction found a decorated-version
> validator defect; correction and safe diagnostics are under independent/IC-1
> review. The
> [new exact packet](client-prepared-media-runtime-diagnostics-hosted-packet-2026-10-14.md)
> requires fresh hosted approval. Earlier preparation-only entries below are
> historical. Activation disabled, AWS unapproved, auto-prompts paused.

> Current October 14 test-auth revision: local construction and independent/IC-1
> review are authorized; the
> [revised hosted packet](client-prepared-media-test-auth-hosted-packet-2026-10-14.md)
> requires new approval before uploads, secret installation or deployment. The
> previous JWT candidate was never deployed/run. A dedicated short-lived test
> key removes the iOS app-session prerequisite only for this experiment;
> production authentication, G1–G4, media-required scope and product acceptance
> remain unchanged. The existing R2 credentials are locally available with no
> values logged. Activation is disabled, AWS unapproved, auto-prompts paused.
> Earlier runtime-packaging status below is historical for its exact candidate.

> October 14 runtime-packaging update: the user authorized four hours of local
> construction and independent/IC-1 review. See the
> [exact hosted-test packet](client-prepared-media-runtime-packaging-and-hosted-packet-2026-10-14.md).
> User-reported private R2 fixture setup is complete; no credentials have been
> read/installed and no hosted test or deployment is authorized. Local packaging
> does not close CPM-1 G1–G4 or IC-1 product acceptance. Package/storage limits,
> media-required scope, historical recovery and later version-actions/redesign
> sequence remain unchanged. AWS is unapproved, activation disabled and
> auto-prompts paused. A single experimental-route exception to the
> whole-backend release hold requires the separate exact hosted approval; PR116
> remains held.

> October 13 subsequent human approval: proceed with the reviewed CPM-1 policy
> targets, bounded local feasibility preparation and PR116 whole-backend source
> hold under the
> [approved local plan](client-prepared-media-approved-local-plan-2026-10-13.md).
> Earlier pending-approval wording below is historical for that decision.
> Runtime schema/audio/reference agreement and candidate qualification remain
> open; hosted/device/push/merge/deployment restrictions remain unchanged. AWS
> is unapproved and activation disabled. The hold is a local source change only.

> October 13 evaluation update: the user authorized drafting and reviewing the
> [CPM-1 client-prepared media amendment](client-prepared-media-amendment-2026-10-13.md)
> before any AWS decision. It proposes a distinct fresh-submission version; it
> does not weaken or reinterpret this document’s existing server-prepared or
> historical contracts. Adoption and implementation remain pending. AWS is
> unapproved, activation disabled, and all external-operation restrictions
> remain. Revision 3 records the user-required G1–G4 acceptance gates:
> original-byte retention, final audio plus signal/quality evidence, concrete
> storage limits, and end-to-end recovery/shared-asset deletion. Specification
> closure and candidate proof remain separate and open; missing numeric budgets
> or feasibility decisions block implementation, not merely release.
>
> The
> [concrete limits and PR116 integration proposal](client-prepared-media-limits-and-integration-proposal-2026-10-13.md)
> now supplies recommended defaults for approval. Its proposed whole-backend
> source hold is separate from activation flags and is not installed. Neither
> integration, new resource limits nor implementation is authorized by the
> proposal.

Status: revised media-required execution roadmap, October 12, 2026. This records
the accepted fresh-library scope and preimplementation requirements; it does not
claim that the proposed contracts are implemented or externally qualified.

The immutable implementation baseline is
`b8eb3d64f66045ba95c4e4fa5feec82d0462d5df`, following the integrated audit at
`07c381d9d77936b85d36109c43b51ceea7b1dae7`. Unrelated working-tree changes are
excluded. Existing evidence remains in
`.artifacts/integrated-identification-history-audit/report.md` and
`.artifacts/v2-description-parity/checkpoint.md`. This roadmap supersedes
earlier planning assumptions about compatibility, not those historical test
results.

## Scope and endpoint

The user confirmed in
[Check current slice](codex://threads/01a12460-a2c6-7b21-abcf-d3be41331b45),
turn `01a12ddc-270a-7b23-a131-e45a7a6f284f`: both new identifications and
reanalysis require media, and video reanalysis is included in current scope.
This supersedes the October 11 standalone text-child plan and blanket video
read-only exclusion. Historical implementation and evidence are not rewritten.

- New initial and reanalysis requests require image, audio or video evidence.
  Text is optional accompanying context, preserved as exact submitted evidence;
  neither nonempty text nor all modalities together is required.
- Reanalysis stages the applicable retained or explicitly chosen source media
  with context. Original media is sufficient; no mandatory fresh capture.
  Missing or removed source media requires replacement or blocked submission,
  never a text-only fallback, another version's media or a thumbnail as source.
- Include source-bound photo, audio and video reanalysis through the existing
  preparation, accounting, durable queue, recovery and completion owners. Video
  community publication/review is not implied; supported actions require their
  own authoritative policy.
- Qualify fresh libraries. Preserve historical text records, original evidence,
  valid already server-admitted operations, exact recovery and deletion. No
  backfill, destructive old-data removal or reinterpretation of saved inputs. A
  local-only queued text request is not an accepted replay: preserve it and
  require explicit media/remediation for fresh admission. Unknown server
  admission must first recover the original status, never rewrite or resubmit.
- End at a qualified release candidate with production installation disabled and
  ordinary access nil. Push, merge, deployment, hosted scheduling, activation,
  device installation, TestFlight and distribution need separate authorization.
  PR116 publication remains blocked on the existing exact-push approval.

The
[Simplify capture tools](codex://threads/01a12c47-6f54-7500-bab9-679c2babf9a0)
plan provides product context: Scan/photo/video and Record/audio with optional
Add details; eligible Auto-submit bypasses optional details. Its full visual and
session-ownership refactor remains separately planned, awaiting both relevant
workstream handoffs and fresh final implementation approval there. Do not absorb
that refactor here or change its schedule. This roadmap owns required fresh
native/backend media admission and media-backed history journeys. Later
photo/audio/video deletion/download and Identification/History/menu redesign
milestones remain afterwards.

Those follow-ups are authorized work, not optional suggestions: after this scope
and its required acceptance close, continue individual-version deletion and
photo/audio/video source export, then the Identification/History redesign and
approved insight menu under the
[version-actions plan](identification-history-version-actions-and-redesign-2026-10-11.md).
No routine proceed confirmation is needed. Completing this roadmap alone does
not complete that follow-up assignment. External-only blockers remain recorded
and do not silently reorder the milestones.

## Current checkpoint boundary — October 13, 2026

Following private admitted-proof SQL parity at `8d4f8c50c`, atomic admission,
original funding, M1 allocation, complete private receipt/status recovery,
positive-unused C1 cancellation/expiry and erasure are accepted locally at
`bc2a5af507a0ee56cbdb1a357f5221bec611371b`. Independent and IC-1 acceptance,
exact source manifests and validation are recorded in
`.artifacts/initial-atomic-admission/final-gates/local-checkpoint.json`. Full
gates qualify the recorded shared checkout, not an isolated commit tree or
hosted runtime. The original stage93 deadlocks remain unreproduced with unknown
cause; their explicit residual-risk acceptance is limited to this inactive
boundary and does not waive new lock qualification. **C1 covers cancellation and
eligible expiry**, as defined by its
[addendum](initial-cancellation-interface-2026-10-11.md), not successful
analysis completion. Provider dispatch, quota commit, result capture and
successful completion stay blocked until their later reviewed S0 owner.
Receipt/status existence never authorizes them. These boundaries are specified
by the [handoff contract](initial-preparation-handoff-2026-10-11.md) and
[admitted-proof transaction matrix](initial-admitted-proof-2026-10-12.md).

Pure Deno handoff codecs are accepted locally at
`10ffb151a4bf38bdf557cbf163fa27a3682a8b3f`; private SQL parity follows at
`f7b7181ec016b4d37206a290d0f54bce822d463d`. Exact evidence is
`.artifacts/initial-media-handoff-v2/sql-parity/local-checkpoint.json`. The
latter passes all 172 catalogs/6,672 assertions and 3,821 DB-backed Edge tests
with no failures or ignored cases, plus the recorded affected gates. These are
pure consistency helpers with no stored claim issuance, runtime I/O or grants.

The inactive runtime copy/M2 v2/transfer family is implemented and passes its
required local full gates and current-source focused qualification under the
[handoff runtime contract](initial-media-handoff-runtime-2026-10-13.md).
Full-family v6 passes 172 catalogs / 6,706 assertions, 3,935 Edge tests / 598
steps, strict lint and advisor gates (warnings retained). Five affected focused
suites cover owners, private readers, transferred recovery/C1, cleanup
contention and one video/audio resource cohort. Exact shared-checkout sources,
independent and IC-1 decisions, original outcomes, database disposal and local
checkpoint identity are recorded in
`.artifacts/initial-media-handoff-v2/runtime-implementation/`. This does not
qualify an isolated commit tree, hosted CI, installed backend, media structural
validation or device behavior. Historical deadlock evidence remains unresolved
and preserved under its recorded scope; later passes do not waive recurrence
handling. The narrow Ghost target-funding prerequisite stays with history
primary; broader identity-merge and Field Trip ownership do not transfer.

The next bounded dependency is a concrete structural-validator and
transform-attestation protocol for the same immutable retained bytes, under the
[S0 dispatch-fence agreement](initial-dispatch-fence-interface-2026-10-13.md).
The
[revised dependency inventory](initial-media-structure-attestation-2026-10-13.md)
recognizes existing local WAV executable qualification and the original
pre-admission preparation ordering. Its dependency boundary is independently and
IC-1 reviewed. The concrete
[local owner integration agreement](initial-preparation-local-owner-integration-2026-10-13.md)
has exact-source independent and IC-1 launch review. The local owner run and
both existing artifact regressions pass. Independent and IC-1 final evidence
review is complete, and local checkpoint
`b3864361dd5c8b4d921650891ca1926a798d9bb0` is committed. Exact decisions are
retained in `.artifacts/initial-media-structure/owner-final-reviews.json`. The
[next target composition proposal](initial-preparation-target-composition-2026-10-13.md)
names an unqualified Linux worker and its feasibility gaps. Independent and IC-1
bounded design concurrence is recorded in
`.artifacts/initial-media-structure/target-design-v4-reviews.json`; the next
implementation agreement awaits a concrete named target. This authorizes no
installation or execution. This binds the original preparation owner to the
pinned WAV artifact only in a separate Edge-ineligible synthetic fixture; it
does not close target runtime or other-format S0 acceptance. No post-M2
transform or duplicate WAV helper is required. Retained-byte transfer alone does
not authorize a provider grant. Initial dispatch, durable result capture,
successful completion, native media-backed journeys and integrated acceptance
remain open. Installed signer/backend and device qualification retain separately
named authorization requirements. Activation remains disabled and ordinary
access nil. History primary retains all overlapping writes; broader hardening
and capture visual work remain separate. Approved deletion/export/redesign
follow current-scope acceptance.

## Checkpoint 0: evidence and integration agreement

Establish the matrix below before checkpoint 1. The history primary agent is the
only writer for this roadmap, history code and shared migrations. Independent
agents review read-only. The initial-analysis hardening effort remains
separately owned under its
[coordination contract](main-analysis-lifecycle-hardening-2026-10-10.md).

The shared interface is recorded in
[Initial completion and history interface, IC-1](initial-completion-history-interface-2026-10-11.md).
It pins the initial input/result/receipt owners, six fixed service operations,
fresh media route adapters and historical Describe recovery, retry/recovery
semantics, private erasure, scoped locking, writer responsibilities and forward
dependency order. IC-1 revision 2 was acknowledged and independently reviewed.
Revision 3 records the media-required scope amendment; its exact review is
recorded separately. Exact revision acknowledgement is retained in
`.artifacts/initial-completion-agreement/checkpoint.md`.

The agreed minimum dependency S0 includes immutable original input, permanent
logical-operation dispatch fencing, durable validated-result evidence, original
configuration/funding and exact media binding. Checkpoint 1 may prepare inactive
schema/contracts/adapters and isolated tests. The new initial completion path
cannot run until all S0 dependencies, fresh media admission guards and
applicable original-route recovery/cleanup adapters are integrated. Existing
live handlers must not adopt a partial sidecar path.
`initial_analysis_lifecycle_enabled` remains false until a separately authorized
coordinated cutover with incompatible workers quiesced.

This resolves the interface design before checkpoint 1; it does not implement or
qualify S0, transfer shared writing ownership, or close the initial-engine
hardening row. The generated initial capture DTO remains unchanged. Current
private scan/ingestion payloads and scan-only success verification cannot be
substituted for the agreed immutable input and exact completion receipt.

## Checkpoint 1: private evidence and media-backed source contracts

### Initial evidence privacy and idempotency

The proposed record is private and write-once during its lifetime, not retained
scientific data. It is owner/scan/operation-bound and stores canonical submitted
descriptions in their original order. Ordinary clients cannot write it, and
public/history projections expose only the authorized contract.

Erase the record on individual scan deletion and account detachment, whether or
not the observation has enrolled in history. A foreign key on scan deletion
alone is insufficient because account detachment can retain the scan row.
Deletion admission must fence late completion; erasure and completion serialize
so neither transaction order can recreate private text after deletion. Retain
only content-free tombstone/operation identity needed to reject resurrection;
text-derived digests remain private evidence and are erased too. Any
immutability guard must permit authorized erasure, including cascades, under the
reviewed lock discipline. Recheck live ownership and deletion fences before both
first insert and duplicate-receipt return. Identical retries are accepted only
while the original live ownership remains valid; erasure takes precedence over
idempotent replay.

Test enrolled and unenrolled deletion, both race orders, duplicate completion,
conflicting text/order/owner/operation retries, lost responses, and delayed
completion after detachment. Evidence must be absent from scientific retention,
logs, public output, remaining private history and recovery payloads after the
applicable erasure completes. Update the
[retention contract](../backend-and-data/17-scientific-observation-retention.md)
with implementation; its current enrolled/unenrolled distinction is not an
exception for this new private record.

### Coordinated media-required admission and transition

Do not implement the superseded standalone V1 text child, `multimodal_text_v1`
profile, no-upload execution path, text-only editor or
`source_text_analysis_enabled` gate. Existing versioned readers retain their
exact supported historical shapes; no source-null or old record may fall through
into a new execution case.

Fresh native and backend admission must require actual eligible media, including
non-UI callers and the old Describe entrypoint. Text may be added to that media;
its accepted ordered bytes must survive source fingerprinting, queue
restoration, provider input, completion and history reading. Do not force a
profile/provider change merely because accompanying text exists. Preserve
existing provider policy and reject conflicting source, permission or profile
before funding or invocation. DTO/version changes, if needed, require
coordinated producer and reader review; this scope decision does not itself bump
protocols.

Separate fresh requests from already server-admitted work by original durable
identity and positive server evidence. Accepted old Describe operations retain
exact status/result/completion/cancellation recovery under their saved route and
funding. Local-only queued no-media work remains preserved but blocked for user
remediation; it is not silently rewritten into another operation. Admission
uncertainty permits original-operation recovery only. This transition must not
create another provider invocation, retroactively demand replacement media for
an already accepted operation, or resurrect deleted evidence.

Every new history child requires the correct source analysis ID, immutable
source media provenance, media availability and accompanying ordered
descriptions. Use the existing source reservation, fingerprint, funding,
prepared-media queue, dispatch, settlement and completion contracts. Exact
source identity must cover raw evidence and derived preparation, not display
thumbnails. Editing details never detaches the child from the explicitly
targeted source analysis/version. Explicit replacement is validated before
admission and cannot mutate an admitted operation's input.

Complete the video extension across source availability/loading, queue-owned
original video and applicable frames/audio, preparation and verified byte
binding, retention/cleanup, original funding and exact recovery, result readers
and native routing. Existing V5 execution/history reading is useful evidence,
not proof of source reuse or the full video journey. Missing/removed raw media
blocks or requires explicit replacement; no media-less fallback or synthesized
source.

Initial completion still stores private immutable submitted context atomically
with the original scan/result receipt. Enrollment may use the agreed closed V3
available/unavailable description projection, but descriptions alone never
confer reanalysis eligibility. Media must have independently verified source
identity and availability. No notes, model reasoning or mutable replay fallback.
Child completion does not automatically change selection/review; unknown
execution permits recovery of the original operation only. Erasure rules above
apply.

## Checkpoint 2: native journey and installed qualification build

Retain immutable source-description context alongside the explicitly targeted
source analysis/version and its media in `ObservationReanalysisSource`. Route
explicitly to photo, audio or video based on validated source capability. Allow
context editing within that media-backed journey; there is no separate text-only
submission/editor. Persist source and child identity, media ownership and exact
context in the durable queue. Restore before dispatch, recover after uncertain
dispatch, await receipt-bound cleanup and reopen the completed child with its
original source evidence.

Add native admission guards for missing media and transition handling for old
local-only no-media queue records. Preserve valid accepted operation recovery.
This functional work does not authorize the separate capture visual refactor or
its detailed Add details session/occupancy redesign. Qualify functional media
admission and photo/audio/video journeys in existing shells first; neither S0
nor this acceptance waits for that later visual refactor. Its implementation
waits for both relevant workstream handoffs and fresh final approval, preventing
a circular qualification dependency.

Prepare a dedicated `HistoryQualification` configuration and scheme in
`project.yml` and regenerate the project. The
[planned real-app environment](../development-guides/24-identification-history-device-review.md#planned-real-app-qualification-environment)
owns target validation, isolated local namespaces, compile-time containment and
separate operation/target approval. Earlier production-denial/nonproduction-only
planning is superseded by that beta-target plan, not by a guard bypass. The
qualification configuration and its executable checks require scoped
implementation and review before use; ordinary Debug/Release installation stays
hard-false. Use actual navigation, `AppDIContainer`, durable queue owners and
disk-backed storage. No preference or remote flag may enable ordinary history.

Current source boundaries are
[`PreparedHistoryReanalysisComposition`](../../apps/ios/Merian/App/Composition/PreparedHistoryReanalysisComposition.swift),
`MerianApp`, `MerianEnvironment` and `project.yml`. Current Debug and Release
both use `Config.xcconfig`; ordinary Debug includes a production-Supabase
allowance. Reusing those defaults without fail-closed qualification checks is
insufficient.

Existing in-memory fixtures are useful component evidence, not installed-app
qualification. The user owns device installation and testing after the specific
build/environment is authorized. Record the artifact hash, source SHA,
configuration, backend revision and sanitized results. For each of photo, audio
and video, exercise actual navigation, submission, process termination,
relaunch, durable restoration, backend status/outcome recovery, completion and
history reopening. Kill after dispatch as well as before dispatch; prove that
recovery does not resend provider work. Preserve pending environment answers and
prior device results; request only missing information needed for this specific
qualification configuration.

## Checkpoint 3: actions, contention and integrated candidate

Qualify supported selection, review, Undo and protected-chat behavior for
photo/audio/video with revision and account fences. Photo publication must be
offered only for qualifying V2 photo evidence, never inferred merely from a
non-audio result version. Tighten
`ObservationAnalysisReviewTicket.supportsPhotoPublicationFormat` and verify that
historical text baselines do not advertise publication. Video reanalysis is
required; video selection/review/publication/chat remain subject to separately
supported policy and must not be inferred from V5 alone. Capture the
supported-action mapping in native and server contract tests.

Close the bounded contention gaps from the integrated audit: cross-version quota
admission and settlement, terminal transitions in both transaction orders, and
multi-owner cases, including media/context changes and the new video source
path. Reuse accepted source release/cascade evidence when its source hashes
remain unchanged; do not invent new slices or rerun broad suites without a
changed boundary. The
[C1 deadlock acceptance](initial-cancellation-interface-2026-10-11.md#deadlock-evidence-and-public-path-acceptance--october-12-2026)
requirement is part of this existing contention gate and applies at final
integration/acceptance before atomic/C1 public-path qualification; fixture
isolation alone cannot close it. Per the user's sequencing clarification,
historical stage93 is not reproduced in subsequent runs; dedicated root-cause
investigation is deferred to final acceptance. Continue implementation and
normal regression/concurrency testing without making that investigation an
intermediate checkpoint prerequisite. Reopen it earlier if it blocks
implementation or reliable validation, or recurs in normal application paths.
Passing reruns are not a fix; retain failures and diagnostics and require
independent/IC-1 final disposition. Normal gates and release/activation
restrictions are unchanged.

Each checkpoint updates contracts/docs and the matrix, receives independent
read-only review and re-review after fixes, and runs focused verification.
Milestones run the full affected repository gates against the scoped candidate.
Preserve failures and distinguish shared-worktree runs from scoped validation.
Record the changed-path CI mapping for handwritten source-media/context
contracts, Swift/Deno/SQL fingerprint vectors, and the new
qualification-configuration guard. Update the shared analysis-history README,
database/API/retention contracts, deployment runbook, testing strategy,
identification-history device review guide and affected iOS ownership READMEs
with their corresponding implementation. Do not describe proposed behavior there
as already implemented. Final CI must name the exact candidate commit and all
required checks; pending, skipped or older-head runs cannot establish
acceptance.

## Checkpoint 4: external acceptance and release handoff

Close installed-device and explicitly authorized beta-target backend
qualification, including hardware/resource behavior for photo/audio/video,
account changes, scan and account erasure, storage cleanup, and operational
recovery. Keep initial-engine hardening and Field Trip's held reconciliation
consumer separately identified; neither is satisfied by history test totals. No
hosted mutation, deployment or worker scheduling occurs without authorization
naming the operation and target.

The handoff contains the exact source/artifact/backend revisions, completed
matrix, independent review findings and their disposition, required CI results,
external evidence, remaining exclusions and rollback controls. Production gates
remain closed. A later activation decision is separate from this handoff.

## Capability and evidence matrix

October 16 allocation status:
[SMA-1](shared-media-allocation-ownership-2026-10-16.md) specifies the proposed
native shared authority and bootstrap boundaries. It adds no passing capability
evidence: G1–G4 and A2/A3/A5/A14/A16/A17 remain open until the relevant exact
implementation, lifecycle and resource gates pass. Legacy readability is not
fresh-admission eligibility; no text-only fallback is added.

Owners: **History primary** is the sole implementation/evidence writer in this
thread. **Hardening owner** is the separately owned initial-analysis effort;
shared writes require the checkpoint 0 agreement. **User/operator** owns device
testing and explicitly authorized named-target operations. Reviewers are
independent and read-only. These assignments do not grant external permissions.

Status meanings: **ready locally** means only the named local checkpoint passed;
**blocked** means a specific prerequisite is missing; **unqualified** means
implementation or external evidence is still required. A row becomes qualified
only when all its pass conditions have exact-candidate evidence. Update evidence
references and status after each checkpoint; do not erase prior failures.

| ID  | Required capability                                       | Accountable owner                                                                       | Current status / evidence                                                                                | Concrete pass condition                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --- | --------------------------------------------------------- | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A0  | Foundation and parity repair                              | History primary                                                                         | Ready locally: `b8eb3d64f`; parity checkpoint                                                            | Preserve reviewed foundation and its scoped validation; publish only after resolving the exact push approval blocker.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| A1  | Initial completion agreement and media-required amendment | History primary, with Hardening owner interface agreement                               | Design only; revision 3 evidence in media-required-scope                                                 | Exact IC-1 revision 3 acknowledged and independently reviewed, including fresh media admission, accepted-operation recovery, local-only queue remediation, video source scope, owners and dependency order.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| A2  | Fresh media-backed initial submitted evidence             | History primary after A1 interface agreement                                            | Unqualified: S0 and fresh admission integration open                                                     | Native and every fresh backend entry require eligible media; original media plus ordered optional context, result and scan commit atomically; identical replay succeeds, conflicts reject, no scan-only success inference.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| A3  | Evidence privacy before and after enrollment              | History primary after A1 interface agreement                                            | Unqualified: new erasure contract                                                                        | Scan deletion and account detachment erase text in both enrollment states; both race orders and delayed completion cannot resurrect it; retention/public/log projections exclude it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| A4  | Media-backed initial enrollment and original evidence     | History primary                                                                         | Unqualified: coordinated evidence/source projection pending                                              | Both closed V3 description variants read exactly; media provenance/availability independently determines reanalysis eligibility; no fabricated execution date/digest, notes fallback or deleted/foreign evidence.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| A5  | Source-bound media/context contracts and transition       | History primary                                                                         | Unqualified: combined contract and transition not implemented                                            | Photo/audio/video source IDs, exact media/context fingerprints, preparation, readers and native actions agree; old text records remain readable; already-admitted operations recover exactly; local-only no-media work is preserved/held and unknown admission recovers before classification.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| A6  | Source-bound video child lifecycle                        | History primary                                                                         | Unqualified: execution/reader foundation is not complete source reuse                                    | Correct retained/chosen raw video plus applicable frames/audio and context flows through source reservation, durable queue, preparation, verified binding, original funding, exact recovery and one completion; missing media blocks, no auto-selection/review transfer.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| A7  | Photo child lifecycle                                     | History primary                                                                         | Ready locally at foundation; integrated/installed journey unqualified                                    | Existing scoped photo evidence remains valid by hash; final source-media/context, transition, cancellation/deletion and recovery integration passes; installed evidence satisfies A11.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| A8  | Audio child lifecycle                                     | History primary                                                                         | Ready locally at foundation; integrated/installed journey unqualified                                    | Retained source/capture queue ownership, exact context, receipt-bound awaited cleanup and separate dispatch/settlement fences remain proven; integration passes and installed evidence satisfies A12.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| A9  | Isolated installed qualification configuration            | History primary; User/operator authorizes target/use                                    | Inactive preparation authorized; implementation pending; installed use awaits named target authorization | Planned acceptance (configuration not implemented): generated HistoryQualification configuration alone compiles the qualification selector and installs real DI/navigation/disk storage with isolated bundle/app-group/keychain/disk/auth namespaces; the planned beta-target contract has reviewed fail-closed project/host and operation-scope checks before use; Debug/Release remain nil in executable checks. See the qualification environment plan; no guard change or installation is authorized here.                                                                                                                                                                                                                                                                                                                                                                                                  |
| A10 | Installed initial video and video child                   | User/operator; History primary packages evidence                                        | Unqualified                                                                                              | Exact artifact/backend run proves initial media save/enroll, retained/chosen video source with context, real preparation, restart before/after dispatch, original operation recovery, history reopen and deletion; in-memory fixtures do not count.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| A11 | Installed initial photo and photo child                   | User/operator; History primary packages evidence                                        | Unqualified                                                                                              | Same real installed journey as A10 for photo, with source/new-media handling and acknowledged cleanup; actual navigation and persistence survive relaunch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| A12 | Installed initial audio and audio child                   | User/operator; History primary packages evidence                                        | Unqualified                                                                                              | Same real installed journey as A10 for audio, including retained composition, source/capture routing, hardware interruptions and receipt-bound cleanup.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| A13 | Supported media-backed actions and exclusions             | History primary                                                                         | Unqualified: combined video/media-context routing pending                                                | Photo/audio/video reanalysis routes correctly and fails closed without source media; selection/review/Undo/chat and qualifying photo publication follow explicit policy. Video reanalysis is included; no inferred video publication/review permission.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| A14 | Database contention                                       | History primary                                                                         | Unqualified: bounded audit gaps remain                                                                   | Both-order admission/settlement/terminal races across media input versions, context edits, accepted legacy transition and multi-owner cases pass; unchanged source-release/cascade evidence remains applicable. Follow [C1 deadlock acceptance](initial-cancellation-interface-2026-10-11.md#deadlock-evidence-and-public-path-acceptance--october-12-2026): preserve stage93 failures, continue normal real-owner overlap tests under actual permissions, capture sanitized correlation on recurrence, and record verified correction or independently/IC-1-reviewed unreproduced residual risk at final acceptance. Dedicated historical investigation is deferred until then unless it blocks work/reliable validation or recurs in normal paths; passing reruns are not a fix. Reproduced unresolved runtime cycles block acceptance; no evidence waiver or scope reduction without explicit user approval. |
| A15 | Initial-engine hardening dependencies                     | Hardening owner; History primary verifies integration                                   | Unqualified: S0 and broader hardening remain open                                                        | Validate IC-1 S0 and media-required admission across fresh entrypoints; preserve original-route recovery/cleanup for accepted Describe work and safely hold local-only no-media requests. Broader hardening and installed/hosted qualification remain separate.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| A16 | Hosted privacy, storage and operational recovery          | User/operator; History primary defines/evaluates cases                                  | Unqualified; target and operation authorization required                                                 | Explicitly authorized beta-target run records its exact operation/data scope and server gate set and proves erasure, storage/cleanup and recovery on exact revisions, including unenrolled evidence deletion and no provider reinvocation after unknown execution; production gates remain false.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| A17 | Device/resource acceptance                                | User/operator                                                                           | Unqualified; preserve prior results and pending answers                                                  | Agreed photo/audio/video hardware, media preparation, interruption, background/resource pressure and fresh-library disk-backed restart cases pass on the exact candidate.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| A18 | Field Trip held reconciliation                            | History primary tracks closure; separate consumer implementer must be named before work | Blocked separately; consumer assignment not established here                                             | Named consumer acceptance demonstrates required reconciliation or the candidate explicitly remains blocked for that requirement; history tests cannot substitute.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| A19 | Final candidate review and local gates                    | History primary; independent reviewers                                                  | NCO/BI isolated local gates passed; full alpha/PR candidate open                                         | Cumulative functional audit above covers the whole implemented candidate, requirement/code/evidence mapping and one findings register; synchronized docs, full affected gates and independent verification of fixes pass on exact final source. Later changes have explicit evidence applicability.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| A20 | Final candidate CI                                        | History primary                                                                         | Blocked: follow-up candidate unpublished                                                                 | Required CI for the exact final PR candidate SHA passes; record check names, run links and head identity. Resolve private-source export approval first; no previous-head green substitute.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| A21 | Qualified release-candidate handoff                       | History primary; User/operator supplies external evidence                               | Blocked on required rows                                                                                 | A1–A20 are satisfied with evidence or an explicit user scope decision changes the requirement; exact artifacts/revisions, exclusions and rollback controls recorded; production gates remain disabled.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

No new execution tests are claimed by this planning document. The foundation's
5,893 native tests preceded two test-only lint edits; its final rebuilt focused
26 tests and backend 3,493 tests plus 484 steps are documented separately. Those
results do not qualify the required media-admission transition, video
reanalysis, installed build or hosted flows. Historical roadmap text and hashes
remain in `.artifacts/media-required-scope/`; this revision replaces planned
behavior, not completed implementation evidence.
