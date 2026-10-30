## Sealed-file upload lifetime candidate — October 30

`SharedMediaNativePhotoUpload` connects the existing file owner to a concrete
upload task while retaining receiving locks and account ownership through actual
termination, including failure and cancellation. Its Release construction is
closed; only intercepted Debug unit tests can construct the candidate. No status
observation, response code or local termination releases durable transfer
liability. Engine source review and focused native qualification passed 13
methods / 31 cases. The earlier test-macro compilation failure is retained
separately. See the
[scan contract](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-30--sealed-file-upload-lifetime-candidate-unqualified)
for exclusions, integration requirements and unqualified copy-budget
measurements.

## Durable historical attempt candidate — October 29

The existing allocation owner now has an inactive V4 status slot for the exact
reserved transfer role. It reserves metadata and revision runway before
monotonic observations and retains the existing copy liability. Engine source
review and focused native qualification passed 24 methods / 79 cases across
retained runs; the initial selector coverage gap remains recorded. No upload
authority or network caller is installed. The
[scan guide](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--durable-historical-attempt-candidate)
owns state transitions, compatibility, accounting and remaining integration.

## Local reserved-role verification candidate — October 29

The existing retained owner now exposes exact-reservation local hash/count
verification for source, AI and display, returning only a bounded summary. It
reuses the sealed 64 KiB reader and keeps the durable hold on every outcome.
Focused native qualification passed 8 methods / 34 cases with unchanged inputs
and no structured runtime warnings. The follow-up hash-loop suite passed 4
methods / 10 cases, including 32 MiB chunk bounds and in-loop faults.
Report-only reader memory measurements are retained in the scan guide; they do
not qualify whole-owner retention. Upload consumption, staging-copy ownership
and remote closure remain absent. The
[current scan guide](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--local-reserved-role-byte-verification-candidate)
owns the lifetime contract and remaining acceptance. A new Debug-only owner
drain test candidate covers shutdown during the actual role hash loop; its
source/AI/display runtime qualification passed one method / three cases with
unchanged pinned inputs and no structured runtime warnings. Follow-up coverage
now drives the registered drain through Auth's ordering helper during the paused
role read; both direct-owner and registered-drain methods passed all six role
cases with unchanged pinned inputs and no structured runtime warnings. This
synthetic, unconfigured drain fixture does not qualify configured discovery
lifetime, real Auth transitions, AppDI installation or full journeys. The linked
scan guide owns those limits.

## Current single-role transfer reservation — October 29

The inactive native allocation owner now persists one exact reserved,
not-started role and reconstructs its 32 MiB additional-copy liability on
restart. It has no source-access, upload or retirement capability. Focused
native qualification passed (28 methods / 67 cases reconciled across retained
runs), alongside Engine source review and corrected preflight. The
[scan-ingestion contract](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--inactive-single-role-transfer-reservation-candidate)
owns the transition, accounting, recovery and remaining integration. Earlier
dated sections below retain their historical scope; v2 transport and Capture
composition are qualified as recorded there.

## October 29 — native v2 transport candidate

The inactive native owner and authenticated adapter now support explicitly
reserved v2 create/status. That owner/transport checkpoint passed Engine review
and 17 methods / 49 cases. The inactive Capture composition now selects v2 and
passed focused native qualification: 9 methods / 22 cases. Engine cleared
production; the corrected test-macro failure remains retained. The ordinary
factory remains disabled. The
[scan transport contract](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--native-v2-transport-integration-candidate)
owns dispatch, durable reservation, exact recovery and remaining integration.

## Current allocation integration — October 29

The inactive Capture allocation caller and cold recovery are locally qualified;
ordinary factory installation remains disabled. This supersedes the pending
caller statements in the dated checkpoints below. The
[scan entry point](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
owns current qualification and remaining journey work. The new
[v2 role projection](../../../../../../docs/backend-and-data/05-api-contracts.md#october-29--versioned-photo-allocation-role-projection-inactive)
and native decoder are joined by an inactive explicit reservation/enrichment
writer, locally qualified across 13 methods / 38 cases. Ordinary callers retain
v1. The
[canonical transition contract](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#native-allocation-enrichment-inactive-candidate)
owns byte preservation, metadata/revision accounting and recovery. Authenticated
v2 transport and Capture composition are qualified above; transfer, remote
closure and admission remain pending.

## October 28 — allocation consuming integration candidate

The inactive `allocateAppPhoto` entry now joins the retained receiving owner,
exact claim/receipt writer and bounded authenticated create/status adapter. This
batch has passed focused runtime validation; **integration acceptance remains
open**. The V67 checkpoint below remains historical evidence for dormant
storage, not qualification of this writer. The canonical
[scan-ingestion entry point](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
owns lifecycle, limits and recovery rules. The existing owner permits one active
operation; overlapping requests fail busy rather than starting another request.
No Capture UI caller, upload, execution or release authority is enabled.

`SharedMediaNativePhotoAllocationPeer` carries clean immutable peer evidence
through existing facts and writer poststates so a held allocation can coexist
with independent drafts; generic mutation of the allocated target remains
closed. Compilation, independent source review and affected runtime validation
passed: **192 methods / 439 cases** across allocation, app writers,
receiving/staging, release and terminal accounting. The managed Release build
also passed on unchanged native/project inputs. The unrelated Auth architecture
size-gate disposition remains open. The canonical scan-ingestion guide linked
above owns detailed evidence, including the retained selector-manifest failure
and its completed missing coverage.

## October 28 — dormant native allocation storage qualified locally

The V67 receiving-side allocation fields and conservative release/recovery holds
are implemented and locally qualified. Combined focused Debug evidence covers
189 methods / 223 cases; the original failed run and four-method repair rerun
remain retained. Engine review and the full iOS tooling gate passed. The
canonical schema contract records exact scope and limitations:
[V67 storage and validation](../../../../../../docs/backend-and-data/04-database-schema.md).
The
[scan-ingestion entry point](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
traces the current journey and owners.

The allocation consuming implementation above supersedes the pending-writer
status of this dormant-storage checkpoint. App wiring and runtime qualification
remain pending. Initial photo result/history, reanalysis with preserved
versions, full photo qualification, audio/video and RUX acceptance remain open,
followed by the approved deletion/export/redesign sequence. Activation,
deployment and PR116 holds are unchanged.

## Retained photo admission — locally qualified checkpoint

The inactive `stageAppReceivingWithAdmission` entry keeps discovery, fresh
preflight and immutable staging inside the original owner's single retained
operation. Fresh preflight occurs before receiving locks; account shutdown still
cancels and drains it. Saved Prepared slots, including legacy nil expectations,
skip recipient discovery. Metadata and ordered selected intents are checked
before preflight and the existing staging fences recheck them before save. The
current authorization validator runs synchronously at the immutable save
boundary.

This reuses the existing grant, lock, identity and persistence owners. It grants
no upload, funding or execution rights. Focused local Debug qualification passed
36 methods / 62 cases with no source drift or structured runtime warnings. Live
consent synchronization and endpoint composition remain unconnected; see the
[photo content contract](../../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md).

## October 28 — inactive saved CPM admission candidate

`SharedMediaNativePhotoAdmission` snapshots protocol 3, identification protocol
6 and the expected processor from a validated dispatch authorization. The
existing V2 Prepared envelope and consumer intent binding retain this optional
value. Supplied retry expectations must match; an omitted expectation recovers
the original saved value. Legacy values without this field keep their encoding.
V1 cannot carry the new value. Older canonical readers reject new bytes rather
than silently dropping the expectation.

`SharedMediaNativePhotoCandidate` wraps the exact saved photo content and
admission expectation using the separate candidate digest defined in the
[content contract](../../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md).
Release-origin reconstruction preserves the field, and existing accounting
measures the enlarged encoded values. Neither the snapshot nor candidate grants
network, storage, funding or execution authority. Live integration still must
bind preflight to the saved logical identity before allocation I/O and
revalidate current authorization independently.

Independent Engine source and test-delta review found no blocking defect.
Combined focused Debug evidence qualifies 26 methods / 45 cases, with no drift
across 3035 native/project pins and no structured runtime warnings. The first
run retained one test lifecycle failure; a test-only correction passed its
focused rerun, with unchanged passing cases reused under an explicit
applicability check. An intermediate filter selected zero tests and was
rejected; the corrected exact selector used unchanged built products. Coverage
includes independent wire bytes, malformed expectations, fixed historical V2
codec bytes (non-admissible nested placeholders), and actual one-photo
receiving/release recovery through terminal settlement with funding assertions.
This does not qualify a complete historical V2 graph fixture, two-photo cleanup,
fault injection, full app journeys or a new Release. No application caller or
profile is enabled.

## October 27 — inactive photo content mapping

`SharedMediaNativePhotoContent` projects a validated saved V2 Prepared value
into the closed photo content declaration defined by the
[content contract](../../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md).
It uses frozen cohort positions, logical role references, exact contexts and
binary64 recipe bits. It stores immutable canonical bytes and an explicitly
unverified digest. It performs no media read, storage write or current receiving
check; successful encoding supplies no account, byte, funding or dispatch
authority. A future consuming operation must use the existing receiving owner
and its exact persisted/current fences. No runtime caller is installed.

Source review and focused native compilation/parity validation passed: seven
methods / twenty cases, with no source drift across 3,033 native/project pins
and no structured runtime warnings. This is shared-checkout Debug validation,
not a new Release or full app-journey qualification. Legacy V1 decoding and all
ordinary activation controls are unchanged.

## October 27 — received-photo input handoff implementation

`readReceivedAppPhotos` reads bounded, ordered AI derivatives from the exact
saved P2 received submission through the existing native owner and receiving
locks. The scoped audit, held quartet, frozen cohort and live account/header
checks remain mandatory. Descriptor-bound reads verify consumed lengths and
hashes; all completion proofs are sealed after the final read. Missing, replaced
or retired media and changed authority withhold the entire projection.

The returned value preserves the original prepared identity, received cohort and
frozen supporting bytes. It contains no original-media bytes or paths and
confers no provider, retry, funding or mutation authority. The mutable prepared
reader keeps its existing contract. Receiving inspection is factored into the
same bounded I/O leaf without changing its checks. This implements the input
handoff needed by the initial-photo execution bridge; queue execution, result
persistence and history delivery are still separate integration work. Ordinary
activation remains disabled.

Local focused Debug validation covers 43 distinct methods / 104 cases across
retained runs: 37 / 83 unchanged passing regression cases, 5 / 20 corrected
received-photo cases, and 1 / 1 release-stage replay/reopen case. The combined
evidence checks all 3,031 native/project inputs; only the corrected test file
changed between the reused runs. Earlier compile, test-helper and incomplete
selector outcomes remain retained failures or incomplete evidence. This is
shared-checkout coding-checkpoint validation, not a single full-target run,
isolated-source qualification, new Release build or complete app journey.
Execution/result integration, explicit history enrollment, installed UI,
photo/audio/video and recovery UX acceptance remain open.

## October 27 — received-identity discovery qualified locally

The inactive native owner exposes bounded received-candidate discovery through
its existing dispatch operation. It runs the complete scoped audit before fresh
release-aware CleanGraph reads and retains grant/profile/header checks. Only
generic received identities are projected; prepared, staged, releasing and
historical released work is excluded. An empty result does not prove that
durable work is absent or authorize resubmission. No schema, execution owner,
funding rule or provider authority changes.

CaptureNativeRecoveryModel presents noneditable local holding identities. All
candidates remain unselected until explicit exact selection and a fresh read.
Changed identities and late account/container/presentation results refuse; Close
changes presentation only. The model neither reconstructs an editable submission
nor proves original-media availability. No production Capture caller is wired to
this model yet: host/current-scope binding, actual process-relaunch UI, remote
Check status, RUX recovery presentation and complete photo/audio/video initial
and reanalysis journeys remain open. Ordinary composition stays inactive.

Local qualification covers 56 unique methods / 101 cases: corrected tests03
passed 24 methods / 28 cases, composed with 32 unchanged methods / 73 cases
independently reviewed from retained passing results. The first focused run's
pause-hook/selector failure and regression01's owner-size failure remain failed
and retained. The correction reuses the existing private operation wrapper and
keeps the 600-line boundary unchanged. Generic Simulator Release passed with
zero errors and 365 warnings; all 3,027 source/project pins matched. These are
local discovery/replay and architecture results, not full-target,
isolated-source, installed UI, device or provider acceptance. Release and
deployment holds remain.

## October 26 — mutable prepared-photo readback qualified locally

`currentAppMetadata` preserves the persisted metadata bytes without editing or
saving. `readPreparedAppPhotos` uses the existing app-dispatch and preparation
owners to return one or two exact ordered ready pairs, immutable original
references and bounded AI/display bytes. It checks both complete cohort budgets
before reading, seals each actual-byte read with the same physical completion
proof, and rechecks the whole persisted selection and every completion after the
final suspension. Cancellation, account changes, metadata drift, replacement
files and Prepared/received slots refuse without returning a partial projection.

No path or file capability escapes. Original decoding/cropping stays native;
display bytes are never substitute originals. This read performs no processing,
save, recovery, queue, funding or provider action. Capture's submit fixture now
uses this producer. Camera/picker/editor binding, frozen restart reconstruction
and full media journeys remain open; ordinary activation remains disabled. The
readback, Capture submission and affected metadata, preparation, lifecycle,
pending-cleanup and architecture checks passed the managed Debug qualification:
50 methods / 103 cases, no failures or skips, no structured runtime warnings and
no drift across 3017 source pins. The earlier two owner-inventory failures
remain retained; consolidating identical dispatch validation in the same private
owner corrected them without changing visibility or limits.

## October 26 — expected selection at native receiving

`stageAppReceiving` accepts an optional exact metadata expectation from the
inactive
[Capture submit bridge](../../../Features/Capture/Submission/README.md). Fresh
and recovered Prepared values must retain the expected profile, package,
membership and persisted envelope. The existing audits, physical checks and
pre-save seals still own authority; unrelated inventory progress does not rebase
the target. Prepared owns the pure draft/pair selection assertion shared by
staging and restaging. Received recovery compares the original submitted
selection, never a mutable post-receive package. The bridge and affected
receiving/recovery checks passed the 60-method / 81-case managed Debug
checkpoint documented in the Submission contract. Ordinary app activation
remains closed; upstream feature binding and complete media journeys remain
unqualified.

## October 25 — deferred native owner admission runtime qualified

The inactive AppDI composition now retains startup provenance until an explicit
feature request obtains stable account admission. Initial Auth transitions have
no native hook to seal. Admission installs one hook and retains the lifetime,
owner and shared opening task before suspension; concurrent requests coalesce
only within the same account runtime. Every preliminary lease is finished.
Signed-out or failed-hook refusal remains retryable before installation.

Fresh bootstrap promotes the same owner and repository to dispatch after
profile, database and physical-binding validation. Handles, epoch, discovery
transfer and fences remain continuous. Initialization grants become invalid;
readiness appears only after inspection and account/lifetime revalidation.
Existing profiles open directly. A cancelled caller cannot abandon shared
opening or cleanup. Failed shutdown retains the owner and repository for
explicit reconciliation; successful shutdown clears AppDI ownership through an
identity-checked callback, leaving the installed lifetime terminal.

Grant creation and lifecycle state remain private to the native owner. The
opening-operations helper orchestrates already-authorized repository work; the
DEBUG extension supplies typed test commands without owner-state access or
capability construction. The existing repository and scoped audit retain their
mutation and validation responsibilities. No owner ceiling was increased.

App acquisition now chooses the reservation envelope once before the first save
and retains those exact bytes in its settlement ticket. An absent package uses
that same envelope for reservation; an existing package retains its original
bytes. Lost reservation acknowledgement cannot require a second JSON encoding,
and semantically equivalent but changed bytes still refuse settlement. The
initial focused run and diagnostic follow-ups failed shutdown recovery and the
60-second media journey. After the envelope and directory-flush corrections, the
focused eight-method / eighteen-case run and the broader 103-method / 237-case
checkpoint both passed and qualified. The three exact-envelope cases passed in
both runs. Prior failures remain retained; passing results do not establish a
fix for the separately deferred historical timeout/performance investigation.

Steady-state bootstrap checks retain every control-file read, byte/identity
validation and file flush. They batch the shared parent-directory flush once at
the end of a successful check, before returning authority to the caller. Initial
bootstrap/discovery reads retain their original per-read directory flush.
Dispatch binding still performs its complete pre- and post-read checks; no
physical or account check is removed by this batching. The complete
prepared-media journey passed at approximately 59.7 seconds in the focused run
and 59.6 seconds in the broader run, against the unchanged 60-second limit. This
is narrow timing margin, not robust performance headroom.

Eight new admission methods cover nine cases, plus a new capability-boundary
check. The broader checkpoint qualified 103 methods / 237 cases with zero
failures, skips, structured runtime warnings or drift across 3,011 source pins.
Release compilation passed and qualified on October 26 for the generic iOS
Simulator destination, with all 3,011 source pins unchanged. Safe cache
deduplication preceded the successful run after an earlier disk preflight block.
Managed isolated cleanup left 25.3 GiB free and retained 9.6 MiB of evidence,
satisfying the unchanged 20 GiB final-space and 256 MiB evidence limits. This
was compilation only; no installation or activation occurred. Project generation
and project validation passed. The ordinary installation gate remains hard
false. Capture adapter, native execution bridge, actual photo/audio/video
initial/reanalysis journeys, RUX-1–RUX-6 and full acceptance remain open. A
local prepared-media receiving test does not qualify provider execution or
funding. Prior dated entries below describe their original checkpoints. PR116
remains frozen and the deployment hold remains active.

## October 25 — inactive App/Auth native lifetime integration

AppDI now has a one-time native lifetime configuration called after the startup
bootstrap result. The existing source-controlled installation gate remains
false, so ordinary Debug/Release creates no lifetime and installs no hook.
Configuration itself retains only the exact container/startup admission; it
performs no account admission, filesystem work, profile opening or dispatch. The
separate native Auth hook is installed before the lifetime becomes reachable.
Duplicate binding refuses without replacing either hook.

Explicit discovery first acquires and retains the original account lease, then
selects the existing fixed control parent. Cancellation or account mismatch
before/after discovery burns the attempt, releases provisional fences and
finishes that exact lease once. Native-owner registration requires successful
discovery and both account accesses to recognize the retained lease, including
its runtime/session scope. Initial owner opening must use the exact configured
container. Same-owner access from another runtime cannot adopt discovery.

Auth joins native shutdown, then photo-preparation shutdown, then its existing
account-work drain. Shutdown seals synchronously and invalidates unconsumed
discovery before awaiting the owner. Success finishes the lifetime lease through
its original account access; failure retains the callback/registration and lease
for explicit retry while admission stays closed. Concurrent and cancelled
waiters cannot cancel the shared teardown. A transition before discovery is
intentionally terminal, including an initial Auth transition: there is no
automatic reinstallation or post-transition discovery in this increment.

No native owner is created or retained by this wiring. Subsequent integration
must retain the actual owner in AppDI through successful shutdown (especially
failed settlement recovery), rather than create an owner/drain retain cycle. It
must also surface configuration failures before any future gate enablement.
Focused local validation passed all 47 methods / 53 argument cases with zero
failures, skips or structured runtime warnings. All 3,005 source/project pins
remained unchanged; the 20 GiB final storage floor and 256 MiB evidence cap
passed. The first attempt failed at compilation before executing any tests; the
corrected attempt only unnested an async test assertion and retained its checks.
Both attempts remain recorded. Evidence is
`.artifacts/native-app-capture-handoff-20261020/app-account-lifetime-tests02-qualified.json`
and XCResult `a6d8c89f96074f0b81659db2133f12c0`.

This qualifies the focused shared-checkout component checks. Actual Capture
installation and initial/reanalysis journeys, full-target, isolated/matrix,
RUX-1–RUX-6 and abrupt-exit acceptance remain open. Prior results retain their
original source attribution. PR116 frozen; deployment hold active; AWS
unapproved; no activation or external action.

## October 25 — fixed startup control-parent checkpoint locally qualified

The source-only startup discovery entry selects the fixed app-private
Application Support child `MerianNativeMedia`. It has no App/Auth/Capture
caller. It retains the exact first-success startup fence, store descriptor and
exclusive parent lock; Capture cannot provide a production path. A missing child
is created exclusively relative to the held existing support anchor, only after
proving the database unassociated and checking the existing
free-space/control-overhead allowance.

Only the successful creator establishes backup exclusion and writes the bounded
canonical `parent-created-v1.json` receipt. That version-1 receipt binds the
SQLite UUID, store-fence parent and control-parent physical identity. File,
child and anchor synchronization precede handoff. Every fixed-path reopen
requires the receipt; pre-existing empty, foreign, malformed, unexcluded or
replaced parents hold unchanged. Creation without a valid receipt is preserved
without repair. Once the receipt is durable, interruption can reopen only after
exact proof validation. Associated storage at an unresolved path cannot
initialize another profile.

The existing bootstrap codec owns this receipt and its bounded encoding. It now
lives in `SharedMediaNativeBootstrapCodec.swift`; private descriptors and
mutation remain in the existing file/discovery owners. Exact receipt bytes
survive bootstrap checks and one-shot transfer, and actual bytes replace their
portion of the existing control-overhead bound. Existing arbitrary-parent
qualification profiles retain their prior no-receipt representation. No account
ownership or media authority is conferred by the receipt, and no limits are
increased.

Focused compiled/runtime evidence covers 49 methods / 115 argument cases across
five suites: 48 methods / 114 cases from candidate02 and one corrected method
from candidate03. The original run remains failed because its direct URL
comparison treated a trailing slash as a different directory. Only that test
assertion changed, to exact path plus physical directory identity; the retry
passed. Exact source pins and assertion-only reversal prove that the remaining
production and test source stayed unchanged. This is combined focused evidence,
not a full candidate03 or app-journey acceptance run. There were no skips or
structured runtime warnings. The separate combination receipt is
`.artifacts/native-app-capture-handoff-20261020/app-startup-parent-combined04-qualified.json`.
Source parse, generated-project/migration guards, Markdown and whitespace checks
also passed. Abrupt-process-exit, full-target, isolated/matrix and actual
App/Auth/Capture acceptance remain open.

Actual App/Auth installation still requires account scope before filesystem
work, retained cancellation and joined native shutdown before the general
account-work drain, preserving existing photo-preparation drain ordering.
Activation disabled; PR116 frozen; deployment hold active; AWS unapproved.

## October 25 — profile discovery checkpoint locally qualified

The inactive discovery and ownership-correction candidate passed the scoped
178-method / 410-case plan across two finalized results: 172 methods / 403 cases
in `c4457fdf776c4e4090ae7d32b045db52.xcresult`, followed by the missing six
Capture methods / seven cases in `90ba511a87ba44a781444923f9bb7c26.xcresult`.
The first packet mistakenly named those six methods under the other suite in the
same source file; its incomplete-coverage record remains preserved. The
supplemental run used the correct `CapturePhotoPreparationTests` selector
without rebuilding or repeating passed tests. Exact disjoint method/case
coverage, all 3,002 source and project pins, and 417 compiled-product pins were
verified. There were no failures, skips or structured runtime warnings. Both
architecture inventory assertions now pass under their unchanged limits.
Retained evidence is under 10 MiB and the unchanged 20 GiB final free-space
floor passed.

Evidence and the corrected suite-identity mapping are recorded in
`.artifacts/native-app-capture-handoff-20261020/app-profile-combined03-qualified.json`.
Project generation, project/migration guardrails and changed-Markdown formatting
passed. This qualifies only the local scoped checkpoint. Candidate02's separate
startup/scoped/receiving-clean results remain attributed to that candidate;
complete-target, isolated/matrix, actual App/Auth/Capture integration, initial
and reanalysis journeys and final acceptance remain open. Discovery remains
inactive. Activation disabled; PR116 frozen; deployment hold active; AWS
unapproved.

## October 25 — profile discovery validation and ownership correction

The frozen discovery candidate completed 121 test methods / 265 argument cases:
119 methods passed and two architecture inventory assertions failed. There were
no skips, structured runtime warnings or source/project hash changes. This is a
failed validation result, not complete acceptance. The failures identified two
inherited oversized owners outside the discovery changes.

The correction moves pure acquisition-successor membership size projection to
`SharedMediaMembership.maximumAcquisitionBytes(pending:)`; the acquisition
budget still owns aggregate charging and the same bounded successor states are
counted. The budget owner is now 584 lines. Original-byte read/write/hash
mechanics move behind the existing descriptor scope in
`PhotoPreparationOriginalFiles`, while all locks and proof constructors stay
with `PhotoPreparationLockedFiles`. The existing architecture inventories and
limits remain unchanged. The scoped correction validation is recorded above.
Earlier discovery results remain separately attributed to their exact candidate.

Activation remains disabled; PR116 is frozen and the deployment hold remains.

## Inactive startup profile discovery

Startup-qualified discovery holds the original store fence and a canonical,
existing, backup-excluded Application Support control-parent lock. It selects
only a provisional saved inventory identity and database profile. A fresh UUID
is selected only after both an empty control parent and an unassociated database
are proved. Interrupted bootstrap preserves its original UUID and journal bytes.
Malformed or conflicting evidence never becomes fresh absence.

A one-use transfer passes those same held resources into the existing native
file owner. The existing initialization/open constructor still validates every
journal, root, marker and database association; discovery grants no write right.
Transfer rechecks container, owner, store, parent, inventory, mode and exact
control bytes. Failure consumes the attempt and closes its resources. A retained
consumed discovery holds no locks, and abandoned discovery can be invalidated
explicitly. Inactive owner entries release unused discovery on every exit.
Discovery retains the observed SQLite UUID and an open store descriptor.
Transfer requires the same logical identity and named device/inode, including
the receiving file owner's descriptor, before bootstrap can write. Replacing the
file at the same URL cannot substitute a different store, even with a copied
UUID. The descriptor remains retained until the receiving owner holds its own.

The V1 acquisition helper now owns its reserve/readback/load/write/complete
sequence, with private I/O primitives. The registered owner still owns the
loader/writer observations, account work, cancellation and uncertain settlement.
The scoped audit owns app-header stability and diagnostic timing, while the
repository supplies read validation and retains grants and file fences. Profile
identity assertions remain with the profile value. These ownership corrections
preserve the existing sealed-owner ceilings without widening capability access.

Production parent selection, lifecycle installation and Capture remain disabled.
This change has not yet been runtime-qualified.

## October 25 — inactive receiving terminal qualified locally

The inactive implementation adds a dedicated all-removed receiving closure
owner: two row updates and deletion of the exact held package, membership and
untouched consumer/queue/job/event quartet. It retains a canonical Released
result and seals all changed/deleted fields and persistent identities. Frozen
descriptors are checked before save; historical shared-original absence does not
fabricate a retirement identity. Uncertain attempts remain owner-held and
read-only until exact before/after resolution or joined shutdown. An unrelated
inventory advance keeps owner-held settlement closed; only separate cold,
read-only historical recovery accepts later revisions under the same stable
header.

A separate paged terminal reader preserves raw orphan/foreign rejection, exact
row/owner/bootstrap joins, role-aware historical identity checks and checked
terminal consumption runway. Terminal payload bytes use the existing durable
physical-metadata route with zero reservation and no pending-package entry. The
final transaction compares a dedicated full successor accounting projection
against clean post-save accounting; surviving original ownership is unchanged.
Normal fresh receiving/staging and release identities consult terminal history.
Historical collision audit batches at most 128 value snapshots per page. Each
batch compares every selected terminal with bounded live roots and every
streamed historical terminal, including exact persistent-identity self-matches.
The inner scan uses the outer audit header; full pending-root/runway validation
runs again in a fresh context before and after page suspension. Byte accounting
remains separate from comparison visits. Deep database validation is repeated
per page rather than per selected terminal; scalar comparison cost remains
quadratic. Multi-page correctness coverage is not a performance qualification.

A historical shared original may later enter a pending recipient's own
retirement. Its reader validates the ordinary retirement rows and derived
membership, or the complete held-release leaf with the exact original-retiring
assertion. These pure readers stay below terminal scans, budget and whole-store
audits to avoid recursive recovery. Only existing owners acquire cleanup rights;
historical evidence never authorizes unlinking. A released receipt still needs
complete absence of the original closure.

The pagination diagnostic uses opt-in, owner-bound Debug measurements only:
monotonic phase summaries and checkpoint counts/time, with saturating counters
and at most 64 reports. It preserves every authority callback and its throwing
order, introduces no suspension, and records no identifiers or payloads. A
periodic aggregate report preserves partial timing if the test deadline fires.
This diagnostic does not qualify runtime performance or permit fewer checks.

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

## Historical October 23 status — versioned physical-root reopen correction (implementation pending qualification)

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

The no-save07 reader failure is now traced to the legacy absolute-path digest:
its three saved markers reproduce the child path's hash, while the relocated
container path produces a different hash with unchanged directory identities.
The bootstrap database profile-equality check correctly rejects that mismatch.

`SharedMediaNativeAppProfile` now distinguishes the historical path-bound format
from `physicalRootsV1`. New empty bootstrap writes version-3 intent, progress
and final records. The explicit new profile tag is present in both its
persistent binding and nested Codable representation. Its domain-separated,
ordered digest binds the authority and fixed namespace-to-directory identities.
Containment, no-follow access, backup flags, nested root journal identities,
markers, store identity, fences and full-owner locks remain required.

Version-2 journals keep the legacy algorithm and exact seven-field/profile
bytes. Missing discriminator stays omitted when encoded; null, unknown and
explicit legacy tags reject. An interrupted legacy bootstrap before any
path-bound commitment may finish as version 2 under existing guards; it never
infers a new version from missing records. Existing committed profiles are never
rewritten or adopted after relocation. Generic V1/qualification bindings are
unchanged. No schema, funding, admission, storage-limit or activation change is
included. Independent and IC-1 design review cleared this approach; compiled
compatibility, new-format reopen and fresh no-save controls remain pending.

## Historical October 23 status — no-save child closure observed; full readback remains open

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

The test-only `SharedMediaStageExitProbeTests` adds two explicitly armed
methods: a single no-save child and a separate readback. The child consumes its
durable attempt before fixture creation, constructs the existing disposable P2
fixture under the store bootstrap fence, retains its complete native owner, and
waits for a host process-watch acknowledgement before its final durable boundary
and self-exit. Ordinary runs verify only an inert arming guard before file
access. The reader requires the matching closure certificate, existing store
identity, constructor fence and complete `appDispatch` ownership before exact
application-state comparison. Missing or conflicting evidence never authorizes a
retry or a production write.

`SharedMediaStageExitProbeState` reuses clean receiving/audit readers for the
frozen slot, header, quartet, package/member, receipt and actual pair values.
`SharedMediaStageExitProbeRecords` bounds disposable fixture paths and rejects
missing stores before construction. Optional fixture bootstrap fencing and
temporary placement change only this opt-in setup. It uses the existing ordinary
P2 path without the unrelated V1 consumer seed; the ordinary non-membership
draft is included in exact readback. The local observer binds host PID,
executable and start time before registering `NOTE_EXIT`; numeric host exit
status remains unobserved. The console sentinel is corroboration, not an
acceptance authority.

All three special methods now return inertly when wholly unarmed, preserving
complete CI's zero-skip gate. Partially armed invocations still fail closed.
This supersedes the transport checkpoint's historical unarmed-skip behavior
below. An inert ordinary-suite pass never qualifies an armed handshake or exit.

The first compiled no-save attempt failed before acknowledgement because the
selected simulator data-container pathname changed. Its child timed out
normally; no self-exit, closure or reader was qualified. The original prelaunch
physical identity was not recorded, so the change cannot be classified as a
rename or copy. The failed attempt and prior nine unarmed passes remain
historical evidence.

The test-only correction adds `SharedMediaStageExitProbeLocation`: an immutable
prelaunch anchor binds the data root and probe-directory chain by no-follow
descriptor identity. Child and reader check that anchor before fixture access.
Fixture paths are canonical relative paths beneath the currently matching root;
physical store-file, store-parent, control and fixture-root identities
supplement the SQLite UUID and existing fence binding. The host retains
descriptors across both launches, accepts only identity-preserving relocation
and records the reader's current location. Copied trees, traversal, symlink
aliases and identical-byte store replacements are covered by focused tests.
Directory continuity compares device/inode/type and requires positive link
counts; raw counts are retained as evidence but may change during publication or
SQLite file lifecycle. Regular store files retain the exact single-link
requirement. A positive held-directory link count alone does not prove the named
entry still exists. Fresh no-follow path capture and physical binding comparison
must reject a missing or replaced entry while the original descriptor stays
open. A publication/deletion/same-path replacement case covers this distinction.

The first relocation correction compiled and passed thirteen safe checks, but
its armed attempt stopped before fixture creation. A read-only check found that
publishing the anchor changed the nonce directory's link count from 3 to 4 while
every device, inode and type stayed unchanged; its unlocated failure does not
prove which guard failed first. The directory-count correction then exposed a
bad test assumption about deleted-directory link counts. After correcting that
assumption, all fourteen safe checks passed. These failed attempts are retained.

The next no-save attempt stopped at strict canonical JSON re-encoding before
child-attempt/readiness. Host JSON left slashes unescaped while the native
sorted-key encoder escaped them. The host correction preserves the native codec
and exact byte equality. A fixed host-produced anchor regression checks native
reading, reverse writing and raw-slash rejection. The twelve-record
host/Foundation byte oracle and all fifteen safe native checks passed. Fixture
digests continue to cover original native bytes.

Three further failed attempts exposed host-observer compatibility issues:
Python's kqueue object does not support the context-manager protocol; an exact
XCTest exit86 case contains a failure-message leaf; and xcresulttool can lack a
console-log attachment even when the managed invocation log contains the marker.
Each correction passed a bounded host diagnostic and exact independent/IC-1
review. Failed evidence remains retained. The observer now closes kqueue
explicitly, validates exactly one expected failure-message leaf, and reads a
bounded, stable, no-follow managed log for exactly one full nonce-marker line.
These checks do not turn a generic XCTest failure into exit evidence.

`stage-exit-nosave07` passed child process closure, physical continuity,
expected singleton exit86 and sentinel checks. Its separate native reader then
failed with `conflict` at the complete owner's `openApp` boundary; the no-save
control remains unqualified. The reader XCResult is
`fe52221ddefb42f08b4617e1b80dfcea`; all 2,940 source/project and 707 product
hashes remained unchanged. Held descriptors were released, so this attempt
cannot resume. Reopen tracing precedes any further reviewed attempt.

This control cannot establish save atomicity, power-loss durability,
installed-store eligibility or feature acceptance. Activation disabled; PR116
frozen; deployment hold active.

## Historical October 23 status — process-exit probe transport focused qualification

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

`SharedMediaStageExitProbeSupport` and `SharedMediaStageProbeTransportTests` are
test-bundle-only preparation for the bounded release-stage process-exit control.
An ordinary test invocation cannot read a ticket or run the handshake. The
opt-in handshake binds a fresh nonce, exact selector/phase, candidate and
compiled app/test binary hashes to per-invocation environment values. Ticket and
consumed-marker files are canonical, bounded, exclusive and synchronized.
Missing arming skips before file access; malformed arming or a consumed marker
fails. No store construction, abrupt exit, provider work or production writer is
implemented by this transport.

Focused shared-checkout verification passed six safe transport tests and one
separate simulator handshake (7 methods / 7 invocations). The handshake proves
actual `TEST_RUNNER_` propagation, the installed test-host ticket location,
Python/Swift canonical ticket agreement and compiled app/test digest binding.
Its runner requires a fresh XCResult with exactly one passing invocation plus
the exact acknowledgement. All 2,935 source/project files and 706 compiled
product files stayed unchanged. Evidence: `stage-transport-focused03` and
`stage-transport-handshake01` under
`.artifacts/native-app-capture-handoff-20261020`; XCResults
`53c5fd5cadec42389d4f6754a313478e` and `84b24a306b764c2586797ce5e88b8412`. The
two earlier Xcode command-line rejections remain retained and ran no tests.

The reviewed managed-lock cleanup removed 2,917 completed app/test object files,
while preserving all 706 qualified product files, dependency downloads and
dependency intermediates, and all test evidence. Its synchronized journal
records each removal and completed status; observed free space afterward was
23.32 GiB.

The no-save exit/full-lock readback control, deterministic transaction-boundary
qualification, full affected-target and isolated-source gates remain open. This
transport grants no production permission or feature activation.

## Historical October 23 status — startup ownership integration (focused qualification)

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

Production startup now builds one explicit non-CloudKit configuration with
unchanged automatic App Group placement, and holds the existing exclusive store
fence across metadata, constructor attempts and classified archive/replacement.
First-parent creation stays beneath the trusted App Group anchor. Test startup
selects memory-only construction before any production path access.

The factory's persistent implementation now lives in
`ModelContainerFactory+Persistent.swift` with a per-bootstrap session,
preserving migration/checksum order and the 600-line review guard. Typed
boundary failures, Objective-C exceptions and missing-container outcomes bypass
persistent retries and destructive recovery. Ordinary classified Swift failures
retain historical signature-gated recovery, with no new stage eligibility.

A default-denied ephemeral construction admission binds only a first successful
attempt to its exact container, configured URL and parent/control fence. Retry,
recovery or subsequent failure cannot mint or revive it. It stays internal to
the bootstrap outcome, with no installed writer consumer. Existing receiving and
saved-result recovery remain token-free; a later clean launch can qualify. No
schema, storage limit, provider policy or release writer changes here. Focused
shared-checkout qualification covers 133 methods / 134 invocations: 130
unchanged methods / 131 invocations from the first run, two corrected XCTest
methods from the second, and the corrected Swift Testing migration method from
the third. The first run's three failures and the second run's incomplete
selector coverage remain retained. Each run preserved all 2,933 frozen
source/project hashes. Source/project/CI-tooling, adversarial guardrail,
Markdown and diff checks passed. Exact combined evidence is
`.artifacts/native-app-capture-handoff-20261020/startup-closure-combined01.json`.
Actual installed App Group path spelling, full affected-target, isolated-source,
and release-stage process-death/save qualification remain open. These checks do
not authorize a stage/start/cleanup writer or feature activation. Canonical
contract: `docs/backend-and-data/08-startup-store-recovery.md`. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved.

## Historical October 23 status — context-local release sizing memo focused validation

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

Scoped audits now pass one explicitly owned sizing memo through each synchronous
pending/context or page read. It is discarded before page suspension and is not
stored on the audit, repository or graph. Only the pure survivor projection is
reused. Every call still reconstructs current staged evidence, consumer and pair
facts, original receipts and historical funding, validates projection inputs,
and performs final saved-row/header checks. Budget independently remeasures the
package. Ordinary and non-audit callers remain uncached by default.

The key compares canonical full Progress, Prepared, Received, package,
membership and ordered pair values, every serialized byte count and exact origin
values. It never uses only a package ID, header, hash or size. The optional memo
retains at most four entries and 4 MiB of encoded/scalar payload plus bounded
collection and allocator overhead. Key fields are encoded sequentially within
the remaining payload budget; original/origin/pair arrays have an
optimization-only two-element bound. Extra origins, oversized keys or encoding
failure use the unchanged uncached calculation. These are cache bounds, not
changes to media, package, durable-storage or temporary-storage limits, and not
an RSS/encoder-scratch memory guarantee. Nothing cached grants write, admission,
funding or recovery authority.

The single managed `projection-memo-focused01` run passed all 20 methods / 44
invocations, with no missing, unexpected, failed or skipped tests. All 2,929
frozen source/project hashes and all ten candidate hashes remained unchanged.
XCResult `812abef9581843d2905e86ec0bc5fb22.xcresult` and exact coverage are
retained under `.artifacts/native-app-capture-handoff-20261020`. Independent and
IC-1 concurrence preceded execution. The eight Swift/test files remain identical
to the tested candidate; these two result documents were updated only afterward.

A report-only comparison against the retained prior run matches thirteen
unchanged test bodies and the same simulator/configuration. The eight-case
staged-funding method took 905.492 seconds versus 1,165.979 seconds previously;
this single comparison does not establish a general performance guarantee.
Changed workloads are excluded. The first timing extraction failed to recognize
inline `@Test` declarations; correcting that evidence script required no test
rerun. Full affected gates, isolated-source, performance and integrated writer
acceptance remain open. Activation disabled; PR116 frozen; deployment hold
active; AWS unapproved; existing limits unchanged.

## Historical October 23 status — typed staged clean routing focused validation

This records an earlier checkpoint, superseded by the qualified October 23
result at the top of this document. Pending statements below describe that
earlier state; retained failures remain failures.

CleanGraph now reconstructs a typed staged funding witness for an exact saved
request. Clean Budget and every scoped audit context route that witness without
opening generic phase, consumer, retained-only or dirty mutation paths. The
budget charges current S and reserved B−S exactly once; metadata and logical
package liability remain B. Staged packages omit ordinary mutable base and
received-liability maps. Physical receipts, shared originals and their identity
headroom retain the outer accounting owner.

The complete pending-root pass indexes six receiving identities plus every
staged/live release ID together. Checked revision arithmetic sums each live
Progress's remaining saves and each staged request's start plus all subsequent
saves, including Released and consumption. A local single-root witness is not a
complete identity/runway audit. Raw paged enumeration still rejects orphan,
foreign, partial and unsupported terminal Released slots, including terminals
without pending membership. Every page revalidates its header and typed facts.

No stage/start, cleanup or terminal writer is introduced. Future writers must
preserve aggregate runway in their exact poststate and qualify disk save and
old-writer closure. The historical sections below describe earlier checkpoints;
this section supersedes their clean-routing exclusion only.

Focused shared-checkout validation passed 18 methods / 40 invocations, with no
missing, unexpected, failed or skipped tests. All 2,929 frozen source/project
hashes and nine candidate hashes remained unchanged. Exact independent and IC-1
review preceded execution. Evidence is retained under
`.artifacts/native-app-capture-handoff-20261020/staged-routing-focused02-coverage.json`,
with XCResult `a086ea035c744545b5526e5c42bd5c01.xcresult`. The preceding
compile-only failure remains retained with zero runtime coverage. Synthetic
release states do not qualify a stage/start or cleanup writer. Full affected
gates, isolated-source and integrated acceptance remain open. Repeated
projection cost, startup writer exclusion and disk save/recovery qualification
are the next integration work; this result makes no performance acceptance
claim. Activation disabled; PR116 frozen; deployment hold active; AWS
unapproved; limits unchanged.

## October 22 — staged funding extraction qualified

Ordinary acquisition accounting and the typed staged-request reader share one
private, nonmutating package measurement. It preserves receipt ownership,
maximum pair-closure and membership charges, receiving-slot bytes, and the
current/reserved split. Only the outer budget owns global deduplication,
physical/logical/preparation totals and asset identity liability. No raw-byte
measurement input is exposed to another owner.

The separate `ReceivedReleaseSnapshot.readStaged` adapter reconstructs the
sidecar-free received liability B under supported immutable receipt/allocation
owners. It charges canonical request data plus its stored digest in current S,
reclassifies the remainder B−S as reserved, and measures complete future release
liability A through the same prospective assembly as the ordinary reader. Both S
and A must fit B; existing metadata category caps apply. Future sizing uses
today's inventory/header and the start successor, including decimal-width
changes. No fresh disk-space query, new funding or historical staging proof is
introduced. This is not protection against arbitrary compatible database
forgery.

Generic clean/dirty routes still reject sidecars. Global identity/runway
integration and actual staging/start save-closure qualification remain separate.
Exact-reviewed focused validation passed 16 methods / 41 invocations across
`staged-funding-focused01`, `focused02` and `focused03`. The first two runs had
incomplete selector coverage (filename versus suite, then enclosing extension);
those failed coverage records remain retained. Only missing methods were run
again, with no source changes. All 2,929 source/project and seven candidate
hashes stayed unchanged in each run. Evidence:
`.artifacts/native-app-capture-handoff-20261020/staged-funding-composite01.json`.
Project, Markdown and diff checks passed. Fresh-context equality is not a
pre-refactor oracle; exhaustive dirty-poststate parity and full affected gates
remain open. This is shared-checkout focused evidence, not writer, runtime
routing or full-feature acceptance. Activation remains disabled; PR116 frozen;
deployment hold active; AWS unapproved; limits unchanged.

## October 22 — staged request origin reader qualified

`SharedMediaNativeStagedReleaseOrigin` is an unconsumed, read-only association
witness. Only its exact persisted-row reader can construct it. It checks both
canonical sidecar columns, immutable received V2 payload/digest/identity
binding, the unverified historical header floor against the current
inventory/bootstrap header, the held receiving quartet and the frozen
consumer/cohort/membership/original joins. The dedicated consumer sibling
rechecks complete row and header equality; a saved witness cannot be reused
after a context change. It grants no funding, global identity, aggregate
revision-runway, release or save authority.

Ordinary slot, consumer, budget, audit and dirty transaction readers still
reject populated sidecars. This leaf is deliberately not routed into clean
accounting until historical B/S/A funding and the complete graph audit are
qualified. No runtime writer creates or consumes a request. Activation disabled;
PR116 frozen; deployment hold active; AWS unapproved; limits unchanged. Focused
validation passed all 14 selected methods / 33 invocations after exact
independent and IC-1 review. The first attempt failed only test compilation and
ran zero tests; its evidence is retained. The corrected fixture run
`staged-origin-focused02` passed with all 2,929 source/project hashes and five
candidate hashes unchanged. XCResult `0a87aabceb70400b9ea16f16b1950600.xcresult`
and exact coverage are retained under
`.artifacts/native-app-capture-handoff-20261020`. Project generation/validation,
Markdown checks and diff checks passed. This is focused shared-checkout
validation, not full-target, device, routing or writer qualification.

Earlier dated sections retain their historical validation scope.

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

## October 22 — release request codec qualified

`SharedMediaNativeReleaseStartRequest` is an unconsumed value codec for a future
versioned durable release request. It binds the exact V2 received payload
identity, historical staging header and fixed receiving transition revision. The
post-stage header is a checked successor; the later release Plan must use its
own then-current audited header. `receivingRequestSHA256` names the existing
receiving transaction digest, not this request's own external digest.

Canonical parsing is bounded by the existing metadata limit. Exact origin
association requires `requireMatch` in addition to decoding. The descriptive
encoding charge is data bytes plus digest UTF-8 bytes; it is not a database/WAL
footprint. Local collision rejection does not establish graph-wide uniqueness.
No schema/model, row decoder, writer, reservation, recovery outcome or runtime
consumer is added. Optional sidecar validation, historical funding
reconstruction, all writer fences, migration, aggregate runway and disk-backed
save-closure qualification remain prerequisites for staging. Historical received
bytes are unchanged.

`release-request-codec-focused01` passed all three selected methods / four
invocations, covering initial and restaged received payloads, identity binding,
canonical parsing, checked header arithmetic and the digest-inclusive metadata
cap. Exact coverage found no missing, unexpected, skipped or failed tests.
XCResult `690aef1f226945e99a5b8872eff67ac2.xcresult` and diagnostics are
retained under `.artifacts/native-app-capture-handoff-20261020`. All 2,924
frozen source/project and four candidate hashes remained unchanged during
execution. Only this README result note changed afterward. Independent and IC-1
review preceded the run. This is focused shared-checkout validation; staging,
full affected gates and integrated acceptance remain open. Activation disabled;
PR116 frozen; deployment hold active; AWS unapproved; limits unchanged.

## October 22 — received release funding adapter qualified

`SharedMediaNativeReceivedReleaseSnapshot` reads an exact received V2 operation
and measures a hypothetical initial release using the common survivor
projection. It validates the frozen consumer/cohort, held quartet, authoritative
original receipts and physical origins. The existing budget now exposes its
received metadata split without changing any total: current plus reserved
liability, excluding globally owned original identities and physical media. The
proposed release must fit that existing charged liability and both metadata cap
categories; no fresh-space query is introduced.

Persisted package, membership, pair and execution rows remain unchanged. Only
the hypothetical slot payload and reconstructed pair-plan inventory revision
reflect the proposed start. Reconstructed pair values include the inventory
revision even though the raw pair rows do not change, so current byte accounting
must include a decimal-width crossing such as 99 to 100. Plan.preHeader stays at
the actual predecessor header; the Received header remains historical.
Arithmetic checks one proposed start increment and its own remaining steps, not
aggregate runway across other releases.

The reader returns descriptive values, not a clean-audit witness, reservation or
write grant. A caller still owes the complete scoped audit and session fence.
There is no production release-start caller, admission change, cleanup writer,
unknown-ack retry authority or schema change. Underfunding remains a read-only
capacity failure; it must never become a new-free-space prerequisite for saved
recovery.

`received-funding-focused01` passed all five selected methods / seven
invocations across received funding, shared-origin budget and held-origin
reconstruction. Exact coverage found no missing, unexpected, skipped or failed
tests. XCResult `b0f23e1bbb9b455bb7bbfb2e7c3361c8.xcresult` and raw diagnostics
are retained under `.artifacts/native-app-capture-handoff-20261020`. All 2,922
frozen source/project hashes and six candidate hashes remained unchanged during
execution. Only this README result note changed afterward. Independent and IC-1
review preceded the run. This is focused shared-checkout validation; full
surface gates, release-start/cleanup writers and integrated acceptance remain
open. Generated project registration is scoped separately from unrelated
working-tree additions. Activation disabled; PR116 frozen; deployment hold
active; AWS unapproved; limits unchanged.

## October 22 — shared release sizing components

`SharedMediaNativeReleaseSurvivorProjection` now accepts immutable component
values as well as the existing clean snapshot adapter. The component values
contain no database rows, audit capability, reservation or write grant. The same
stage enumeration supplies both diagnostic identity-inclusive projections and
explicit identity-excluded current/future totals consumed by the global budget.
Global original identity charging remains separate and unchanged. Live-package
and terminal-slot metadata caps retain their existing categories.

This extraction prepares a common calculation for an eventual
received-to-release proof. It does not implement that predecessor adapter,
fresh-admission predicate, revision-runway preservation, release-start seal or
cleanup writer. The older unconsumed ReceivingReleaseProjection remains
historical feasibility arithmetic; it must not be used unchanged as an
identity-excluded funding proof.

`release-components-focused01` passed all 9 selected methods / 12 invocations
across the survivor projection and integrated clean audit/budget suites, with no
missing, unexpected, skipped or failed tests. XCResult
`8c7573d0110e43bfaef75004ffae3a90.xcresult` and exact coverage are retained
under `.artifacts/native-app-capture-handoff-20261020`. All 2,920 frozen
source/project hashes and all four candidate hashes stayed unchanged during
execution. The three Swift/test files remain identical afterward; this README
result note was updated after execution. Independent and IC-1 review preceded
the run. This is focused shared-checkout validation, not full-target,
isolated-source, cleanup writer or feature acceptance. Raw simulator/Xcode
diagnostics remain retained; XCResult reports no runtime warnings. Activation
disabled; PR116 frozen; deployment hold active; AWS unapproved; storage limits
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

## October 20 — prepared-intent staging locally verified

The inactive staging owner discovers a saved package slot before generating
fresh identities, then revalidates under retained native/account ownership and
queue/observation locks. Fresh staging seals the complete original/AI/display
cohort, saves one canonical prepared row and increments inventory once. Package
and membership bytes remain unchanged. Recovery returns the exact saved bytes
without another save, including when original files are now unavailable.

Prepared-only graph validation is bounded and runs at every scoped audit
boundary. Competing target edits, acquisition, preparation and cleanup are
blocked before file mutation; unrelated drafts and read-only inspection remain
available. Unknown/malformed phases and legacy qualification remain closed.
Prepared bytes count as materialized metadata; receiving headroom is reserved
once within unchanged limits. No queue, consumer, job, event or execution
authority is created.

Focused shared-checkout validation passed 76 methods across seven suites, with
166 invocations, zero failures/skips/runtime warnings and all 2,895
source/project hashes unchanged. Exact persisted metadata-cap boundaries,
receiving, abandonment, consumer lifecycle, Capture handoff and integrated
acceptance remain open. Activation is disabled, PR116 frozen, deployment held
and AWS unapproved. The foundation full-target results below remain historical;
this changed runtime has scoped validation only.

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

## October 19 — V2 metadata write integration under qualification

Legacy cleanup protection is committed as `ffbae1c15`. The next inactive V2 leaf
edits metadata on an existing native pending package through the same registered
owner. Each operation performs the complete asynchronous scoped audit under its
account lease and retained file/store fences. A repository-minted read fence
pins both inventory and independent bootstrap headers; a private, single-use
operation witness admits one typed metadata save only.

The transaction changes exactly the package envelope/revision and inventory
revision. Its private dirty projection explicitly includes pending changes and
rebuilds only bounded membership-rooted pending packages. Membership and
bootstrap metadata remain unchanged; every other pending package/member and
consumer scalar plus exact cohort bytes must remain equal. Public clean scoped
projection and consumer audit remain strict. The existing aggregate metadata,
package, durable and free-space limits still apply. Ordinary unanchored drafts
are excluded. A consumer-bound, frozen, retiring or unfinished target is
refused. Known-save acknowledgement requires exact fresh readback; lost
acknowledgements allow only exact read-only recovery, never a second write in
that operation.

V1 metadata/settlement orchestration is extracted without changing its authority
or recovery behavior. Capability constructors remain fileprivate in their
original owner/repository files. Existing app construction stays DEBUG-only;
there is no Capture installer, provider call, funding change, schema change,
acquisition/member creation or release authority. Tests and exact review are
pending. Native acquisition/preparation/receiving, result/cleanup, Capture/Auth,
RUX recovery, integrated acceptance, deletion/export and redesign remain open.
Activation disabled, PR116 frozen, Supabase deployment hold active, AWS
unapproved and numeric limits unchanged.

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

## October 19 — inactive V2 initialization locally verified

The same registered native owner/repository adds a separate initialization-only
qualification entry. It creates a `nativeAppContainerV2` profile in a dedicated,
existing, backup-excluded Application Support control parent. The fixed child
layout is `authority`, `photo/PhotoPreparation`, and `inbox/InboxSources`; the
SQLite store remains outside these media roots. Existing V1 inspection and
qualification formats are never converted.

Under the existing store fence and store-parent lock, a locked control parent
receives a create-only canonical intent before any media root is created. The
intent binds account, inventory, generation, operation, nonce, store UUID,
parent identities and fixed names. Five fixed create-only progress receipts bind
each directory to its exact descriptor and parent identity. A progress-absent
path must be absent and is created exclusively; a progress-present path must
match the recorded child and parent identities. A crash after mkdir but before
durable progress is held, never adopted or silently repaired. This supersedes
the earlier proposal to accept existing empty named directories from intent
alone. The separate create-only final receipt binds all five progress digests
and every root/namespace identity before ownership markers. Once final evidence
exists, missing or replaced directories are held, never recreated. All existing
markers must agree before any absent marker is completed; a committed database
pair requires every marker already present.

Locked root and namespace descriptors transfer directly into the existing file
owners. The store, control parent and root locks remain held through an atomic
inventory/membership save and for the repository lifetime. A lost
acknowledgement reopens only the exact saved association. Malformed, partial,
foreign or V1 associations fail closed. Ordinary unanchored drafts are
preserved. This leaf supports empty V2 initialization/reopen only; it does not
enable media admission, cleanup, funding, provider execution or app
installation.

Intent, progress and final records are bounded profile control metadata. Their
fixed encoding fits the existing metadata allowance and marker limit; free-space
preflight includes remaining record/marker bytes and encoding workspace without
charging a user's package, duplicating already materialized record bytes or
adding a library cap. All package/storage limits remain unchanged. Directory
URLs are explicitly directory-valued before creation and during locked-root
handoff; no identity check is relaxed.

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

Continue populated V2 scoped writes and atomic local receiving admission with
the same owner. Activation is disabled, PR116 frozen, deployment hold active and
AWS unapproved.

## October 19 — inactive scoped native inspection locally verified

The same registered native owner and repository now have a separate read-only
entry for an existing `nativeAppContainerV1` profile. It requires pre-existing
private Application Support roots, backup exclusion, store and namespace
bindings, and the existing store fence. Missing prerequisites fail closed;
inspection never bootstraps, converts a qualification store, repairs rows,
processes media, or enables dispatch or settlement. App installation remains
nil.

The scoped grant binds the actual account lease and active operation, process
epoch, inventory generation, store identity and root binding. Inspection retains
the owner and fences until it returns, including cancellation and account drain.
Every outer page uses a fresh context and releases model objects before
yielding; headers and authority are rechecked across boundaries.
Reverse-reference audits are paged with cancellation/authority checks. This
bounds page materialization, not total library work or latency; retained-library
size is not capped.

Pending roots are existing inventory membership rows, queried without filtering
out stale generations. Exact joined records, owners, generations and canonical
membership must match. Inventory-anchored receipts, consumers, derivative pairs,
allocations and reference counters are audited, including retained consumers and
all reverse original references. Ordinary unanchored app records are untouched.
This deliberately cannot detect completely unanchored corruption, assert
physical file availability, authorize cleanup, or prove admission/result
recovery. Existing package and storage limits apply unchanged; receiving
metadata is counted once.

Focused tests cover absent prerequisites, mutation rejection, account drain and
fence lifetime, header changes across pages, pending capacity, corrupt joins,
shared originals and retained immutable facts. The exact independently and IC-1
reviewed candidate01 passed all 126 methods in fifteen focused suites with zero
failures, skips or Xcode runtime warnings. All 2,842 source/project hashes
stayed unchanged. Evidence:
`.artifacts/native-scoped-inspection-20261019/focused01-result.json`, XCResult
`61a5c783bea541d492fd1de25370c299`, candidate SHA256
`7425151624d927ebf2af35269ec8d4be94c2dccab36be7f054a5cc8e0e3e12a8`. This is
scoped shared-checkout verification, not full-target, isolated-source, device,
hosted or activation acceptance. Native admission, retained transitions,
Capture/Auth integration, recovery presentation and integrated acceptance remain
next. Activation is disabled, PR116 frozen, deployment hold active and AWS
unapproved.

## October 19 — native owner dispatch and settlement separation

`SharedMediaNativeOriginalOwner` owns the registered account lifecycle in its
own file. Its private constructor and file-local capability constructors remain
closed. The repository retains its private constructor, file fences and
file-local binding/mutation/inspection authority constructors. No second owner,
container, drain registration or production installer is introduced.

Every cross-file repository operation requires a dispatch grant tied to the
actual account lease and unique active operation, owner, process epoch and
existing qualification profile. It expires when the operation ends, Auth seals
the owner or pending settlement closes dispatch. Debug fault hooks stay owned by
the controller and grant no runtime authority.

Settlement uses a different capability type, binding a unique pending identity
and exact request only after the loader/file writer has returned. The repository
can only read that receipt, acknowledge completed/held state, or persist the
existing reserved-to-held transition and read it back. It cannot load media,
write files, reserve another operation or mint preparation/cleanup operations.
Missing evidence after a loader started remains closed and retains the fence and
capacity. Only successful exact reconciliation clears pending settlement.

This inactive structural integration preserves the existing qualification
profile, topology, persisted formats, limits and recovery semantics. Scoped
app-container validation, native receiving admission and live composition remain
pending. Activation stays disabled, PR116 frozen, deployment hold active and AWS
unapproved.

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

After the verified reservation/worker-drain checkpoint, the inactive native
owner can replace an exact active attempt with a durable `nativeDerivativeV2`
pair plan and its two work rows. The immutable V3 intent retains exact output
hashes, lengths, types, recipe and focus outcome. Inventory/package/membership
revisions advance atomically; both children, all fixed row fields and the exact
envelope are checked on fresh readback after a save error. Planning transfers
the existing maximum output reservation to the actual prepared byte lengths
without a gap or double charge. The remaining aggregate metadata allowance stays
reserved; a bounded canonical row/witness projection must also fit that
allowance.

Only no-file `planned` rows are admitted by this increment. They have no output
allocation, asset, reference, counter or writer lease. Whole-store pair/work
reverse checks reject missing, extra or mismatched children and any premature
physical rows. The one-incomplete-plan guard is not a retained-library cap;
ready/retained derivative states remain closed until their typed owner lands.
Inspection and reopen report a plan as recovery work, blocking other mutations
and never repeating preparation. Explicit abandonment under the serial owner
requires the exact saved plan and unchanged no-output namespace, then removes
only those planned rows and restores original-only membership. It preserves
sequence, original bytes and supporting content; stale plans cannot erase newer
work. There is no file deletion in that transition.

Native output reservation/write/retirement/recovery, ready publication, freeze,
consumer ownership and live composition remain pending. Candidate03 passed the
six focused suites (52 test methods, no failures, skips or runtime warnings)
after exact independent/IC-1 review. All 2,820 source/project hashes remained
unchanged. Failed candidate02 evidence is retained; its preparation-pool charge
was reordered after package registration without changing amounts or limits.
Evidence is in `.artifacts/native-pair-plan-20261018/`. This shared-checkout
focused result is not acceptance for later stages or a repeat of the preceding
full-target qualification. Activation, PR116 freeze and deployment hold remain
unchanged.

## October 18 — native preparation reservation locally verified

The inactive native owner now reserves an explicit preparation attempt in a
separate V2 envelope before any processor or file writer can receive authority.
The first reservation compares exact V1 bytes, revisions and membership; reopen
never converts a draft. The owner allocates a monotonic sequence and binds the
original reference, physical byte/descriptor identity, recipe and writer epoch.
Only one attempt is permitted across the inventory.

The attempt reserves the unchanged maximum AI/display allowances and all
remaining space in the existing aggregate 1 MiB metadata budget. Output bytes
are counted once physically and once logically in the preparation pool; free
space subtracts the outstanding reservation once. This deliberately conservative
metadata headroom avoids promising a future pair/result encoding that cannot
fit. Capacity denial leaves the prior envelope and sequence unchanged.

Inspection reports unresolved attempts as recovery work. The reservation API
grants no source URL, arbitrary processing callback, filesystem write or AI
dispatch. A DEBUG-only qualification entry now exercises the concrete image
processor under the same registered owner. It reserves before source access,
verifies original bytes/descriptors before and after preparation, uses existing
crop/downsampling/encoding policy and waits for actual focus-worker drain. It
returns memory-only output assertions while leaving the attempt held; no
pair/output files, freeze or receiving consumer is published. A saved attempt
cannot dispatch the processor again. The later pair owner must consume outputs
within that same retained operation before ordinary composition can be enabled.
Explicit abandonment runs under the same serial registered owner after prior
work drains, drops the unused reservation and preserves the sequence, originals,
contexts and membership. Saved acknowledgement recovery compares exact bytes and
revisions; old attempts cannot release a newer reservation. Mutable V2 metadata,
acquisition and removal preserve sequence; sharing creates an original-only V1
destination. Legacy V1 decoders remain unchanged.

The V2 codecs also define separately hashed derivative intent and ordered frozen
cohort values. Durable intents use a versioned compact preparation identity
(`nativePreparedIdentityV1` inside `nativeDerivativeIntentV3`) containing
original, recipe, operation/revision facts and hashes/lengths of prior envelope
and membership bytes. Raw prior bytes remain only in the active attempt for
exact CAS; retained intents never recursively embed earlier drafts. The
unreachable draft intent format containing `attemptBytes` is rejected. The
reservation checkpoint rejected those later stages; the current plan-only
increment above still rejects file-writing, ready and frozen states. Codec
support is not pair, freeze, queue, product or activation acceptance.
Independent and IC-1 review cleared candidate14. Its focused correction passed
28 methods / 31 executions, then the complete `merianTests` target passed 6,246
methods / 10,047 executions, with zero failures, skips and runtime warnings.
Full12's failed evidence remains retained. All 2,815 source/project hashes were
unchanged during verification. This qualifies the inactive reservation/processor
and worker-cleanup increment in the shared checkout; paired
files/freeze/consumer/live composition remain pending. Evidence is under
`.artifacts/native-preparation-integration-20261018/`. All existing deployment,
PR116 and activation holds remain in force.

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

## Native empty-store admission — locally verified

`SharedMediaNativeStorageRepository` is a private-constructor, Debug-only
fixture factory. It holds the existing exclusive store fence before eligibility
and binding work, and exposes only an exact empty-store snapshot. Pristine
initialization saves `nativeQualificationV1` / `readyNativeAccountingV1`
inventory and bootstrap together. Reopen requires their exact identity,
generation, revision and root/store bindings. All other model rows, real
Documents/Application Support locations and legacy graph adoption are rejected.
Partial marker installation is preserved and fails closed; a lost save response
can reopen only the exact committed state. No media operations or live
composition are enabled.

A sealed native binding bridges to the existing namespace owners without
exposing raw-byte construction. Shared photo/inbox reopen now opens existing
namespaces without `mkdir`; missing or symlinked directories fail without being
recreated. Standalone photo creation stays unchanged. Held-owner replacements
are detected by existing descriptor checks. Empty-directory inode continuity
across different owner lifetimes is not established by these root markers; this
empty-only factory requires empty namespaces and grants no media or cleanup
authority. Complete native namespace/file and retirement-identity qualification
remains required before nonempty operations can open.

Independent and IC-1 review cleared candidate02. Focused coverage passed 65
tests; the full native target passed 6,118 tests, with zero failures/skips and
unchanged candidate/shared-baseline hashes. Evidence:
`.artifacts/shared-media-native-owner-20261017/`. The rejected first candidate
was corrected before execution. This is local shared-checkout validation only.

The next native reserve/commit owner requires a durable versioned request
receipt: existing P1 reservation rows omit future reference, asset-generation
and other immutable intent facts. Reviewed design preserves exact recovery and
terminal replay rejection, counts receipt payloads within the originating
package's existing metadata allowance, and never reruns a loader from a saved
reservation alone. The additive V64 receipt schema foundation has passed focused
migration qualification. The transaction owner and complete descriptor audit
remain to be implemented and qualified; no live composition or limits change
follows.

## Native original reference audit — locally verified

`SharedMediaNativeOriginalAccounting` audits one persisted original under the
caller's unchanged native store fence. It independently checks all-live totals
and exhausts both P1 and shared-reference directions in 128-row pages, including
retained packages. Missing counters, equal-count substitutions, orphan edges,
unknown roles and mismatched owner/generation/lease facts fail closed. A zero
count requires the exact native V2 retirement binding and final retired pair.
The physical-origin package need not still exist as a logical owner.

The immutable result is a read-only accounting snapshot, not a mutation, file or
cleanup capability. The helper rejects unsaved contexts and exposes no partial
success. Paging bounds row materialization, not total database work or measured
memory. Fencing is a caller precondition; this helper does not acquire a lock or
establish native store eligibility. Dedicated package/consumer, derivative,
reservation and whole-store/namespace validation remain separate requirements.
There is no production caller and no native composition is opened. The next
closed transaction owner must own paired writes, memberships and reverse counts
in one save and retain exact operation recovery.

Independent and IC-1 review cleared the exact candidate. The focused run passed
51 tests and the full native target passed 6,109 tests, with no failures, skips
or candidate/shared-baseline drift. Evidence and earlier failures are retained
in `.artifacts/shared-media-native-accounting-20261017/`. This proves the scoped
read-only helper in the shared checkout, not native composition or live media
retention. The closed owner and complete native audit remain required.

# Inactive shared media storage

## Pending graph and retirement format — locally verified

`SharedMediaPendingGraph` discovers bounded mutable package rows from logical
references, reservation work, handoffs and derivative pairs. It preserves source
holds as dependencies and follows shared allocations independently of their
physical-origin package. Exact membership checks include the inventory and draft
generations and the existing combined metadata allowance. Retained packages do
not consume pending slots. The reader does not save, reconstruct missing rows,
validate every lifecycle phase, audit whole-store orphans, or grant file access
or cleanup. Native mutation, reverse accounting and complete audit owners remain
required before composition can open. Existing qualification barriers remain.

`SharedMediaNativeRetirementIdentity` encodes the native original retirement ID,
asset/generation, inventory/generation, account and exact descriptor facts in a
canonical V2 record within the existing 512-byte allowance. Its distinct
`nativeOriginalRetiringV2` state cannot enter the qualification V1 path. Parsing
rejects noncanonical UUIDs, numeric descriptors and JSON. This value is not a
cleanup capability; the native owner must still jointly persist retirement and
reference accounting and prove writer closure and exact physical absence. No
native caller or composition is enabled by the codec.

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

## Metadata and local freeze — locally validated

The isolated inbox composition saves bounded metadata through the same account
operation and joint store. Growth needs the unchanged reserve plus outstanding
reservations and the positive encoded-byte delta. Local freeze requires an
ordered, complete original/AI/display graph and verifies every file identity.
The caller retains a private request containing the entire encoded envelope,
references and file facts; only that exact request can reconcile a saved
`preparedHeld` receipt. The snapshot alone omits presentation and is
insufficient. Prepared-held packages reject fresh draft mutations, including
pair discard. No server admission or inference occurs. Independent and IC-1
review cleared candidate03; eight focused suites passed 109 cases and the full
native target passed 6,066 cases, with no failures, skips or source drift. This
is shared-checkout qualification, not live composition acceptance. See SMA-1 for
the exact retained evidence and remaining integration requirements.

## Paired derivatives — isolated implementation

V62 adds scalar pair/work rows, preserving all V61 inbox fields and starting
empty. The isolated inbox composition now validates the exact derivative joins;
standalone P1 owners and purge still reject these liabilities. The schema's
focused migration/storage validation passed 82 cases. Runtime candidate04 passed
four focused suites after correcting an account boundary and extracting lookup
helpers. The full run retained 6,055 passing cases and two size-guard failures,
both resolved by that focused rerun. This is shared-checkout evidence; see the
current SMA-1 status for exact results.

The existing inbox coordinator, account lease, repository and destination actor
own both AI-input and display roles. One saved plan retires the previous pair
and records both prepared replacements. Original bytes remain separately owned.
After exact old-file cleanup, one reservation admits both bounded roles; both
verified completions are required for atomic pair publication. Incomplete edits
remain `needsAttention`, and reopened plans require explicit discard/new edit.
Recovery verifies only the saved complete partial/final; it never reloads an
encoder or invokes AI. Fixed-inode proofs, saved retirement readback and joint
absence acknowledgement govern cleanup, including zero/one/two completed roles.
Ready receipts reverify both role files and the original. Low disk blocks fresh
reservation but does not prevent identity-proven discard.

Typed handoff and derivative adapters share only descriptor byte mechanics.
Role-qualified references preserve original ordinals; derivative reservations
consume the existing preparation overlap and physical storage once. Limits,
activation, live Capture/AppDI composition, metadata/freeze and cloud behavior
are unchanged. This increment is fixture-only, not whole-product acceptance.

## Isolated typed source inbox

`SharedMediaInboxOwner` adds a distinct `p1InboxQualification` composition with
sibling SQLite, authority, inbox and P1 fixture roots. It uses the scalar V61
source/handoff schema. The current increment implements source acquisition,
reopen, explicit source discard and joint handoff. Local focused and full native
qualification passed for the isolated composition. There is no live Capture or
AppDI composition and no adoption of the legacy inbox.

The source catalog is a bounded projection of ready source rows, not a JSON
sidecar. Before loading, one transaction reserves the source and 32 MiB of
inventory-wide copy headroom. Source reservations plus headroom remain within 96
MiB and the existing temporary/free-space limits. Preparation records exact
size, digest and type before creating a fixed partial. Its stable device/inode
is saved before payload writes. Completion verifies and synchronizes the exact
original, then jointly closes its writer and publishes its unassigned reference.
Lost acknowledgements use exact fresh readback, never another source callback.

Reopen holds the exclusive store/root fences. A matching completed partial or
final may finish the original operation after verification and synchronization.
Missing, incomplete and identity-conflicting sources remain visible recovery
items and charged. After actual local writer closure, descriptor-bound occupancy
reconciliation splits an unfinished source's charge into occupied bytes and its
unwritten reservation. The total charge is retained; filesystem availability
subtracts only the latter. A failed reconciliation retains the conservative
reservation and cannot grant completion or deletion authority. S+H+A handoff
accounting is qualified locally in the handoff extension; this is not
whole-inventory acceptance. No source is automatically reloaded.

Explicit discard requires a closed local writer, no handoff hold and exact
fixed-file inspection. Saved irreversible intent precedes unlink. Only the
repository can mint the release capability from a fresh read of that saved
intent; the namespace owner synchronizes and rechecks absence before joint row
reclamation. Unknown entries, links, replaced inodes and changed originals block
cleanup. Legacy import operations hold a shared root fence and reject the new
persistent marker, including nested paths, before reading or mutating the inbox.
The new owner holds the root exclusively through actual asynchronous drain.

Qualification roots are retained fixtures, not installed-app retention proof.
Future live integration must use the separately agreed private Application
Support root, backup exclusion and file-protection policy. Numeric limits,
activation, PR116 freeze and deployment hold remain unchanged. Typed schema
validation passed 116 cases. Source-focused validation passed 94 tests, followed
by 31 after the occupancy correction. A full shared-checkout run retained four
architecture/inventory failures alongside 6,021 passing cases; the reviewed
formatting and purge-fixture corrections passed 50 targeted checks. Unchanged
runtime evidence is carried forward with independent and IC-1 review, without
claiming a final-candidate full-green or live retention result.

## Joint inbox/P1 handoff — locally validated

The same `SharedMediaInboxOwner` and one operation coordinator retain all store,
inbox and P1 fences. No standalone owner is nested. Immutable Codable requests
bind every source, destination, nonce and inventory revision. One joint save
creates the source hold (`SharedMediaReferenceRecord` with `inboxHandoffV1`
role), P1 reservation and shared destination allocation/lease before file work.
A fixed partial's inode is saved before payload; source and destination
identities and digest are checked before completion. Exact saved readback
resolves uncertain saves; an interrupted copy is never restarted automatically.
Original-account recovery can verify and finish only a complete original
partial/final.

Source operations remain accountless. Destination operations use one current
account-work lease, with checks around asynchronous work. The shared controller
holds exclusion until cancellation actually drains. Abandonment uses a sealed,
stat-only destination closure/liability proof and never reads or deletes a
foreign draft or changes its phase/revision. It has no admission free-space
precondition; all numerical accounting checks still apply. Incomplete
abandonment retains the destination reservation and typed detached row, while
restoring the source to unassigned readiness. Its original account must become
current with a fresh lease before cleanup. Completed abandonment removes only
the P1 `PhotoPreparationLease`, handoff record and source hold; the complete
inbox graph/file and durable destination survive.

Separate physical allocations account for both copies. Logical acquisition is
S+H+A, with active B consuming part of H; the P1 physical reservation is counted
once and has no second logical B charge. Restoring headroom on abandonment must
fit the unchanged limit. Closed incomplete destinations split occupied bytes
from unwritten reservation. Source release requires a verified destination and
saved irreversible source intent. It deletes only the source graph, hold,
handoff and P1 source-liability lease after exact absence proof; destination
shared lease, asset/allocation/reference survive. Detached destination cleanup
similarly saves identity-bound intent before unlink and releases its reservation
only after namespace synchronization and absence acknowledgement. Unknown
identities stay held. Cleanup and recovery reclaim only unreferenced empty
directories, preserving all live and pending tokens. The exact runtime candidate
passed 94 focused and 6,038 complete native cases with zero failures or skips.
These mechanisms are not live Capture/AppDI integration or full acceptance.

`SharedMediaPhotoAcquisitionOwner` is the isolated P1 adapter. It opens a
distinct `p1Qualification` inventory with sibling database, authority and photo
roots, outside live Documents. First binding requires empty P1 rows and
namespace; reopen validates exact paired rows and markers. No automatic adoption
or mode promotion exists. Ordinary capture and AppDI remain disconnected.

The lock order is the SQLite parent's `.merian-media-fence` control file, parent
directory, authority, P1 root and P1 namespace, held for the adapter lifetime.
Standalone persistent P1 owners hold the control file shared and deny any shared
ledger, including when given another media root. The zero-byte regular fence is
opened without following links, has exactly one link, and is never removed,
replaced or upgraded. Every opener synchronizes the file and parent, including
after EEXIST, and revalidates both identities before admission. Held/named
identities and size are rechecked before mutations; a mismatch permanently
invalidates that owner. All shared-storage modes hold this fence exclusively.
Thus standalone purge can upgrade its separate media-root lock even when photos
and SQLite share a parent, without releasing allocator exclusion. This
coordinates participating owners; arbitrary external filesystem mutation is not
supported. A create-only P1-root binding blocks another database's standalone
owner after adapter closure. Partial initialization stays closed. File work uses
the already held descriptors on a dedicated actor; it does not reacquire locks
from a lower-ranked namespace.

A single fresh non-autosaving context commits the P1 reservation and shared
allocation/lease together before loading bytes. A verified namespace-owner proof
then permits one joint asset/reference and measured-allocation completion save.
Lost save acknowledgements require fresh exact readback. The provider is never
replayed; restart may restore only committed handles. `p1Reserved` and `p1Held`
retain their maximum and fixed partial/final destinations; `p1Materialized`
retains actual bytes and the exact original reference. Missing or changed files
block use, preserving the ledger and sole original.

The allocation ID is the deliberate P1 asset UUID. The paired shared lease uses
the P1 lease UUID, asset UUID, process epoch and fixed `p1AcquireV1` purpose.
Shared reference IDs and owner IDs identify the exact P1 reference and revision.
Every transaction validates both directions. One physical allocation counts once
against filesystem availability and durable limits; the P1 lease contributes the
same ceiling logically to acquisition/temporary budgets, and the encoded empty
P1 envelope contributes once per package. No schema field or numeric limit
changes.

The adapter now supports explicit same-account sharing and exact-reference
retirement of committed originals. A share request retains the complete source
handle, destination, fresh nonce and inventory generation/revision. Exact saved
readback recovers an uncertain outcome; an absent result may be saved only at
that revision. Replaying a reclaimed request cannot resurrect an old handle. The
caller must retain that request; a live caller adapter is not yet installed.

The joint graph counts each physical original once and each package's logical
original cohort separately. Allocation package IDs remain immutable origin
provenance; an empty origin package can disappear while another package retains
the file. Paired references and their revisions stay authoritative. Retiring one
reference preserves survivors. Last-reference retirement saves intent before
file work, prevents new holds and retains the charge until proof-backed release.

The namespace owner verifies bytes and saves parent/namespace identities with
the retirement intent. Only typed, current-lifetime capabilities authorize exact
unlink and synchronization. Restart may confirm an absent fixed file only under
the saved irreversible intent, same intact directories, exclusive admission/
store/root/namespace fences, zero live references/work and successful fsync plus
absence recheck. This proves current absence, not who removed the bytes. Missing
files before intent, changed objects and missing/replaced directories remain
blocked. The generic token-only unlink API grants no shared release authority.
Explicit current-account `finishRetirements()` retries saved intents;
cancellation drains actual I/O and unresolved retirement keeps account
transition incomplete. Final joint deletion reclaims graph rows and capacity;
stale absent handles are no-ops without file authority, not historical-success
receipts. No unbounded release tombstones are accumulated. After release, a
bounded descriptor-relative empty-directory pass removes only canonical
directories with no ledger token prefix. Every held, missing, pending or
retiring prefix is preserved. Explicit `finishRetirements()` performs this pass
before the capped ordinary inventory, so crash remnants can be reclaimed even
after exceeding that scan's steady-state entry ceiling. Inspection errors,
unknown files or symlinks block cleanup; no file, namespace or root is removed
by this pass. The pass makes at most four 128-entry scans; any further progress
requires another explicit recovery call.

Pending acquisition remains charged and blocks share/retire/release; no writer
closure or provider replay is inferred. The adapter exposes no source handoff,
metadata editing, derivatives, freeze, transport or AI admission. Generic L1
mutation APIs reject adapter mode, and any shared row still blocks ordinary
library purge. These local mechanisms do not qualify mixed production
allocators.

## Original L1 foundation

The following foundation behavior remains applicable to observation and
synthetic qualification modes. These modes have no file writer and cannot be
promoted to the adapter mode.

`SharedMediaStorageRepository` is the sole writer of four scalar V60 ledger
entities. It has no AppDI composition, ordinary Capture access, file writer,
unlink operation, physical-release acknowledgement, network call or AI
admission. The product retains its existing media owners and activation hold.

## Authority and recovery

Construction requires an explicit persistent container, inventory ID and empty
authority directory separate from media and SQLite. Nonblocking exclusive locks
on the SQLite containing directory and authority directory are held for the
entire repository lifetime. This deliberately stronger L1 lock excludes a second
repository, including one proposing a different root for the same store. It is
not a lock shared with ordinary legacy producers. Distinct SQLite files in the
same containing directory are conservatively mutually exclusive. The SQLite file
is opened only for identity checks; Core Data retains its own file locks. Both
the containing directory and file identities are revalidated before
transactions. Qualification rejects any pre-existing legacy/P1 rows. Never
install this composition in a live library.

A bounded, versioned create-only directory xattr binds inventory UUID, Core Data
store UUID and the root/source binding digest. It survives loss or replacement
of the database at the same path. An existing marker with missing ledger rows
fails closed; it is never automatically cleared or overwritten, including after
an interrupted first save. This deliberately leaves initialization repair to a
future exact reconciliation procedure. No reservation can be issued meanwhile.

Each synchronous transaction opens a fresh non-autosaving context and checks
root/store identity, persisted binding, graph and generation/revision. Scalar
references cannot grant cross-account ownership; a package has one account.
Retiring allocations cannot gain references or leases. Closing admission retains
all liabilities. Only the same controller epoch may close a local qualification
lease; restart does not prove work ended. Retirement never refunds capacity in
L1, because no physical-release proof API exists yet.

Legacy observation accepts only tokens beneath explicitly registered roots. The
immutable registry (namespace, canonical path and directory identity) is hashed
into the persisted root binding and rechecked on reopen and save. Stat rejects
symlinks, hard links and changing identities. Progress pages contain at most 128
entries; tokens/cursors at most 1024 UTF8 bytes. Progress is advisory: L1
intentionally has **no completeness assertion**, stable-source-revision proof,
semantic reference import, promotion, adoption or cleanup. Those require
source-owner adapters. Changed source evidence fails closed instead of silently
replacing the prior observation.

## Accounting

Checked arithmetic preserves the adopted 96 MiB package, four/384 MiB pending,
96/64/32 MiB temporary subpools, 192 MiB temporary total and 256 MiB free
reserve. Preparation and transfer reservations each admit one package. Observed
library bytes are physical occupancy, not pending packages. Only unmaterialized
reservations are subtracted from current filesystem availability; materialized
bytes already reduced it. Per-role/media constraints remain the source owner's
responsibility. This inactive ledger does not qualify whole-product limits.

Any ledger row (including an orphan) blocks identity replacement and library
purge before existing cleanup callbacks. A failed lookup also blocks purge. Zero
rows preserve the existing path. Future integration must implement each owner's
intent/file/finalize handoff, reference reconciliation and physical release
proof before removing these barriers.

See
[SMA-1](../../../../../../docs/rfcs/shared-media-allocation-ownership-2026-10-16.md)
and the canonical
[local schema](../../../../../../docs/backend-and-data/04-database-schema.md).

### NCI-1 bounded ownership metadata (implementation in progress)

V63 additionally defines the pending-membership lookup record, inventory
bootstrap receipt and per-asset reverse-reference accounting record. These
records remain behind the closed native integration boundary. Missing metadata
is a liability, not permission to reconstruct ownership or release files. The
pending lookup assertion and immutable consumer cohort use versioned,
size-bounded canonical encodings. Context, lookup and cohort bytes share the
unchanged 1 MiB metadata allowance; they do not each receive a separate
allowance.

The consumer join verifies exact package, inventory, reference, asset,
allocation, lease, derivative pair/work and reverse-accounting identities.
Hashes assert byte identity; they do not establish safe decoding or faithful
video provenance. Pure joined values grant no file access, cleanup, funding or
provider authority. Pending/retained transitions, bootstrap, reverse-count
maintenance and production composition remain unqualified until their
transactional owner is integrated and tested.

### V64 acquisition receipt storage foundation

The additive `SharedMediaAcquisitionReceiptRecord` preserves operation identity
and supports full intent/result retention followed by a minimal terminal replay
rejection witness. Its exact stored shape and phase requirements are documented
in
[the database schema](../../../../../../docs/backend-and-data/04-database-schema.md#v64-native-acquisition-receipt-foundation).
Migration creates no receipts. Existing fixture owners reject these rows,
including tombstones, and liability checks cannot silently ignore them. Closed
transaction validation, namespace audit and native capture composition remain
separate implementation work; the model itself grants no capability.

The frozen V63 build preceded the active addition. The real-store V63→V64
migration preserves existing ownership and creates no receipts. Focused tests
passed 140/0/0. Full candidate04 recorded 6,118 passed and two architecture
line-count failures; candidate05 consolidated the identical legacy guards in
`SharedMediaStorageLookup.requireNoNativeOwnership`, then passed all 43 tests in
the five affected suites. This is composite local evidence, not a clean full
candidate05 run. Evidence: `.artifacts/shared-media-native-receipt-20261017/`.

### Native acquisition codec — locally qualified

`SharedMediaAcquisitionIntent` freezes the direct picker/camera original
request, including exact expected revisions, package absence/revision, original
identity, writer epoch and canonical tokens. Its versioned sorted JSON and
SHA-256 bind all request facts; noncanonical or unknown fields fail.
Foundation's canonical UUID encoding is used in JSON, with lowercase UUID
components in file tokens. `SharedMediaAcquisitionResult` binds exact completion
postconditions and bounded file descriptor facts. Descriptor syntax and hashes
do not prove actual media or authorize cleanup. Historical UTI values are
preserved with the existing nonempty/128-byte bound, without invoking a later OS
decoder registry.

`SharedMediaAcquisitionReceipt` interprets only reserved revision 0, held or
completed revision 1, and released terminal revision 2. Exact same-operation
reads do not mutate the row. Cold recovery decodes the persisted row without a
caller-supplied request; terminal recovery returns its saved replay identity. A
separate expected-intent check rejects conflicting inputs. Terminal rows must
shed request/result and package/asset aids. This codec cannot perform a phase
transition, restart a loader, reconstruct a missing row or validate the current
ownership graph.

The result encoder is bounded to an internal 8 KiB reservation within the
existing 1 MiB metadata allowance. The closed owner must still reserve combined
request/result headroom and projected membership/cohort bytes for every pending
operation, derive charges from exact authoritative joins, and reject orphans.
`metadataCharge` only computes one receipt's charge; it does not establish a
complete package budget. Native nonempty admission remains disabled pending that
owner, full namespace/reverse-receipt audit and transactional qualification.

Independent and IC-1 review cleared the codec. The corrected codec suite passed
all 13 test methods; four unchanged focused storage/architecture suites passed
in the prior run. That run retains one test-fixture failure (two assertions),
corrected without production changes. This is composite focused evidence only.
Exact manifests and both results:
`.artifacts/shared-media-acquisition-codec-20261017/`.
