# IC-1 S0: permanent initial-dispatch fence

> October 13 evaluation update: the user authorized drafting and reviewing the
> [CPM-1 client-prepared media amendment](client-prepared-media-amendment-2026-10-13.md)
> before any AWS decision. It proposes a distinct fresh-submission version; it
> does not weaken or reinterpret this document’s existing server-prepared or
> historical contracts. Adoption and implementation remain pending. AWS is
> unapproved, activation disabled, and all external-operation restrictions
> remain.

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
