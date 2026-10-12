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
xid/token/phase is not a freely settable GUC authorization. Force deferred
checks, seal/consume under the accepted guard protocol, then finish with the
last nonmutating cutoff check. Durable complete proof remains available after
stage consumption, including under early SET CONSTRAINTS. All intended writes
roll back if an expected member/image/set or last clock check fails.

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
