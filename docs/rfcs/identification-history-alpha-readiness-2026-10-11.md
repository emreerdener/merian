# Identification history alpha readiness

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
`project.yml` and regenerate the project. Installation and use against a named
nonproduction environment require separate authorization. It must use actual app
navigation, `AppDIContainer`, prepared history composition, normal durable queue
owners and disk-backed storage. Use distinct bundle, app-group, keychain, disk
and auth namespaces and explicit nonproduction backend configuration that fails
closed if absent or pointing to production. Require a compiled qualification
marker and validated nonproduction project/host before creating the live client
or installing history. A warning-only check is insufficient. No preference or
remote flag may install history in the production app.
`PreparedHistoryReanalysisComposition.isAppInstallationQualified` stays false; a
separate immutable compile-time qualification branch selects the prepared
composition only in `HistoryQualification` after environment validation. Debug
and Release retain the hard-false ordinary installation path. The qualification
branch must be structurally absent from those builds, with executable
configuration-specific acceptance tests.

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

Close installed-device and authorized nonproduction backend qualification,
including hardware/resource behavior for photo/audio/video, account changes,
scan and account erasure, storage cleanup, and operational recovery. Keep
initial-engine hardening and Field Trip's held reconciliation consumer
separately identified; neither is satisfied by history test totals. No hosted
mutation, deployment or worker scheduling occurs without authorization naming
the operation and target.

The handoff contains the exact source/artifact/backend revisions, completed
matrix, independent review findings and their disposition, required CI results,
external evidence, remaining exclusions and rollback controls. Production gates
remain closed. A later activation decision is separate from this handoff.

## Capability and evidence matrix

Owners: **History primary** is the sole implementation/evidence writer in this
thread. **Hardening owner** is the separately owned initial-analysis effort;
shared writes require the checkpoint 0 agreement. **User/operator** owns device
testing and explicitly authorized nonproduction operations. Reviewers are
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
| A9  | Nonproduction installed configuration                     | History primary; User/operator authorizes target/use                                    | Inactive preparation authorized; implementation pending; installed use awaits named target authorization | Generated HistoryQualification configuration alone compiles the qualification selector and installs real DI/navigation/disk storage with isolated bundle/app-group/keychain/disk/auth namespaces; pinned nonproduction project/host validation fails closed; Debug/Release remain nil in executable checks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| A10 | Installed initial video and video child                   | User/operator; History primary packages evidence                                        | Unqualified                                                                                              | Exact artifact/backend run proves initial media save/enroll, retained/chosen video source with context, real preparation, restart before/after dispatch, original operation recovery, history reopen and deletion; in-memory fixtures do not count.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| A11 | Installed initial photo and photo child                   | User/operator; History primary packages evidence                                        | Unqualified                                                                                              | Same real installed journey as A10 for photo, with source/new-media handling and acknowledged cleanup; actual navigation and persistence survive relaunch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| A12 | Installed initial audio and audio child                   | User/operator; History primary packages evidence                                        | Unqualified                                                                                              | Same real installed journey as A10 for audio, including retained composition, source/capture routing, hardware interruptions and receipt-bound cleanup.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| A13 | Supported media-backed actions and exclusions             | History primary                                                                         | Unqualified: combined video/media-context routing pending                                                | Photo/audio/video reanalysis routes correctly and fails closed without source media; selection/review/Undo/chat and qualifying photo publication follow explicit policy. Video reanalysis is included; no inferred video publication/review permission.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| A14 | Database contention                                       | History primary                                                                         | Unqualified: bounded audit gaps remain                                                                   | Both-order admission/settlement/terminal races across media input versions, context edits, accepted legacy transition and multi-owner cases pass; unchanged source-release/cascade evidence remains applicable. Follow [C1 deadlock acceptance](initial-cancellation-interface-2026-10-11.md#deadlock-evidence-and-public-path-acceptance--october-12-2026): preserve stage93 failures, continue normal real-owner overlap tests under actual permissions, capture sanitized correlation on recurrence, and record verified correction or independently/IC-1-reviewed unreproduced residual risk at final acceptance. Dedicated historical investigation is deferred until then unless it blocks work/reliable validation or recurs in normal paths; passing reruns are not a fix. Reproduced unresolved runtime cycles block acceptance; no evidence waiver or scope reduction without explicit user approval. |
| A15 | Initial-engine hardening dependencies                     | Hardening owner; History primary verifies integration                                   | Unqualified: S0 and broader hardening remain open                                                        | Validate IC-1 S0 and media-required admission across fresh entrypoints; preserve original-route recovery/cleanup for accepted Describe work and safely hold local-only no-media requests. Broader hardening and installed/hosted qualification remain separate.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| A16 | Hosted privacy, storage and operational recovery          | User/operator; History primary defines/evaluates cases                                  | Unqualified; target and operation authorization required                                                 | Authorized nonproduction run records its explicit server gate set and proves erasure, storage/cleanup and recovery on exact revisions, including unenrolled evidence deletion and no provider reinvocation after unknown execution; production gates remain false.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| A17 | Device/resource acceptance                                | User/operator                                                                           | Unqualified; preserve prior results and pending answers                                                  | Agreed photo/audio/video hardware, media preparation, interruption, background/resource pressure and fresh-library disk-backed restart cases pass on the exact candidate.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| A18 | Field Trip held reconciliation                            | History primary tracks closure; separate consumer implementer must be named before work | Blocked separately; consumer assignment not established here                                             | Named consumer acceptance demonstrates required reconciliation or the candidate explicitly remains blocked for that requirement; history tests cannot substitute.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| A19 | Final candidate review and local gates                    | History primary; independent reviewers                                                  | Unqualified for follow-up candidate                                                                      | Reviewed scoped diff, synchronized contracts/docs, full affected gates and independent re-review pass on exact final source; later changes have explicit evidence applicability.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| A20 | Final candidate CI                                        | History primary                                                                         | Blocked: follow-up candidate unpublished                                                                 | Required CI for the exact final PR candidate SHA passes; record check names, run links and head identity. Resolve private-source export approval first; no previous-head green substitute.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| A21 | Qualified release-candidate handoff                       | History primary; User/operator supplies external evidence                               | Blocked on required rows                                                                                 | A1–A20 are satisfied with evidence or an explicit user scope decision changes the requirement; exact artifacts/revisions, exclusions and rollback controls recorded; production gates remain disabled.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

No new execution tests are claimed by this planning document. The foundation's
5,893 native tests preceded two test-only lint edits; its final rebuilt focused
26 tests and backend 3,493 tests plus 484 steps are documented separately. Those
results do not qualify the required media-admission transition, video
reanalysis, installed build or hosted flows. Historical roadmap text and hashes
remain in `.artifacts/media-required-scope/`; this revision replaces planned
behavior, not completed implementation evidence.
