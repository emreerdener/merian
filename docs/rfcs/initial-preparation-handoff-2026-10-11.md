# Initial preparation outcome and admission handoff

Revision 2, accepted October 11, 2026. This is the concrete design for the next
dependency under the shared IC-1 revision 2 agreement, following execution
checkpoint `0a0d5bb104c6044ad75869604209351f78407efb`. It is not implemented or
qualified behavior. The history primary remains the sole writer; IC-1 and
independent acceptance of this revision precede code. Production gates remain
false, ordinary access nil, and catalogs uninstalled. The agreed fresh-library
alpha roadmap and its separate installed, hosted, device and release
authorization still apply. Those shared planning records remain locally
preserved outside this scoped checkpoint.

## Current scope and implementation boundary — October 12, 2026

The media-required amendment in
[IC-1 revision 3](initial-completion-history-interface-2026-10-11.md) and the
[alpha roadmap](identification-history-alpha-readiness-2026-10-11.md) supersedes
older text-only planning references in this historical design. New initial
identification and reanalysis require photo, audio or video; original retained
media is sufficient for reanalysis and supporting text is optional. Historical
text records and exact already-admitted recovery remain preserved. No standalone
Describe or text-only child/editor is an active implementation requirement.

Private admitted-proof SQL parity is accepted locally at `8d4f8c50c`. The next
funded candidate must combine original funding, complete private receipt and M1
allocation, exact admitted recovery, positive-unused C1 cancellation/expiry and
scan/account erasure. Receipt construction follows the accepted clarification:
preallocate opaque receipt/destination IDs without authority, compute mapping
and binding without the enclosing receipt digest, insert the complete receipt
before M1 members under the canonical lock order, force complete-state checks,
seal the stage, then perform the final nonmutating cutoff check. See
`.artifacts/initial-outcome-admission-handoff/admission-mapping-order-agreement.md`.
This clarification supersedes any older construction-order shorthand below.
M2/copy/transfer may remain disabled. Provider dispatch, quota commit, result
capture and successful completion stay blocked; C1 covers cancellation and
eligible expiry. Missing unused proof retains conservative unknown handling
without refund. No funding-only or M1-only callable intermediate is acceptable.
This is the next implementation boundary, not a claim that it is implemented or
qualified.

## 1. One operation and existing owners

`finalize_initial_preparation(owner, scan, ip_hash)` remains the admission
owner. It first checks live ownership and deletion, then recovers the exact
original admission. A new media branch consumes only the original validated
preparation outcome. It does not call v1 admission as a black box, reselect
media profiles, repeat a transform, or create another logical operation.

Existing core8/core4 quota, complimentary allocation, provider-attempt and C1
settlement owners retain their writes. Their existing comparison hook gains a
strict media case. The hook runs before the first core8 hold/entitlement-epoch
mutation and again before core4 reservation/counter mutation. The second hook
must match the first decision, not recompute a different entitlement after the
first mutation. No media handoff grants provider dispatch in this increment.

The permanent `blocked_pre_admission` literal remains unchanged. Its historical
name means deny every writer except the exact admission, M1/M2 and cancellation
transitions described here. It is never cleared and is never itself evidence
that a reservation is unused. Provider invocation, result, completion, scan
ingestion and history writers remain blocked until their separate S0 agreement.

## 2. Closed original qualification and protocol cutover

Create immutable private `initial_preparation_handoff_profiles` keyed by UUID
generation, with canonical JSON and a domain-separated digest. Its version-1
payload has exactly these fields:

- `version`, `generation`, `source_backend_generation`,
  `source_backend_config_digest`, `destination_backend_generation`,
  `destination_backend_config_digest`;
- `protocol_artifact_digest`, `copy_adapter_digest`,
  `verification_adapter_digest`: exact retained protocol and adapter
  source/build identities, never a mutable executable label;
- `cohort_limits`: maximum media ordinals, unique destination objects and total
  unique-object bytes; closed accepted source/prepared content-type pairs per
  image/audio/video kind; `alias_policy: same_ordinal_exact_bytes_only` and
  `video_policy: source_only`;
- `phase_ms`: positive integer ceilings for `admission`, `copy`,
  `verification_claim`, `verification`, `verification_settlement`, `transfer`,
  `reconciliation` and `protocol_margin`;
- `total_ms`, exactly the checked integer sum of those eight ceilings and less
  than 300,000; `execution_model: sequential_whole_cohort`.

The destination is an immutable existing M1 backend generation, including its
namespace and credential-profile reference; no credential value is stored.
Limits may narrow but never exceed M1's 8 ordinals, 10 unique objects and
28,625,792 bytes. Content-type pairs must be supported by both preparation and
M1/M2 validators. Reject an unrepresentable cohort before funding. There is no
cross-ordinal deduplication or implicit parallel execution qualification.

`protocol_artifact_digest` identifies one retained composite handoff artifact:
canonical-input projection, M1 v2 allocator/mapping rules, M2 v2 envelope and
receipt codecs/validators, transfer validator and deadline/response protocol.
Its closed manifest lists each component digest and schema version. Profile,
installation, original v3 assignment, v2 grant, admitted receipt and transfer
receipt all bind this digest. New binaries must resolve that exact artifact or
hold; they cannot apply changed projection/mapping semantics to an old
operation.

An immutable `initial_preparation_handoff_installations` record binds profile
generation/digest, protocol artifact and adapter digests, qualification
harness/source revision and retained evidence digest. A separate eligibility
record may revoke the exact installation. Only the existing trusted
catalog-installation boundary may register it; service admission cannot install
or qualify anything. Synthetic disposable fixtures are not live installations.
No production row is seeded.

An immutable selection association binds a preparation selection generation to
one handoff installation. This association is required before that generation
can be selected for a fresh qualified media allocation. Existing generations
without it are never enriched. Current selection is consulted only for a new
operation. Admission and recovery use saved IDs; revocation can deny new work
without substituting another profile, backend, adapter or budget.

| Contract                                         | Fresh qualified media                                                                                                                 | Existing records and other routes                                           |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Source candidate                                 | v2 unchanged                                                                                                                          | Unchanged                                                                   |
| Saved preparation assignment                     | Closed v3: existing full media assignment plus `handoff` containing complete profile, profile digest and installation identity/digest | Media v2 lacks qualification and cannot gain funding; no-media v2 unchanged |
| Preparation allocation reply                     | v3 containing assignment v3                                                                                                           | Original reply version retained on exact recovery                           |
| Source verification, output and resolved mapping | Existing v1 shapes, bound to assignment v3 digest                                                                                     | Existing shapes unchanged                                                   |
| Execution grant and outcome                      | v2: grant binds handoff profile/installation digests and total suffix; outcome binds that grant                                       | Existing v1 original outcome/status/C1 recovery only; no new funded path    |
| Execution response                               | v2 for the v3-assignment branch                                                                                                       | Explicit v1 decoder for original recovery, never a permissive union         |
| Admission binding                                | v3 binding candidate, assignment, original outcome and handoff receipt digests                                                        | No-media v2 and ordinary v1 unchanged                                       |
| Admitted M1 binding and M2 service envelope      | v2 with original expiry, phase deadlines, receipt and mapping digests                                                                 | Existing v1 branch unchanged and rejects v2                                 |
| Transfer receipt                                 | v1, dedicated handoff digest domain                                                                                                   | Absent on old protocols                                                     |

Old unissued media assignments cannot issue a new qualified grant; return a
closed `handoff_qualification_unavailable` hold. Already-issued old grants may
recover/register only their original permitted outcome under the accepted
execution contract. They do not acquire the new admission path. Fresh initial
capture DTOs and initial text/no-media behavior are unchanged.

## 3. Budget and immutable deadlines

Let `E` be the original preparation expiry, 300 seconds after its allocation,
`W` the saved qualified preparation runtime bound, and `H` the pinned whole-
cohort handoff total. Before sole issuance, require strictly:

```text
server_now + 45,000 + W + H < E
```

The existing prefix is grant response 5s, registration 5s, retained-output write
30s and outcome response 5s, plus `W`. `H` replaces the unqualified future 35s
reserve; it does not stack that reserve or double-count the prefix. The grant
stores this exact computation and original expiry. Missing qualification or
insufficient remaining time denies issuance without funding or a new identity.

`admission` includes the complete funding transaction, M1 allocation and its
response. `copy` includes every sequential original-object GET, conditional
destination PUT and read-back for the whole supported cohort. M2 claim response,
all verification reads, settlement response, and transfer transaction/response
have their own ceilings. `reconciliation` reserves terminal/status recovery;
`protocol_margin` covers measured protocol overhead and conservative delay.
Every I/O is counted once; aliases are one physical object. Fixtures must use
the maximum supported topology and byte bounds. Constants alone are not proof
that a live adapter meets these bounds.

Before the first funding write, under all required identity and catalog locks,
choose server admission anchor `A`; require `A + H < E` and recheck the original
outcome, eligibility, consent, funding decision and deletion fences. Store `A`
and eight cumulative phase cutoffs in the prospective/admitted receipt. Every
phase must obtain its final locked authorization before its cumulative cutoff;
no retry extends them. Receipt construction samples and stores
`authorized_at_ms` using `clock_timestamp()` under the shared scope locks; it
must be strictly before the phase cutoff. After all intended writes, retirement,
private erasure and forced deferred checks, the owner performs one final
`clock_timestamp() < cutoff` check as its last nonmutating validation. No
further locks, I/O or member writes follow that check; failure rolls back the
entire transaction including the provisional receipt. Stage sealing and member
guards also reject caller writes after the routine returns. The stored
authorization time is not a claimed physical commit time or a sample of that
final check.

Retain the shared admission/transfer/expiry locks until commit or rollback. Only
the committed receipt makes the authorization durable. Expiry arriving later
waits, then observes the committed timely-authorized receipt or a rollback with
no receipt. An uncertain commit is recovered by original identity. Neither a SQL
clock check, deferred trigger, statement timeout nor client timestamp proves
physical WAL commit completion before a wall-clock deadline. A receipt committed
after the on-time final check remains the sole success authority. Transfer
reserves reconciliation and margin before `E` in its phase budget.

Server checks use post-lock time. Clients subtract the full measured request
round trip from returned remaining duration and use a monotonic local deadline;
they never trust their wall clock to extend authority. Responses arriving too
late authorize only status recovery. A timely committed transfer remains
recoverable after every deadline. M2 verification alone does not extend expiry.

## 4. Prospective admission proof and atomic funding

Add private `initial_preparation_admission_staging`, unique by scan and by
`(scan_id, owner_id)`. Fields are current transaction ID (`xid8`), random token,
phase, original owner/scan/route/expiry, canonical candidate and assignment with
digests, complete source-verification/grant/output/resolved/outcome chain with
digests, resolved initial input/digest, pinned handoff profile/installation,
anchor/cutoffs, funding projection and expected write images, followed by the
original reservation/lease/attempt and destination mapping once allocated.

Its sole creator is a revoked internal SECURITY DEFINER helper called from the
existing finalizer after the canonical locks and complete original proof. There
is no service/public table access or exposed stage-creation RPC. The creator
requires live ownership; no deletion/account-removal job; the original operation
and allocated source fences; one issued grant and coherent outcome; no quota,
complimentary hold, submission, admission, M1 allocation, invocation, ingestion,
result or history alias for this operation. A GUC may carry the token between
nested owners but cannot substitute for this row, current transaction, locks or
complete proof.

Phases advance once: `validated` → `compared` → `reserved` → `admitted` →
`allocated`. Identity and original proof cannot change. Before core8 mutates,
the existing comparison hook sets the funding projection once: effective plan,
tier/model/fallback, entitlement and policy versions, provider/model binding,
capability/consent, complimentary classification and exact counter charges. It
compares the actual proposed core8 decision to the entire saved assignment.
Core4 checks the same projection. Current selectors are not consulted.

Each existing owner registers its exact proposed OLD/NEW row image in the stage
before its authorized mutation, after computing its normal decision.
Registration is private, one-use and limited to the matrix below. The barrier
trigger must compare the complete image, transaction/token/phase and immutable
operation proof, then consume that expectation. Other columns are not ignored.
The deferred verifier recomputes the complete final state; an expected-image
entry is not by itself authority. Existing owners remain responsible for
amount/counter computation, and the stage cannot ask them to charge a different
amount, select another model or take a recovery/reacquisition branch.

| Writer                                       | Allowed prospective transition and final predicate                                                                                                                                                                                                                                                                                                                                     |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Complimentary usage                          | No prior operation allocation; insert original held allocation, with no reacquisition. Match original scan, owner, entitlement and core8 projection. No consume/release/reopen in admission.                                                                                                                                                                                           |
| User entitlement epoch                       | Only the existing core8 increment corresponding to that original hold; the existing entitlement_version trigger increment is included; all other user fields unchanged. No increment if no hold.                                                                                                                                                                                       |
| Quota reservation                            | One fresh core4 INSERT, original `request_id=scan_id`, scan-identification operation, attempt 1, reserved state, original lease. The existing core8 UPDATE may attach `original_analysis_id=scan_id`, complimentary reference and protocol; core4 may set its computed daily remaining. No existing reservation replay, stale recovery, re-lease, state transition or identity update. |
| Quota counters and reservation-counter links | Only the original core4 projected daily/user/IP charges and their links to that one reservation. Exact charged amount and computed remaining must agree. No second links or unrelated counter mutation under this exception.                                                                                                                                                           |
| Provider attempt                             | Exactly one original attempt INSERT by the existing 11-argument owner, matching saved provider/model/policy/capability/consent and reservation; no invocation, successor or attempt-state update.                                                                                                                                                                                      |
| Submission/admission/lifecycle               | Exactly the saved canonical resolved input, config and original funding snapshot/digests; owner/scan/route unchanged; binding v3; lifecycle only fresh `pending_pre_dispatch`. Existing operation fence is reused.                                                                                                                                                                     |
| M1 fence, registry and cohort                | Exactly one fresh destination allocation by the internal allocator, mapping and metadata specified below. Every registry object belongs to this operation and saved backend. No pre-source ID reuse, second cohort or early retirement.                                                                                                                                                |
| Admitted receipt                             | One immutable receipt INSERT equal to the final stage proof, funding and M1 mapping. No update or replacement.                                                                                                                                                                                                                                                                         |

All INSERT/UPDATE barriers check both OLD and NEW alias identities, including
nullable aliases before the core8 attachment. Existing ingress order, FK
parents, statement-level paths and effective BEFORE triggers must be audited
again in the candidate. No generic `binding.version=3` exception is allowed.
Unlisted writers remain blocked. Raw DELETE and delete/reinsert cannot clear or
recycle the stage. Only the finalizer consumes it after complete final
validation; rollback removes all its transactional writes.

Deferred constraint triggers on stage creation and every admitted member must
reject commit unless: stage is consumed; exactly one complete receipt,
submission, admission, original reserved quota and attempt exist; all saved
identities/projections/digests match; no competing aliases exist; every expected
write was consumed once; complimentary classification and counter links match;
M1 registry union is exactly the mapping with no extras; source proof remains
live; and lifecycle is pending with no provider/result/history activity. A stage
deletion without this final state fails. Triggers must retain the original
identity needed to check even if the stage row has been deleted. No deferred
check may merely test stage absence or receipt presence. Preserve the original
transaction identity and proof in the trigger event/immutable receipt so stage
consumption cannot erase the evidence needed for validation. Every admitted
member's INSERT, UPDATE and DELETE queues a final check, including member
DELETE/reinsert; make early `SET CONSTRAINTS ... IMMEDIATE` plus later mutation
fail or revalidate the entire complete state. A final authorization seals the
stage against further funding/member writes. No caller can validate once and
then mutate an unguarded member before commit.

## 5. Canonical input, destination mapping and M2

Derive input from saved source plan and verified outcome, never client replay:
source metadata stays original; prepared metadata comes from verified outputs;
description, context, transforms and timeline/ordinal order stay saved. Parse
through the existing closed initial-input validator before funding. Preserve all
media indices and nonmedia timeline items. A video has source only.

The internal M1 allocator emits one ordered mapping per media ordinal: `index`,
source/prepared role, original backend/object ID, destination backend/object ID,
content type, byte count and SHA-256. Equal source/prepared identities and exact
byte metadata within an ordinal map to one destination. Distinct original
identities with equal bytes may share the ordinal's one destination only when
both role validations prove exact equality. Different ordinals never share a
destination. Every destination UUID is newly generated and disjoint from every
preparation object and other operation's registry. The full mapping and
unique-object union are digest-bound. M1 binding v2 stores the original expiry,
admission receipt identity, cutoffs and mapping digest.

Public allocation can only recover this original v2 cohort; it cannot allocate
or extend it. Existing v1 M1/M2 entry points reject v2 unless routed through an
explicit reviewed v2 branch. Copy uses the pinned adapter and exact mapping,
conditional writes and read-back. Lost replies recover/read the same destination
or make an identical conditional write within the original copy cutoff; there is
no new destination, transform or changed content. An uncertain mismatch holds.

M2 v2 has one original claim per admission, bounded by the saved verification
cutoff. An exact repeated claim returns its original token/deadline and no lease
renewal. A conflicting token or expired claim cannot reacquire. Verification may
read only the mapped destination union under the pinned validator. Settlement
requires the original claim and full binding/mapping/byte evidence, with final
locked validation strictly before the settlement cutoff. Its immutable receipt
becomes recoverable only when the transaction commits. Exact receipt replay
remains available after expiry; it is not copy or dispatch authority.

The transfer transaction checks that exact M2 receipt, live ownership, complete
admitted proof, unretired exact M1 union and transfer cutoff. It writes the
immutable transfer receipt first, then retires all original preparation objects
and deletes preparation-private intent/proofs. The receipt binds the complete M2
receipt and digest, admitted receipt digest, protocol artifact digest, full
destination union and `authorized_at_ms`. Receipt insertion is provisional until
the final locked complete-state/deadline validation and commit. That final
validation is the SQL linearization point; deferred constraints reject
retirement without the exact transfer receipt. Expiry waits on the retained
locks through commit/rollback. Neither physical commit time nor client
acknowledgement timing is represented as deadline evidence.

## 6. Ownership, erasure and recovery precedence

`initial_preparation_admission_receipts` has `(scan_id, owner_id)` primary key,
unique scan, and a composite FK to the submission with ON DELETE CASCADE. It
retains the full immutable original proof, resolved input, funding, phase
deadlines and M1 mapping. It has no FK to the erasable preparation intent.
`initial_preparation_transfer_receipts` has the same identity and ON DELETE
CASCADE FK to the admitted receipt; it retains complete M2 proof. Both are
private, RLS-enabled, no ordinary/service DML, bounded closed payloads. Digests
and source text are private evidence, not permanent-fence content.

Existing M1 cohort and M2 preparation/verification records remain subordinate to
the submission; their deletion guards must accept the same authorized erasure.
Permanent operation/source/destination fences and opaque retired registry IDs
survive, but no private receipt, text or text-derived digest does. Account
detachment explicitly erases submissions even when a scan is scientifically
retained. Before private rows cascade, retire both source and destination
registries in deterministic order. Delayed completion/copy cannot recreate them.

Every preparation status/action, finalizer, M1/M2 status, transfer and expiry
entry point follows this precedence under the canonical locks:

1. Live owner and deletion/account-removal checks; erasure wins over replay.
2. Existing cancellation/terminal fence; no private replay after erasure.
3. Exact committed transfer receipt: recover success even after original expiry.
   Automatic preparation or M1 expiry must not retire this destination cohort.
4. Exact committed admission: recover its original M1 binding and current phase;
   deadlines bound new actions. Unknown funding responses recover here, never
   invoke the funding owner again.
5. Unadmitted original preparation: normal original grant/outcome recovery or
   unfunded C1. No intent after transfer must never be misreported as a fresh
   missing/expired operation.

For the qualified branch, status recovery after those first three checks returns
the closed envelope
`{version: 2, outcome: "transferred", authority: "none",
scan_id, admission_receipt_digest, transfer_receipt_digest, binding}`.
`binding` is the exact M1 v2 binding, not newly reconstructed from catalogs.
This lookup precedes the old preparation-intent lookup. Repeated
source/issue/output/outcome actions after transfer return
`{version: 2, outcome: "held", authority: "none",
reason: "already_transferred", transfer_receipt_digest}`;
they never recreate an intent or grant. Admitted-but-not-transferred status
returns the closed
`{version: 2, outcome: "admitted", authority: "none", scan_id,
admission_receipt_digest, binding, phase}`
envelope, where phase is one of `copy`, `verification`, `transfer`, `expired`.
Expired is a recovery state, not new-work authority. No receipt-bearing response
is available after erasure. Reply schemas, SQL constructors and Deno/native
decoders must agree on these explicit unions; old v1 responders may not emit or
reinterpret them.

Phase classification clarification (IC-1, October 12): `phase` describes the
next unresolved handoff stage under its original deadline, not a time schedule
that implies work has happened. Until qualified copy/M2 progress records exist,
admitted recovery reports `copy` strictly before the saved copy cutoff and
`expired` at or after it; a pre-anchor observation rejects instead of asserting
expiry. Elapsed time alone never advances it to verification or transfer. Once
those owners exist, classification uses their original progress/claim/receipt
records and the deadline relevant to that state. Exact committed transfer takes
precedence even after expiry. `expired` grants no refund or retirement
permission and does not prove unused funding. Test cutoff equality and the
absence of synthetic progress across every later cutoff. This clarifies the
previously underspecified classifier; it does not claim a locked recovery
implementation or qualify the later owners.

Explicit user cancellation and deletion still apply to transferred operations
under the existing lifecycle owner. For explicit post-transfer cancellation,
load the self-contained admitted/transfer receipts instead of the deleted
preparation intent, then apply the same positive original-unused-reservation
proof and settlement owners specified below. That proof authorizes at most one
refund; otherwise the existing dispatched/unknown classifications apply without
refund. Retire M1 objects and erase submission plus both private receipts in the
same terminal transaction; original preparation objects are already retired.
Transfer wins only against automatic preparation/M1 expiry, not an explicit
cancellation request. It never substitutes for proof that a reservation is
unused.

Funded abandonment applies to admitted-but-not-transferred operations on expiry
or explicit C1, including a verified M2 receipt without timely transfer. Under
the existing C1 locks prove pending_pre_dispatch; exact original reserved quota,
owner/request/original scan and attempt 1; no commit/fail/refund timestamps,
refund count or stale recovery; exact submission/admission funding digest;
matching held complimentary allocation or no allocation; and no invocation by
scan or reservation, ingestion, result or completion. Also require the complete
admitted handoff proof. Only then call the existing quota-finalize refund and
complimentary `cancelled_before_dispatch` settlement owners. Their success,
terminal fence, both registry retirements and private erasure commit atomically.
Any mismatch rolls back settlement or follows C1's conservative unknown outcome;
it never invents absence or refunds uncertainty. A known dispatch uses existing
dispatched cancellation. Raw scan/account erasure remains conservative and does
not infer a refund from missing private rows. Failed/unknown transfers have no
success receipt and cannot defeat terminal cleanup.

## 7. Lock order and acceptance

Retain READ COMMITTED, owner row → ingestion advisory → scan/history → lifecycle
and original intent/submission/admission scope. Catalog locks use saved IDs,
NOWAIT on first acquisition, before funding writes. Preserve existing quota
request, reservation, counter and complimentary settlement ordering; do not lock
complimentary usage ahead of the existing counter owner. After the existing
outer scope and funding locks, use this one total order: preparation
source/output registry union in UUID order → admitted receipt → transfer receipt
→ M1 allocation fence/cohort → M2 claim/verification receipt → destination
registry union in UUID order. Admission, transfer, C1, expiry and scan/account
erasure must acquire these in the same order, including validation reads that
lock objects. Source and output IDs share one preparation registry; never lock
them in separate role-dependent passes. Newly inserted rows stay in this order;
no path may acquire a missing outer/source lock after taking M1/M2. All entry
points take the same outer scope; cleanup claims only already-retired rows and
never acquire owner/catalog locks afterwards. No database lock is held across
storage I/O.

Implementation checkpoints first pin closed profile/budget and protocol
validators without enabling funding, then add atomic admission/writer proof,
then M1/M2 transfer/C1/recovery. Each needs exact-candidate review; no
checkpoint activates a partial lifecycle. Migration order follows those
dependencies. Each source change updates its canonical API/database/privacy
documents and tests.

Required evidence rows, all owned by history primary with independent review:

| Row             | Pass condition                                                                                                                                                                                               |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Protocol/budget | SQL/Deno closed vectors agree; old media never gains a suffix; overflow, missing qualification, alias limits, insufficient time and changed eligibility hold before grant/funding; no-media regressions pass |
| Funding         | Injection before/after each listed write rolls back all funding; exact original recovery after lost reply; aliases, raw DML, stage forgery/delete/replacement and second reservation/cohort reject           |
| Mapping/M2      | Exact whole union, order and alias tests; no extra objects or raw-video prepared role; conditional-copy recovery; original claim only; no renewal or transform retry                                         |
| Expiry/C1       | Both winners at every boundary, M2-without-transfer expires, timely transfer survives stale expiry, explicit cancellation still works; exact unused funding settles once; unknown never refunds              |
| Privacy         | Both deletion/detachment race orders before and after admission/transfer; no private evidence survives or resurrects; unrelated operations survive                                                           |
| Locks           | Effective nested-writer/FK/BEFORE-trigger inventory; deterministic two-session schedules for admission, transfer, expiry, C1, raw ingress and erasure                                                        |
| Candidate       | Focused tests plus full affected gates on frozen candidate, retained failures and exact manifests; independent correction re-review and IC-1 acceptance                                                      |
| External        | Adapter/backend whole-cohort qualification, durable restart and installed/device/hosted journeys remain unqualified until separately authorized evidence; final candidate CI waits for exact-push approval   |

These rows supplement the roadmap matrix; local tests do not mark external rows
qualified. S0, dispatch/result/completion integration, media-backed reanalysis,
native journeys and Field Trip's separately held consumer remain open.
Historical text reading and exact accepted-operation recovery are preserved;
fresh text-only admission, children and editors are superseded requirements.

## Appendix A. Mutation statements and effective trigger order

The read-only catalog inventory is from the existing 477-migration disposable
candidate matching accepted checkpoint `0a0d5bb10`: 10 effective function
signatures, 28 triggers and 121 columns/defaults, retained in the handoff
artifact directory. It includes dynamic replacements, not just the original
migration text. Relevant signatures are:

- C8:
  `internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)`.
- C4: `internal.reserve_ai_quota_core(uuid,text,uuid,text)`.
- Counter:
  `internal.consume_ai_quota_counter(text,text,text,timestamptz,integer,integer,text)`.
- Provider:
  `public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)`.
- Finalizer: `public.finalize_initial_preparation(uuid,uuid,text)`.
- Lifecycle trigger: `internal.record_initial_pending_state()`.
- Existing M1 reference:
  `public.allocate_initial_analysis_media(uuid,uuid,text,uuid)`; the new
  internal allocator owns its corresponding v2 statements.

Every expectation key starts with `(transaction_id, stage_token, scan_id)` and
adds the statement key below and row primary key. It is registered immediately
before its exact DML by that owner, after its normal decision. UUIDs and default
values are materialized once before registration: generated reservation/lease
IDs, transaction `now()` defaults and the owner's sampled `quota_now`. They are
then used unchanged by DML. SQL physical tuple fields such as xmin/ctid are not
application columns and are not serialized. The entire application row must
match; no unlisted column can change. For the user row, retain only ID and
entitlement counters, compare other OLD/NEW fields in the trigger without
copying personal/profile/authentication fields into the stage or evidence.

| Statement key                    | Exact relation / operation                      | Expected fields and trigger placement                                                                                                                                                                                                                                                                                                                                                                                        |
| -------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `C8.hold.insert`                 | complimentary_scan_usage INSERT                 | Original owner/scan, held state; held/created/updated at quota_now, reacquisition count 0, settlement fields null. Existing a0 barrier precedes other guards. The usage UPDATE/reacquisition branch is forbidden for this fresh operation.                                                                                                                                                                                   |
| `C8.epoch.update`                | users UPDATE                                    | Same owner; complimentary epoch +1 and entitlement_version +1 only, iff original hold was inserted. Existing BEFORE `bump_user_entitlement_version` computes the second increment. A new final `zz_` BEFORE guard validates after it; all other columns unchanged. None of the user INSERT/DELETE or unrelated-column AFTER triggers apply.                                                                                  |
| `C4.reservation.insert`          | ai_quota_reservations INSERT                    | One generated ID/lease, original request/user/operation; reserved, attempt 1, refunds/stale 0; quota_now timestamps, lease quota_now+10min; original aliases initially null until C8 attachment; projected policy/model/plan/tier/daily limit and post-hold entitlement version. Other nullable fields null, defaults exact. Existing a0 barrier then guard_insight_chat_execution_quota are validation-only for this route. |
| `Counter.daily.upsert`           | ai_quota_counters INSERT ON CONFLICT UPDATE     | Present only for nonnull daily limit; exact user_daily key, UTC day window, 86400s. New request_count 1 or locked OLD count+1 below limit; all key/window fields unchanged on update, updated_at transaction now().                                                                                                                                                                                                          |
| `C4.daily.link`                  | ai_quota_reservation_counters INSERT            | Original reservation plus exact daily counter composite key; no extra/default columns.                                                                                                                                                                                                                                                                                                                                       |
| `Counter.user.upsert`            | ai_quota_counters INSERT ON CONFLICT UPDATE     | Exact user_rate key, bucket and policy-computed window; same count/delta/default rule.                                                                                                                                                                                                                                                                                                                                       |
| `C4.user.link`                   | ai_quota_reservation_counters INSERT            | Original reservation plus exact user-rate counter composite key.                                                                                                                                                                                                                                                                                                                                                             |
| `Counter.ip.upsert`              | ai_quota_counters INSERT ON CONFLICT UPDATE     | Exact supplied private IP hash, ip_rate bucket and policy-computed window; same count/delta/default rule. Hash is never emitted in logs/evidence.                                                                                                                                                                                                                                                                            |
| `C4.ip.link`                     | ai_quota_reservation_counters INSERT            | Original reservation plus exact IP-rate composite key.                                                                                                                                                                                                                                                                                                                                                                       |
| `C4.remaining.update`            | ai_quota_reservations UPDATE                    | Only daily_remaining_after_reservation=max(limit-resulting daily count,0), or null with no daily limit, and updated_at=quota_now. Same original row; a0 then chat guard.                                                                                                                                                                                                                                                     |
| `C8.attachment.update`           | ai_quota_reservations UPDATE                    | Original scan/link/client protocol attachment, saved fallback, projected effective/subscription plan/tier/trial and post-hold entitlement_version, updated_at=core8 quota_now; existing values must match the original projection. Lease, ID, attempt, state and charges unchanged.                                                                                                                                          |
| `Provider.attempt.insert`        | identification_provider_attempts INSERT         | Exact reservation/attempt1 and complete saved provider/model/policy/binding/permission/profile/minimum+accepted protocol columns; created_at transaction now(). Existing conflict branch cannot create authority; any preexisting attempt denies new admission.                                                                                                                                                              |
| `Finalizer.submission.insert`    | initial_analysis_submissions INSERT             | Complete canonical input/config/funding/descriptions/assets columns and digests, original owner/scan/route. a0 barrier precedes guard_initial_analysis_submission; neither rewrites NEW.                                                                                                                                                                                                                                     |
| `Finalizer.admission.insert`     | initial_analysis_admissions INSERT              | Exact original reservation, version3 candidate/assignment/outcome/handoff proof and all admission digests. Explicit binding_version3 replaces default1. a0 then guard_initial_analysis_admission; AFTER record_initial_pending_state creates next row.                                                                                                                                                                       |
| `Lifecycle.pending.insert`       | initial_analysis_lifecycle_fences INSERT        | Original scan and pending_pre_dispatch only, registered by record_initial_pending_state immediately before INSERT. Existing guard_initial_lifecycle_fence validates transition without rewriting NEW.                                                                                                                                                                                                                        |
| `M1.fence.insert`                | initial_analysis_media_allocation_fences INSERT | Original scan/allocated; a0 first, existing state guard covers UPDATE/DELETE.                                                                                                                                                                                                                                                                                                                                                |
| `M1.object.insert[ordinal,role]` | initial_analysis_media_registry INSERT          | Fresh destination UUID, scan, saved backend; retired=false, marker_confirmed=false, claims null. One expectation per unique physical object; aliases do not insert twice.                                                                                                                                                                                                                                                    |
| `M1.cohort.insert`               | initial_analysis_media_cohorts INSERT           | Original owner/scan and complete v2 binding with exact union/digest. No new default expiry.                                                                                                                                                                                                                                                                                                                                  |
| `Handoff.receipt.insert`         | new admitted receipt INSERT                     | Full final original proof/funding/mapping; unique original identity; private final-state guard.                                                                                                                                                                                                                                                                                                                              |

Core4's existing-reservation replay/recovery UPDATE and reservation-counter
release/DELETE statements are not allowed by this protocol. C8 usage
reacquisition UPDATE is also denied. The existing ordinary paths retain those
behaviors; this exception never enters them. Core8's user trigger is the only
NEW-row rewrite found in the affected fresh-admission inventory. Its automatic
entitlement-version increment must be included in the precomputed post-hold
projection, not mistaken for a later change to the saved inference assignment.

Counter UPSERTs require special one-use handling: PostgreSQL can execute both
BEFORE INSERT and BEFORE UPDATE for one statement. Registration freezes the
counter key/limit/delta, not an unlocked old count. BEFORE INSERT checks the
proposed count=1 and key; on conflict BEFORE UPDATE checks the now-locked OLD
count, +1 delta and unchanged key/window. Consume the single expectation only in
AFTER INSERT or AFTER UPDATE for the winning write. Those guards must check that
the counter transition came from the original C4 charge, not accept any
registered arbitrary row. Deferred validation requires its one exact link and
computed original reservation effect. A shared counter may receive a later
legitimate operation's increment; that does not alter this operation's recorded
charge, and validation must not require a permanent global counter total.

New guards must register/consume expected images for each statement above,
without bypassing existing guards. The candidate must compare pg_trigger order
and definitions to this inventory. Newly found automatic mutation requires an
explicit matrix amendment and re-review; it is not implicitly authorized by this
appendix. Terminal C1 uses its existing refund/counter-release/complimentary
settlement owners under a separate positive terminal proof, never these
admission expectations. M2 and transfer use their exact receipt/claim predicates
and cannot reopen a consumed funding stage.
