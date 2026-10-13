# Admitted proof: closed component design, revision 4

Interface design accepted October 12, 2026 against
`69aa7ddf8dd3542eff27eb5d8525ce28afab1cc6`, under
[IC-1](initial-completion-history-interface-2026-10-11.md) and the
[alpha roadmap](identification-history-alpha-readiness-2026-10-11.md). IC-1 and
independent read-only review accepted revision 4, exact source SHA-256
`7cbda4c9bf4563c08677a37485a2fe24a852088b6cadaa84493616cd0705d52e`. This is
design acceptance. The inactive Deno codec, private SQL counterpart and shared
vectors now implement the pure validation boundary below. Private storage,
funded transaction, concurrency and erasure qualification remain open. The
history primary owns all writes. Activation remains disabled.

## Current implementation status — October 13, 2026

The historical design and incremental evidence below led to locally accepted
checkpoint `bc2a5af507a0ee56cbdb1a357f5221bec611371b`: coherent atomic
admission/original funding, M1, recovery, positive-unused C1 cancellation/expiry
and erasure. This dated note supersedes earlier pending implementation,
uncommitted-compositor and pending full-gate status, while preserving the
original design and intermediate evidence. Exact shared-checkout validation,
independent/IC-1 acceptance and disposal are recorded in
`.artifacts/initial-atomic-admission/final-gates/local-checkpoint.json`.
Stage93's original deadlocks remain unreproduced, cause unknown, under its
explicit residual-risk disposition; no fix or new-lock qualification is claimed.
This is not isolated commit-tree, hosted, media-transfer, provider or full S0
acceptance. The next
[dispatch-fence agreement](initial-dispatch-fence-interface-2026-10-13.md)
remains a draft; activation and external-operation restrictions are unchanged.

## Storage and commitment

Use one private immutable receipt row with eleven mandatory canonical TEXT
columns and one canonical manifest TEXT column. No nullable component, dynamic
component name, extensible map, generic JSON payload, external blob reference,
or independently visible member row exists. Store original bytes; do not
reconstruct a missing component from a hash, mutable table or current catalog.
The opaque receipt UUID is allocated before mapping; no nested component
contains the eventual receipt digest. All component digests and lengths are
recomputed before insert, on deferred verification and before private recovery.

The manifest has exactly these keys:

- `version: 1`, `owner_id`, `scan_id`, `admission_receipt_id` (canonical UUIDs);
- `route` (`identify` or `identify-multimodal`), `input_schema_version: 1`,
  `binding_version: 3`, `funding_binding_id` (original reservation UUID),
  `authorized_at_ms` (existing nonnegative safe integer milliseconds);
- `metadata`, exactly `{mapping: Ref, media_binding: Ref}`;
- `proof`, exactly
  `{candidate: Ref, input: Ref, configuration: Ref,
  funding: Ref, outcome: Ref, installation: Ref, protocol: Ref,
  destination: Ref, accounting: Ref}`;
- `metadata_digest`, `proof_digest`, `assignment_digest`, `phase_window_digest`,
  `descriptions_digest`, `assets_digest` (lowercase 64-hex).

`Ref` is exactly `{digest: <64-hex>, byte_count: <positive safe integer>}`. Its
name fixes its domain and maximum; callers cannot supply a domain or schema
selector. `metadata_digest` commits the canonical `metadata` object;
`proof_digest` commits the canonical `proof` object. Their domains are
`merian.initial-analysis.handoff.admitted-metadata.v1\n` and
`merian.initial-analysis.handoff.admitted-proof.v1\n`. The final receipt digest
uses `merian.initial-analysis.handoff.admitted-receipt.v1\n` plus exact
canonical manifest text, excluding the receipt digest itself. These domains are
implemented by the inactive Deno codec. References are commitments to mandatory
co-retained complete bytes, never a digest-only recovery substitute.

| Column/component | Exact closed value and digest owner                                                                                        | Maximum canonical UTF-8 bytes |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------: |
| candidate        | Existing media source candidate v2; existing preparation-candidate v2 digest                                               |                     1,048,576 |
| input            | Existing exact projected initial input v1; input v1 digest                                                                 |                     1,048,576 |
| configuration    | Exactly `{version: 2, assignment: <original media assignment v3>}`; configuration v1 digest                                |                        65,563 |
| funding          | Existing `{version: 1, original: <all twelve fields>}`; funding v1 digest                                                  |                         4,096 |
| outcome          | Existing qualified outcome v2, including original grant/source/output/resolved/profile/retained entries; outcome v2 digest |                       131,072 |
| installation     | Original handoff installation v1; installation v1 digest                                                                   |                        16,384 |
| protocol         | Original handoff protocol artifact v1; protocol_artifact v1 digest                                                         |                        16,384 |
| destination      | Original destination backend closed catalog shape; destination_backend v1 digest                                           |                        16,384 |
| mapping          | Existing admission mapping v2; mapping v2 digest                                                                           |                        65,536 |
| media_binding    | Existing admission media binding v2; media_binding v2 digest                                                               |                        16,384 |
| accounting       | Closed accounting v1 below; new handoff accounting v1 digest                                                               |                        32,768 |
| manifest         | Exact manifest above; admitted-receipt v1 digest                                                                           |                         8,192 |

The configuration ceiling is the original 65,536-byte assignment ceiling plus 27
bytes for its exact canonical wrapper. The assignment is retained once, at
`configuration.assignment`; its separately computed existing assignment digest
keeps its current v2 domain even though the shape version is 3. The original
preparation profile is retained once at `outcome.profile`, and the handoff
profile once at `configuration.assignment.handoff.profile`. The phase window is
retained once at `media_binding.phase_window`. Source verification, grant,
output and resolved manifests remain their exact existing outcome subtrees.
Standalone canonicalization of a subtree preserves original canonical bytes. Do
not retain a second configurable interpretation or shorten these schemas.

Complete independently hashed input and configuration bytes remain mandatory.
The candidate cannot replace the input merely because projection is possible.
The installation, protocol and destination bytes permit full original catalog
validation without substituting current selectors. Catalog eligibility may still
deny new phases; it cannot replace saved identity or prevent terminal status
recovery. Archive executable availability remains separately checked; these
metadata bytes do not constitute an installed adapter or credential.

## Accounting v1

The object has exactly `version: 1`, `reservation`, `attempt`, `charges`, and
`complimentary`. New digest domain:
`merian.initial-analysis.handoff.accounting.v1\n`.

`reservation` has exactly `reservation_id`, `owner_id`, `scan_id`,
`attempt_count: 1`, `lease_token` (UUIDs except count), and `lease_expires_at`
(the exact timestamp type below). ID/owner/scan/count equal the manifest,
funding and current locked original reservation at admission. The lease is
historical evidence only, never returned as a new dispatch grant.

`attempt` has exactly `reservation_id`, `attempt_count: 1`, `operation`,
`effective_plan`, `model`, `policy_version`, `provider`, `binding`,
`processor_permission`, `input_profile`, `provider_model`,
`minimum_client_protocol`, `accepted_client_protocol`,
`minimum_identification_protocol`, `accepted_identification_protocol`. These
preserve the effective attempt table's nullability and scalar constraints AND
the saved assignment's stronger coupled semantics; satisfying only one is
insufficient. `model` equals assignment `quota_model`; selection/protocol fields
equal the original assignment. Integer values must fit existing safe canonical
integers; no bigint rounding. `created_at` is validated as a full expected
INSERT image in the temporary stage, not retained as selection authority.

`charges` has exactly `policy` and `links`. `policy` has exactly `operation`,
`effective_plan`, `policy_version`, equal to original funding and attempt.
`links` is the exact ordered two- or three-member array. Every member has
exactly `reservation_id`, `scope_type`, `scope_key`, `bucket`, `window_start`,
`window_seconds`, `delta: 1`. `scope_type` is one of `user_daily`, `user_rate`,
`ip_rate`; exactly one user_rate and one ip_rate, with zero or one daily. Order
is daily (if present), user, IP. No duplicate or missing link, different
original reservation, reassigned key or invented amount is accepted. User/daily
key is the exact owner UUID string; IP key is exactly 64 lowercase hex from the
original trusted IP hash. The proof is private.

`bucket` is a nonblank scalar string, proposed maximum 1,024 UTF-8 bytes,
without normalization. This is a NEW qualified-policy eligibility bound, not an
existing table constraint (tables have only nonblank checks). A policy outside
this bound must be ineligible before preparation allocation or costly work;
admission rechecks the current locked policy against the saved assignment and
exact expected charges. The policy row is mutable and policy_version is not a
content hash. This proposal explicitly accepts same-version bucket/window/limit
changes when the current locked policy remains allowed/enabled, within these
bounds and consistent with every saved assignment model/plan/version/permission
comparison. It freezes that current policy decision once in the temporary stage
before the first write; core8 and core4 must use the same decision. The durable
footprint records the actual charges under that decision, not an invented
historical policy body. An out-of-bound, missing, disabled or
assignment-inconsistent current policy yields a configuration-changed hold
before any funding/counter/complimentary write, even if preparation already
finished. No remint, current-model fallback, automatic version rewrite or
repeated preparation follows. Exact replay and C1 compare original retained
charges and never re-evaluate a current policy. This is an explicit
configuration-drift boundary, not a guarantee that prepared work stays
admissible through policy changes. No post-execution truncation or silent bucket
substitution is permitted. The new eligibility check and drift behavior require
implementation/review with the coherent funded owner; it is not permission to
mutate existing policy data. `window_seconds` is integer 1..86,400; daily is
exactly 86,400; user/IP windows also satisfy the policy limit1..3,600. Window
identity comes from the same server reserve timestamp and frozen current policy
in the expected transition, not from a second clock or a current policy read
during recovery. `window_start` uses the timestamp type below. Counter totals,
updated_at and remaining quota are NOT retained. Fresh owner inserts/increments
exactly one for each member and inserts that exact link set. Full OLD/NEW images
prove it.

`complimentary` is either null or exactly
`{owner_id, client_scan_id,
classification: "pro_complimentary", state_at_admission: "held"}`.
Null requires funding's complimentary_client_scan_id null and no linked
allocation; otherwise owner and scan equal original funding and effective plan
is pro_complimentary. Existing allocation reacquisition/entitlement semantics
remain owned by core8, with full expected OLD/NEW validation; no additional hold
is introduced. Held-at-admission is historical. Later C1 checks the live hold
and existing settlement owner, never this field alone.

Funding retains exactly reservation_id, request_id, original_analysis_id,
operation, attempt_count, effective_plan, effective_tier, entitlement_version,
policy_version, model, complimentary_client_scan_id and flash_fallback_used.
Admission requires request_id=original_analysis_id=scan, operation
scan_identification, count 1, and every saved-assignment/funding comparison
already required by the existing owner. Full user rows, xid/token, daily
remaining and shared totals never enter this durable proof.

## Exact timestamps

Use fixed 27-character UTC strings `YYYY-MM-DDTHH:mm:ss.ffffffZ`, years
0001–9999, valid Gregorian dates, hours 00–23, minutes/seconds 00–59, exactly
six fractional digits. Reject infinity, BC/out-of-range years, offsets,
leap-second spelling, missing zeroes and invalid calendar dates. PostgreSQL
formats the unchanged TIMESTAMPTZ at UTC with microsecond precision and verifies
exact round trip; Deno validates calendar/string components without a
millisecond Date roundtrip. No floating epoch conversion or millisecond
truncation. Lease and counter window timestamps use this type. Existing
millisecond handoff phase deadlines remain distinct types; their protocol does
not redefine quota timestamps.

## Cross-component proof and transaction boundary

The fixed temporal sequence is:

1. Before preparation allocation/cost, check policy bucket encodability and
   original profile/consent eligibility. At admission, lock current
   policy/consent/profile eligibility under the agreed outer scope and compare
   against the saved assignment. Freeze one prospective funding/entitlement
   decision before any write; core8 and core4 cannot select again or fall back.
2. Before its authorized writes, the original owner materializes each
   reservation UUID, lease, timestamp and full expected OLD/NEW transition
   exactly once. The counter window computation uses that one reserve timestamp.
   The current owner may generate values here; a second allocator, clock or
   fabricated already-existing accounting record is forbidden.
3. After original core8/core4 writes, re-read and verify the complete actual
   original reservation/attempt/link set against those materialized images and
   the frozen bounded policy. Construct the funding/accounting components from
   these exact originals. Any discrepancy or bound violation rolls back every
   hold/charge/write; report the closed configuration hold without retrying
   funding.
4. Insert all eleven components and manifest, perform M1 and the other agreed
   intended writes, force complete-set/deferred checks, then seal/consume the
   stage and finish with the last nonmutating cutoff check. No independently
   callable funding-only or M1-only success escapes.

Existing components are decoded and immutable snapshots captured individually
before the first await. The accounting/funding values are finalized only after
their original owner materializes them. Do not call initialCanonicalText on a
new aggregate wrapper containing all texts or parsed components: each keeps its
own 1 MiB/depth 12/nodes 4,096 guard. Component-wise snapshot validation must
preserve exact bytes and all existing semantic checks.

Derive original qualification context from candidate, configuration.assignment,
outcome.profile, installation, protocol and destination; validate the complete
outcome and its source/grant/output/resolved/profile/retained associations.
Validate existing metadata against that context, original expiry and manifest
scope. Project input from the exact candidate and outcome; compare canonical
bytes with stored input. Require configuration's exact wrapper and all funding,
attempt, charge, permission/protocol and entitlement decisions to match the
pre-funding comparison and actual expected inserts. Recompute descriptions and
assets digests, input route/schema, assignment/outcome IDs and every metadata
scope/reference. `authorized_at_ms` is sampled by the server under the accepted
locks and strictly before the saved admission cutoff. Receipt identity is never
caller-selected authority.

The fixed digest prefixes below include one final newline and are prepended to
the exact canonical component bytes before SHA-256. Names fix domains, not
caller strings:

| Ref                    | Prefix (followed by newline)                             | Exact equality                                                                                                  |
| ---------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| proof.candidate        | merian.initial-analysis.preparation-candidate.v2         | configuration.assignment.candidate_digest                                                                       |
| proof.input            | merian.initial-analysis.input.v1                         | admission.submission_digest and media_binding.submission_digest                                                 |
| proof.configuration    | merian.initial-analysis.configuration.v1                 | admission.configuration_digest                                                                                  |
| proof.funding          | merian.initial-analysis.funding.v1                       | admission.funding_digest                                                                                        |
| proof.outcome          | merian.initial-analysis.preparation-execution.outcome.v2 | mapping.outcome_digest and media_binding.outcome_digest                                                         |
| proof.installation     | merian.initial-analysis.handoff.installation.v1          | configuration.assignment.handoff.installation_digest and media_binding.phase_window.handoff_installation_digest |
| proof.protocol         | merian.initial-analysis.handoff.protocol_artifact.v1     | configuration.assignment.handoff.profile.protocol_artifact_digest and the same saved phase-window field         |
| proof.destination      | merian.initial-analysis.handoff.destination_backend.v1   | configuration.assignment.handoff.profile.destination_backend_config_digest                                      |
| metadata.mapping       | merian.initial-analysis.handoff.mapping.v2               | media_binding.mapping_digest                                                                                    |
| metadata.media_binding | merian.initial-analysis.handoff.media_binding.v2         | the original admitted M1 binding association                                                                    |
| proof.accounting       | merian.initial-analysis.handoff.accounting.v1            | exact actual original reservation/attempt/charge proof                                                          |

Every byte_count equals octet length of that exact co-retained canonical TEXT.
Manifest assignment_digest equals the current assignment v2-domain hash of
canonical configuration.assignment, and all assignment_digest fields in outcome,
mapping, media_binding and nested original receipts. Phase_window_digest equals
the existing phase_window v1 hash of media_binding.phase_window and its
media_binding.phase_window_digest. Descriptions_digest equals the existing
descriptions v1 hash of exact input.ordered_descriptions and
admission.descriptions_digest. Manifest assets_digest equals
configuration.assignment.asset_manifest_digest and admission.assets_digest; the
retained configuration archive must resolve that exact assets-domain identity,
not the current rollout on replay. At fresh admission the existing locked
configuration/rollout checks still apply.

Manifest owner/scan/receipt UUIDs equal mapping and media_binding scopes
(including its phase window), accounting reservation and original trusted
operation scope; outcome and all nested receipt scan IDs equal scan. Manifest
route equals candidate.source_plan.route, input.route and
configuration.assignment.route; schema1 equals input.schema_version and
candidate.source_plan.schema_version. Funding_binding_id equals
funding.original.reservation_id, accounting.reservation.reservation_id and
accounting.attempt.reservation_id. Funding request_id and original_analysis_id
equal scan. Binding_version3 selects only this complete qualified-media case;
source-null or older versions cannot fall through. Mapping source/destination
generations equal the original configuration/profile and destination component;
full existing validators enforce index, bytes, object alias and phase
equalities, not just these hashes. Lifecycle pending_pre_dispatch is checked at
original admission as a fact; no replay can recreate it over a terminal/deletion
fence.

Temporary private stage retains complete expected OLD/NEW images for user,
complimentary, reservation/core8 attachment, counters and links, provider
attempt, submission/admission/lifecycle, M1 fence/cohort and registries. Its
xid/token/phase is not a freely settable GUC authorization. The validated
allocated-to-consuming transition acquires the transaction denial seal before
ordered child consumption and guarded parent deletion. Then the completion owner
forces all deferred checks and finishes with the last nonmutating cutoff check.
Durable complete proof remains available after stage consumption, including
under early SET CONSTRAINTS. All intended writes roll back if an expected
member/image/set or last clock check fails.

The deferred predicates establish consistency, not elapsed-time eligibility.
Every callable admission owner must route through the completion owner and its
final deadline sample; source-routing contracts and the callable-owner inventory
must prove this before public integration. Direct private lower-level proof
probes are not deadline-qualified admissions. If a caller catches a failed final
cutoff, the restored incomplete stage must still prevent funding from
committing. Repeated full-proof decoding across the event queue also requires
separate capacity qualification; small-fixture correctness tests do not
establish it.

Retained-proof integrity is a separate private check: validate all original
components and the receipt digest, bind the canonical manifest's owner, scan and
receipt UUIDs to the typed receipt row and captured identity, and compare the
immutable submission/admission rows exactly. It must not reconstruct evidence
from current quota, preparation intent or source rows. This check alone proves
neither live ownership nor action eligibility. Recovery owners still apply the
canonical locks, erasure/cancellation/transfer precedence and closed status
projection; unused-funding settlement separately requires current positive
proof.

## Allowed mutation matrix after stage consumption

| Surface/event                                                               | Permitted effect and required proof                                                                                                                                                                                                                   | Denied                                                                                                                                                   |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Same admission transaction after early SET CONSTRAINTS or stage consumption | Reads and final nonmutating validation only after completed intended writes; deferred guards can resolve full durable bytes                                                                                                                           | Any member/link insert, update, delete or delete/reinsert outside exact expected transition; receipt presence or GUC alone is insufficient               |
| Receipt/components while private ownership is live                          | Exact read/replay after ownership, deletion and terminal checks                                                                                                                                                                                       | Partial component writes; UPDATE; missing/swapped/altered bytes; reconstruction from current rows; return of raw private proof to ordinary clients       |
| Original reserved reservation/attempt/links                                 | Unchanged identity/lease/selection and original exact live link set; shared counters may change under unrelated legitimate operations                                                                                                                 | Lease/attempt reacquisition, provider reselection, link PK update/rebinding, independent deletion/reinsert, using pruned counter absence as unused proof |
| Positive unused C1/expiry cancellation                                      | Locked original funding/lease/attempt, pending lifecycle, zero stale/refund counts, no ingestion/invocation/result/completion, live linked hold; existing quota release and complimentary owner settle once, then terminal fences and private erasure | Timeout-only or absence-only refund; stale/missing/changed proof; second allocation or attempt; legacy sweeper bypass of initial fences                  |
| Future provider dispatch/commit/result/completion                           | Remains blocked in this increment. A later separately reviewed S0 owner may consume links on commit, preserve charged counters, and settle under original authority                                                                                   | Enabling it from receipt/status existence; premature committed/failed transition; restoration of pending lifecycle                                       |
| Legacy expiry/retry/recovery workers                                        | Continue for unrelated operations; new initial operations remain excluded and route only through reviewed C1                                                                                                                                          | Treating a generic legacy release/retry owner as permission to touch an active new initial operation                                                     |
| Merge/detachment                                                            | Preserve existing multi-owner barriers; no active proof reparenting. Authorized detachment/deletion serializes and erases private proof                                                                                                               | Source→destination owner or reservation remap; collision recovery retaining only hashes or replacing funding                                             |
| Terminal pruning                                                            | Only after reviewed terminal settlement and no active private proof dependency; existing unrelated pruning unaffected                                                                                                                                 | Cascading away live proof/accounting to manufacture unused status; keeping a manifest after components disappear                                         |
| Scan/account erasure                                                        | Same transaction fences resurrection, retires both registries, erases every component, manifest, digest and private scope key; content-free allowed fence only survives                                                                               | Delayed recreation, receipt recovery after erasure, scientific retention of these private bytes/digests                                                  |

The immutable footprint records admission-time charges. It does not freeze
shared totals or imply links must survive permitted terminal settlement forever.
Absent counters/links are never recreated. If positive unused proof cannot be
established, preserve a held/unknown terminal outcome without refund. Actual
trigger/FK/function lock sequences and deterministic races remain required in
the implementation checkpoint; this matrix is not a concurrency proof.

## Bounds evidence and acceptance

`.artifacts/initial-admitted-proof/boundaries-3.json` and
`.artifacts/initial-admitted-proof/measure-boundaries.ts` retain synthetic
measurements: plain and maximally escaped descriptions each produce a valid
1,048,554-byte candidate and 1,048,576-byte projected input; wrapping both
rejects. These are candidate/input boundary witnesses, not end-to-end qualified
assignments. Independent schema traversal conservatively allows all branches
simultaneously: candidate659 nodes/depth5, input667/depth 4, assignment301/depth
6, outcome498/depth 6, mapping199/depth 5, media binding30/depth 3.
Configuration adds two nodes/one level to assignment; none approaches 4096nodes
or depth12.

The eleven component ceilings sum to 2,461,723 bytes; adding the 8,192-byte
manifest gives an explicit 2,469,915-byte retained canonical TEXT ceiling per
receipt. This is a conservative sum of individual enforced ceilings, not a claim
every maximum can coexist. It excludes database/index/TOAST overhead and
temporary validation allocations; no disk or memory estimate follows from it.
The 1MiB canonical serializer limit is unchanged for each component and
manifest. No giant aggregate JSON serialization or RPC payload is introduced by
this storage design. A future transport requires its own bounded contract.

Codec qualification requires exact golden/negative vectors for all component
roles and cross-links, per-component and aggregate limits, non-BMP and escaped
Unicode, maximal supported media topology, missing/extra/swapped components,
integer edges, timestamp precision/invalid calendar inputs and full snapshot
mutation resistance. Before runtime acceptance, test complete-set insertion and
erasure rollback; early constraint forcing then post-stage mutation; C1/expiry,
prune, merge, scan/account races; exact recovery after lease deadline; and all
existing affected gates on the scoped candidate. No old suite is rerun merely
because this design document changed.

Revision 3 corrects a sizing error in revision 2: three1,024-byte bucket strings
can each expand sixfold under JSON escaping. The accounting cap is 32,768 bytes,
with the conservative scalar bound measured separately. Revision 2 and its
evidence remain historical; no implementation used that cap.

Revision 4 makes policy-content drift and the before-write/after-write
accounting phases explicit in response to IC-1. The fixed 1024raw-byte bucket
ceiling is retained with the larger proven accounting cap. IC-1 and independent
review subsequently accepted the exact revision as recorded above; runtime
policy eligibility is still unimplemented.

The conservative maximum accounting scalar object is 22,541 canonical bytes/60
nodes/depth 4, including three maximally escaped buckets and the nonnull
complimentary branch. The maximum manifest uses all eleven fixed refs at their
component caps plus every identity/digest. These are structural upper-bound
objects, not assertions of coupled provider/policy validity. See
boundaries-3.json for the exact measured manifest result.

Active pre-settlement link equality is required through the initial transition
and for positive-unused C1 proof. After a reviewed terminal settlement, the
accounting footprint is historical: legitimate link absence/deletion is neither
a replay corruption by itself nor proof of non-execution. Status still resolves
the original terminal fence; the storage policy never reconstructs links or
restores pending authority. Any retained live private receipt still requires its
complete canonical components until their atomic authorized erasure.

## Inactive Deno codec checkpoint

`admittedProof.ts` validates eleven complete original canonical TEXT components
and the fixed manifest without serializing them together. Shared schema and
synthetic fixtures cover media cohorts, cross-component identity and integrity,
accounting, microsecond timestamps and large exact Unicode text. Independent
review and candidate gate evidence are recorded under
`.artifacts/initial-admitted-codec/`. This is not a receipt issuer or live
recovery owner. The private SQL counterpart is described below; the complete
funded transaction remains next. The codec cannot qualify locked policy, actual
database rows, original archive availability, terminal/erasure fences or
external operation merely from internally consistent retained bytes. Funding
model means the returned effective provider model; the attempt and underlying
reservation retain the quota-policy model.

## Inactive SQL parity checkpoint

The forward SQL implementation now mirrors the complete Deno proof using twelve
fixed canonical TEXT parameters, returning the receipt digest only. It reuses
specialized context/metadata validators and enforces component bounds, exact
UTF-8 commitments, funding/accounting coupling and Gregorian microsecond
strings. Its four private invoker helpers have all API-role execution revoked.
The schema and golden/negative fixtures remain shared with Deno; source and
candidate qualification evidence belongs to `.artifacts/initial-admitted-sql/`.
This supersedes the historical SQL-parity-next status only. Receipt storage,
original-row locks, atomic funding, recovery, completion and erasure are still
unimplemented by this slice, and activation remains disabled.

### Defensive settlement boundary while admitted C1 is incomplete

The prepared migration excludes admitted media from the legacy C1 funding-only
refund predicate and rejects a raw pending-to-cancelled-pre-dispatch lifecycle
UPDATE. Detection uses either a v3 admission, its private receipt, or the
conjunction of permanent preparation-source and M1-allocation fences. Those
fences survive private erasure. The conjunction is deliberately conservative: it
also holds an older prepared-media operation with both fences, not only a proven
v3 lineage. Direct M1-only and unfunded source-only operations do not match that
conjunction.

Generic quota-core commit/fail/refund and held complimentary settlement are also
denied for this boundary, including after private erasure. The existing public
quota wrapper may reject earlier with `initial_analysis_execution_required`; the
private settlement fence uses `initial_analysis_settlement_unavailable`. Neither
an elapsed deadline nor deletion of private proof opens settlement. Existing
explicit cancellation uses conservative unknown (or known-dispatched)
classification, preserves accounting, retires both registries and erases private
components. Exact cancellation replay cannot refund or recreate admission.

This is a temporary denial boundary, not positive-unused C1 implementation or
successful completion. The dedicated C1 owner must prove complete original
unused state and exact original settlement under ordered locks before granting a
pre-dispatch terminal transition. Its review must replace the defensive hold
with proof-bearing authority, never a caller-controlled bypass. Automatic
expiry, authoritative account/scan qualification and full candidate gates remain
open; activation stays disabled.

### Private cancellation prestate capture

The revoked `capture_initial_admitted_cancellation_prestate` helper captures
original rows under the cancellation owner's user/scan scope and ordered
accounting, source, receipt and media locks. It checks retained integrity and
live unused evidence separately, rejects missing or zero counters and any
invocation by scan or reservation, and retains exact private preimages plus
one-charge counter deltas. Complimentary absence is JSON null. No current
catalog selection or lease refresh occurs.

This covers only an admitted, pre-transfer operation with no M2 claim or
receipt. It does not qualify verified-M2 abandonment or post-transfer
cancellation. The returned snapshot is private, transaction-local and
`authority:none`; it must not be logged, transported or persisted as a reusable
authorization. A matching transaction ID alone does not establish provenance.
All existing settlement and lifecycle fences remain in force after successful
capture.

Cancellation locks submission before admission; recovery locks admission before
submission. Both hold the same outer user/scan locks first. This explains the
same-operation serialization, not a claim that all nested owners use one order
or that cross-owner/direct-writer concurrency is qualified. Future integration
must recheck and consume original evidence through the closed transition owner,
verify exact settlement postimages before terminal transition, and model counter
row deletion when the original release consumes its last charge. Complete
settlement, retirement, erasure, deferred proof and terminal protection remain
required before positive-unused C1 acceptance.

### Private settlement postimage comparison

`assert_initial_admitted_cancellation_settlement` compares the locked original
capture with the existing quota and complimentary owners' resulting rows. It is
revoked, non-mutating and grants no settlement, lifecycle or erasure exception.
It must run before private receipt cleanup. The original receipt must remain
unchanged and pass retained integrity; its accounting supplies the complete,
unique charge-link set. Each captured counter must match its original link key,
window and one-charge delta. Omitted, duplicated or foreign entries reject.

Successful comparison requires the exact original quota refund with one refund
count, no surviving reservation links, unchanged provider attempt, and exactly
one decrement of each linked counter. A counter whose original count was one
must be absent. Surviving counters use the existing release owner's transaction
clock; quota and credit use their distinct observed post-lock settlement clocks.
Clock regression fails closed. Held credit must be released with the original
failure reason and exactly one increment of both complimentary epoch and public
entitlement version: the existing users trigger increments the latter when the
epoch changes. No-hold requires both to remain unchanged.

The retained receipt authenticates original charge membership, not mutable
counter totals or caller-supplied snapshots and timestamps. The future closed
owner must obtain and bind these originals and transition witnesses itself.
Successful comparison alone cannot satisfy a guard, authorize cleanup or prove
that no later mutation occurred. Terminal retirement, erasure, immutable
deferred proof and protection after consumption remain separate required work;
all existing defensive settlement fences stay active.

### Private cancellation entry (rollback-only)

The prepared C1 entry stores one private transient row per transaction, keyed by
scan and unique `xid8`. Its only inputs are owner and scan. The insert guard
obtains the complete locked cancellation prestate itself and assigns the current
transaction ID. Non-null supplied proof or transaction identity is rejected; SQL
NULL/default is equivalent to omission and is overwritten. Table access and
trigger execution are revoked from all API roles, including `service_role`.

This increment has no public or private action wrapper and grants no settlement
or lifecycle exception. Arbitrary UPDATE, DELETE and TRUNCATE are denied. Its
deferred insert constraint always rejects completion, including forced immediate
checks, so the private snapshot cannot commit. Ordinary errors/savepoint
rollback erase the transient attempt. The future owner must acquire the
canonical outer scope before insertion and before any lower-order lock. It must
also enforce no second entry after proof consumption; the present row cannot be
consumed at all.

This is preparation for authentic capture, not cancellation qualification. The
original-owner clocks and exact winning write events, accounting-before-terminal
check, complete registry retirement/erasure, immutable deferred terminal proof,
and denial of late writes remain required before this rollback-only constraint
can be replaced. Snapshot bounds do not establish resource qualification.
Private proof must never be logged, transported, or persisted as recovery
authority.

### Original quota sampling site (rollback-only)

The original quota finalizer retains its admitted-settlement denial before its
clock sampling site. That sampling expression now calls a revoked hook. With no
current C1 entry it returns the ordinary wall clock. With an entry it requires
the original reservation, owner, lease, reserved state and refund intent. The
entry guard recaptures and compares the entire locked original prestate before
generating the timestamp internally and making the one-way captured-to-quota
transition. No caller timestamp is accepted; all identity/prestate fields stay
immutable. A repeated hook or a pre-armed stage fails instead of supplying a
reusable clock. The original owner uses that returned timestamp unchanged.

This binds the sampling seam only. It neither records winning accounting events
nor authorizes refund, lifecycle change or commit. The existing defensive fence
and unconditional deferred completion rejection remain in force. The clock does
not authenticate a raw equivalent mutation, and must never be used as a stage-
existence or phase-based action exception. Credit sampling, exact per-statement
BEFORE/AFTER witnesses, terminal erasure and deferred proof remain required.

### Closed quota statement witnesses (prepared, rollback-only)

The existing quota finalizer and counter-release owners now register each exact
statement immediately before its original DML and close it immediately after. A
private ledger derives the next statement from the authenticated cancellation
snapshot and original quota clock; callers cannot supply expected images. The
closed sequence is each original counter UPDATE followed by its zero-counter
DELETE, the unordered original link DELETE set, then the reservation refund.
Counter timestamps retain the original transaction time. Positive remaining
counters have an empty DELETE event set; zero counters require both winning
UPDATE and DELETE events. At most three original links produce eight statements.

Member BEFORE guards require the one pending exact relation/operation/OLD/NEW
image. AFTER guards consume that exact event once; closure requires the complete
set. Missing, duplicate, no-op, changed-image, extra and unregistered writes
cannot satisfy it. During the quota phase, unrelated accounting writes in the
same transaction are also denied. Ledger fields cannot be rewritten or erased;
member TRUNCATE is denied. Each failed owner statement rolls its registration
and observations back with the original writes.

IC-1 clarified the trust boundary: supported callers can request only the fixed
reviewed operation; all registration functions and ledger access remain revoked
from PUBLIC, anon, authenticated and service_role. Registration and original DML
remain inside the existing definer execution chain without returning control to
an API caller. PostgreSQL does not attest the source line or call stack of
administrator-issued equivalent SQL. A migration/object administrator can
assemble exact registered transitions or alter enforcement; such probes test the
protocol, not resistance to the trusted administrator. Before an action
exception, inventory all reachable definer/helper routes and ensure no ordinary
runtime role holds comparable bypass ownership.

This increment supplies quota event evidence only. The original defensive
settlement fence and unconditional deferred cancellation rejection remain
unchanged. Phase, clock or a closed quota ledger alone authorize nothing.
Original credit-clock/held-or-absent witnesses, terminal lifecycle, retirement,
erasure, immutable deferred proof and late-write protection remain required
before a successful C1 owner can exist.

### Original credit witnesses (prepared, rollback-only)

A separate private credit witness follows the completed quota ledger while the
cancellation stage remains in quota phase. This keeps all quota member guards
active through credit work. Its insertion checks unchanged captured credit and
owner projection, derives held versus absent, and generates a clock only for
held credit at the original settlement owner's sampling site. The existing
held-settlement fence remains effective and is checked before sampling too.
Absent credit has a NULL witness clock and no credit or owner events.

The original owner snapshots its locked usage lookup's FOUND into a local
Boolean before instrumentation and uses that Boolean in both held and previously
consumed branches. Fixed private begin/end steps surround the original release
and owner-epoch UPDATE statements. The user BEFORE guard sorts after the
existing entitlement-version trigger. BEFORE and winning AFTER images must match
the exact release and both epoch/version increments; all other user fields must
remain unchanged and are never retained in the witness. Missing, repeated,
out-of-order or rewritten events fail closed. API roles cannot register, mutate
or erase this witness.

Before returning, original result flags must match the held or absent branch,
and the complete existing accounting comparator verifies quota, original
provider attempt, counters, links, credit and owner projection while the private
receipt still exists. This is accounting evidence only. No lifecycle transition,
retirement, erasure, deferred terminal owner, expiry or action exception is
introduced. The unconditional deferred cancellation rejection still prevents a
successful commit; activation remains disabled.

The credit member trigger uses a fixed SECURITY DEFINER boundary with empty
search_path and revoked API EXECUTE. Ordinary permitted users writes must not
need SELECT on private cancellation staging just to take the no-stage path. No
private-table grant or callable snapshot helper is introduced. Existing table
privileges and RLS still govern whether the original row operation may run; the
trigger only validates its fixed accounting event and internal witness. The
permitted authenticated owner's marketing_opt_in column UPDATE is covered
separately from definer settlement-owner tests. In the fresh catalog,
service_role has no users UPDATE grant; that existing ACL boundary is preserved
and is not evidence of this trigger's regression.

### Lifecycle event witness (prepared, rollback-only)

The next private witness brackets only the existing cancellation owner's
lifecycle UPDATE. With no C1 stage its hooks do nothing, preserving ordinary
legacy cancellation behavior. With a stage it requires the original owner, scan
and current transaction, closed quota statements and a complete held or absent
credit witness. Before beginning, it compares the complete captured pending
lifecycle tuple and reruns receipt-dependent accounting validation. The expected
transition preserves the tuple except for state becoming cancelled_pre_dispatch;
no supplied image or clock is accepted.

A BEFORE guard requires the exact pending event. Winning AFTER records that same
full OLD/NEW event once; the end hook requires the observed event and exact
current terminal tuple. Missing, suppressed, rewritten, repeated and unrelated
lifecycle events fail. Main stage stays quota, keeping quota/credit guards
active, and the completed lifecycle witness denies later writes. Witnesses
cannot be deleted or truncated. No-stage table privileges remain unchanged.

This adds evidence without opening the admitted lifecycle transition fence or
unconditional deferred rejection. Positive lifecycle tests substitute the
existing defensive predicate only inside trusted rollback fixtures. A lifecycle
witness alone authorizes neither erasure nor successful return/commit. Both
registry retirements, private erasure, the later cancellation receipt and
immutable deferred terminal evidence still require their complete protocol and
caller review. The current cancellation owner inserts its minimal receipt after
submission and preparation-intent deletion; this increment does not reorder it.

### Registry retirement witnesses (prepared, rollback-only)

The retirement protocol retains separate source and destination witnesses, in
that order, while the main stage stays quota. First entry requires completed
accounting and lifecycle evidence, exact current terminal lifecycle and a fresh
receipt-dependent accounting comparison. Full current sets must match captured
original allocated/live preimages; pre-retired objects, claims and markers are
rejected. The source union includes raw sources and prepared outputs. Membership
counts are bounded before aggregation (16 source/output objects, ten
destinations). Those limits bound witness allocation, not full resource
qualification.

The original retirement functions retain their fence-first and UUID-ordered
registry updates. Expected events preserve every field except fence state or
registry retired. BEFORE matches the next full image; winning AFTER appends it
once, and end requires all events plus exact surviving full-set postimages.
Missing, additional, suppressed, rewritten and out-of-order effects deny.
Completed witnesses and all earlier accounting/lifecycle guards remain active.
Original cleanup metadata and permanent object/backend identity remain intact.

Repeated original retirement calls can occur through later erasure triggers.
With a completed witness they must prove exact permanent postimages and produce
zero row effects; they do not reread erased receipts. New cleanup claims, marker
acknowledgements or unrelated media writes in that transaction remain denied.
No-stage legacy retirement callers keep their original behavior.

This is logical retirement evidence, not physical storage deletion, worker
cleanup authority, late-upload qualification or supported C1. The existing
admitted action fences and unconditional deferred rejection remain closed. There
is no new compositor or public cancellation branch. The private erasure owner
below requires both original retirement functions to complete before removing
private proof. The later terminal owner must preserve immutable evidence, final
cancellation receipt, deferred validation and a denial seal through commit.

### Private erasure images (prepared, no deletion authority)

The capture prerequisite freezes all 15 operation-owned private cascade
relations at an authentic C1 entry, including explicitly empty downstream
result/completion and M2 sets. Submission and preparation-intent are separate
roots. The former owns admission, admitted receipt, media
cohort/preparation/verification and result/completion; the latter owns source
mapping/verification, execution grant, output manifest/mapping and outcome.
Shared configuration assets and permanent operation/lifecycle/source/destination
fences and registries are not private cascade targets. Capturing their
references never transfers ownership.

The source mapping is locked at the original source-capture boundary. A fixed
private catalog permits at most 8 rows for each ordinal mapping and 1 for each
other relation. Indexed count preflight uses limit+1; a separate byte preflight
bounds each relation to 32 MiB and the full image set to 64 MiB before JSON
aggregation. The existing 64 MiB full-prestate bound still applies. These are
closed capture limits, not resource or performance qualification. Shared assets
keep their existing immutable content/identity binding without new late locks.

Each captured relation has a full-row array even when empty. Outside the exact
private root protocol below, all private mutations remain denied during the
authentic stage, including insertion into initially empty relations. No-stage
paths retain their existing guards. Capture alone grants no deletion, lifecycle,
settlement or deferred-completion exception.

The private erasure protocol below establishes current-xid context before either
root DELETE, observes exact unique full-OLD events across each actual cascade,
and verifies complete target-scoped absence. Later terminal evidence must
survive without rereading erased receipts. Existing retirement UPDATE side
effects must be zero-write reentry after completed retirement witnesses. The
stage cannot be consumed until an effective late-write denial seal survives its
removal. Actual role/no-stage erasure regressions and the complete caller
inventory remain required before public C1 acceptance.

### Ordered private erasure (prepared, uncommittable)

A revoked root owner now prepares submission-then-intent deletion under the
original authentic stage and its held row locks. The first witness requires
complete quota, credit, lifecycle and both retirement witnesses, unchanged full
private images and a final receipt-dependent accounting comparison. It freezes
surviving accounting postimages before submission cascades remove the receipt.
The intent witness requires completed immutable submission evidence, complete
submission-closure absence, exact remaining intent images and unchanged
surviving accounting/lifecycle/retirement facts. It never rereads the erased
receipt.

Expected events derive solely from the fixed catalog and frozen full OLD rows.
BEFORE accepts only an exact, unique, unobserved DELETE in the active root;
winning AFTER records its index once. FK cascade order within a root is not a
contract. Root completion requires every expected index and exact absence of
every root member, including originally empty relations. Inserts, updates,
truncation, cross-root effects and later private recreation remain denied.
Original source/destination retirement triggers must reenter with exact
permanent postimages and zero writes. Provider-attempt mutations are denied once
erasure begins; earlier accounting guards remain effective in quota phase.

The reviewed bounded incoming-FK/trigger trace found only the catalogued
cascades and original source/destination retirement side effects. Shared
configuration assets, operation fences and unrelated staging records are not
deletion targets. This trace is not the complete transitive/dynamic runtime
caller inventory still required before a public action exception.

This is a private, rollback-only protocol with unconditional deferred rejection.
No public cancellation branch calls it and no terminal consumption exists. Full
OLD images and accounting snapshots must not survive a successful commit. The
later complete owner must atomically write the minimal cancellation receipt,
verify immutable terminal proof, consume transient witnesses and retain an
unavoidable denial seal against later writes. Activation and ordinary access
remain disabled; this increment grants neither supported C1 nor M2 authority.

### Minimal cancellation receipt (prepared, uncommittable)

After both private roots complete, a revoked private owner derives the existing
three-field cancellation row from the authentic stage: scan identity, owner and
`dispatch_prevented`. It records one exact INSERT through a private pending
witness and winning AFTER observation, then closes only after the persisted row,
exact private absence and all surviving postimages still match. Earlier erasure
callers continue requiring receipt absence; the overload accepts only absence or
that exact derived closed receipt shape. Caller-provided images, preexisting
receipts, duplicate events and late receipt mutation are denied. Original
receipt guards, foreign keys and no-stage deletion semantics remain.

This helper is not integrated into the public cancellation owner. At the
receipt-only checkpoint, unconditional deferred rejection remained; receipt
presence alone does not authorize commit, dispatch, settlement or recovery
success for a staged operation. Final immutable proof, consumption, surviving
denial seal and whole-owner/caller qualification remain required.

### Current consumption candidate supersedes earlier incremental fences

Earlier sections describing unconditional deferred rejection and no consumption
record their individual preparation checkpoints. The integrated private
candidate below replaces that unconditional failure with mandatory guarded
cleanup and terminal deferred obligations; it retains the public action fences.
It remains unqualified until candidate validation and independent review
complete.

### Transient terminal snapshot and private consumption (candidate)

The private terminal snapshot derives full rows from a fixed seven-relation
catalog: stage, quota statements, credit, lifecycle, both retirements, both
erasures and receipt witness. Protocol version1 fixes this catalog; each array
has deterministic key order and its complete cardinality is validated. Capture
rederives quota/credit/event contracts, exact erasure OLD events and all current
surviving postimages/absence before freezing. Guarded predecessor provenance and
fresh live comparisons are separate requirements. No erased admitted receipt is
reread. Only the scan locator is input; owner/xid/content are derived.

Before row-array aggregation, count limits and serialized component sums plus
exact JSON framing enforce64MiB per relation and128MiB combined. Actual final
serialized size must equal the estimate. These fail-closed protocol limits do
not qualify peak heap, CPU or maximum-size workloads. The full private snapshot
must never be logged, transported or committed. API access, proof mutation and
TRUNCATE are denied. Guarded consumption is described below. Existing guards
remain active, and a private assertion compares the frozen proof with a fresh
complete capture. This assertion is valid only before predecessor consumption;
later deferred verification must use immutable captured/DELETE OLD evidence and
surviving facts, without recapturing removed witnesses.

Snapshot presence alone grants neither consumption nor successful commit. The
integrated private consumption candidate leaves the original stage in quota. A
separate closed version1 order deletes quota, credit, lifecycle, retirement,
erasure and receipt witnesses, then the stage. Within those completed witness
sets, retirement order is destination then source, and erasure order is intent
then submission, matching the version1 frozen key order. These are witness
cleanup orders, separate from the earlier source-first retirement and
submission-first private-root erasure. The snapshot remains until last.
Frozen-to-consuming revalidates all original rows and surviving facts and takes
an unavoidable transaction denial seal. Exact full OLD and untouched suffix
checks bracket each winning DELETE; only that AFTER chain advances the immutable
proof's separate cursor. Per-key suffix comparisons avoid full-row aggregation.

The final snapshot DELETE requires complete predecessor absence and surviving
accounting, lifecycle, registry and receipt equality. Its immutable DELETE OLD
carries the sole deferred full proof. Earlier stage INSERT and final DELETE
obligations require complete transient absence plus terminal facts; their safety
depends on the mandatory deletion chain, never absence or a seal alone. The
final validator reads frozen evidence and surviving facts, not erased witnesses
or the admission receipt. The distinct denial seal covers a closed48-relation
catalog, including competing admission protocol and all C1 tables, and remains
after stage/snapshot removal. Exact row guards mediate narrow cleanup
exceptions. Mandatory AFTER STATEMENT transition-table checks require one
winning row, rejecting zero-row protocol DELETE or snapshot UPDATE even where
the statement routing guard permits the relation. An existing admission seal
also denies consuming entry.

This is an unqualified private candidate until exact runtime and independent
review finish. It does not integrate the public cancellation owner or open the
original admitted-settlement fence. Full caller audit, failure/race/resource
qualification and affected gates remain required. No activation route is added.

The integrated candidate gives only the two read-only deferred C1 trigger
validators a trusted migration-owner `SECURITY DEFINER` context and empty
`search_path`, with explicit table/schema/AFTER/ROW/operation guards. This is
required when deferred constraints fire after the private owner returns to an
API role. All API/PUBLIC execute and private table privileges stay revoked;
cleanup helpers remain invoker-only. Elevation enables proof reads and does not
replace the immutable event chain or permit incomplete cleanup.

The private consumption/deferred/seal increment is now boundedly accepted from
exact local held/absent fixtures, actual service-role deferred COMMIT and
independent re-review. This does not install the public compositor or qualify
the full atomic checkpoint. The prior missing-admission corruption fixture's
deadlock remains unexplained: historical normal and scheduler-quiesced replays
both passed without reproducing it. The corrected stage suite preserves actual
missing-row integrity tests and uses exact-identity fault injection to verify
public-wrapper propagation separately; it passed876 on the unchanged candidate.
Its temporary helper replacement must roll back with the exact definition,
owner, security attributes and ACL restored. This permits preparation of the
inactive public integration after independent review, but is not a deadlock fix
or real-owner concurrency qualification. IC-1's next-owner design keeps generic
legacy-expiry/account-erasure cancellation separate from positive C1: only the
existing explicit public cancellation endpoint may later reach the dedicated
private compositor, preserving its DTO and grants. The surviving CANC seal must
not interrupt account batches that still need scan/user writes. Exact terminal
receipt classification wins on retry; partial C1 failure never falls through to
another settlement path.

### Dedicated explicit cancellation candidate (October 12)

At this historical October 12 stage, the uncommitted candidate routed the
existing service-only `public.cancel_initial_analysis` wrapper through the
revoked, fixed-search-path `internal.cancel_initial_analysis_explicit` owner.
Its signature, grants and v1 response stay unchanged. Earlier statements that no
public compositor exists refer to the preceding private-helper checkpoints.

Owner, deletion and completed-result checks precede classification. A saved
terminal receipt retains its exact classification. Non-pending lifecycle states
and operations without an admitted footprint retain the conservative generic
owner. Pending operations with any admitted footprint require the complete C1
prestate; missing or conflicting proof raises an error without falling through
to generic erasure. The original `internal.cancel_initial_analysis` remains the
separate legacy/account-erasure owner.

The new owner composes guarded capture, the original quota and complimentary
settlement owners, witnessed lifecycle change, source then destination
retirement, submission then intent erasure, minimal receipt, frozen terminal
proof and ordered consumption. The original admitted-settlement predicate
remains unconditional. Only its quota, held-credit/sample and lifecycle
callsites accept narrowly authenticated current-transaction C1 state. Raw held
settlement and lifecycle mutation remain denied; an absent complimentary hold
retains the original false/false no-op behavior. No exception handler converts
partial C1 failure into another cancellation or refund path.

Exact candidate evidence belongs in
`.artifacts/initial-atomic-admission/c1-explicit-progress.md`. Actual public
service-role held/absent COMMIT and replay, selected corruption/rollback cases,
and two same-operation contention schedules have local synthetic evidence. These
are not full public-path acceptance: portable packaging, remaining
cross-owner/caller/resource boundaries and full affected gates remain open.
Production installation, fresh finalization and activation remain disabled.

The
[C1 deadlock acceptance](initial-cancellation-interface-2026-10-11.md#deadlock-evidence-and-public-path-acceptance--october-12-2026)
requirement applies to this atomic candidate before public-path acceptance.
Preserve all eight historical stage93 failures and exact evidence; controlled
real-owner overlaps and an explicit reviewed disposition remain required.
Passing replacement fixtures do not establish a fix. This tightens the existing
acceptance gate without authorizing activation or changing the
current-versus-later S0 boundary.

## Submission storage representation bounds — October 13, 2026

The input contract remains at most 1,048,576 canonical UTF-8 bytes. PostgreSQL's
JSONB display text adds spaces after commas and colons; that spelling is not a
second, shape-dependent admission limit. The forward storage correction
`20261013030931_align_initial_submission_storage_bounds.sql` preserves JSON
container types and bounds display text at 1,056,766 bytes for input and ordered
descriptions, and 73,753 bytes for configuration. Configuration's canonical
ceiling is 65,563 bytes: the 65,536-byte assignment plus its 27-byte wrapper.
Funding retains its 16,384-byte legacy container; current admitted proof still
limits canonical funding to 4,096 bytes.

For the accepted canonical grammar, keys, string escapes (including control and
non-BMP characters), and safe integer spellings agree with PostgreSQL JSONB
rendering. Each non-root value node contributes at most one comma space and one
object colon space. The 4,096-node ceiling therefore bounds extra rendering
bytes by `2 * (4096 - 1) = 8190`. These are conservative structural storage
ceilings, not larger canonical limits or peak memory estimates. Original
canonical, semantic, field, node/depth and identity validators remain the
admission authority. The migration only widens three existing checks; it
rewrites no historical evidence, canonical bytes or digests and changes no
privileges, trigger, result/completion owner or activation gate.

The discovered pgTAP fixture `initial_submission_storage_bounds.sql` tests the
effective catalog checks, plain/escaped/non-BMP canonical boundaries, the full
node allowance, configuration wrapper, description separators and raw container
rejection. Its copied CHECK table tests structural storage only. Full guarded
materialization, original cancellation/replay and rollback resource evidence
remain separate required qualification; a passing container test is
insufficient.
