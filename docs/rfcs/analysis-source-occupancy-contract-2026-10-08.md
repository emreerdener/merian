# Analysis source occupancy and recovery contract

Status: required design checkpoint, October 8, 2026. **Partially implemented;
not activated.** This extends the approved identification-history audio
integration milestone; it does not authorize deployment, a new provider retry
policy, or an ordinary Capture route. Existing saved-photo replay must remain
unchanged.

Initial October 8 descriptor checkpoint (historical): the strict executable
request/descriptor and 2 KiB decoder are now prepared in `sourceDiscovery.ts`,
with no live producer or consumer. The
[current API contract](../backend-and-data/05-api-contracts.md#prepared-source-discovery-contract)
fixes their fieldsets. At that checkpoint, the SQL resolver, fingerprint parity,
source index and proof storage remained unimplemented. The subsequent notes
below supersede that partial status; discovery was not activated.

Subsequent October 8 implementation note: the default-false service-only SQL
resolver now classifies bounded existing intents/results and terminal receipts,
with nonunique source indexes. It never emits advisory absence; the durable
reservation binding, source claims, all-writer cutover and native recovery
consumer are still pending. Pure fingerprint helpers are described below. This
read-only checkpoint does not authorize fresh entry or release activation holds.
See the current API contract above.

## Evidence and scope

The prepared native audio path now persists exact input, binds execution and
supports explicit saved-child recovery. Its local source guard cannot establish
remote absence after reinstall, another device, or damaged local linkage.

The current server intent table is keyed by child analysis ID. Audio admission
in `20261007171421_prepare_audio_analysis_admission.sql` locks and replays that
child, then reserves quota. Recovery in
`20261003074429_prepare_observation_analysis_recovery.sql` also requires the
child identity. Neither is a read-only source lookup. Calling funded admission
to discover existing work would reserve funding too early.

The unit of coordination is `(owner, observation, immutable source analysis)`.
It is **not** a permanent one-child-per-source constraint: a later explicit
reanalysis after conclusive completion remains supported. Multiple completed
children are valid history. Never pick a latest row by date or discard older
unresolved work. Every attributable unresolved operation must be accounted for.

This contract concerns unresolved reanalysis occupancy. It does not change
selection, review revisions, original evidence, provider profiles or result
projection. A historical source need not currently be selected.

## Separate discovery, reservation and execution

1. A bounded authenticated Edge reader derives owner from verified
   authentication and calls a service-only read-only resolver for the exact
   observation/source. Ownership, deletion, source linkage and rollout checks
   still apply. Discovery must not reserve quota, create an intent, authorize
   uploads or obtain a work token. Its absence result is advisory and cannot
   authorize a mutation.
2. At an explicit fresh tap, native code freezes and durably saves the proposed
   child/media identities, exact canonical input and fingerprint **before any
   remote mutation**. Reopening or an uncertain save retains that candidate.
3. A separate service-only atomic reservation binds that exact candidate to the
   source before upload and funded admission. It neither reserves quota nor
   grants dispatch. Under canonical locks it either replays the same immutable
   claim, reserves an unoccupied source, or returns existing recovery/held
   state. A stale advisory read cannot bypass this transaction.
4. Upload and funded admission validate the exact reservation binding. Existing
   consent, eligibility, entitlement, evidence, quota and dispatch checks remain
   at their established boundaries. Only the existing dispatch grant can
   authorize the existing one-time provider attempt.
5. A lost reservation reply permits exact lookup/replay of the original claim.
   Lost funded admission, dispatch or outcome replies retain their existing
   uncertainty rules. A resolver response never converts them into fresh work.

The reservation binds child identity to the complete immutable request identity
including source, ordered evidence digest and provider input profile. The new
RPC contract must define a versioned canonical fingerprint shared by SQL,
TypeScript and Swift; it cannot rely on differently serialized JSON text. No
claim ID or child ID may be rebound to changed input, owner or source.

## Durable states and release predicates

| Durable evidence                                                                                                          | Discovery classification          | New explicit same-source reservation                                         |
| ------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------------- |
| No recorded occupancy and complete, validated namespace coverage                                                          | Advisory absence                  | Only the atomic reservation transaction may admit it.                        |
| Reserved, not yet admitted                                                                                                | Existing claim                    | Denied until exact replay or explicit durable retirement.                    |
| Admitted, dispatched with or without outcome, or draft                                                                    | Existing operation, recovery only | Denied. Expired leases and exhausted retries do not release it.              |
| Complete with exact canonical result and matching durable settlement                                                      | Completed history                 | Allowed only after atomic verification of every prior occupancy.             |
| Exact immutable `retired_before_dispatch` receipt with matching terminal intent and settlement                            | Retired history                   | Allowed only after atomic verification that execution is permanently fenced. |
| Any other failed-terminal reason                                                                                          | Held                              | Denied in the initial implementation; a status label alone proves nothing.   |
| Missing/malformed linkage, ambiguous multiple blockers, missing settlement, unknown state, deletion or erasure transition | Held or unavailable               | Denied; never select a guessed winner.                                       |

Completion proof must match owner, observation, child, immutable source/request
binding, canonical result and durable accounting disposition. It must not depend
on a quota row that may later be pruned. The forward implementation must
identify an existing durable settlement proof or introduce a minimal durable
proof; missing evidence remains held. Preserve immutable terminal records when
current occupancy is released. They remain durable while the owner observation
exists, not after its intentional erasure: existing retirement receipts
cascade-delete with their intent. Parent deletion removes private source links
and proofs under the existing deletion/tombstone contract; no new perpetual
owner-linked ledger is authorized. A past terminal child cannot reopen as live
execution, a source claim or fresh admission. Its endpoint-specific exact
terminal receipt replay remains allowed until deletion.

Retirement is an explicit exact-candidate action. A never-funded reservation may
be retired only while holding the same locks as upload, admission and dispatch,
with proof that no funded/provider/result namespace exists. It writes a durable
immutable retirement receipt and fences every later writer before returning.
After admission, reuse the existing exact execution-retirement contract only
where its complete preconditions hold. Never infer non-execution from absent
prunable quota/invocation rows. Other terminal failure reasons require a later
independent review of their complete remediation proof before allowing a new
attempt; no automatic successor or refund is introduced here.

Reservations have **no automatic expiry or release** in the initial design.
Timeout and cancellation of a caller affect only that caller. Timestamps may
support diagnostics, but cannot authorize replacement. This avoids treating a
late original request as nonexistent. Abandoned reservations require explicit
retirement under the never-reopening fence above.

## Storage, locking and all-writer obligations

Use a durable source index and operation bindings, with at most one unresolved
occupancy per exact source tuple. Do not make the historical source itself
unique across terminal operations. Index records must follow existing
observation/account ownership and deletion semantics; merge conflicts must abort
the whole transaction rather than drop or reassign conflicting work.

Keep the established owner/observation lock first. Source coordination follows
it; existing child ingestion/evidence, intent, funding and invocation locks must
retain their established relative order. The migration review must enumerate
actual writer lock sequences before adding a new lock: do not retrofit a
conflicting ordering into only one RPC. No remote calls occur under SQL locks.

Fence all writers capable of creating, funding, uploading or dispatching a child
for this source, including fresh photo and audio admissions and privileged
helpers. Exact already-recorded request replay precedes new admission gates.
Ordinary client-field omission cannot choose an unfenced legacy path. Existing
saved-photo requests retain their original shape, fingerprint and replay result.
The coordinated cutover must withhold unsupported fresh callers rather than
silently reinterpret their request. Audio-only occupancy cannot claim protection
against an unfenced photo writer.

Backfill must validate complete scope/linkage and classify every historical
operation. Multiple unresolved rows, malformed source links or orphaned funding/
evidence become held scopes; do not choose the latest, delete them, or create a
successor. Activation remains disabled until namespace coverage and all-writer
fencing are proven. Deletion wins over read, replay, reservation and retirement;
cleanup retains existing tombstone semantics and never resurrects a source.

## Bounded descriptor and native consumer

The proposed descriptor has its own schema version and fixed discriminated
variants: advisory absence, one existing claim/operation, conclusively completed
or retired history, held, and unavailable. It contains only the exact owner,
observation/source scope, applicable child identity and bounded reason/phase. It
exposes no request body, media paths, names, quota record, provider response,
credentials, grant, work token or dispatch capability. Ambiguous multiple active
identities return held rather than an arbitrarily selected child. History
browsing remains the existing independently paged result reader.

The implementation checkpoint must fix exact field sets, byte/count limits,
reader negotiation, closed reason enums and endpoint configuration in executable
schemas before generating/updating decoders. No provisional field here is a
shipped wire contract. Five-second retry-free lookup and reservation transports
must enforce actual response limits and account/attempt fences after Auth.

A remote existing-child descriptor cannot be fed into the current native resume
factory by fabricating local input, consent, files or an execution job. The
explicit remote recovery consumer must be outcome/status-only until authentic
saved context supports the existing recovery boundary. The source lookup is not
that consumer. Native local ambiguous occupancy remains held even if the server
reports advisory absence. New terminal-proof admission requires an explicit new
tap; no automatic reopening, UUID reminting or result selection.

## Reviewable implementation checkpoints and acceptance

1. Freeze executable state/descriptor/fingerprint contracts and durable proof
   ownership. Add forward storage/index and read-only discovery with role,
   owner/deletion, malformed/backfill and bounded-response tests. No reservation
   or ordinary route is enabled by this checkpoint.
2. Add atomic unfunded reservation and exact durable retirement, coordinated
   all-writer fencing and compatibility. Prove distinct-child source races, lost
   replies, reservation versus retirement/admission/upload/dispatch,
   pruning-safe proof and whole-transaction deletion/merge conflicts.
3. Add strict TypeScript and native mappings and retained, account-scoped
   outcome-only remote recovery. Prove second-device/reinstall behavior without
   fabricated local evidence, including ambiguous local saves and scope loss.
4. Connect explicit fresh entry only after all these authorities agree. Prove a
   completed B permits a later explicit C from the same A, while unresolved B
   blocks C. Repeated same-ID calls recover B; they never invoke another
   provider.

Each checkpoint includes docs, focused tests and independent review. SQL work
requires a fresh disposable reset, catalogs before real concurrency tests,
security/privilege/advisor checks, affected backend gates and endpoint-specific
configuration validation. Native consumers need exact selectors and affected
native gates. Preserve failed evidence and separate shared-worktree results from
clean-candidate CI. Real device, hosted runtime/storage/erasure and Field Trip
qualification remain separately held. This design does not close slice 5 or 7.

## October 8 fingerprint preparation checkpoint

The pure TypeScript
[fingerprint contract](../backend-and-data/05-api-contracts.md#prepared-source-reservation-fingerprint)
now defines versioned UTF-8 framing and fixed reviewed photo/audio vectors. It
preserves existing saved request digests and excludes owner from immutable bytes
while retaining owner as mandatory authorization scope. The next checkpoint adds
pure ungranted SQL and native encoders with shared byte/hash parity tests.
Storage, reservation, retirement and all-writer cutover remain unimplemented.
This is contract groundwork, not admission or activation.

## October 8 private storage checkpoint

The pure SQL/native encoders now match the TypeScript fixed vectors. Private
immutable source bindings and a separate unresolved-occupancy table are prepared
with ownership, source/fingerprint validation, API-role denial and
parent-erasure constraints. No callable reservation or release routine exists.
The existing prepared-history merge hold extends to retained bindings; generic
reparenting cannot change their explicit owner identity.

This completes storage groundwork only. Atomic reservation, exact retirement,
terminal proof release, complete namespace coverage and coordinated all-writer
fencing remain unimplemented. An unoccupied binding is held, not absence. The
writer audit confirms that existing photo/audio cohort RPC signatures can remain
if a prior authoritative child binding supplies source and immutable input; new
cohorts must compare exact stored media projection, while old unclaimed cohorts
retain only exact replay. The source lock belongs after parent locks and before
child locks in every coordinated path. This is a required subsequent
implementation boundary, not an active compatibility guarantee.

## October 8 reservation wire checkpoint

The executable prepared mutation boundary now fixes action reader 11, a complete
InputV2/V3 reservation request with recomputed fingerprint, and bounded exact
reservation receipts. Held responses disclose scope and a closed reason only,
never competing child identity. Explicit unfunded retirement uses a separate
operation UUID and `retired_unfunded` receipt; the existing intent-backed
`retired_before_dispatch` proof is unchanged. See the
[canonical wire contract](../backend-and-data/05-api-contracts.md#prepared-source-reservation-and-unfunded-retirement-wire).

This is a decoder and contract checkpoint, not a reservation implementation. The
next coordinated SQL change must use a source-aware sibling of the existing
parent lock helper, before child evidence/intent/quota locks, and patch every
writer. The generic parent helper lacks source identity and cannot safely stand
in for that fence. Existing unclaimed cohorts retain exact replay only; missing
or unattributable parent evidence holds fresh reservation. No callable mutation
or consumer opens until terminal-proof storage and all-writer coverage are
independently reviewed together.

## October 8 ingestion prerequisite

The prepared binding now excludes legacy scans and ingestion jobs/intents under
shared owner-before-child locks. Normalized UUID comparison also detects older
uppercase, braced and unhyphenated text identities without rewriting their saved
request identity. Real concurrency tests cover both winning orders and different
owners. This checkpoint does not establish all-writer coverage: generic funding
and invocation paths, protected media/admission/execution, and exact terminal
retirement remain prerequisites before reservation can open.

## October 8 funding prerequisite

Generic quota admission and fresh invocation commitment now reject bound
original analysis identities under their shared child advisory lock. Exact
invocation replay remains before the fresh gate. Quota request UUIDs are scoped
idempotency keys, not child references; guarding them would reject valid
distinct requests and introduce opposing multi-child lock orders. No
source-aware funding grant or reservation API opens in this checkpoint.
Protected writer cutover remains.

## October 8 shared validation prerequisite

The private source-validation checkpoint
`20261008191800_centralize_observation_source_binding_validation.sql`
centralizes owner/deletion/enrollment and exact source membership under owner →
parent → source locks. Storage inserts retain child-ingestion then
child-evidence locks before namespace validation. The separate exact-binding
helper recomputes the fingerprint from complete InputV2/V3, compares the full
saved input and all scope IDs, and requires matching active occupancy. Missing,
source-less, mismatched or unoccupied bindings fail closed; the source need not
be selected. Frozen transaction snapshots are unavailable. Both helpers are
private, revoked from all API roles, and grant no reservation, funding, release
or dispatch authority.

Existing terminal or legacy replay must precede this live-binding check. Current
protected writers are not switched to it until their lock order, cohort binding,
admission and narrow funding/dispatch exceptions change together. Cohort-only
enforcement is not a supported activation boundary.

### Prepared immutable cohort source links

Migration `20261008194407_prepare_source_linked_evidence_cohorts.sql` adds
nullable `binding_analysis_id` to photo and audio upload cohorts. A non-null
link must name the same child and reference its immutable source binding. The
private insert backstop checks owner, observation and exact media projection:
photo order is preserved; audio metadata must match the single saved audio item.
Descriptions remain in the complete binding and fingerprint, not the upload
projection. Existing update guards make both links and legacy NULL values
immutable. Parent deletion can cascade through either history or binding;
receipt cleanup continues retaining the cohort and its fixed expiry.

This is additive storage groundwork. Existing RPCs still create NULL-linked
cohorts, with unchanged saved-request replay, receipts, gates and grants. No
existing cohort is backfilled or upgraded. The validator acquires no late locks
and grants no occupancy, upload receipt, admission or dispatch. A future linked
writer must validate live occupancy under the canonical source-before-child
locks as part of the coordinated reservation/cohort/admission/execution cutover.
The source link alone never establishes that cutover is complete.

### Prepared source-bound intent fence

`20261008200418_fence_source_bound_analysis_intents.sql` adds a deny-only insert
backstop for source-bound analysis intents. After owner/parent authorization and
child-ingestion then child-evidence locks, a bound child requires the exact
immutable input/fingerprint, owner/parent association, live source occupancy and
one matching linked photo or audio cohort. NULL-linked legacy cohorts, opposite
or mixed cohort types, and changed media or descriptions cannot establish this
chain. Existing ready-evidence checks still apply. The private chain check takes
no late locks and grants no quota or provider authority.

Fresh insert guards require current statement snapshots (read committed/read
uncommitted); frozen snapshots cannot prove post-wait namespace absence. A
legacy unbound insert retains its existing behavior under supported isolation.
This closes binding-versus-direct-intent races in both commit orders. This
migration leaves bound-child funding and invocation exclusions unconditional;
the subsequent initial-admission checkpoint below narrows only funding. No GUC,
metadata validation success or raw intent row opens a funding exception. The
future coordinated writer change must move source proof before child and intent
locks, retain exact replay before fresh gates, and additionally prove intent
state/context and original quota when opening the narrow funding/dispatch path.

### Source-aware evidence writers

Migration `20261008203348_bind_source_evidence_writers.sql` connects existing
photo/audio cohort reservation and raw receipt reservation/completion to the
private source entry helper. A bound child requires exact live binding and
occupancy under owner/parent → source → child ingestion → child evidence locks.
New cohorts preserve the binding link and exact ordered photo or single-audio
projection. Existing NULL-linked cohorts never upgrade. Receipt allocation and
completion also validate the linked chain; existing expiry, readiness and object
identity rules remain unchanged. No quota, intent or provider grant is created.

An apparently unbound caller takes child locks then rereads the binding table.
If a binding appeared while waiting, it fails instead of acquiring a source lock
late. Conversely, a committed legacy cohort makes a later binding fail its
existing no-retrofit namespace check. These writers require read committed/read
uncommitted isolation; repeatable-read and serializable snapshots fail closed,
including for unbound requests. Legacy saved photo/audio replay retains its
original receipt, object and deadline under supported isolation.

This is closed bound-branch preparation, not all-writer cutover. Atomic source
reservation, exact retirement and coordinated admission/funding/execution remain
required before a new source API can open. No grant, rollout gate, wire field or
ordinary route is added; existing activation holds remain.

### Source-bound initial admission

Migration `20261008210355_prepare_source_bound_initial_admission.sql` connects
fresh bound V2/V3 admission to source-before-child/intent locking and narrows
the quota exclusion for exactly one initial funding transaction. The admission
context must match owner/child; operation, original child, request ID and
protocol constants must match. The private intent must be admitted with no saved
quota, work claim, outcome, invocation, draft, result, retirement or prior
accounting. Exact live binding, input fingerprint, occupancy and linked media
projection are mandatory. A context setting alone is insufficient.

The current eleven-argument identification quota wrapper also compares its
profile, processor permission and identification protocol with the immutable
input. Mismatch rolls back the transaction. Older identification quota overloads
and the eight-argument generic quota wrapper reject bound children before and
after their core call; unbound callers retain their existing behavior. No new
public signature or privilege is introduced.

A recorded bound intent is recovered under owner/parent authorization before
live occupancy, evidence expiry and fresh gates. Its original input and quota
identity must validate. Even an admitted replay returns that saved quota; it
never invokes generic quota reservation again. Expired, refunded or pruned quota
therefore cannot mint another lease or attempt. Missing/malformed saved quota
holds rather than funding. Deletion still wins. Recovery is not dispatch
permission and does not select or alter an analysis.

This is admission-only preparation. The source-bound invocation exclusion stays
unconditional; no provider may start through this checkpoint. Atomic source
reservation, terminal release/retirement and the coordinated execution cutover
remain required before source access opens. All activation gates remain false.

Admission, including saved receipt replay, requires read-committed or
read-uncommitted isolation before any source existence lookup. Repeatable-read
and serializable calls fail closed with
`analysis_history_current_snapshot_required`; a frozen snapshot cannot hide a
committed deletion. Saved quota replay does not assert that its original lease
is still live.

### Source execution lock preparation

Migration `20261008213302_prepare_source_execution_lock_order.sql` installs a
private entry helper before intent row locks in claim/recovery, dispatch, draft
recording, completion, failure and the public work-advance owner. V2/V3 append
uses the same ordering before its own result/child locks. Supported isolation is
read committed/read uncommitted. Owner/deletion authorization precedes binding
inspection; bound work takes source, child ingestion and child evidence locks,
then verifies immutable saved-intent input/fingerprint association.

This helper establishes identity and lock order without requiring live
occupancy, media rows or unexpired uploads. Existing operation-specific token,
payload and receipt checks still apply. Apparently unbound calls take child
locks and reread binding absence; a binding committed during the wait holds
instead of acquiring a source lock late. Unbound behavior is preserved under
supported isolation.

This is lock preparation, not execution authority. Source-bound invocation
remains denied. Original-quota dispatch proof and atomic retirement/release
remain separate coordinated checkpoints before source access opens. No public
signature, grant, gate or provider successor is introduced.

### Source-bound generic accounting holds

Migration `20261008220335_hold_source_bound_generic_quota_cleanup.sql` closes
inherited generic accounting paths before source execution opens. The public
quota finalizer rejects bound children even with a matching provider context;
generic expiry refund and terminal quota pruning skip bound children while
continuing unrelated cleanup. No schedule is created, changed or enabled.
Generic failure/cancellation and fresh funded retirement hold; exact existing
terminal/retirement receipt replay remains before the new holds. Unbound
finalization retains its existing isolation behavior.

Parent deletion retains a separate private refund path only for the exact unused
original reservation, owner, child, request, lease and attempt. A live-parent
intent deletion is not that proof. Known invocation/outcome/result evidence
prevents refund; deletion still erases the intent. The unused-work proof applies
to all admitted intent erasure because source bindings may be removed earlier in
the same deletion transaction. Other unbound accounting behavior remains
unchanged under supported isolation. Immutable binding and occupancy are not
released by generic accounting cleanup.

Atomic source retirement/release and original-grant dispatch remain required.
Until their reviewed durable proofs exist, bound quota records intentionally
stay held instead of being expired, pruned or treated as permission for another
provider call. Activation gates remain false and ordinary access remains nil.

### Source dispatch witness preparation

Migration `20261008222349_prepare_source_dispatch_witness.sql` adds
default-false `source_dispatch_enabled`. Fresh bound dispatch requires the
existing modality, admission, append and dispatch gates, current consent, exact
live source/input/ occupancy/media chain and the original reserved quota,
request, child, lease and attempt. The assigned input profile must match the
immutable input and saved quota. Canonical owner/parent/source/child/intent
locks precede quota locking.

A private immutable intent-owned witness records original reservation, lease
digest, attempt, source fingerprint, provenance and creating transaction. The
invocation writer accepts it only in that transaction; finalization and
invocation insertion are atomic with the witness and intent transition. A
retained witness is audit evidence, never reusable dispatch authority. Exact
invocation replay continues to return `may_dispatch=false` before fresh gates.
Generic quota finalization remains held. No new public signature or grant is
introduced.

Witnesses have no quota foreign key and cannot disappear through quota pruning.
They cascade with intent deletion; the unused-reservation erasure proof rejects
any witness before that cascade, including an interrupted/tampered partial
state. Binding deletion therefore cannot hide dispatch evidence and permit a
refund. Account merge remains held by the existing bound-source guard. Atomic
retirement and source release remain separate work before source access opens.
All activation gates remain disabled; uncertain execution permits recovery and
reconciliation only, never a successor provider invocation.

Fresh invocation also checks the permanent child deletion tombstone after its
child lock. Once deletion erases binding, intent and witness, a held reservation
cannot fall through to generic dispatch. Existing invocation replay remains
non-dispatching.

### Atomic source-bound funded retirement

Migration `20261008223804_prepare_atomic_source_execution_retirement.sql` adds
default-false `source_retirement_enabled` alongside the existing retirement API
gate. The existing request, receipt and reader9/10 compatibility are unchanged.
Read-committed/read-uncommitted isolation is required before ownership locks or
receipt replay; frozen snapshots fail closed. Owner/deletion and reader checks
still precede exact receipt recovery. That recovery needs neither live occupancy
nor the original quota row and does not create another operation.

Fresh retirement uses the live source-before-child lock helper before intent and
quota locks. Apparently unbound callers reread binding absence after child
locks. The bound input/source must match the saved intent, and a dispatch
witness blocks retirement even if accounting still appears reserved. Existing
exact unused-work, original reservation/lease/attempt and complimentary-credit
proofs remain. A live worker claim is revoked atomically; it is not itself
evidence of provider dispatch. Expired original leases may retire only when
those unused-work proofs hold.

Application atomically refunds through the private quota core, settles the held
complimentary allocation, writes terminal `retired_before_dispatch` state and
its permanent receipt, then deletes only the matching occupancy. The storage
trigger requires the complete binding/input/fingerprint, terminal intent, exact
receipt, refunded original quota and absence of witness/invocation/result before
permitting that live-parent occupancy deletion. Any failure rolls back all of
these changes. Immutable binding and dispatch-witness deletion rules remain
unchanged. Generic quota cleanup is still held and cannot release occupancy.

This is a closed funded-retirement capability, not source API activation. Source
reservation, unfunded retirement, native consumption and remaining media
acceptance remain separate. No new public signature, privilege, provider retry
or uncertain refund is introduced. All activation gates stay disabled.

### October 8 terminal reservation replay decision

The
[canonical API contract](../backend-and-data/05-api-contracts.md#source-reservation-terminal-replay-and-successor-admission)
now fixes the remaining pre-implementation decision: exact terminal children
with released occupancy return the existing operation-conflict error, never a
replayed `reserved` receipt or recreated occupancy. Conflict is not terminal
proof and never authorizes a new UUID. Original operation-specific terminal
recovery and a later explicit new tap remain required. Missing terminal proof
holds.

A new child requires complete bounded predecessor and namespace inventory under
canonical locks. The first paired reservation/unfunded-retirement implementation
may accept only proven funded/unfunded retirement predecessors. Completed-source
release remains separate, unimplemented work; the broader feature still requires
later reanalysis after qualified completion. No new response variant, reader,
RPC, native consumer or gate activation is introduced by this decision.
