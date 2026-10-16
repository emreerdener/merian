# Initial analysis and reanalysis: reliability review and hardening plan

Status: proposed; source review and planning only. Updated 2026-10-10. No
engine, schema, funding, deployment, or activation change is made by this RFC.

## Current scope amendment — October 12, 2026

The user confirmed that new initial identifications and reanalysis require
physical image/audio/video evidence, with optional supporting descriptions, and
video reanalysis is in current scope. The amended
[alpha roadmap](identification-history-alpha-readiness-2026-10-11.md) and
[IC-1 revision 3](initial-completion-history-interface-2026-10-11.md) control
current work. Standalone text-child/Describe fresh admission and the blanket
video-reanalysis exclusion in older notes below are superseded planning, not
remaining implementation requirements. Preserve their dated audit facts.

Preserve historical text records and already server-admitted operations'
original identity, funding, exact outcome/completion recovery and deletion.
Local-only queued no-media requests require explicit media/remediation; retain
them without silent rewriting or classifying them as accepted replay. Unknown
admission requires original-operation recovery. Reanalysis uses the explicitly
targeted source version's retained or deliberately chosen media, not a
thumbnail, another version or text-only fallback. Original media is sufficient;
text may be empty. Video preparation/source binding/retention, original
funding/recovery and native journey qualification are required; video
publication/review is not inferred.

History remains sole shared implementation writer. Hardening explicitly agreed
this bounded documentation-only update to its current summary/matrix, retaining
its broader design/review responsibility and all historical sections. No engine
ownership transfer or activation, publication, hosted or device permission is
added. Scope reconciliation evidence is `.artifacts/media-required-scope/`.

The separately planned
[Simplify capture tools](codex://threads/01a12c47-6f54-7500-bab9-679c2babf9a0)
visual/session refactor needs both workstream handoffs and fresh final approval
there. Functional media admission and history qualification proceed in current
shells; they do not wait for that later refactor. Deletion/download and
Identification/History/menu redesign remain later roadmap milestones. Other
schedules and ownership are unchanged by this document.

## Review basis and scope

This replaces the conversation-only four-slice plan, retaining its cancellation,
uncertainty, permanent cleanup retirement, and exact-consumed-byte invariants.
The working-tree review used HEAD `e8b25d6c66197aa10366ea9ac92a1c2e5e8e6f76` as
a reference; concurrent uncommitted changes were present and preserved. Recheck
affected owners before implementation. This is not an exact-SHA runtime
qualification or a claim that the engine is production ready.

Scope: two end-to-end execution paths evaluated against the same reliability
requirements: initial analysis (foreground, offline queue, server replay, and
fresh media entry points plus exact recovery of already accepted legacy
description work), and history-bound reanalysis (explicit historical source,
Capture preparation, durable admission/upload, child execution/recovery, history
append, and native delivery). Shared persistence, provider, funding, media,
cancellation and delivery changes require regression coverage for both paths.
Reanalysis is no longer only a source of reusable patterns. Its full audit
remains to be performed; this scope update does not claim that it has passed.

Preserve distinct initial-scan and child-analysis identities and completion
behavior. Reuse proven owners without forcing the paths into one generic engine.
Include optional enrichment in cost and ownership review, without making it a
success requirement. Model quality, pricing, purchase processing, and changing
current funding policy are separate projects.

The roadmap conversation **Scan pack finances**
(`01a1057e-d8a4-7881-a57b-6badab3fcfbd`) proposes welcome grants, monthly Pro
allowances, purchased non-expiring packs used last, no charge for failed scans,
and one credit per multi-media analysis. Treat these as future policy inputs,
not implemented or fully specified rules. Pack amounts, prices, expiry treatment
for in-flight reservations, inconclusive results, and customer compensation
remain outside this hardening decision.

Current contract owners:

- [Ingestion and recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
- [Complimentary funding](../backend-and-data/18-complimentary-pro-scans.md)
- [API contracts](../backend-and-data/05-api-contracts.md)
- [Edge ownership](../system-architecture/06-edge-modularization.md)
- [Testing strategy](../development-guides/08-testing-strategy.md)

## End-to-end audit matrix

Record source owner, durable identity, transition/lock owner, existing test, new
fault-injection case, finding and disposition for every row on both paths. A
shared helper passing tests does not close either caller's end-to-end audit.

| Boundary                                  | Initial analysis                                              | Reanalysis-specific proof                                                                                                                                                                                                     |
| ----------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| User intent and capture                   | Freeze one new scan request before I/O                        | Freeze exact displayed historical source, owner and revisions; selection changes cannot retarget submission                                                                                                                   |
| Local preparation and restart             | Durable ordered files and queue identity                      | Retain one child ID through preparation, submission intent, files-pending recovery and one-time binding; pristine discard is distinct from attempted cancellation                                                             |
| Admission and funding                     | Durable operation plus original funding authorization         | Bind parent/source/child and current execution consent; preserve saved processor and allocation; recovery-only state cannot create an analyze request                                                                         |
| Upload and evidence                       | Exact verified inputs, immutable snapshots                    | Child-owned media IDs, original versus added/cropped provenance, exact order/digests and fixed expiry; no mutable parent-media fallback or silent replacement                                                                 |
| Provider dispatch and recovery            | Permanent authorization fence and typed outcomes              | Audit `analyze-observation`, its native one-time send boundary and `recover-observation-analyses`; exact outcome reads do not authorize dispatch                                                                              |
| Completion and delivery                   | Durable initial result, one settlement, restart-safe delivery | Atomic append plus child queue retirement and erasure receipt; completion never changes selection, duplicates a result or transfers review authority                                                                          |
| Selection, review and publications        | Preserve initial authority projection                         | Restore/Undo must obey current revisions; authority and Field Trip effects reconcile from acknowledged state; existing publication and chat snapshots retain their exact context                                              |
| Cancellation, deletion and account change | Pre-row cancellation and account fences                       | Distinguish closing editor, pristine child discard, attempted work and entire observation deletion; deletion blocks every child, late append and private delivery while sibling evidence remains protected from child cleanup |
| Retention and recovery operations         | Permanent holds and claims survive ordinary TTLs              | Non-biological result selection cannot expire biological history; account deletion materializes only its explicit scientific allowlist before private cascade                                                                 |
| Runtime and rollout                       | Qualify every supported input path and worker                 | Qualify photo/audio/video plus optional supporting context, accepted legacy recovery and local-only no-media remediation; independent gates remain closed and initial-engine readiness cannot activate reanalysis             |

Start from the
[child orchestration owner](../../services/supabase/functions/analyze-observation/README.md),
[shared history boundary](../../services/supabase/functions/_shared/analysisHistory/README.md),
and
[history implementation record](reversible-reanalysis-and-identification-history-2026-10-02.md).
Native preparation, admission, execution and erasure owners live under
`apps/ios/Merian/Core/Data/AnalysisHistory/`; trace their queue, Capture and
History consumers rather than assuming the service layer alone establishes
safety. Classify each requirement as already satisfied with evidence, gap
requiring a change, or unqualified. Do not reimplement satisfied history
contracts.

## Evidence and broader findings

| Finding                                                             | Source evidence                                                                                                                                                                                            | Review conclusion                                                                                                                            |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Returned SDK errors can lose uncertainty                            | `functions/_shared/scanPersistence.ts`, `persistOwnedScanRow`, classifies every returned error as rejected; the prior audit reproduced status-zero SDK errors entering this path                           | Confirmed source defect; preserve transport status and classify only proven statement rejection as definite                                  |
| Provider uncertainty is lost above the adapter                      | `_shared/ai/gemini.ts` emits `unknown_execution`; `identify-multimodal/index.ts` converts both operational failure and unknown execution into an exception, calls `quotaLease.fail()`, and marks retryable | Confirmed orchestration gap; preserve the typed outcome through durable settlement, not merely inside the adapter                            |
| Recovery can become another paid execution                          | `replay-scan-ingestion/README.md` documents claim-specific quota UUIDs, expired-lease replay, and terminal settlement after ten claims                                                                     | Existing behavior conflicts with the proposed permanent unknown-attempt fence; recovery claims must not imply provider permission            |
| Missing result evidence cannot be reconstructed                     | Multimodal post-result catch inserts provenance into `failed_scan_ingestions`, not the validated result; generic failures can enable retry and media rollback                                              | Require durable result evidence and a visible unrecoverable hold; provenance alone is not a result                                           |
| Cancellation and cleanup gaps remain                                | Native `OfflineQueueManager+QueueDeletion.swift`; `request_scan_deletion`; `_shared/identify/moderation.ts`; `reconcile-scan-media-assets/worker.ts`                                                       | Earlier audited gaps remain plan blockers: pre-row cancellation, source destruction during partial promotion, and stale cleanup snapshots    |
| Timeouts are individually bounded, not yet qualified end to end     | Native inference uses a 90-second resource budget; provider snapshots use 90 seconds; replay documents a 120-second downstream request and at least 150-second lease                                       | Not proof of a runtime failure, but no guaranteed headroom for preparation, persistence, and delivery; qualify the whole path before release |
| Funding already has useful separation                               | Funding document and completion/terminal orchestrators distinguish provider counters from complimentary holds and durable consumption                                                                      | Preserve this implementation; future packs need a policy adapter, not a second execution engine                                              |
| Modularity has a strong base but orchestration owns too much policy | `_shared/ai/README.md` separates request preparation, registry, adapter, and single invocation; the handler owns retries, funding, result persistence, and rollback                                        | Reuse provider boundary; extract cohesive lifecycle transitions rather than another provider framework or mechanical file splitting          |

Backend paths above are relative to `services/supabase/`; native queue paths are
under `apps/ios/Merian/Core/Data/OfflineSync/`. These are source findings, not
measurements of incident frequency. Existing account/generation fences, provider
preparation, canonical result readback, and atomic complimentary completion are
strengths to retain.

### Independent funding review

A read-only contract audit identified an additional admission boundary:
`identify-multimodal/index.ts` reserves provider quota (which can acquire a
complimentary hold) before `beginScanIngestion`. Its admission catch calls
`quotaLease.refund()`, whose `_shared/aiQuota.ts` owner finalizes provider
quota, not the complimentary hold. This creates a potential stranded-hold path
when admission is conclusively rejected before a terminalizable job exists. This
is source evidence, not a reproduced database incident. Slice 1 must atomically
bind admission and funding, or provide a durable idempotent pre-admission
release transition. An ambiguous admission response must reconcile first; a
missing read alone does not prove that admission cannot still commit.

The quota decoder is intentionally specific to today's plan enum and three
complimentary credits; do not stretch it into a pack-balance model. Existing
terminal provider reservations are prunable, so they cannot be the only lasting
record of a held operation's execution or funding authority. Preserve a separate
minimal lifecycle receipt before allowing provider-accounting pruning.

Purchased entitlement ownership also differs from the account-owned
complimentary ledger. Future monetization must decide purchase-principal, merge,
deletion, revocation and unused-pack ownership explicitly. Engine hardening must
honor the funding owner's decision, not repurpose the complimentary table or
silently transfer allocations. See the existing
[purchase-principal proposal](purchase-principal-auth-separation.md).

## Shared lifecycle and ownership contract

Keep authenticated owner, logical analysis ID, semantic request fingerprint,
provider attempt, recovery claim, funding authorization, and media operation
identities distinct. A new recovery claim is not a new provider attempt.

At most one primary dispatch authorization may ever commit per authenticated
owner and logical analysis ID, across all attempt, reservation and
recovery-claim IDs. Enforce this at the durable logical-analysis boundary, not
merely with a per-attempt token. A lost grant response still consumes that
authorization; creating another reservation cannot restore it. Explicit
reanalysis uses a new child logical analysis ID; recovery cannot mint one.
Separately metered enrichment and other non-primary calls remain separate
operation types and cannot bypass this primary-dispatch rule.

Resolve a lock-order documentation/source discrepancy in slice 1: the funding
document lists quota before ledger, while the complimentary wrapper in
`20260802235833_three_complimentary_pro_scans.sql` locks its usage row before
calling the underlying quota routine. The earlier broad hierarchy is
provisional, not an instruction to reorder existing locks. Preserve proven
serialization, including the outer user lock, unless the complete path inventory
and concurrency review justify a change. This ambiguity is not evidence of an
existing deadlock.

Before any overlapping implementation, publish an exact lock table for initial
analysis, child admission/recovery, funding, cancellation, completion, cleanup,
merge and deletion. For every routine record acquisition sequence, lock
identity, mode, nested calls and transaction lifetime. Explicitly include the
current parent-observation locks before child advisory/intent locks; do not
flatten both into a generic lifecycle category. Account transitions involving
multiple owners must specify deterministic owner ordering, followed by
deterministic parent/child and row ordering wherever multiple identities are
acquired. Enumerate exceptional paths and prove they share serialization or
cannot cycle. Conform and test all participating paths together before
activation, never introduce a new hierarchy piecemeal alongside opposing legacy
paths. No locks span external I/O.

The durable state machine separates execution, cancellation, result, delivery,
funding, and media states:

1. Admission freezes semantic identity, execution configuration, and funding
   association. Pre-dispatch failures may retry only when non-execution is
   proven.
2. One transaction authorizes dispatch and commits provider quota under a
   permanent logical-analysis dispatch marker bound to the original attempt.
   Only the fresh grant response allows invocation. Losing the response holds
   the attempt without invocation or grant replay.
3. Cancellation before authorization prevents inference. Authorization first
   preserves accounting; cancellation thereafter prevents result resurrection.
4. Attempt to durably save validated result evidence before promotion and
   finalization. Unknown acknowledgement reconciles that exact write. If neither
   canonical result nor evidence is recoverable, retain **Recovery needed**;
   never infer permission to invoke again.
5. An unchanged original attempt may submit its late known result under the
   original owner/attempt fence after lease expiry; expiry prohibits new
   dispatch. Cancellation/deletion still wins. Replaced claims cannot overwrite
   results.
6. Durable result completion and device delivery are different facts. Device
   restart or lost success response retrieves the same result without spending
   another token. No device acknowledgement is required by today's funding rule.
7. Unknown state survives process death, pruning, exhausted retries and cleanup
   TTLs. Failure to write a secondary uncertainty marker is safe because the
   pre-dispatch permanent logical-analysis marker already denies further
   execution.
8. Cleanup irreversibly retires an object from binding. Tokens only transfer
   cleanup responsibility. A retired key is never reused, even after lease
   expiry or successful deletion; a late storage delete therefore cannot hit a
   successor.

Cohesive owners: pure request/evidence preparation; durable lifecycle
repository; existing provider adapter; funding adapter; result finalizer; media
registry and cleanup worker; native durable queue and presentation projection.
HTTP handlers compose these owners. UI never owns financial or execution
transitions. Shared helpers require real consumers; avoid speculative generic
workflow frameworks.

## History integration checkpoint and sequencing

The active history work is tracked in thread
`01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1`. Before editing overlapping native,
history, funding or database owners, record a reviewed history commit SHA and an
agreed integration checkpoint in this RFC or its linked implementation record.
The checkpoint must include:

- The history SHA, relevant uncommitted/unfinished contracts and dependencies,
  reviewed diff, and validation evidence; no moving branch name as the baseline.
- One designated writer for each overlapping module, a non-overlapping change
  list, and the handoff sequence. Preserve user changes and do not run
  concurrent writers against the same worktree or shared owner.
- A designated owner for shared migrations and their generation/application
  order, including funding, parent/child admission, deletion and media
  registries. Each migration remains forward-only; neither effort rewrites the
  other's work.
- Agreement on shared interfaces and acceptance cases, and a review of the
  combined diff before overlapping implementation continues. Reopen the
  checkpoint if the baseline or shared contract changes.

This checkpoint is pending, not inferred from this plan's acceptance. Read-only
audits and isolated initial-analysis changes with no shared ownership can
proceed concurrently. Overlapping implementation waits for the recorded
coordination; this document does not itself authorize messaging another thread.

Admission identity, immutable execution configuration and verified-media binding
are shared activation prerequisites, even though their detailed changes appear
in slices 3 and 4. Earlier slices may be developed and tested behind closed
gates, but cannot admit production work or authorize inference until all
prerequisites, the exact lock inventory, and the history checkpoint for shared
owners are integrated and validated. Slice order is review sequencing, not
permission for partial activation. Keep existing runtime paths unchanged until
the coordinated cutover and old-writer/worker quiescence requirements below are
satisfied.

## Four implementation slices

### 1. Durable execution and uncertainty

Audit both paths in the matrix before assigning fixes. Trace existing child
dispatch/result recovery and funding settlement; preserve satisfied protections
and repair only evidenced gaps. Close the lock table for both paths.

Integrate the reviewed lifecycle skill from its isolated branch after overlap
review; verify its discovery link and agent-asset gate. Do not claim it is
already installed in the active checkout.

Add permanent attempt fences and typed persistence/provider outcomes across all
scan-producing callers. Durable evidence stores must be owner-only, bounded,
versioned, included in deletion, and excluded from diagnostic logs. Persist
enough validated result and original configuration to finalize without a new
model call. Update replay, funding, dead-letter, and retention workers in this
same slice. Quota pruning cannot remove the permanent authority record. No
automatic provider successor after dispatch, including malformed output or
unknown execution.

Close the pre-admission funding gap described above, including conclusive
denial, lost acknowledgement and process-death recovery without a second
allocation.

Implement bounded recovery with explicit pending, saved, complete, cancelled,
and recovery-needed projections. Preserve late-result settlement and exact
idempotent replay. Operator remediation may classify proven facts or recover
saved evidence; it cannot reset a dispatch fence. Customer compensation remains
a separate future policy operation.

### 2. Durable cancellation and delivery

Verify reanalysis editor closure, pristine discard, attempted work and parent
delete independently. Audit append-only delivery and selection/review races;
never route successful child completion through pristine discard.

Persist an owner-bound cancellation outbox entry in the same local transaction
as native cancellation; deliver it idempotently to the server. Local persistence
and server acknowledgement are separate transactions. Keep this cancellation
path independent of successful queue retirement. Fence a scan before its
canonical row exists without authorizing another owner's deletion. Upload
admission, dispatch, replay, and completion honor cancellation. Show pending
cancellation until acknowledged, and retain receipts across restart.

Keep presentation closure separate from cancellation. Distinguish saved result
awaiting local delivery from failed analysis. Preserve exact
request/owner/session and generation fences across background completion,
logout, account merge, local store recovery, and multiple devices. Never use
history child IDs as legacy IDs.

### 3. Exact media and irreversible cleanup

Audit child-owned evidence, provenance, expiry and erasure receipts alongside
initial media. A child cleanup claim cannot retire parent or sibling evidence.

Verify bounded bytes before dispatch and consume those exact verified bytes.
Create an acknowledged private write-once snapshot for durable
recovery/promotion; no issued signed upload may overwrite its key. A trusted
digest of a mutable key is insufficient. Preserve transformed input lineage
(crop, audio processing, video frames), transformation version, order, and
digests alongside originals.

Register unique destinations before writes. Bind promoted output to the verified
snapshot, never reread mutable staging as authority. Preserve originals until
snapshot acknowledgement, and preserve snapshots until completion or authorized
cleanup. Registry binding and permanent retirement contend atomically.

Late copies/uploads cannot bind; track capability expiry and write deadlines and
repeat targeted cleanup until all possible writes have ended and deletion is
confirmed. Never declare cleanup finished solely from one successful delete. Use
explicit object mappings, not filename inference. Existing storage lifecycle
rules must not expire unresolved evidence behind the registry's back.

### 4. Identity, integration and operational qualification

Close the complete audit matrix with separate initial-analysis and reanalysis
evidence. Exercise native submission through server execution, local restart,
history delivery and authority projection; service-only tests are insufficient.

Versioned fingerprints cover normalized inference-affecting inputs and ordered
verified media. URLs, sessions and keys are excluded. Inline/staged equivalent
bytes have equal identity. Compare before completed replay: changed input is
409; exact input recovers. Transport rebinding requires independently verified
equivalent evidence and confers no execution permission. Preserve legacy
completed read-only recovery; hold unverifiable pending work without fabricated
fingerprints.

Freeze provider/model/prompt/schema/preprocessing and result-policy versions at
admission. Configuration changes must not silently rebase saved work. A retired
configuration holds explicitly unless a separately reviewed equivalent recovery
path exists. Existing model-quality qualification remains a separate gate.

Qualify one absolute deadline across preparation, grant, invocation, evidence
save, and finalization, with reserved settlement time before grant. Bound actual
stream bytes, decoded memory, concurrency, and retry work. Native timeout may
end waiting but never authorize a new analysis. Slow valid work must remain
recoverable even when synchronous delivery cannot finish. Do not enlarge all
network limits.

## Future scan-token integration contract

Implement only the current funding adapter and contract tests now. Do not add
balances, purchase webhooks, monthly grants, pack expiry, pricing, or
speculative ledger tables in this work.

- Admission accepts a server-owned funding decision/reference, never a
  client-selected balance source. Persist its identity and policy version with
  the logical analysis. All recovery keeps that association.
- Funding reservation and analysis admission coordinate transactionally when
  stored together. An external future purchase service must provide an
  idempotent durable inbox/outbox contract before it can authorize dispatch;
  callbacks alone are insufficient. No external network calls inside database
  transactions.
- Completion and current funding settlement remain atomic. Future settlement is
  keyed by analysis and original authorization, with one consumption maximum.
  Repeated receipts or device deliveries cannot consume again.
- Preserve provider expenditure independently of customer credits. An uncertain
  provider attempt can remain internally charged even if a future
  customer-policy adjustment restores entitlement. Such an adjustment never
  reopens execution.
- Expose facts: valid biological/non-biological/inconclusive result, durable
  completion, delivery pending, proven pre-dispatch failure, proven
  post-dispatch terminal failure, cancellation, and unknown outcome. Policy
  chooses charging; labels such as low confidence are not transport failures.
- Test a fake future adapter with multiple funding sources and idempotent
  settlement. Changing month, subscription or account state cannot silently
  substitute a purchased token on recovery. Preserve today's explicit
  `paid_before_completion` settlement override: release the original
  complimentary hold and record the reason, without choosing or consuming
  another allocation. Immutable authorization association and provider
  accounting remain intact. Future overrides require named atomic policy
  transitions; reservation-expiry behavior remains a monetization decision, not
  inferred here.
- A multi-media request is one logical analysis; attachments, moderation,
  enrichment and recovery are not additional primary user-token operations.
  Provider subcalls remain separately metered. Reanalysis is a distinct explicit
  analysis whose future charge policy remains undecided. Each explicit child has
  its own funding association; upload retries, result recovery, restore, review
  and selecting an existing identification cannot become new scan charges.

## Qualification, rollout and completion criteria

Deterministic tests must create a fresh attempt, quota reservation and recovery
claim after an uncertain primary dispatch and prove that every second primary
authorization is denied for the same owner/logical analysis ID. Repeat after
lease expiry and quota pruning. Test independently metered enrichment without
allowing it to masquerade as primary inference.

Deterministic barrier tests cover cancellation versus grant/completion; lost
quota/evidence/result/settlement responses; failed uncertainty writes; process
kill at every boundary; pruning and exhausted replay; stale cleanup after lease
replacement; late uploads after deletion; staging overwrite between verification
and consumption; partial promotion; changed-input completed replay; and
equivalent inline/staged inputs. Verify exact byte consumption and promotion,
not digest metadata alone. Test cross-owner denial and account/deletion races
under real roles.

Add integration tests for funding reservation followed by admission denial or
uncertain acknowledgement, holds without jobs and lifecycle receipts surviving
quota pruning. Primary dispatch authorization remains after successful
admission. Add two-device concurrent admission, subscription transition, month
boundary via fake funding, repeated settlement, durable result with lost client
response, restart with damaged queue metadata, and missing local evidence. Use
synthetic providers and storage barriers first; paid/provider/device/runtime
qualification remains separately authorized and explicitly recorded when unrun.

For reanalysis also test selection A → B during preparation/execution of child
C; completion appends C while B stays selected; lost append replies recover
exactly one C and one settlement; stale source/review revisions fail without
rebasing; parent deletion during upload/inference blocks C; child discard
preserves siblings; account switch prevents private callbacks; expired/missing
evidence requires explicit remediation. Verify non-biological retention,
account-deletion allowlist, restore/Undo races and delayed authority
reconciliation. Run the shared invariant suite against both paths plus these
path-specific end-to-end cases.

Release criteria: at most one primary dispatch authorization per owner and
logical analysis ID across all attempt, reservation and recovery-claim IDs; zero
duplicate user-credit consumption, zero cancelled-result resurrection, zero
bound-object deletion in adversarial tests, and exact input/result/funding
association. Measure latency percentiles, peak heap/CPU by supported modality
and maximum input, durable completion rate, and recovery backlog age. Establish
measured performance budgets before activation; do not invent success
percentages from unit tests.

Every hold has an owner, reason, durable evidence status and operator next
action. Alert immediately on invariant violations; report overdue work against
its recorded stage deadline and holds unresolved for 24 hours. Alerts contain
aggregate counts and safe reason codes, never private payloads. The 24-hour
alert is operational, not automatic expiry, refund, deletion, or execution
permission. Provide a read-only support lookup and audited, separately
authorized remediation runbook.

Before new states are activated, stop old ingress/replay/cleanup, drain
invocations, and account for outstanding upload capabilities and external
writes. Database guards cannot recall storage deletes already issued by old
workers.

| Participant        | Required treatment                                           |
| ------------------ | ------------------------------------------------------------ |
| Old client         | Completed reads allowed; unsupported writes fail explicitly  |
| Old writer         | Quiesced; new protected writes denied by database guards     |
| Old replay worker  | Disabled; no reclamation of held work                        |
| Old cleanup worker | Disabled and drained before new object ownership             |
| New writer/workers | Default-off admission; exact grants and registry claims only |

Rollback closes admission and retains compatible recovery/cleanup owners; never
restore old workers over new states. Implementation, green CI, and this RFC do
not authorize merge, deployment, scheduling, activation, data repair, or
TestFlight.

Neither path is complete while any matrix row lacks source/test evidence or an
explicit blocking qualification item. Report the two paths separately; shared
code success cannot hide an unqualified reanalysis path.

Each slice needs independent review, focused checks, full affected-surface
gates, and synchronized canonical docs. SQL needs fresh disposable replay,
catalogs, concurrency and privilege checks. Native changes use the managed build
wrapper. No migrations, native builds, hosted calls, or provider executions are
required for this documentation-only review. Completion of this RFC is not
completion of its implementation or runtime qualification.

## Final implementation-readiness review — 2026-10-10

Disposition: roadmap contracts are ready for bounded design/test preparation;
**overlapping implementation is not yet cleared**. No implementation was
started. This review closes policy ambiguity but does not fabricate a history
handoff, complete lock inventory or runtime evidence while their owners are
changing.

### Baseline and ownership checkpoint

The latest completed history checkpoint observed was
`15e60d0a585e4fad96d249b2d5ea92ddfcda8647` (private video successful usage
accounting). Its ten-file commit inventory, continuation record and relevant
source boundaries were inspected. The history record reports independent staged
review and full backend gates; this review did not rerun those gates or endorse
the entire history diff. Treat this as the comparison baseline, **not the agreed
integration SHA**. Thread **Scan ID History** was actively implementing video
terminal settlement/completion when read.

The same checkpoint lists video completion receipts, reader version, source
release, public/native execution, integrated capability acceptance,
external/device qualification and Field Trip held reconciliation as unfinished.
The prior photo/description-only qualification wording was therefore stale.
Audio and video are explicit audit rows, with profile-by-profile source and
qualification status; input/draft version numbers cannot be assumed to equal
public snapshot versions.

| Surface                                                                                                                   | Writer reservation and handoff rule                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| History source admission, private evidence, child execution/completion, review/selection and native History/Capture queue | Existing history effort retains exclusive implementation ownership until an explicit handoff; this effort is read-only                                              |
| Shared funding, provider accounting, media, account transitions and their migrations                                      | Treat as overlap, even if called by initial analysis; history owner controls current changes, then one named successor owns the combined forward migration sequence |
| Isolated initial-analysis handlers and cancellation planning                                                              | Hardening effort may prepare isolated changes only after explicit implementation instruction and a dependency check showing no shared-owner mutation                |
| This RFC and readiness evidence                                                                                           | Hardening review owns these documentation edits only                                                                                                                |

Before transfer, record the final agreed SHA, exact file/routine ownership,
unfinished contracts and tests, migration owner/order, and combined-diff review.
Do not cherry-pick the skill branch into this busy checkout during review. Its
integration remains the first isolated implementation preparation step. No
message or instruction was sent to the other thread; reading its status is not a
handoff.

### Source-inspected nested lock sequences

These are concrete inspected sequences, not a complete migration-expanded
catalog. All listed row/advisory locks are transaction-scoped. An external I/O
operation must not extend their lifetime.

| Source owner                                                          | Observed acquisition sequence and modes                                                                                                                                                               |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lock_owned_observation_evidence`, migration `20261003051251`         | Owner user `FOR UPDATE` → observation scan-ingestion exclusive advisory → owned scan `FOR UPDATE` → observation history `FOR UPDATE`                                                                  |
| `lock_owned_observation_source`, migration `20261008191800`           | Parent evidence helper above → exact observation/source exclusive advisory; validates immutable source membership                                                                                     |
| `lock_observation_analysis_source`, migration `20261008213302`        | Parent helper → bound source helper when present → child scan-ingestion exclusive advisory → child history-evidence exclusive advisory; caller takes intent row lock afterward                        |
| `lock_video_observation_analysis`, migration `20261010144617`         | Parent helper → exact source helper → child scan-ingestion advisory → child history-evidence advisory → child intent `FOR UPDATE`; dispatchability subsequently locks original quota row `FOR UPDATE` |
| `observation_source_completion_candidate`, migration `20261009032643` | Within its caller's ownership scope: original quota `FOR UPDATE` → invocation `FOR UPDATE` → usage event `FOR SHARE` → complimentary allocation `FOR UPDATE`                                          |

This demonstrates why a global ledger-before-quota or quota-before-ledger
rewrite is not justified from one wrapper. The same-owner outer lock can
serialize paths with different inner sequences; independently scheduled
retention/cleanup and multi-owner transitions require separate analysis. The
remaining inventory must include their final routine bodies, triggers and
retention lock modes, not only these helper definitions. Preserve existing
serialization until that proof closes.

The independent read-only audit additionally confirmed that legacy media cleanup
uses asset/scan/job snapshots and lease/retry deadlines, not the required
durable object-retirement claim. That owner must change before held-state
activation. Legacy admission's base migration and later dynamic patches differ;
do not label its current order from the base definition alone.

To close the inventory after the history SHA is fixed, replay that exact
migration set in a disposable database and retain `pg_get_functiondef`
definitions for every applicable overload plus trigger call edges. Cover initial
admission/deletion; source V2/V3/V4 admission, claim, dispatch, outcome, append,
retirement and recovery; media erasure/retention; Ghost merge and account
deletion. Record caller-held locks as preconditions, including completion
helpers and merge internals. Assert the resulting catalog contract in tests.
Multiple-owner entrypoints must either prove existing deterministic ordering or
acquire source/target owners in canonical UUID order before subordinate locks.
Any change must be coordinated across all callers. The exact nested
parent/source/child sequence remains path-specific; a legacy initial scan must
not acquire fictional history-parent locks for uniformity.

### Closed transition decisions

| Event                                                  | Allowed durable transition                                                                                             | Denied transition                                                       |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Funding reservation, admission conclusively rejected   | Idempotent release of original reservation/hold under the funding owner, or rollback of combined admission transaction | Release based only on timeout or an absent read                         |
| Admission accepted, identity/configuration/media valid | One logical-analysis primary grant, original quota committed atomically                                                | Second grant via a new attempt, reservation, endpoint or recovery claim |
| Grant reply unknown                                    | Keep logical dispatch consumed and visible hold; exact reads                                                           | Provider invocation based on a replayed grant                           |
| Provider result received                               | Save exact bounded validated evidence using original authority; then finalize                                          | Re-inference because evidence persistence is uncertain                  |
| Exact evidence found after lost write reply            | Finalize same result and original funding association                                                                  | Replace result/configuration or allocate new funding                    |
| Result unavailable after unknown execution             | Recovery-needed hold with support classification                                                                       | Pretend reconstruction, automatic successor, or timeout-based refund    |
| Cancellation outbox delivered                          | Server fence orders against grant/completion; local acknowledgement persisted separately                               | Claiming local cancellation itself stopped a remote provider            |
| Cleanup retires object                                 | Reassign cleanup token if necessary; key remains retired forever                                                       | Binding the key after cleanup lease expiry                              |
| Account transition                                     | Transfer or reject exact durable identities through reviewed account transaction                                       | Treating a new owner namespace as fresh dispatch authority              |

Account merge must carry the dispatch-used fact and original operation identity
without reset; collisions deny/hold the whole conflicting transition. Tombstones
must deny old-session replays after deletion. Minimal permanent authorization
receipts are private technical records, not permission to retain deleted media,
result payloads or unrestricted personal data.

### Test ownership and proof matrix

These are required acceptance IDs, not claims that new tests already exist. Each
needs initial-analysis and child-analysis variants, or an explicit source-backed
non-applicability decision. Unit mocks alone cannot close database serialization
or storage races.

| ID      | Deterministic scenario                                          | Required proof boundary                                                          |
| ------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| LIFE-01 | Fresh reservation/claim after lost grant, including pruning     | Real database logical-analysis uniqueness and exactly zero second provider calls |
| LIFE-02 | Cancellation before/after grant and during completion           | Database barriers, native outbox restart and no resurrection                     |
| LIFE-03 | SDK returned error, write commit then lost reply, process death | Pinned SDK mock plus exact database evidence/result reconciliation               |
| LIFE-04 | Staging overwrite after verification                            | Storage barrier; compare bytes actually submitted and promoted                   |
| LIFE-05 | Cleanup sent, lease expires, new worker/completion resumes      | Irreversible registry retirement plus delayed external delete                    |
| LIFE-06 | Late upload/copy after cancellation cleanup                     | Capability-expiry timeline, repeated deletion and no binding                     |
| LIFE-07 | Funding reserve then denial/unknown admission                   | No stranded proven-unused hold; ambiguity never releases; one settlement         |
| LIFE-08 | Restart/account merge/delete during every await boundary        | Exact owner/generation fencing, preserved dispatch-used fact, collision rollback |
| LIFE-09 | Child C completes while selection changes A to B                | One appended C, B stays selected, correct review/credit projection               |
| LIFE-10 | Maximum supported media and slow dependencies                   | Real abort propagation, memory/CPU measurements and settlement reserve           |
| LIFE-11 | Lost delivery, two devices and month/subscription transition    | Same saved result and original funding association, no second consumption        |
| LIFE-12 | All legacy callers and old workers against new states           | Fail-closed compatibility and no pruning/replay of held work                     |

### Deadline and operational acceptance decisions

Use one monotonic remaining-budget calculation per invocation. Require remaining
request and claim lifetime to cover authorization timeout + configured provider
maximum + evidence/settlement reserve before granting. The measured reserve must
cover the bounded critical database/media operations, including their failure
path; a caller-specific deadline cannot be guessed from provider timeout alone.
If the inequality fails, do not grant. Release only a provably unused
reservation through its owner; retain ambiguous state. End of client waiting is
not cancellation.

Concrete numeric profiles are release evidence, not invented in this source
review. Before activation, record supported modality/size,
request/lease/provider budgets, settlement reserve, peak heap/CPU, tail latency
and measured cancellation behavior for each profile. No activation until each
profile fits the supported runtime or is explicitly unavailable. Do not solve a
failed profile by unbounded retries or silently dropping media. Report user
completion, durable completion, unknown holds and provider cost separately so
successful HTTP responses cannot hide lost scans.

Read-only support lookup returns lifecycle stage, safe reason, evidence-present
flag, original funding settlement state and next permitted action. No raw media,
provider output or credentials. Recover saved evidence automatically only with
exact authority; unresolved loss stays held. Any customer adjustment remains a
separate audited policy decision and cannot reset dispatch authority. Assign an
operational owner before activation for immediate invariant alerts, overdue
stage queues and the existing 24-hour hold escalation.

### Remaining gates and honest readiness

| Prerequisite                                                    | Review disposition                                     | Completion evidence                                                                                                  |
| --------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| Primary uniqueness, uncertainty, permanent cleanup, exact bytes | Contract closed                                        | LIFE-01 through LIFE-06 during implementation                                                                        |
| Current funding versus future token policy                      | Contract closed; no pack implementation                | LIFE-07/LIFE-11 plus existing settlement regression tests                                                            |
| Module ownership and history overlap                            | Writer reservation defined; handoff pending            | Agreed immutable SHA, ownership and migration record before overlap                                                  |
| Exact nested lock inventory                                     | Source sequences inspected; not globally closed        | Final migration-expanded definitions, nested modes/order and concurrency proof; preserve current outer serialization |
| Skill availability                                              | Reviewed isolated skill identified; active link absent | Integrate only during authorized implementation preparation and pass agent-assets                                    |
| Runtime and operational budgets                                 | Acceptance procedure fixed; measurements pending       | Per-profile artifact and named operational owner before activation                                                   |
| Old writer/worker quiescence                                    | Required rollout contract, unexecuted                  | Separately authorized target-specific drain and capability evidence                                                  |

No unrun gate is marked complete. Read-only inspection can continue while
history changes, but an exhaustive frozen lock table and agreed handoff cannot
honestly be declared final against an active moving implementation. Recheck that
delta at the checkpoint rather than prematurely rewriting its locks.

## Review validation record

For this documentation update: ten existing persistence/promotion tests passed
using cached dependencies with no network permission; the user-skill link check,
changed-Markdown formatting gate and `git diff --check` passed. An independent
read-only funding audit informed the additional admission and ownership
findings. Existing tests do not prove the proposed contracts (one promotion test
explicitly asserts today's destructive rollback behavior). No native build,
database replay, load test, device test, hosted mutation or paid inference ran.
Those remain implementation/qualification gates, not completed review evidence.

The end-to-end reanalysis scope expansion updated planning only. It also
clarifies the lock-order discrepancy and the current funding settlement
override. Markdown and whitespace checks were rerun; no additional runtime
coverage is claimed.

The accepted-roadmap amendments make primary dispatch uniqueness analysis-wide,
keep lock ordering provisional until nested and multi-owner paths are
inventoried, and require a recorded history integration checkpoint before
overlapping edits. Earlier slices remain inactive until identity, configuration
and exact-media prerequisites are integrated. These are planning changes; no
checkpoint agreement or implementation/runtime validation is implied.

Final readiness review added the fixed comparison SHA, active-history ownership
reservation, nested lock evidence, transition/test matrices and operational
acceptance procedure. Independent source review was bounded; final catalog
replay, handoff agreement and runtime qualification remain open. Only
documentation formatting and whitespace checks were run for this readiness
update.

## History coordination response — 2026-10-10

The user explicitly authorized messaging **Scan ID History** to settle this
checkpoint. The history thread responded with the following agreement:

- `15e60d0a585e4fad96d249b2d5ea92ddfcda8647` is a completed comparison baseline,
  **not a final shared-contract transfer**.
- History retains the sole writer for shared history, funding, media, account
  and native owners. Hardening retains this RFC and read-only review. Transfer
  must list exact files/routines, unfinished contracts, migration order and
  combined-diff review.
- History owns the current shared forward migrations. Its validated sequence
  ends at `20261010162902`; pending `20261010164735` follows it. No other effort
  may insert a competing shared mutation during this ownership period.
- Video terminal settlement was under validation; successful video completion,
  reader support and source-release proof were still unfinished.
- `.artifacts/video-accounting/` holds the comparison baseline's reported
  461-migration/catalog/ACL validation evidence. The disposable workspace
  `/private/tmp/merian-audio-selection-db` was actively validating the next
  462-migration candidate, so it is **not** a live catalog of that baseline and
  must not be reset, queried as exact-SHA evidence or otherwise disturbed.
- No complete retained migration-expanded function/trigger lock inventory
  exists. Source snippets and passing catalog assertions do not substitute for
  it.

Ownership and migration coordination are therefore agreed; shared-contract
transfer and the lock-inventory proof are not settled. A follow-up requested a
precise freeze milestone after video terminal settlement, successful completion,
reader support and source release are reviewed, plus a retained schema-only
catalog inventory from the matching completed disposable validation. That
proposed milestone is pending confirmation. The inventory must carry exact SHA,
migration manifest hashes, function definitions and trigger edges without
credentials or user data. Audit nested modes/caller-held locks and cross-owner
ordering against that artifact before approving transfer.

Do not treat this coordination as permission to start implementation or as proof
that missing history contracts have completed. The active history operation was
left undisturbed; this update changed documentation only.

The follow-up response confirmed the milestone and committed to retaining a
schema-only expanded-routine/trigger catalog after active validation, with
commit and migration-manifest hashes. This settles the coordination procedure
and evidence owner. The export alone will not close the prerequisite: the
hardening review must analyze nested call paths, caller-held locks and
multi-owner ordering against the final baseline. Any earlier export is
comparison evidence and needs a final baseline delta check. No ownership
transfer or complete lock proof is claimed.

## Scheduled coordination check — 2026-10-10 17:58 UTC

History advanced to private V4 durable completion at
`70ba0105b2e4e49a50bd934ad2ba8cf2707a2356`. Its continuation still lists public
reader support and source-release proof as unfinished. Shared ownership remains
with history; the agreed final checkpoint and transfer have not occurred.

The preliminary export at `.artifacts/video-terminal-settlement/catalog/` is now
available for commit `6147f6fee2f799275807d794be4b7d2a94cbf932`. This review
independently verified the catalog and manifest SHA256 values, commit tree, all
462 migration file hashes against that commit, and the exported applied
migration version list. It contains 1,015 routines, 271 triggers and 351 foreign
keys. Verification used local files/Git only; no database was started or
queried.

Expanded definitions resolve two previously uncertain points at that historical
baseline: `public.begin_scan_ingestion` does acquire the owner user row
`FOR UPDATE` before the scan advisory lock (base migration text alone misses
later patches), and `internal.perform_ghost_profile_merge` acquires the two
profile rows with `ORDER BY profile.id FOR UPDATE`. These observations do not
prove all nested merge/retention paths or a complete lock-order graph.

The history thread was notified that this export is verified comparison evidence
and asked to retain the corresponding updated catalog at the final milestone.
Full overload/call/trigger/retention analysis and final-baseline delta review
remain pending; no complete readiness, ownership transfer or implementation is
claimed. The recurring review remains active.

## Catalog review checkpoint — 2026-10-10 18:54 UTC

History explicitly confirmed `6c842d4ed191815aa2e6e84bc53d8ce75deeb59e` as the
review baseline covering private video completion, public reader11 and durable
source release. This closes the missing-schema-evidence prerequisite for
starting the lock review. It does not transfer implementation ownership. History
reports public video begin/advance/recovery, native execution and integrated
acceptance still unfinished; its active normalization checkpoint adds no SQL.

Independently verified `.artifacts/video-source-release/catalog/`: commit tree
`cb8c3f1e232217bca9355b9d33f56fa8cc43d3da`, catalog SHA256
`d5907f72e0ce0011927bad3fafba3b73eefac19a33c766338734c05b7d42df88`, manifest
SHA256 `ef9bc561b69f7a59a2ed7cf54da4ab4787886171bdb8c25595be20598f40543f`, all
465 migration file bytes against Git, and the applied migration version list.
The export has 1,024 routines, 272 triggers and 352 foreign keys. Verification
used local files only and left the active history database untouched.

The expanded initial/account and child/retention paths are now under independent
read-only review. Preliminary inspection preserves these existing guarantees:

- Private evidence erasure claims lock only the due queue row using
  `FOR UPDATE SKIP LOCKED`; finishing updates only the matching live claim.
  Enqueue is driven by evidence deletion, so this queue is distinct from the
  original evidence/admission owner. Full cascade/caller ordering still matters.
- Publication object erasure locks one due registry row; its binder rejects
  expired, revoked, claimed or erased objects. The registry trigger forbids
  increasing `available_at`, changing an existing revocation or deleting the
  registry row. Claim replacement therefore does not make an expired object
  bindable again. Preserve this existing mechanism rather than infer a missing
  permanent fence from token expiry alone.
- The effective provider-quota pruner excludes reservations with source
  bindings. This is stronger than its old base migration, but is not a universal
  permanent execution fence for initial analysis or a proof for all deletion
  paths.

Nested overload/trigger/FK and retention analysis is in progress. No global lock
safety, concurrency proof or implementation transfer is claimed. A later schema
change must be compared against this verified baseline before the review closes.

### Bounded expanded-catalog findings

The following supplements the earlier source-inspected table at the verified
465-migration baseline. It is source evidence, not a runtime deadlock proof or
final handoff. No disposable database or concurrency test was run by this
review.

| Path                         | Expanded acquisition and caller requirements                                                                                                                                                                                                                                                                                                                                                                                        |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial admission            | `begin_scan_ingestion`: owner `FOR UPDATE`, then scan-ingestion transaction advisory, then job/intent writes. Later patches supply the owner lock missing from an early base definition.                                                                                                                                                                                                                                            |
| Funding                      | The original-analysis overload of `reserve_ai_quota_core` takes owner `FOR UPDATE`, policy `FOR SHARE`, analysis advisory, optional complimentary usage `FOR UPDATE`, then calls core quota admission. Generic core admission takes owner/policy `FOR SHARE`, request advisory and reservation `FOR UPDATE`. Generic finalization starts from the reservation; retain caller-specific analysis rather than impose one global order. |
| Observation deletion         | `request_scan_deletion`: owner, observation advisory, scan `FOR UPDATE`, tombstone and its triggers. `complete_scan_deletion`: owner, observation advisory, tombstone `FOR UPDATE`, scan deletion. Intent/evidence cascade triggers reacquire existing owner locks on these ordinary paths.                                                                                                                                         |
| Private evidence retirement  | Photo/audio retirement takes the parent evidence helper and child evidence advisory before cohort/object locks. Video retirement uses the locked exact source binding and rechecks execution clearance. Discovery snapshots are not deletion authority.                                                                                                                                                                             |
| Account scientific retention | `apply_user_tombstone` takes owner `FOR UPDATE`, publication/community rows with `NOWAIT`, then observations in UUID order: advisory, scan/history `FOR UPDATE`, selected result/authority `FOR SHARE`. Preserve allowlisted scientific retention and examine subordinate cascades before changing lifecycle ownership.                                                                                                             |
| Ghost merge                  | `perform_ghost_profile_merge` locks both profile rows in UUID order before subordinate work. Complimentary rows use `(user_id, client_scan_id)` order. Reservation collision pairs are ordered by source reservation, not a universal canonical pair order; preserve the outer two-owner serialization.                                                                                                                             |

Remaining implementation prerequisites are explicit:

1. **Identity-merge recovery policy:** the expanded
   `prepare_scan_ingestions_for_identity_merge` changes interrupted committed
   quota into failed state and describes eligibility for a newly charged retry.
   Its outer merge currently rejects pending ingestion and history/source work;
   do not infer that every branch is reachable or that a duplicate was observed.
   Trace effective callers and supersede any reachable reopening policy with
   permanent logical-analysis hold/reconciliation in the lifecycle forward
   migration. Quiesce incompatible writers/workers before activation. Test a
   fresh reservation after uncertain execution and an account transition.
2. **Account deletion and retention:** specify how each new dispatch,
   uncertainty and cancellation record is fenced before scientific detachment
   and private cascades. Preserve the existing scientific scalar allowlist;
   neither erase those facts nor retain private payloads by changing cascade
   behavior accidentally. Qualify admitted, dispatched and uncertain child
   completion against account deletion.
3. **Caller and worker closure:** finish generic quota finalization/pruning,
   nested dynamic calls, trigger/FK and multi-owner collision analysis. A
   differing inner order under the same owner lock is not by itself a deadlock.
   Any newly introduced multi-owner path needs deterministic owner and
   subordinate ordering or a proof of existing serialization.

These findings were sent to the history owner for coordination. No concrete lock
inversion was established in the bounded initial/account subset, and no
implementation or migration was changed. The complete lock prerequisite and
named-successor transfer remain open; the verified catalog permits useful review
while history finishes its integration contracts.

The independent child-path review also found no concrete cycle in its bounded
V2/V3/V4 trace. Known completion/advance owners establish owner → parent →
source → child → intent before quota/accounting. Expired quota refund and
pruning both exclude source-bound analyses; no static reverse
quota-holder-to-parent acquisition was established. This does not resolve
unknown dynamic callers.

Two additional named boundaries must close before accepting the lock inventory:

- `release_completed_observation_source` takes no canonical ownership locks
  itself. Its completion-candidate helper locks quota/invocation/usage/credit,
  and the proof insertion trigger calls that helper again. Known advance and V4
  completion callers supply the prefix. Inventory and restrict every direct,
  trigger and dynamic entry; test rejection outside the required context and
  contention against terminal settlement.
- `erase_observation_analysis_intent` can be reached through deletion cascades
  while subordinate locks are already held. Record every supported cascade
  initiator and its held locks. Test completion versus retirement/tombstoning in
  both orders, alongside generic quota reservation versus each V2/V3/V4
  admission path. Retain separate late external-erasure tests: storage I/O is
  outside database locks and needs permanent non-bindability as well as token
  ownership.

Both independent reviews are complete for these bounded catalog subsets. The
repository-wide caller closure, corresponding contention evidence, final history
delta and explicit successor agreement remain prerequisites. None is waived by
the absence of a concrete cycle in the inspected subset.

## Schema delta review — 2026-10-10 19:57 UTC

History advanced through service orchestration
`64500eacc138fb06ce5617aae6dd44bff47edaf7` and Edge execution
`6100dddbf722a1aad62e10963ba3dd04592b7ecb`. Native video work remains active and
ownership has not transferred. This review left its build and database
untouched.

Independently verified the retained `.artifacts/video-orchestration/catalog/`
against the orchestration commit: tree
`2481f74c181c46f2a755af820a1e02bfb39c8261`, catalog SHA256
`ea44b63be92c698a59f3a8ee56c112626a5717e1bcdf328ee0e65b2ba6478cef`, manifest
SHA256 `a0a40f18867e461583afe596bcdd0c317f2276ebfa6f9b98d1980e0e25653451`, and
all 466 migration file hashes against Git. There is no migration delta between
that commit and `6100dddbf`. Relative to the verified 465-migration catalog, the
expanded routine delta is exactly four additions, no changed or removed routine
bodies, and identical 272 triggers and 352 foreign keys.

Migration `20261010190000_prepare_video_orchestration.sql` adds:

- `begin_owned_observation_video_analysis`: service/gate checks, canonical
  private admission, then initial claim in the same transaction.
- `claim_observation_video_analysis_recovery`: canonical video lock helper,
  saved-outcome/draft eligibility and dispatch identity checks, then intent
  work-token update. It does not authorize a provider retry.
- `list_observation_video_analysis_recovery`: bounded identity discovery with no
  row locks or execution authority; the claim rechecks eligibility.
- `advance_owned_observation_video_analysis`: canonical video lock helper before
  operation routing. Original-token late outcome capture remains separate from
  live-work progression; completion and terminal settlement delegate to existing
  private owners. Taxonomy reads lock at most two normalized matches `FOR SHARE`
  in UUID order and do not invoke taxonomy insertion or its advisory locks.

This additive composition preserves the inspected owner/parent/source/child
prefix. It does not close the earlier direct-helper, cascade or cross-version
contention obligations. Existing source tests in
`observationVideoEvidenceDb.test.ts` cover competing public begin/recovery
claims and known-result settlement. The retained validation summary reports six
focused tests and 151 catalogs/2,906 assertions; these are history-owned
results, not tests rerun here or global deadlock proof.

The coordination request asks for matching existing contention evidence and
final checkpoint confirmation without duplicating validation. Final caller
closure, integration delta and named successor agreement remain open. All
activation gates and the no-implementation boundary remain unchanged.

## Caller and cascade review — 2026-10-10 20:55 UTC

History's native execution-record checkpoint is
`2a0e466698badf53d83b41ed6f1425201a179b42`. Its use of “handoff” describes
transfer from native upload to an execution record, not ownership transfer to
this hardening effort. Transport, queue execution and integrated acceptance
remain in progress. Git confirms no migration changes from the verified
466-migration orchestration checkpoint through this native commit.

Further read-only inspection narrows the remaining caller inventory:

- `release_completed_observation_source` and its proof trigger function have
  explicit EXECUTE revocations for PUBLIC, anon, authenticated and service_role
  in `20261009032643_prepare_source_completion_release.sql`; no later named
  reference changes those grants. The expanded ordinary advance routine is the
  identified direct helper caller. The proof INSERT trigger requires the exact
  owner/analysis/current-transaction setting before validating the completion
  candidate. These are useful reachability constraints, not proof that a setting
  alone acquires ownership locks. Final effective privilege evidence and
  indirect/dynamic entry analysis are still required.
- Intent erasure has an explicit AFTER INSERT tombstone path:
  `fence_observation_analysis_intents` deletes matching intents, invoking the
  BEFORE DELETE erasure trigger. Its known scan-deletion caller already owns the
  owner/observation prefix.
- The exported foreign-key path is `public.scans` →
  `internal.observation_histories` → `internal.observation_analysis_intents`,
  with ON DELETE CASCADE at both edges. `complete_scan_deletion` is the
  identified explicit scan DELETE routine; deleting a user can also cascade to
  remaining owned scans.
- Account detachment has a separate path: AFTER UPDATE of scan `user_id` from
  nonnull to null invokes `clear_detached_observation_history`, which deletes
  the history and cascades into intents. Its ordinary scientific-retention owner
  locks the observation before detachment. Any other supported updater or
  dynamic writer must supply compatible preconditions; the trigger itself does
  not establish the full prefix.

These are identified entry paths and constraints, not an exhaustive assertion
about privileged SQL or all dynamic callers. Match them to existing denial and
two-session contention evidence before closing the prerequisite. No runtime
checks, builds or database operations were started in this pass; implementation
ownership and default-off gates remain unchanged.

## Final local history checkpoint — 2026-10-11 00:58 UTC

History explicitly confirmed `07c381d9d77936b85d36109c43b51ceea7b1dae7`, tree
`d74ded71f623f04a2e6fbce068bc5cf5cecd23ba`, as its final local comparison
checkpoint. Its retained validation reports 38 focused and 5,890 full native
tests passing. This review independently verified the Git tree and absence of
migration changes from the verified 466-migration orchestration catalog.
Publishing that local commit remains separately blocked on fresh user approval;
that does not prevent local read-only comparison and is not authority to push.

The ownership agreement is now explicit: history retains shared code/migration
ownership. Hardening thread `01a112ae-2c97-77a1-bd53-5a4434510d4c` is the
conditional named successor only after lock prerequisites and final SQL-delta
review close, followed by a later user implementation instruction. No write
authority transfers through this confirmation. History's own follow-up remains
paused; this review does not restart it.

History supplied these existing evidence pointers:

| Boundary                     | Existing evidence and limits                                                                                                                                                                                   |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V2/V3 source completion      | `.artifacts/source-completion-release-validation.md`: eight actual completion/reservation and completion/deletion races, both orders; malformed-proof denial, rollback, no-backfill and parent-erasure checks. |
| V4 completion/source release | `.artifacts/video-source-release/final-checkpoint.md` and `lock-inventory.md`: duplicate completion, completion/tombstone both orders, permanent proof and gate-closed replay.                                 |
| V4 pre-execution retirement  | `.artifacts/video-retirement-sql/checkpoint.md`: observed blocking for duplicate/successor/recovery, cohort/deletion both orders, admission and dispatch.                                                      |
| Service orchestration        | `.artifacts/video-orchestration/validation-summary.json`: six focused cases and 151 catalogs/2,906 assertions, including competing begin/recovery claims.                                                      |

These are retained historical candidate results, not new test executions or
complete cross-version coverage. In particular, existing scientific-retention
concurrency tests cover selection/rejection against deletion, not every active
execution phase. The final source audit is now pinned to an agreed local SHA;
release-helper reachability, effective privileges, complete cascade initiators,
generic quota versus each input version, terminal contention and late external
erasure qualification remain individually tracked. Neither native test totals
nor a successful narrower race substitutes for those specific obligations.

## Source-inventory closure and text gap — 2026-10-11 01:57 UTC

Independent read-only reviews at `07c381d9` resolve the following previously
open source-inventory subsets. This supersedes their earlier “unknown caller”
status; it does not claim new runtime validation or overall handoff completion.

- **Completion release:** supported photo/audio entry is the locked
  `advance_owned_observation_analysis` draft-to-complete branch. Video entry is
  the locked `advance_owned_observation_video_analysis` completion branch,
  through `complete_video_observation_analysis` and its transaction fence.
  Private release/candidate/guard routines and receipt tables deny direct API
  roles, including service_role. Receipt insertion checks the exact
  transaction-bound proof; video also checks live occupancy. The review found no
  supported indirect or dynamic entry bypassing these owners. Migration-time
  definition patching is distinct from executable API reachability; arbitrary
  database-owner SQL is outside this API guarantee.
- **Supported cascade initiators:** tombstone insertion, physical scan deletion
  and account detachment reach the known erasure triggers under their
  owner-first entrypoints. Normal creation uses guarded scan persistence. Ghost
  reparent locks both user rows in UUID order and changes nonnull owner to
  nonnull owner, so it does not invoke the detach-only history deletion trigger.
  Current merge rejects active history/source state; no supported history-intent
  path enters legacy stranded-ingestion recovery.
- **Legacy merge policy:** newly charged retry is a legacy ingestion recovery
  policy, not proof that history can redispatch. It still requires explicit
  treatment in initial-analysis hardening. Preserve the outer merge guards and
  prove effective branch reachability before changing them; do not remove
  serialization or infer a historical duplicate from comments alone.

Evidence inspected includes `observation_source_completion.sql`,
`observation_video_source_completion.sql`, direct-denial cases in
`observationVideoEvidenceDb.test.ts`, and the source completion/retirement and
scientific-retention concurrency suites. None was rerun by these reviews.
Remaining lock qualification is concrete: the complete generic-quota versus
V2/V3/V4 admission and terminal-settlement contention matrix, effective
candidate privilege/catalog validation, multi-owner transition regressions, and
late external-erasure/non-bindability qualification. Existing narrower races
remain valid evidence for their own cases. These qualification limits still
prevent claiming the entire handoff prerequisite settled.

### Description-only history is a separate missing integration

History's later read-only audit, retained at
`.artifacts/written-description-readiness-audit.md`, identifies an additional
scope limit at the same SHA. Initial Describe has a native queue/execution/save
journey; description-only historical child analysis does not yet have the
source-bound lifecycle. Generic V1 parsing/storage/read support is not that
integration. Native preparation and execution currently require media, while V1
admission does not establish the newer source binding and occupancy.

The hardening modality inventory must therefore distinguish initial text from
history-bound text. Before implementation of that missing journey, agree its
versioned identity/compatibility, exact ordered text and digest, frozen source,
no-upload execution, original funding/processor, durable dispatch uncertainty,
result binding, atomic append, retirement and release proof. Qualify restart,
Unicode/whitespace/bounds, deletion/account changes, lost completion and source
contention without changing selection or inventing media. Reuse supported V1
read/storage owners where appropriate; never remove photo guards globally or
route through legacy admission as a fallback.

This is an inactive integration gap, not an observed exploit or permission to
add another implementation slice. Shared writer ownership remains with history
until explicit agreement. The 5,890 native passes do not qualify this absent
journey. Any eventual text schema addition needs a new catalog delta and the
same lock/identity/funding review before it joins the hardening baseline.

## Integrated audit reconciliation — 2026-10-11 03:01 UTC

History's integrated audit at the unchanged `07c381d9` checkpoint is retained in
`.artifacts/integrated-identification-history-audit/report.md`. It confirms the
supported release/cascade source closure and does not establish another
execution, funding or source-release defect. Do not restart those closed source
investigations merely because runtime qualification remains incomplete.

A concrete additional contract defect must be repaired before activation: V2
photo-description validation uses ECMAScript `String.trim()` on the backend and
Foundation `.whitespacesAndNewlines` in native request/history admission. The
retained synthetic host predicate probe shows U+0085 accepted as content by Deno
but rejected by Foundation, and U+FEFF rejected by Deno but accepted by
Foundation. These are fail-closed interoperability failures, not an
authorization bypass. Probe evidence is not an iOS device or endpoint
qualification run.

Plan amendment: make V2 producer/request/reader predicates agree with the
canonical text contract, preserving exact frozen text. Add shared ordinary
whitespace, U+0085, U+FEFF, mixed-content, Unicode and length-boundary vectors.
Do not normalize stored text or alter a persisted fingerprint to hide a
mismatch. This is a named repair under the existing shared-writer boundary; this
planning review does not implement or authorize it.

The audit also confirms two scope/documentation requirements:

- Reconcile current reader summaries to reader11 and version-specific support;
  retain historically accurate older protocol sections as historical. Current
  summaries in the API and Supabase READMEs lag the native implementation.
- Keep V5's read-only history support distinct from ordinary video editing,
  selection, review, reanalysis-source reuse, publication and selected Field
  Chat. Gates cannot create those absent action contracts. Any expansion needs
  an explicit capability decision and qualification, not an inferred new slice.

The description-only historical-child gap and concrete contention/late-erasure
qualification remain open as previously recorded. The audit's evidence binding
matches all 466 migration hashes and six native checkpoint hash sets; it reports
no backend delta since `6100dddbf`. This pass inspected the report and probe,
checked no migration delta, and changed only this plan. It did not rerun suites,
change canonical product contracts or transfer ownership. Final handoff remains
conditional; no implementation or external publication is authorized.

## Parity repair reconciliation — 2026-10-11 04:02 UTC

History completed the separately authorized parity/documentation repair in local
commit `b8eb3d64f66045ba95c4e4fa5feec82d0462d5df`, directly following
`07c381d9`. This supersedes IA-02 and IA-05 as open repair items; the historical
audit findings remain intact. The 13-file change uses the existing
ECMAScript-compatible predicate in V2 reader, preparation and request paths,
preserves exact description bytes, adds shared Unicode vectors, and corrects
current reader summaries. Git comparison confirms no migration delta, so the
verified 466-migration lock baseline remains applicable.

Retained `.artifacts/v2-description-parity/checkpoint.md` reports 5,893 full
native passes, followed by a rebuilt 26-test focused pass after two test-only
lint corrections, and 3,493 Edge tests/484 steps. No new catalog/ACL/advisor run
is claimed for this SQL-unchanged repair. This review inspected the checkpoint
and committed scope; it did not rerun validation or publish the commit.

The remaining readiness items are unchanged: description-only history-bound
children, specifically uncovered quota/terminal/multi-owner contention, external
erasure and device qualification, and separately held Field Trip reconciliation.
V5 ordinary actions/editor remain outside its read-only capability. Ownership
transfer, activation and external publication are not inferred from this repair.
The read-only coordination remains active.

## Initial completion interface agreement — October 11, 2026

The user authorized finalizing the shared initial-completion/recovery interface
with history before alpha checkpoint 1. Both threads acknowledged
[IC-1 revision 2](initial-completion-history-interface-2026-10-11.md) at SHA-256
`4e3f4ad5e6157548fcc8f58a3f05b89dcc5bf312917d8aab126c84c8eb51f3f4`. Independent
read-only review and re-review found no remaining concrete agreement gap.
History primary recorded this append-only coordination note; the historical
reviews above are unchanged.

This closes the alpha roadmap's A1 design prerequisite. IC-1 names immutable
submission/result/completion owners, all three initial route adapters, six fixed
service operations, complete receipt bindings, exact recovery and
pre-row/account erasure. S0 requires durable original input, permanent logical
dispatch fencing, validated result evidence, original configuration/funding and
exact media before the new completion path can run. The server-owned
`initial_analysis_lifecycle_enabled` gate remains false; checkpoint 1 can
prepare inactive artifacts, not switch live handlers to a partial sidecar path.

History retains sole shared code/migration writer ownership. No transfer to the
hardening successor or implementation in this thread is authorized by agreement.
A15/S0 implementation, expanded SQL lock/privilege validation, missing
contention, installed/device/hosted qualification and separate Field Trip
reconciliation remain open. Remote provider retention/erasure requires its own
documented qualification; local deletion is not proof of remote erasure.

Evidence and acknowledgement provenance:
`.artifacts/initial-completion-agreement/checkpoint.md`. Baseline remains
`b8eb3d64f66045ba95c4e4fa5feec82d0462d5df`. No execution tests, source changes,
SQL changes, publication, deployment, activation or schedule change occurred in
this coordination checkpoint.
