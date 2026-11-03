# IC-1 S0: permanent initial-dispatch fence

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

Status: draft bounded interface for independent and IC-1 review. This document
does not enable dispatch or transfer implementation ownership. History primary
remains the sole writer under IC-1 sections 2 and 7; the hardening owner reviews
read-only. Broader engine hardening and Field Trip reconciliation remain
separate.

The accepted local atomic/M1/C1 baseline is
`bc2a5af507a0ee56cbdb1a357f5221bec611371b`, tree
`d9237d4b02d6aba002f2a67161dbdf66d0d0263d`. Evidence is in
`.artifacts/initial-atomic-admission/final-gates/local-checkpoint.json`.
Validation binds the recorded shared-checkout manifests; it is not an isolated
commit-tree or hosted-CI claim. The original eight stage93 deadlocks remain an
accepted, unreproduced limitation of that inactive boundary, with unknown cause.
This agreement does not extend that acceptance to new dispatch locks.

## Scope and dependency order

The existing operation and lifecycle fences already supply permanent scan
identity and irreversible classification. Do not presume a second dispatch-fence
table or a speculative dispatch-proof codec. Extend existing owners only where a
concrete missing invariant is proven alongside its consuming owner. The next
necessary dependency is admitted-v3 M1 to exact M2 v2 verification and transfer
under the accepted handoff, with structural and transform proof explicitly
required before execution. Its concrete protocol and lock delta require review
first. Every current initial provider/result/completion barrier remains
effective. No service-callable grant, deployed route import, provider request,
original-quota commitment or lifecycle transition to `dispatch_authorized` is
permitted by this agreement.

A later separately reviewed compositor may expose one fresh grant only after all
of these dependencies are implemented and qualified together:

1. Exact original admission, configuration, funding and M1 binding.
2. The saved handoff's M2 v2 verification and transfer receipt, where required
   by that admitted protocol. M1 allocation or a verification flag alone is not
   sufficient. An old M2 v1 receipt cannot stand in for the v2 handoff.
3. Structural validation of the exact immutable retained bytes under the saved
   qualified codec/transform policy. Matching length, digest and signature does
   not establish decodability, expansion safety or executable derivation.
4. The permanent one-primary-dispatch fence, original invocation/accounting
   association and compatible C1/deletion lock protocol.
5. Durable original-result capture and atomic completion contracts that preserve
   uncertainty without repeat execution. A grant-only live cutover is excluded.

The [M2 contract](initial-media-verification-interface-2026-10-11.md) and
[handoff contract](initial-preparation-handoff-2026-10-11.md) retain their own
copy, deadline, transfer, codec and hosted-qualification requirements. No
optional supporting description replaces physical photo, audio or video.
Historical already-admitted routes retain exact recovery; a queued but
unadmitted text-only draft needs explicit media remediation.

## Existing owners and reserved change surface

| Surface                      | Current owner and required treatment                                                                                                                                                                                                                                        |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Original admission/M1/C1     | Preserve the complete receipt and original funding proof in `20261012041337_prepare_initial_atomic_admission.sql`; add a forward migration for a new protocol, never edit that accepted migration.                                                                          |
| Permanent logical identity   | `internal.initial_analysis_operation_fences` and `internal.initial_analysis_lifecycle_fences` already survive private erasure. Preserve `operation_id = scan_id` and route collision protection.                                                                            |
| Private dispatch binding     | A future private record may bind the original admission, exact verified/transfer media, original attempt/configuration and funding. Its field schema and erasure guards require review before SQL; no caller-selected replacement identities.                               |
| Quota/invocation writer      | `public.commit_identification_invocation`, `internal.finalize_ai_quota_reservation_core` and their existing accounting owners retain their writes. Current initial-operation denials remain effective outside a future complete, separately reviewed compositor.            |
| Complimentary credit         | `internal.settle_complimentary_analysis` retains original settlement ownership. Dispatch quota commitment is not successful-completion credit consumption; no new policy is introduced here.                                                                                |
| Cancellation                 | `internal.cancel_initial_analysis_explicit`, its captured-prestate/witness/terminal guards and the public C1 wrapper remain the sole positive-unused refund path. A dispatch proof must not borrow C1 authority.                                                            |
| Result/completion            | `internal.initial_analysis_results` and `internal.initial_analysis_completions` remain private inactive containers until their fixed validated-result and atomic-completion owners are reviewed. A dispatch record is neither result evidence nor completion.               |
| Deno integration             | Existing `_shared/ai/identificationUsage.ts:prepareAccountedIdentification` is the original fresh-grant/one-invoke boundary. New initial private schemas belong under `_shared/initialAnalysis/`; no public Identify DTO or native consumer changes in the first increment. |
| Deployment and native routes | `identify`, `identify-multimodal`, historical `identify-describe`, ingestion/replay workers and native queues remain unchanged by the first increment. No selection/catalog installation is seeded.                                                                         |

History primary owns any later overlapping edits, with independent and IC-1
review. This table reserves responsibility; it does not authorize a second
writer, a new accounting engine or an unreviewed exception to the provider
barrier. No additional physical dispatch object is justified now. A future
concrete compositor contract must justify any additional private binding and fix
its schema and write owners before adding it.

Source evidence for the existing boundary:

- `20261011070945_prepare_initial_analysis_admission.sql` creates the immutable
  `initial_analysis_operation_fences(scan_id)` and the original private
  submission/admission owner. The scan identity survives private erasure.
- `20261011092418_prepare_initial_analysis_cancellation.sql` creates
  `initial_analysis_lifecycle_fences(scan_id, state)` subordinate to that
  permanent identity, with no transition into `dispatch_authorized`.
- `20261012041337_prepare_initial_atomic_admission.sql` co-retains the complete
  admitted proof privately in `initial_preparation_admission_receipts`,
  cascading from the submission. That erasable proof is not permanent dispatch
  state.
- `_shared/initialAnalysis/mediaVerification.ts` and
  `20261011113000_prepare_initial_media_verification.sql` implement the earlier
  M2 v1 boundary. They do not implement the admitted v2 mapping, phase window,
  claim/replay or complete transfer contract in handoff sections 5–7.

The next M2 agreement must identify the closed v2 claim, verification receipt
and transfer receipt schemas, byte caps and digest domains, complete ordered
object evidence and original-operation response correlation. It must fix durable
copy/verification/transfer states, saved deadlines and C1/expiry/deletion/claim
fencing. Reuse existing storage and verification owners where valid. Existing
service operation signatures and v1 historical recovery stay unchanged unless
the concrete v2 interface explicitly justifies and reviews an extension. Do not
begin from a grant schema with placeholder media digests. Before any grant, name
and qualify the concrete structural validator and transform attestation against
the same immutable bytes execution consumes.

## Fresh grant and uncertain outcome

One logical initial operation may acquire primary provider authorization once,
bound to its original provider attempt and immutable execution input. Neither a
new worker lease nor a recovery claim creates another primary attempt. Permanent
fences retain only the minimum content-free scan identity and irreversible
classification; owner, media/text digests, payload and funding details remain
private and are erased under their owner.

Only a fresh successful transaction response can authorize a provider call. That
transaction must atomically bind the original invocation, commit original quota
under its existing owner and advance the permanent dispatch state. A duplicate
response/status read returns recovery information with no dispatch authority.
The trusted caller must accept at most one invocation from its fresh grant; no
new idempotency key, model selection or provider retry is inferred.

Loss of the grant acknowledgement is conservatively unknown even if a later
status read confirms the transaction committed. A process crash after grant but
before the network call is also not proof of non-invocation. Both permit only
original-operation status/outcome recovery and reconciliation, never another
invocation or refund. SQL rollback before a grant exists must leave no partial
commit, fence or invocation row. No provider/storage I/O occurs under SQL locks.

Deletion or C1 wins before a fresh grant when it serializes first and commits
under the same logical-operation lock scope; arrival time alone does not decide
the winner. After dispatch authorization, cancellation retains the
known-dispatched or unknown classification and cannot use the positive-unused
refund path. Late provider results cannot resurrect erased private state or a
scan. A known validated original result may later settle through a
settlement-only owner; that owner cannot grant execution, alter configuration or
replace funding.

## Lock and caller inventory required before SQL

The baseline source establishes the following entry and nested owners. These are
concrete starting points, not a claim that a new dispatch lock graph is already
qualified:

- `internal.cancel_initial_analysis_explicit` takes READ COMMITTED, service
  caller validation, owner `FOR UPDATE`, scan-ingestion transaction advisory,
  existing scan/history `FOR UPDATE`, then lifecycle/submission/cancellation
  scope. Its complete C1 stage reaches the original quota and credit writers,
  registry retirement and guarded private erasure before terminal consumption.
- The original `public.commit_identification_invocation` implementation takes
  owner `FOR KEY SHARE`, reservation `FOR UPDATE`, resolves the assigned attempt
  and invokes the original quota finalizer before inserting one invocation.
  `20261011070945_prepare_initial_analysis_admission.sql` adds the explicit
  initial-operation denial. It cannot simply be called or unblocked beneath a
  new inner lock; the complete effective wrapper and trigger graph must be
  inventoried.
- `20261011205141_prepare_initial_preparation_execution.sql` installs permanent
  preparation provider-writer barriers on invocation/result/completion and
  related ingress surfaces. The atomic migration adds narrow admission/C1
  exceptions only. Reusing its permanent `blocked_pre_admission` literal never
  proves unused execution or grants a general bypass.
- Handoff section 7 orders saved catalog checks before funding, preserves the
  original request/reservation/counter/credit owners, then orders the combined
  preparation registries, admitted/transfer receipts, M1/M2 and destination
  registries. Do not acquire an omitted outer/source lock after M1/M2, invert
  counter/credit order, or create a row merely to obtain an absent-row lock.
- Raw scan/account erasure, Ghost identity paths, expiry, quota pruning and
  cleanup claims keep their existing caller permissions and deterministic
  multi-owner rules. Cleanup of retired rows cannot later acquire owner/catalog
  locks. Their actual nested triggers, FKs and statement guards belong in the
  expanded inventory, not just the top-level routine list.

Before any callable transition is proposed, retain an exact baseline effective
routine/trigger/FK inventory and the proposed lock delta, including lock modes,
fresh/replay paths and caller privileges. Identify the precise site where each
existing owner can recognize a complete private dispatch witness. A returned
boolean, caller-supplied token, transaction setting, lock presence or isolated
helper must never independently authorize quota, lifecycle or invocation writes.
No source-only lock inventory is a substitute for actual two-session schedules.

## Evidence and acceptance

The M2 v2 dependency requires closed bounded codecs, original-identity
conflicts, least privileges, erasure/immutability checks, fresh-media
requirements, and tests proving all public dispatch/result/completion paths
still deny this operation. It cannot claim fresh grant or provider execution
acceptance. Pure codec parity alone cannot close stored claim, I/O, transfer or
structural validation acceptance.

Before a later grant compositor is accepted, qualify exact original funding and
verified media, first grant versus replay/lost acknowledgement, rollback at
every write boundary, process loss, cross-owner denial, revoked/unqualified
saved configuration, expiry, and damaged/missing proof without fallback.
Exercise dispatch versus C1, scan/account erasure, media retirement, recovery
and relevant accounting owners in both real lock orders under actual caller
permissions. Assert state, charges/credits and privacy, not just return codes.
Keep trusted fixtures distinct from public admission and successful provider
execution.

Any reproduced unresolved deadlock blocks the affected checkpoint. Preserve
sanitized transaction/lock/statement correlation, implement a scoped correction
and re-review its regression. The historical stage93 acceptance does not waive
these new checks or justify blind retries.

Synchronize executable schemas and every actual consumer when implementation
introduces a payload. Private unconsumed codecs do not justify native DTO churn;
later public Identify changes follow generation and consumer validation. Focused
tests, complete affected gates, exact candidate manifests, independent review
and IC-1 concurrence precede each coherent local commit. Production access stays
nil, activation false, and no push, merge, deployment, hosted scheduling,
installation or distribution is authorized.

## Open agreement items

This draft must be reviewed before advancing. Existing permanent state is
sufficient for the current closed boundary; no dispatch storage increment is
proposed. The next concrete M2 v2 agreement must fix its exact schemas,
write-owner inventory and expanded effective routine/trigger/FK lock delta. M2
v2 transfer and structural/transform validation remain prerequisites before any
callable grant. Result-save, completion and live route/worker cutover are later
dependency increments, not implicit permissions from this document. IC-1 section
8 reopens review for any change to baseline, receipt/input shape, route
coverage, ownership or lock order.

## November 3 — consuming S0 integration after dormant CPM admission

This addendum is the current proposed implementation boundary, based on local
checkpoint `6613e0dc8`. It supersedes the earlier statement that M2 v2 is the
immediate dependency for every new initial operation: historical server-prepared
operations still require their exact saved M2 contract, while the separately
versioned CPM photo branch now has a dormant atomic admission and physical
verification composition. Neither branch is activated. The prior evidence and
restrictions remain historical facts, not permission to bypass media proofs.

The next user outcome is an initial result retained once and recoverable through
History. Its required chain is **original admission → original dispatch →
validated original result → atomic completion → read-only recovery → history
import**. This is one integrated extension of the IC-1 owners, not a separately
callable grant increment. No new dispatch table, status codec, SQL grant or
provider exception is justified by this addendum alone. Concrete SQL signatures,
closed result/projection schemas and effective lock deltas must be reviewed
before their consuming implementation changes an existing barrier.

### Fixed consumers and authority

| Step                     | Existing owner / concrete integration requirement                                                                                                                                                                                                                                                               |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Resolve admission        | `initialAnalysis/cpmPhotoAdmissionDb.ts` and the retained admission receipt resolve the exact original assignment, content, funding and verified role mapping. Its binary admission reader stays pre-terminal. Historical protocols use their exact existing reader, not a CPM reinterpretation.                |
| Prepare execution        | `ai/identificationUsage.ts:prepareAccountedIdentification` and the existing AI preparation boundary retain the one-invoke rule. Preparation must consume saved configuration and exact verified input; it cannot resolve a newer model, mint a reservation or dispatch during preparation.                      |
| Commit original dispatch | The fixed IC-1 dispatch operation must atomically validate the complete original binding, use the existing invocation/quota writers and advance the permanent lifecycle fence. The ordinary `commit_identification_invocation` initial-operation denial remains effective outside the complete compositor.      |
| Capture validated result | `initial_analysis_results` is the existing private bounded destination, not an implemented writer. A route's validated result and exact original invocation/provenance must be retained before promotion/completion. `AIExecutionOutcome.kind = draft` is unvalidated provider output, not completion evidence. |
| Complete                 | `initial_analysis_completions` retains the exact receipt. One transaction consumes immutable submission, validated result, original funding and finalized-media proof, writes the allowlisted initial scan projection and private descriptions, and performs existing settlement/lifecycle transitions.         |
| Recover / import         | A separate fixed read-only status resolves live ownership, cancellation/deletion, validated result and completion receipt. Completion-backed History V3 import remains under `enroll_owned_observation_history`; later user selections and edits must survive replay.                                           |

The proposed dispatcher accepts only the original owner/scan, expected
submission/configuration/funding/media identities and the original attempt
binding resolved by the service. It does not accept a model override, arbitrary
routine name, caller-selected replacement reservation or new media/text. Saved
CPM verification is an admission prerequisite; before dispatch, the compositor
must still prove live ownership and the retained bytes that execution will
consume. A prior successful read is not a transferable lease.

A fresh committed grant received positively by its original trusted caller may
permit one invocation. Replay, status recovery, a lost grant acknowledgement or
a crash between grant and call cannot. Existing invocation records and permanent
operation/lifecycle fences must be evaluated together before proposing any
additional private binding. An invocation's `(reservation_id, attempt_count)`
uniqueness alone is not the permanent per-scan fence.

### Result and completion boundary to implement together

The result writer must validate the saved route/output contract and original
attempt/configuration binding before accepting immutable evidence. Reuse the
existing result/provenance contract owners under `_shared/identify/contract.ts`
and the route normalization owners; do not treat the mutable completed-scan
response reconstruction as original provider evidence. The existing private
containers cap result at 1 MiB, provenance at 64 KiB and completion receipt at
16 KiB. Those are storage ceilings, not qualified maximum-runtime resources.
Closed encoding, allowlisted projection fields and shared digest vectors remain
required before the first writer; a generic JSON object is insufficient.

A valid original result may be captured after the worker lease expires if its
original dispatch and live ownership are proven. It confers settlement-only
recovery, never a new execution grant. Exact result replay preserves the same
content and provenance; conflicting result evidence rejects. Refusal, invalid
output, operational failure and unknown execution must not be fabricated into
successful result evidence. Their usage-accounting outcomes continue through the
existing accounting owner; unknown execution with no recoverable validated
result remains `recovery_needed(dispatch_outcome_unknown)` or
`recovery_needed(result_evidence_unavailable)` as applicable under IC-1.

Atomic completion must resolve the result and submission itself. No second
submitted-text payload or arbitrary scan JSON is accepted. A scan row without
the matching completion receipt is a conflict/reconciliation condition.
`scanPersistence.ts:persistOwnedScanRow` proves owner-row persistence for its
existing routes; it cannot substitute for an IC-1 completion receipt. Likewise,
`identify/completedResponse.ts` reconstruction cannot grant completion or
execution authority. Retain these historical routes unchanged until their
explicit integration adapters and recovery tests are ready.

### Lock, erasure and acceptance delta

All fresh operations enter owner `FOR UPDATE` → scan-ingestion advisory →
existing scan `FOR UPDATE` → history when present, before nested accounting or
private evidence locks. The expanded effective invocation/quota/credit,
preparation/provider-barrier and C1 trigger graph must identify the exact
recognition site for a complete original-dispatch witness; no transaction flag,
row count or isolated helper is independent authority. Lifecycle transition and
quota/invocation writes must commit or roll back together. Complimentary-credit
consumption remains successful-completion settlement under current policy.

Pre-row public scan deletion currently returns `not_found`; it does not cancel
pending analysis or install a tombstone. Use the existing C1 cancellation path
for that user action. Actual durable tombstone/account erasure must win late
result/completion and remove private submission, result, receipt and
descriptions. Permanent content-free fences survive as specified by IC-1. The
implementation must not reinterpret the now-qualified pre-row deletion no-op as
a new positive deletion guarantee.

Required next evidence covers fresh grant versus replay/lost reply, rollback at
each writer, C1/account/deletion both orders, original funding and credit
settlement, result conflict/late capture, result-write uncertainty, completion
response loss, exact receipt recovery and later History selection preservation.
The separately open SQL function-body timeout case must be tested before
installed timeout/recovery readiness. No automatic provider retry is permitted.
The historical stage93 deadlocks remain deferred under the cumulative audit
agreement unless blocking or recurring on the normal path.

Photo is the first consuming CPM route; audio/video and optional context remain
required functional journeys, not exclusions from acceptance. Fresh text-only
identification stays forbidden. Full affected gates, concrete lock schedules,
independent fix review and the cumulative functional audit precede functional
acceptance; deletion/export and redesign retain their agreed later order. No
hosted, provider, device, deployment or activation action follows from this
local interface preparation.

### Effective accounting seams at checkpoint `6613e0dc8`

The November 3 read-only trace identifies these concrete changes to review, not
permissions to remove the corresponding barriers independently:

| Effective seam                                                                                              | Present behavior                                                                                                                                                                                                                                                       | Required integrated delta                                                                                                                                                                          |
| ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)`                                     | The original writer in `20260927230801_account_identification_invocations.sql` is patched by `20261011070945_prepare_initial_analysis_admission.sql` to reject an initial operation immediately after service authentication, before ordinary owner/reservation locks. | Enter the initial outer scope first. Permit the existing writer only under the complete original-dispatch witness and retain its provenance/attempt checks, quota commit and invocation insertion. |
| `public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)` / `internal.finalize_ai_quota_reservation_core` | Public initial-operation denial plus private admitted-initial barrier. The atomic admission migration grants only captured C1 cancellation settlement, not dispatch commitment.                                                                                        | Recognize the integrated original-dispatch witness for `committed`; preserve the separate C1 proof for unused release. No generic finalizer bypass or new quota owner.                             |
| `internal.settle_complimentary_analysis`                                                                    | Original owner/held-usage locks; initial-operation exception is C1 only.                                                                                                                                                                                               | Keep dispatch separate from successful completion credit consumption. Completion needs its own exact validated-result/receipt witness under this owner.                                            |
| `internal.guard_initial_lifecycle_fence`                                                                    | Admission creates pending state; cancellation transitions are guarded. No pending-to-dispatch authorization exists.                                                                                                                                                    | Authorize that one transition only with the same complete atomic dispatch witness. Permanent scan identity still prevents another attempt after private erasure.                                   |
| `public.complete_identification_invocation(uuid,uuid,uuid,text,jsonb)`                                      | Initial invocation reporting is hard-denied by the original admission migration.                                                                                                                                                                                       | Add only the reviewed original-invocation usage reporting path; a dispatch witness alone does not authorize result capture, scan completion or credit settlement.                                  |
| `guard_initial_analysis_storage` and preparation provider-writer triggers                                   | Result/completion are guarded private containers; the broad `blocked_pre_admission` barrier also covers invocation, quota, scans and legacy ingress.                                                                                                                   | Each actual consuming writer needs bounded recognition of its own complete witness. Keep every unrelated route/worker denied; a lifecycle flag alone is insufficient.                              |

The starting lock owner is
`20261011192000_prepare_initial_saved_assignment.sql:lock_initial_preparation_scope`.
It takes owner, scan advisory, existing scan, history/lifecycle and deletion/C1
scope. The accounting/media tail in
`20261013103454_prepare_initial_media_handoff_runtime.sql:lock_initial_media_handoff_scope`
then covers admission/preparation/cancellation, admission, quota reservation,
provider attempt, reservation-counter links and daily/user/IP counters,
complimentary usage, then handoff members. Its present `binding_version = 3`
check makes it unsuitable for CPM v4 without a coordinated extension.

The CPM reader in
`20261102213355_prepare_initial_cpm_admission_bridge.sql:read_initial_cpm_admission_state`
locks capacity, source registry and write-attempt members under initial scope.
The next v4 consuming extension must preserve the accounting tail before those
CPM members; it must not first call the binary reader and then acquire omitted
outer accounting locks. Actual effective routine/trigger/FK inventory and both
lock-order schedules are required before SQL acceptance, including existing
counter, credit, C1, erasure and cleanup peers.

The remaining concrete schema decisions are the exact v4 retained-media
consumption proof, frozen CPM configuration to provider-provenance mapping,
validated route-result/projection codec, and complete witness lifetime/erasure
for late original results. These are implementation dependencies of the chain
above. They are not additional product scope, authorization for a standalone
schema, or a reason to repeat the accepted admission qualification suites.

### November 3 review resolutions and next exact-contract work

Engine's first addendum review accepted the boundary and lock direction but
found four unresolved contracts. The following decisions resolve the direction
for those contracts; executable signatures/schemas and the expanded effective
lock inventory still require the next consuming review before a barrier changes.

1. **Accounting adapter seam.** `prepareAccountedIdentification` currently
   hard-codes generic commit/report RPCs; it is not an S0 adapter today.
   Preserve ordinary callers and its local one-invoke guard. The proposed
   extension is a trusted internal accounting port supplied by the S0
   composition, with fixed original-dispatch and original-invocation-report
   operations. It is never decoded from HTTP input or a routine-name string.
   Generic defaults remain unchanged. The port grants invocation only from the
   fresh positively received atomic dispatch result. Keep usage reporting
   bounded and best effort after invocation, then return the original outcome
   even when reporting fails; accounting uncertainty cannot discard an otherwise
   valid original result. Route validation and durable result storage follow
   before any promotion or finalization. This does not equate usage-report
   success with valid result evidence.
2. **Late-result authority.** Original owner/scan, submission and admitted
   receipt, assignment/configuration digest and retained asset manifest,
   original reservation/funding binding, provider attempt, invocation
   ID/provenance and media role/version/digest bindings must remain resolvable
   under live private ownership. Dispatch additionally needs a current original
   lease and complete current media/consent checks. Late result capture does not
   renew that lease or authorize execution; it requires the same committed
   invocation and retained immutable facts. Pruning/cleanup integration must
   preserve those dependencies until exact terminal settlement or authorized
   private erasure. If any compulsory fact has already disappeared, hold
   recovery-needed; do not reconstruct authority, substitute current
   configuration or allocate funding. C1 cancellation fences result/scan
   resurrection under its existing dispatched or unknown classification. Account
   deletion erases private evidence and returns only the existing
   authorization-safe denial/absence, never private cancellation details.
   Neither path permits revival.
3. **Exact bytes and provenance.** The execution adapter must consume the same
   bounded buffer that has just passed saved digest/length and structural
   checks, or an immutable storage version explicitly bound to that
   verification. A mutable URL or a previously successful verification Boolean
   is insufficient. Reopening retained bytes requires verification against the
   original ordered photo/role mapping, backend generation, object/write-attempt
   identity, verification snapshot, structural policy/build and original content
   digest; the verified buffer then supplies execution without an unverified
   reread. Promotion must similarly bind the immutable input and verified
   destination identity/digest, under its existing lifecycle owner. An issued
   deletion or retired registry entry permanently prohibits rebinding even after
   cleanup claim expiry. Preparation resolves the saved configuration through
   its pinned asset manifest and trusted compatible implementation; no
   current-default registry fallback. `identificationProvenance` projects that
   exact prepared snapshot. Unsupported/missing saved execution assets hold
   before dispatch.
4. **Result-write uncertainty.** Normalize the original provider outcome, parse
   the route's success envelope and attempt immutable result persistence before
   external enrichment, media promotion or completion. A lost acknowledgement
   enters `recovery_needed(write_outcome_unknown)` and permits only
   reconciliation of that exact result identity/digest. Recovery of the exact
   stored evidence permits settlement-only continuation. Absence or
   corrupt/conflicting evidence holds recovery-needed, without another inference
   or timeout refund. Result readiness does not imply completion, and completion
   replay cannot rewrite later user choices.

The server trace fixes the initial reuse point: `identify-multimodal/index.ts`
calls `normalizeIdentification`, shapes the response, attaches
`identificationProvenance(result.execution)` and calls
`parseIdentifySuccessEnvelope` before `runDurableIngestion`. Freeze the parsed
`data` and successful result state there, excluding the separately attached
completion `entitlement`. Cached enrichment already represented in that parsed
value becomes part of this immutable initial result; later dictionary lookups or
follow-up enrichment cannot rewrite it. The older image-only path has its own
parse/sanitization boundary and must produce the same reviewed result contract
when integrated; no implicit route fallback is allowed.

The existing scan/funding finalization chain is `identify/db.ts:insertScan` →
`persistOwnedScanRow`, followed separately by
`scanIngestionJobs.ts:completeScanIngestionFinalization` →
`complete_scan_ingestion_with_entitlement`. This explains the atomicity gap: the
scan insert precedes the job/entitlement response transaction. S0 must consume
an allowlisted scan projection and exact result/media/funding proofs in its
single completion transaction, integrating the existing settlement owners rather
than calling the current split-phase route and appending a receipt afterward.
Its media consumer reuses the finalized ordered manifest produced by
`buildCapturedMediaManifest`; URLs alone cannot reconstruct that evidence. That
builder supplies manifest shape and ordering, not verified bytes or finalized
ownership; its output must bind the independently validated immutable storage
and media evidence.

`scan_ingestion_jobs.response_envelope` is a useful existing stored-response
precedent. The `fetchCompletedIdentifyResponse` fallback rebuilds from current
scan/species rows, so it remains excluded as original result evidence. Native
response validation and local hydration are downstream delivery concerns; they
do not replace this server result writer. Mixed media and telemetry require
explicit immutable-evidence mapping before their completion adapter is enabled;
photo-leading implementation does not waive their functional acceptance.

The next concrete review packet must include closed result/status/completion
schemas, canonical digest domains and positive/negative vectors, exact SQL/port
signatures, projection field allowlist, witness creation/consumption/erasure and
pruning behavior, plus the complete effective routine/trigger/FK lock delta.
These must describe this consuming chain together. This document does not mark
that packet complete, implement a writer or grant authority.

### November 3 consuming-contract review refinements

The subsequent bounded Engine review accepted these design directions, not the
unfinished consuming packet or any barrier change:

- **Original dispatch association:** use a narrow private association from the
  existing invocation to the original immutable admission receipt instead of a
  second durable dispatch-binding table. Retain original invocation facts while
  live result/settlement authority needs them. Five-minute unknown usage
  reconciliation remains unchanged; successful result capture is not a
  prerequisite for refusal, invalid-output or unknown accounting. The current
  usage-event insertion has no user/scan FK or INSERT-trigger outer-lock
  dependency. Any new association FK or immutable-field guard must preserve that
  property. Erasure must not turn a null association into ordinary-operation
  classification for pruning; the exact erasure mechanism remains to review.
- **Immutable completion projection:** the existing completion row is the owner
  for a proposed bounded `completion_projection_snapshot`, separate from the 16
  KiB receipt. Input/result/admission alone cannot reconstruct original
  completion time, species/privacy association or terminal credit/entitlement
  outcome after mutable rows change. The proposed projection ceiling is 64 KiB,
  subject to exact schema and resource qualification. SQL derives and stores it
  atomically with the receipt/scan/description/settlement writes. Historical
  entitlement in that projection is response-loss evidence, never current
  spending authority. Replay cannot depend on a surviving mutable species row or
  rewrite later user selection/review state.
- **First-completion digest:** IC-1's logical `expected_completion_digest` is
  nullable. A first completion requires null; SQL derives the actual projection
  digest under locks after resolving original settlement. A non-null digest is
  an optional equality assertion against an already stored completion, never
  permission to create caller-chosen projection evidence. On replay, null skips
  only that assertion: original submission/result/configuration/funding/media
  identities and stored receipt/projection still must validate. Concurrent first
  calls converge on one stored completion without repeated settlement.
- **Private result numbers:** the parsed Identify result has fixed object keys;
  cached species language maps and later `species_id` are not fields to add to
  it. A closed private encoding may convert schema-declared fractional numbers
  to decimal strings using existing canonical primitives, preserving optional
  omission, null, text and array order. Public numeric DTOs remain unchanged.
  The fixed trusted Deno writer and every recovery decoder enforce finite IEEE
  round-trip validity; SQL enforces closed syntax/range and canonical digest.
  This is a deliberate division of validation responsibility, not identical
  SQL/Deno numeric semantics. No alternate writer or digest alone may bypass the
  Deno check. Digest domain prefixes end in exactly one LF byte (`0x0a`), never
  literal backslash-plus-`n`; shared vectors must specify those bytes.

Exact media/projection schemas, original usage retention with result evidence,
transaction witness phases/images, erasure/pruning classification and the
effective lock matrix remain required before consuming implementation. In
particular, current CPM photo content v1 carries photos and ordered contexts,
not capture telemetry or an explicit privacy choice. Completion must not read
unstored request metadata or reconstruct it from current device/EXIF data.
Historical variants retain their exact original metadata contracts; any richer
fresh CPM metadata needs an explicit versioned contract. These refinements do
not qualify native delivery, all-media functional journeys or external use.
