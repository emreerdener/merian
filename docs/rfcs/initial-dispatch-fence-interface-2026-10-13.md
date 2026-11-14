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

### November 3 terminal media and consuming implementation boundary

A further bounded Engine review accepts beginning the integrated private chain
and adapters behind the existing denials. This supersedes the preceding
pre-implementation hold for the reviewed design framework; it does not accept an
executable writer, callable grant or functional journey. The actual statement
catalog, taxonomic projection and qualification evidence remain implementation
gates before their corresponding guards recognize authority.

For CPM photo v4, adopt the existing immutable source/AI/display objects in
place, preserving their original IDs and pinned backend generation. Reuse
`initial_preparation_transfer_receipts` with an explicit disjoint adoption
variant, its own validator and variant-aware guards. Its current legacy CHECK
and every “transfer exists” branch must be reconciled: adoption is not legacy
copy completion or permission to retire the source. Keep the pre-terminal CPM
cohort reader strict; it currently rejects a transfer receipt, so post-adoption
completion/replay needs its own original-authority predicate. No extra physical
copy, second object registry or independent adoption grant is justified.

Adoption keeps the original capacity charged. Generic preparation expiry,
retirement and private-root deletion must reject a live adoption. Authorized
scan/account erasure retires every adopted role before cascading away its proof,
preserving content-free permanent object fences and the existing safe
capacity-release conditions. Neither an expired token nor erased proof permits
rebinding an old physical key. A closed adoption receipt binds original
admission/result/verification/role identities, pinned backend, fresh verified
byte hashes and types, and compatible retention policy/build. Hosted retention
and alternate-writer qualification remain separately authorized acceptance work.

Delivery reuses `resolve-history-photo` through an explicit completion-backed
adopted-display variant and the bounded private-ticket transport. Only display
members are addressable; source/AI members do not become public media. Existing
photo profiles cannot silently reinterpret the broader CPM image-type set. Never
store an expiring signed ticket in `captured_media`, whose existing contract
expects stable credential-free URLs. The native initial snapshot and
result/library/history hydration must consume the protected display reference;
an invisible initial photo does not satisfy functional completion.

The smallest durable invocation extension has two distinct facts: the nullable
original admission-receipt association for live authority, and immutable
`is_initial_analysis`, set at invocation creation and retained through
anonymization. No receipt FK or receipt-locking lookup is added to the row-first
usage path. Ordinary writers cannot set or clear the classification. Five-minute
unknown accounting remains unchanged; pruning preserves live initial authority.
An anonymized initial invocation becomes eligible for ordinary accounting
retention only through the authorized erasure transition, whose exact cleared
fields and guards must be specified before pruning implementation. A missing
association alone is never sufficient.

Fresh dispatch validates the pending live cohort; later result/completion
predicates validate the original committed invocation and retained proof instead
of demanding charge links removed by quota commit or a credit hold already
settled. The live admission receipt reconstructs original charge links and
deltas, not historical shared counter totals. Unrelated legitimate consumption
must remain possible. Late valid original results may survive lease expiry or
unknown accounting, without another inference, event rewrite or charge.

The consuming witness is a private current-transaction, operation-specific
ledger of exact before/after images, ordered statements and cardinalities.
Dispatch, usage, result and completion have distinct allowed writes. Generate
its actual catalog from effective writers and their trigger/FK side effects;
review it before any guard recognizes the witness. Deferred checks require
sealed consumption and no leftover stage at commit; errors roll back the whole
operation. Existing original quota, usage and credit owners remain responsible
for their transitions. The new result snapshot retains bounded original usage
facts even when reporting failed. SQL derives the immutable completion
projection and never accepts arbitrary scan JSON.

Implementation still requires direct-writer denials, rollback and both-order
account/C1/deletion/retirement schedules, exact numeric/canonical vectors,
resource measurements and independent fix verification. This review does not
require replaying unchanged admission suites and does not relax rollout,
provider, native, release or external authorization holds.

## November 3 — private result-v1 compatibility boundary

The uninstalled Edge integration now snapshots its data/provenance/primary rules
in `resultSchemaV1.ts` and primary semantics in `resultSemanticsV1.ts`. Capture
and recovery use these immutable version-one definitions and private scalar
rules. Future public Identify parser changes cannot reinterpret saved v1
evidence. Types derive from the frozen definition; a later public delivery shape
requires an explicit adapter, not a historical-to-current DTO assertion.

The existing Supabase tooling gate discovers
`initial_result_v1_contract_test.ts`. It checks structural drift and the
complete dependency-free public contract source fingerprint, covering transitive
validation helpers/constants. Drift requires a documented compatibility
decision; harmless public additions need not force a new durable version. Never
automatically regenerate old v1 rules. Saved synthetic evidence, original hashes
and primary/scalar vectors remain pinned. SQL generation must consume that same
frozen definition and qualify syntax/range/digest parity before installation.
This is private draft source implementation; SQL authority, adoption,
completion, native delivery, resource qualification and activation remain
pending under the earlier holds.

The subsequent SQL draft starts fixed structural consumption in
`20261103074331_consume_initial_analysis.sql`, generated from that frozen owner.
Its private invoker schema/matcher/parser have all API execution revoked; no
writer or consuming-witness exception exists yet. Canonical and JSONB-text caps,
UTF-16 lengths, decimal syntax/ranges and embedded provenance agreement are
locally tested. SQL primary semantics, usage, original identities/digests,
authority and exact transaction-witness consumption remain unfinished and must
precede result acceptance. The same uncommitted migration must grow into the
complete integrated chain before release; do not ship an unused codec/helper
increment separately.

The next November3 draft increment adds frozen primary semantics, exact bounded
provider-usage shapes and the closed result wrapper with actual-LF result and
provenance hashes. Six private invoker helpers remain API-denied. This validates
supplied content and correlation within that content; original invocation/
admission ownership, expected provenance/configuration, permanent uniqueness and
exact witness consumption still require the integrated compositor before any
result write. No identity or hash alone becomes durable authority.

For the consuming witness, “exact images” means exact secret-redacted row
projections where an existing row contains a raw lease. The shared private
normalizer replaces only quota `lease_token` with SHA256 of canonical UUID text
encoded as UTF-8, preserves a null lease as null, retains all other columns and
rejects column-set drift. SQL NULL still means absent row. Expected-image
construction and actual OLD/NEW verification must use that same projection; the
hash is correlation evidence and cannot replace the credential or authorize
execution. The current dispatch/report/result statement skeleton and normalizer
remain behind existing denials. They do not yet recognize a witness or verify
the complete compositor/trigger/FK graph; completion remains unsupported.

### November 3 — private consuming witness mechanics

The uncommitted consuming migration now includes a private current-transaction
stage and an unattached paired row/statement adapter for dispatch and result.
Exact expectations and original identity fields are immutable; queued AFTER rows
consume unique matching BEFORE indices. Statement completion rejects missing,
extra, suppressed or changed rows. Stage deletion requires complete sealing
immediately and a captured-terminal-image deferred check; a denial-only
transaction latch prevents reuse after successful removal. Full savepoint
rollback removes all stage/latch/SQL effects, while constraints already
immediate reject unfinished entry. No business writer or guard recognizes this
stage.

Report remains unavailable at stage creation until attempted INSERT images and
an exact existing-event conflict are explicitly modeled: a skipped ON CONFLICT
insert fires BEFORE but not AFTER. Completion remains unavailable until its
actual writer graph is complete. The maintained mechanics fixture retains FKs
but isolates legacy user triggers in a disposable rollback transaction; its
multi-row dispatch portion stops after original-link deletion. It does not
qualify original authority, terminal business state or the integrated journey.
The local initialAnalysis README owns the mechanical bounds and test pointers;
those bounds still require integrated resource measurements. Original invocation
association/classification, erasure/pruning, producer-derived expected facts and
operation-specific live terminal assertions remain prerequisites to recognition.

### November 3 — single accounting candidate preparation

The private consuming draft extracts usage validation, metadata and pricing into
`internal.prepare_identification_usage_event`, returning the complete
`public.ai_usage_events` row. The existing `complete_identification_usage` owner
still locks the invocation first and returns an existing event before validating
new input. Otherwise it prepares exactly once, inserts that same image and links
the actual conflict winner. The helper is volatile: Gemini pricing reads the
pricing relation, while UUID and transaction-time defaults are generated once.
Future witnesses must consume that prepared image inside the writer;
independently recomputing expected pricing or defaults is forbidden.

This changes no funding authority or accounting ledger. The helper has no
writes, invocation/owner/receipt lookup or API execution grant. The focused
accounting fixture observes the full attempted/effective row, six former
implicit defaults, invocation-only linkage, invalid-input zero-write replay, and
a skipped insert that retains an existing unknown winner. Pricing-call
instrumentation and concurrent winner schedules remain pending alongside report
witness integration. Report-stage admission and initial creation stay denied;
this preparatory extraction is not an independently releasable milestone.

### November 3 — report witness and private original producer

The subsequent integration supersedes the report-mechanics hold above. The
private stage now attaches the writer's once-prepared candidate to its immutable
original invocation, observes one attempted BEFORE row, then binds the actual
locked winner. A new insert requires the exact AFTER image. Zero AFTER rows mean
**existing-winner resolution**, not proof that PostgreSQL chose ON CONFLICT: a
suppressed insert is acceptable only with a different-ID existing winner under
the fixed original source key. Missing winners and missing AFTER observation of
the newly inserted candidate fail. The invocation may change only its event link
to that winner. Terminal deletion and deferred validation check both exact live
images. The private deferred validator uses trusted-owner definer security so
validation still works after the API definer returns to service_role.

Report-only observers are installed on usage INSERT and invocation UPDATE in the
uncommitted draft. They restrict report stages and leave other operations alone;
dispatch/result adapters remain unattached. The new API-revoked
`internal.report_initial_analysis_usage` enters existing owner/scan/deletion
scope, locks retained roots, validates the original admission proof and input
binding, then locks all scan/reservation invocation matches in ID order. It
requires the original classification, receipt, owner, lease and provider
snapshot. Future dispatch must share that outer serialization to exclude
concurrent aliases; this query alone does not lock absent rows. Ordinary
accounting retains its invocation-first path without new outer owner/receipt
lookups.

The producer uses the existing accounting writer and changes no funding. Exact
already-accounted replay validates original authority but ignores new usage and
creates no stage. Report and accounted cancellation share the same pure saved
attribution validator: modality, provenance, provider/binding/policy/profile,
usage contract and outcome must agree with the original invocation. Saved
outcome is checked against saved metadata, never the incoming replay outcome,
and is not repriced. HQ101 records the initially weaker report check and its
correction; HQ100 preserves the earlier terminal-fault fixture failure.

The local runner's report modes distinguish original-authority producer checks
from injected-stage mechanics, observed event/erasure contention, and actual
service-role deferred commit. Dispatch state and invocation creation are still
injected in these fixtures. No public report RPC, API execution grant, initial
creation or provider execution is opened. Full dispatch provenance/native-price
construction, committed-deletion late reporting, result/completion/adoption,
whole-graph and resource qualification remain open.

### November 3 — inactive original invocation classification

Historical checkpoint; the later scan/account retirement increment below
supersedes the temporary all-initial pruning hold.

The consuming draft now adds the accepted nullable original receipt association
and immutable initial classification to the existing invocation owner. No
receipt FK is added. Detectable legacy invocation/fence overlap aborts migration
before ordinary defaults are assigned; already-anonymized history remains
outside that check. The exact redacted invocation image includes both fields.

Initial insertion is still denied. The initial-row guard permits only the
existing row-local accounting event transition and denies classification,
receipt, identity and provenance mutation. The five-minute unknown loop remains
unchanged. All classified initial records are conservatively excluded from
thirty-day pruning, even without a receipt; direct deletion/truncation is
denied. This temporary hold is not a final positive retention/erasure policy and
cannot be combined with enabled initial creation.

The effective erasure trace identifies the next required integration: original
accounting/invocation locks must precede the media-member tail in
`lock_initial_media_handoff_erasure_rows`; reconcile and retire correlation
after irreversible fencing but before private root cascades, including the
existing-tombstone owner-deletion fallback. C1 erasure requires its
corresponding write-catalog update. The provider barrier currently exempts
user-only changes, so full detachment needs an exact reviewed erasure
transition. Initial classification must survive that transition, and pruning
must use guarded row-local terminal facts without reverse owner/receipt locks.
These positive erasure paths remain unimplemented and initial insertion must
remain closed.

The classification preflight now requires read committed and acquires a SHARE
lock on operation fences followed by ACCESS EXCLUSIVE NOWAIT on invocations
before its check, holding both through column/guard installation. This closes
the original snapshot race with concurrent fence or invocation creation. Lock
timeout remains unchanged and aborts the migration atomically; source inspection
or rollback checks alone do not qualify the lock ordering.

Independent review also found the initial-admission reader order: it can read
invocations before inserting an operation fence. Waiting for that reader while
holding the fence lock would form a cycle. The second lock therefore uses
NOWAIT; contention rolls back the whole migration, allowing the reader/writer to
finish. A later migration attempt must restart the entire transaction. Ordinary
lock-timeout protection remains in place for the first lock.

### November 3 — bounded scan/account invocation retirement

The consuming draft now integrates exact retirement with existing scan/account
erasure owners. After permanent fencing, it reconciles original unknown usage
and clears exactly five correlation fields while preserving initial
classification and accounting identity. The outer owner locks receipt,
reservations and invocations before the shared media tail; direct-update
backstops fail nonblocking on owner/receipt/reservation/advisory contention. The
provider barrier recognizes only this transition. Captured-OLD deferred proof
requires private-root absence, including immediate-constraint denial. Pruning
uses the identical complete row-local retired predicate. Missing original
receipt and partial clearing remain ineligible.

Engine independently accepted the bounded source structure. Nineteen maintained
local assertions use a genuinely committed guarded synthetic photo admission,
with only the unavailable invocation creation injected. They cover scan and raw
owner erasure, existing-tombstone fallback, original unknown accounting,
pruning, negative receipt/transition cases and rollback. This does not qualify
public account cancellation, tombstone-free C1, invocation-only leftovers or
concurrency. The initial INSERT denial remains. The current owner and exact
disposable-run command are in the
[initial-analysis README](../../services/supabase/functions/_shared/initialAnalysis/README.md#s0-original-invocation-classification-draft).

C1's exact mutation catalog, both-order accounting/erasure schedules and
affected effective-catalog checks are still required before creation can be
enabled. Producer witnesses, report conflict winners, completion/adoption,
native delivery and cumulative functional qualification remain outstanding; no
release or external-operation authorization changes.

### November 3 — replay atomicity and bounded erasure contention

Fresh pinned-CLI `db start` exposed SQLSTATE25P01 at the draft's top-level
classification lock; earlier508-plus-normal-apply evidence did not exercise that
replay path. One outer `DO` executes the unchanged business SQL atomically, with
session timeouts outside it and all errors uncaught. This preserves the same
fence SHARE / invocation ACCESS EXCLUSIVE NOWAIT ordering through complete
installation without prohibited top-level transaction control. A static red
regression preceded the fix. Both full fresh replay and normal apply, plus
reader-held rejection/whole-statement rollback, now have separate evidence.

The maintained erasure fixture adds discovery and atomic denial for a corrupt
invocation-only leftover whose receipt is missing. It does not claim successful
retirement without proof. Controlled three-session schedules observe exact
blockers in both accounting/scan-erasure orders, reverse-owner rejection,
rollback preservation, committed retirement and late original report reuse, then
pruning with one preserved accounting event. The disposable accounting cron is
explicitly suspended, checked for in-flight work and restored; scheduler
qualification is excluded. The earlier failed prune assertion and inconclusive
zero-row probe remain evidence, not passing qualification. Mutation and state
observation now use separate commands under the reporter's row lock, with a
nonempty precondition. Public account/C1 and whole-graph qualification remain
required before initial creation.

### November 3 — cancellation retirement safety hold

A rollback-only local probe exposed generic cancellation deleting the original
admission receipt while a classified invocation retained its correlation. The
actual public account path reached this early cancellation before the later
owner-deletion retirement guard, which then rejected missing authority. Initial
creation remains denied, so this is a draft integration defect, not evidence of
production exposure.

The consuming draft now holds generic cancellation before saved receipt replay
or mutation when a classified invocation matches the scan or the original
reservation from its locked admission. It raises the existing cancellation
incomplete error. It neither refunds known execution nor substitutes a saved
cancellation row for retirement proof. The unchanged positive-unused C1 path
remains separate. See the
[current owner contract](../../services/supabase/functions/_shared/initialAnalysis/README.md#s0-original-invocation-classification-draft).

Non-refunding C1 needs an exact invocation/accounting witness and an account
composition boundary before initial creation can open. The ordinary explicit C1
transaction seal cannot simply wrap account deletion across other scans and the
final user mutation. Whole-graph and successful public-account qualification
remain pending; the hold alone is not completion of either journey.

### November 3 — permanent pre-row account retirement composition

The draft now routes classified pre-row work in `public.apply_user_tombstone`
through the existing permanent scan-tombstone retirement owners. It discovers
owner-bound invocation-only identities, rechecks the absence of a public scan or
completion under the exact advisory scope, and rejects aliased reservation or
owner associations. Existing tombstones run the explicit cleanup fallback.
Scientific detachment and final user deletion remain with their existing owner;
ordinary cancellation is unchanged. No account-specific C1 witness, refund or
credit release was introduced. Explicit known-execution C1 remains held.

The
[current owner contract](../../services/supabase/functions/_shared/initialAnalysis/README.md#s0-original-invocation-classification-draft)
describes the focused actual-public cases and remaining limits. Initial fixture
assertions incorrectly searched retained usage by its deliberately anonymized
source_id; a second count assertion omitted the science helper's prior backfill.
Both test failures and corrective review are retained in local candidate
evidence. Passing corrected checks do not qualify untested account variants or
the complete concurrency graph. Initial creation and release holds remain.

### November 3 — non-refunding C1 implementation direction

The reviewed next extension uses the established C1 stage with a server-derived
already-accounted variant. Its guarded stage insertion validates original
receipt/identity and reconciles through the existing accounting producer before
the stage becomes visible, then freezes the exact invocation/event and funding
images. The composer must receive exactly one matching stage; failure or
suppression rolls reconciliation back. Positive-unused capture and refund proof
remain separate and unchanged. The complete protocol is not implemented yet.

The uncommitted draft now implements the private
`capture_initial_accounted_cancellation_prestate` prerequisite. It locks the
original receipt before accounting, rejects ordinary/aliased invocation matches,
checks the original receipt lease rather than a renewed lease, and independently
verifies the event returned by the unchanged accounting producer. It preserves
existing completed reports and current funding images. Entry also rejects the
exact current-transaction S0 latch after its stage has been consumed; the latch
grants no authority. The positive-unused capture is unchanged.

Fresh local replay and41 focused assertions validate this bounded subset and
existing erasure/unused-C1 paths. Initial fixture failures exposed hardcoded
plan/model values that differed from the guarded receipt; the injection now uses
that receipt's original assignment. Original syntax and fixture failures remain
retained. Capture has no direct API grant. The next bounded increment wires it
into server-derived stage insertion through `begin_initial_cancellation_stage`,
which requires exactly one matching returned/stored row. The schema admits only
unused captured/quota phases or accounted-without-quota-clock.
Missing/suppressed insertion, later failure and immediate constraints roll back
observed accounting. Both the existing public composer and deferred completion
still reject accounted stages until retirement/shared-owner/terminal integration
is complete; unused C1 continues through its existing proof.

Fresh replay and67 assertions validate that entry subset, including actual
service-role ledger writes outside C1 and denial while staged or terminally
sealed. The new ledger freeze uses a narrow security-definer trigger, with empty
search path and revoked execution, to read private staging without granting
callers access. The first invoker version's42501 failure is retained with its
fix and independent verification. The usage table is also in the actual terminal
seal trigger installation and catalog. Retirement witness, shared-owner and
terminal proof integration remain required. Component byte checks and the
final64MiB prestate rejection do not qualify peak allocation or the duplicated
composite's pre-allocation bound; resource qualification remains open.

The private statement-observed witness mechanics are now implemented with a
256KiB bound, RLS/API denial, actual terminal seal and exact five-field
retirement images. Every transition rechecks live invocation/event/funding;
statement guards reject zero-row, extra and no-op mutations. An unrelated nested
trigger's premature writing state cannot authorize the real invocation
statement, and observation requires the actual retired row. Trigger depth alone
is never proof. Accounted funding writes are frozen at statement level.

Fresh replay and105 focused assertions validate these mechanics while retaining
the production retirement authority and accounted composer/deferred holds. The
mechanical positives isolate only the older retirement/provider row barriers
inside rollback; the authority-denial case retains every production guard. The
single failed first-run quota probe used a nonexistent column and is retained
with its corrected test and independent review. Successful cancellation still
requires shared lifecycle/media/private transitions, cleanup and exact terminal
survivors. The witness will then authorize only the five-field invocation
retirement before lifecycle cancellation. Existing stage INSERT/DELETE and
terminal-snapshot DELETE deferred checks retain the exact operation association
in their captured tuples after cleanup; a generic seal or saved receipt is not
authority. Unused and accounted witness families must remain exclusive, keeping
the existing cleanup limit16 and existing aggregate byte limits.

The subsequent lifecycle increment passes a fresh replay and125 focused
assertions. Shared lifecycle owners use exclusive settlement prerequisites:
unused quota/credit completion or accounted invocation completion with exact
retired invocation, unchanged event, receipt and funding. Pending known
execution derives `cancelled_unknown`; authorized dispatch derives
`cancelled_dispatched`. Exact lifecycle row observation remains mandatory.

The first increment incorrectly applied a live-phase check when deriving the
event for deferred captured stage-INSERT evidence. It failed real unused C1
after witness cleanup. Event derivation now uses only immutable
variant/prestate; mutation owners retain the live-phase check. The failed run
and two corrected fixture expectations remain recorded, with independent fix
verification and a passing actual-unused cleanup/deferred regression. Known
lifecycle positives remain rollback-only mechanical coverage with original
retirement barriers isolated; successful accounted C1 still requires
media/private owners and terminal proof/cleanup before the existing holds can
change.

The next shared-owner increment passes a fresh509 replay and149 focused
assertions. Source/destination retirement and private-root deletion preserve
existing exact witnesses and order. Accounted receipt/funding prerequisites run
before submission erases the original receipt; later boundaries verify surviving
invocation/event/funding by captured identities. Accounting images include
actual known quota links and retained invocation/event. Both root cascades must
finish before the observed receipt records outcome unknown or dispatch already
authorized. The actual unused public cancellation still completes its cleanup
and deferred checks.

Five new rollback-only positives and eighteen negative/hold cases plus exact
rollback cover this shared path. Terminal predecessor/catalog/cleanup
integration, independent captured-stage and terminal DELETE survivors, and
public accounted composition remain held. The mechanical fixture still isolates
the original retirement barriers and injects dispatched prestate before capture;
it is not successful accounted cancellation or frozen-result/all-media
qualification.

Explicit cancellation may erase an exactly captured frozen private result before
completion under the existing owner/advisory scope. A public scan or completion
makes cancellation too late; cancellation-first prevents later resurrection.
This follows the
[cancellation contract](initial-cancellation-interface-2026-10-11.md). Ordinary
cancellation preserves the append-only usage ledger; account deletion retains
its separate anonymization policy. Full implementation, adversarial mutation
checks, both-order races and resource qualification remain required before
initial creation can open.

### November 3 — integrated accounted C1 candidate

The draft now completes the real public non-refunding C1 transaction. Its exact
current writing witness authorizes only the original five-field invocation
retirement. Terminal capture excludes mixed witness families; accounted cleanup
requires eight rows and unused retains the sixteen-row maximum. Independent
captured stage, terminal DELETE and invocation checks validate final state after
live proof rows are removed. The original lock order and nonblocking retirement
backstops remain. Initial invocation creation is still denied.

Fresh replay and171 assertions pass, including the actual service-role public
composer with retirement guards enabled, pending/dispatched and
unknown/completed accounting, both deferred proof orders, saved replay, cleanup
failures and exact rollback. Two changed concurrency schedules additionally
pass: reconciler-first blocks C1 and rejects reverse owner acquisition, while
C1-first commits before a waiting late report reuses the original event. An
independent observer verifies unchanged funding and receipt replay in a new
transaction on its existing connection. Race sessions use service claims;
separate public assertions cover the database service role. The earlier
scan-erasure schedules were not rerun or counted in this mode.

This171-assertion checkpoint establishes the selected integrated C1 path.
Subsequent focused SQL qualification covers selected injected frozen-result
erasure, the six existing media vectors, and CPM cancellation in held-credit and
quota modes, including commit/accounting/pruning. These separate receipts do not
qualify actual initial provider dispatch, producer-derived result or completion,
every account/cohort/race combination, measured resource bounds or installed
delivery. Earlier intermediate holds and failures above are historical
checkpoints. The current implementation and maintained commands are in the
[initial-analysis README](../../services/supabase/functions/_shared/initialAnalysis/README.md#s0-original-invocation-classification-draft).
The whole S0 integration remains uncommitted and undeployed; no grant,
activation or release authority is implied.

### November 3 — complete accounted capture size preflight

The draft now measures the full accounted cancellation representation before
private, registry and CPM aggregation, including duplicated private components
and JSON framing. Existing 32/64/128 MiB and 256 KiB limits are unchanged;
constructed sizes must match their estimates. Shared private-image framing also
applies to unused cancellation. The maintained README documents the focused
structural boundary command and its limitations. Exact candidate qualification
and peak memory/runtime acceptance remain distinct; this amendment grants no
initial dispatch or deployment authority.

### November 3 — private original result and recovery integration

The uncommitted S0 candidate now implements private immutable result record and
read producers, superseding the earlier missing-producer status for this local
boundary. The
[owner README](../../services/supabase/functions/_shared/initialAnalysis/README.md#s0-original-result-integration-november-3)
describes shared original authority, schema-directed numeric comparison,
statement/row consumption, exact replay and no-lease read recovery. Public RPC
wrappers/grants, production composition, dispatch construction, adoption and
atomic completion remain absent. No activation or functional acceptance follows
from this increment.

Report/result callers still present their original invocation and lease; reads
derive the unique invocation from locked original receipt/funding membership.
Result acceptance is independent of accounting success. Encoded v1 provenance is
validated first and compared to original numeric provenance with exact JSONB
numeric equality, while original canonical bytes/hashes remain unchanged. SQL
casting does not independently establish the Edge codec's IEEE round-trip rule.
A matching object alone cannot replace input/configuration/funding identity.
Exact replay includes the stable evidence UUID and full original reference.

Result observers and fixed guard exceptions were independently reviewed before
local qualification. Their local tests do not qualify injected dispatch or the
future completion state: completion/read recovery must retain or explicitly
adapt the original roots and lifecycle predicate. Committed result erasure,
both-order account/C1/deletion schedules, combined maximum-state resources and
all-media cumulative acceptance remain integration obligations; use the current
checkpoint for executed evidence and retained failures.

### November 3 — private original dispatch integration

The uncommitted candidate now includes the complete private original dispatch
chain under the existing transaction-stage, invocation, quota and lifecycle
owners. This supersedes the earlier missing-dispatch-construction status for the
SQL boundary only. The
[owner README](../../services/supabase/functions/_shared/initialAnalysis/README.md#private-original-dispatch-integration-november-3-inactive)
and
[schema contract](../backend-and-data/04-database-schema.md#private-initial-dispatch-transaction-inactive-candidate)
identify its phases, exact images and maintained disposable qualification owner.

The first guarded CPM test uses actual dispatch and service-role deferred
commit, without injected invocation rows. It does not replace earlier
injected-fixture scope or establish all-media, race, resource, installed-runtime
or functional acceptance. Original failed compilation and qualification
assertions remain in the findings register with their concrete corrections.
Public transport, installed executable/media binding, adoption and atomic
completion remain separate unfinished integration steps. No activation or
deployment follows.
