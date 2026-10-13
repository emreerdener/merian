# Admitted media handoff runtime contract candidate 2

Status: independent and IC-1 design concurrence recorded October 13, 2026, for
`.artifacts/initial-media-handoff-v2/runtime-contract-v2.md`, SHA-256
`0aed34a1f10bc6239643fbef8743344141064315b6d2b0693353b86adaf4f102`. This is the
agreed implementation design, not implementation, runtime qualification or
activation authority. Representation, protocol and statement-accounting design
choices have concurrence. The
[source-specific lock and erasure closure](initial-media-handoff-lock-erasure-2026-10-13.md)
now has independent and IC-1 design concurrence as well. These reviews close the
pre-DDL design prerequisite for the agreed inactive family; actual
implementation, effective-graph verification and concurrency qualification
remain required. The following candidate text is retained as reviewed.

October 13, 2026. Proposed local implementation contract, not runtime
acceptance. Baseline `f7b7181ec016b4d37206a290d0f54bce822d463d`; retained
runtime catalog inventory is the 485-migration extract, with the 486th migration
adding only pure revoked validators. History primary is sole writer. Independent
and IC-1 review must close the contract before runtime DDL. All
activation/installations remain absent or disabled; no external operation is
authorized.

## Scope and trusted boundary

Implement durable original copy progress, one M2 v2 claim, exact retained-byte
verification and transfer, and the accompanying C1/expiry/erasure changes as one
coherent inactive dependency. Preserve v1 storage and renewable claims; they
must not accept v2. Do not add provider dispatch, structural execution
validation, result/completion, native installation or a new admission/funding
policy.

The existing twelve-component admitted receipt is the sole original context.
Every writer reloads and validates it under live ownership and canonical locks.
No caller supplies a replacement context or a boolean asserting validation.
Canonical claim-v2, verification-v2 and transfer-v1 use the accepted Deno/SQL
codecs without changing their versions, bounds or domains.

Physical I/O can only be attested by the pinned server copy/verifier adapter.
SQL proves original row provenance, immutable correlation and allowed
transitions, not that a GET happened. The production composition remains nil. A
future fixed service adapter must derive owner authority, load saved backend
generations and protocol artifacts, and invoke only the reviewed fixed owners.
Public clients cannot submit copy or verification evidence. A bearer UUID,
recovered document, service caller's hash or matching schema alone is not
physical proof. Test-only injected I/O/SQL owners establish local algorithm
evidence, not hosted signer or storage qualification. Generic service
credentials remain a trusted-server boundary, not a cryptographic attestation of
remote bytes.

For this private runtime preparation, all new relations and internal mutation
functions remain revoked from PUBLIC, anon, authenticated and service_role, with
RLS enabled and empty function search paths. Existing service entrypoints may
recover an already valid committed receipt through their original authorization
and gates; they cannot reach a new writer by a caller-controlled routine name. A
later callable adapter/grant needs its exact reviewed implementation; do not
infer it from this private owner acceptance.

## Durable records and lifetimes

Each of these is a new `internal` relation. `scan_id` is the primary key;
`owner_id` is required and `(scan_id, owner_id)` is unique. Each has a composite
ON DELETE CASCADE FK to
`initial_preparation_admission_receipts(scan_id,
owner_id)`. There is no FK to
preparation intent, no FK to a scan row that may not yet exist, and no
peer-to-peer cascade. The admitted parent already cascades from the immutable
submission. New rows survive preparation-intent retirement and disappear with
submission/account/scan erasure. Permanent registry rows remain content-free;
private digests/documents never move into them.

| Relation                                 | Persisted columns beyond identity                                                                                                                                | Write rule                                                                                                                                        |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `initial_media_copy_progress`            | `admission_receipt_digest`, `copy_adapter_digest`, `started_at_ms`, `completed_objects` canonical TEXT, nullable `last_object_at_ms`, nullable `completed_at_ms` | One original insertion, append only newly verified destination tuples; completion can transition from null once after the exact union is present. |
| `initial_media_verification_claims_v2`   | `claim` canonical TEXT, `claim_digest`                                                                                                                           | One immutable original claim, token generated and issued time sampled by locked SQL owner. No UPDATE, renewal or replacement.                     |
| `initial_media_verification_receipts_v2` | `receipt` canonical TEXT, `receipt_digest`                                                                                                                       | One immutable receipt, exact stored claim and original proof validated.                                                                           |
| `initial_preparation_transfer_receipts`  | `receipt` canonical TEXT, `receipt_digest`                                                                                                                       | One immutable transfer receipt; complete original verification proof retained in accepted shape.                                                  |

Canonical TEXT bounds apply before parsing: progress object union at most 8 KiB,
claim 32 KiB, verification 64 KiB and transfer 96 KiB. Progress uses the exact
object tuple shape of verification: `object_id`, `backend_generation`,
`content_type`, `byte_count`, `sha256`, ascending UUID order, no unknown keys or
duplicates. A partial union may be empty only before completion. Every tuple is
an exact member of original mapping.objects; it never invents source selection
or aliases. The admitted mapping retains every source/prepared-role pair; copy
proves every mapped original source role required for a shared destination.
There are at most ten unique destinations and original byte/profile limits
apply. `completed_at_ms` is SQL post-lock settlement time, not physical commit
or storage observation time. Started/completed times must be within original
admission authorization and strictly before original copy cutoff.

Do not create another permanent namespace fence or durable lease. Original
admitted identity plus the existing lifecycle/registry fences prevents
recreation after private rows erase. Re-entry after transfer returns its
original receipt; after erasure returns authorization-safe terminal denial. A
claim/progress row cannot be recreated just because its old private FK parent is
absent.

## Fixed private owners and progress transitions

The proposed internal operations are fixed functions, not a dynamic dispatcher:

1. `begin_initial_media_copy_v2(owner, scan, admission_digest)` reloads the
   original proof and exact unretired registries. It creates the empty original
   progress row only before the copy cutoff; exact re-entry returns the saved
   row. It neither allocates a destination nor extends any cutoff.
2. `record_initial_media_copy_object_v2(owner, scan, admission_digest,
   destination_object_id)`
   is reached only after the pinned adapter has verified the mapped original
   sources, conditional destination creation/recovery and exact readback. SQL
   derives the tuple from its original mapping rather than accepting new byte
   metadata. It appends that tuple under the common scope and final copy cutoff.
   Repeated identical object returns unchanged progress; missing/foreign/retired
   objects reject. This fixed function's trusted caller obligation is explicit;
   knowing an object ID alone proves no I/O.
3. `complete_initial_media_copy_v2(owner, scan, admission_digest)` requires the
   exact full union of durable object settlements, marks completion once under
   final copy cutoff, and returns the original completion on exact replay. No
   elapsed time or missing reply implies completion.
4. `claim_initial_media_verification_v2(owner, scan, admission_digest)` requires
   that completed original copy plus live unretired destination union. It issues
   exactly one server token and time strictly before verification_claim cutoff.
   Recovery returns the identical stored claim, even after expiry, with no new
   I/O permission. There is no alternate token or claim-generation counter.
5. `settle_initial_media_verification_v2(owner, scan, admission_digest,
   original_claim_token)`
   is reached after the pinned verifier reads and hashes every exact destination
   under the original verification cutoff. SQL builds the receipt from its
   original proof, claim and exact union; it rechecks
   provenance/ownership/retirement and samples final authorization strictly
   before verification_settlement cutoff. An exact existing receipt returns
   unchanged, never updates its timestamp.
6. `transfer_initial_preparation_v2(owner, scan, admission_digest,
   verification_receipt_digest)`
   loads the original stored receipt and full original proof. It performs the
   atomic transfer transaction below.

SQL argument types are UUID for identities/tokens and TEXT for digests. New
writers do not accept caller-supplied timestamps, canonical receipts, arbitrary
object arrays, storage URLs or replacement backend/adapter profiles. All held or
recovered responses have authority none. Durable copy recording proves the
trusted owner performed its protocol; these are not public completion callbacks.
New fixed Deno owners must snapshot dependencies/input before async work,
resolve saved originals, and never expose internal writer operations to client
input.

## Exact replay and time ordering

Recovery precedence never relaxes supplied identity checks. After live owner and
terminal checks, every operation compares its supplied admission digest with the
saved original before returning progress, a held transferred result or success.
`record_initial_media_copy_object_v2` also requires the supplied destination ID
belong to the original union; settlement compares the supplied token with the
original claim even if a receipt already exists; transfer compares the supplied
verification digest with the original stored verification even if transfer is
already committed. Changed immutable arguments reject instead of receiving
cached success. No replay re-resolves funding, catalog defaults or identities.

For begin-copy, an existing exact progress row is recoverable after cutoff; a
missing row may only be inserted before cutoff. Recording an already settled
exact tuple returns the unchanged row after cutoff; a new tuple cannot be
appended after cutoff. Completing an already completed copy returns its original
completion after cutoff; a full but incomplete union cannot be completed late.
Existing original claims and exact settled receipts recover after their cutoffs;
new claim/settlement cannot. Exact committed transfer recovers after expiry; new
transfer cannot. After transfer, copy/M2 mutation requests return the agreed
held already_transferred result only after these argument checks; original
private evidence recovery remains separate from any new I/O authority.

SQL stores `last_object_at_ms` in the one progress row. Empty progress has null
last-object and completion times. Each new object append takes a server sample
only after locking and requires admission_authorized <= started_at_ms <= prior
last_object_at_ms <= new sample < copy cutoff (omit the prior comparison for the
first append). It atomically updates the sorted union and last-object time.
Identical tuple replay changes neither. Completion requires the exact full union
and last_object_at_ms <= completion sample < copy cutoff. Clock regression fails
closed; no client timestamp substitutes. The full union remains incomplete until
that explicit transition. This records the maximum ordered settlement time, not
a fabricated per-object remote I/O timestamp.

## Physical copy, verification and late writes

The copy adapter processes the exact saved mapping in deterministic destination
UUID order. It reads each required original source/prepared object at its pinned
source backend, bounds content length/type/encoding/metadata and hashes the
exact bytes. Distinct original role identities that alias one destination must
each pass their required source proof. It conditionally creates the one original
M1 destination (`If-None-Match: *`), then performs exact
length/type/no-encoding/ no-extra-metadata/hash readback at the pinned
destination. Data already present must match exactly; mismatches hold and are
never overwritten. No new transform, object ID, backend generation or funding is
selected.

One adapter attempt makes at most one PUT per unique destination. Lost PUT reply
uses exact-key GET only within that attempt. A later recovery attempt may
perform an identical conditional PUT only under the original copy deadline and
fresh live-owner/registry checks; a recovered progress/status response itself
does not authorize writes. If object-record acknowledgement is lost, recover
that stored row first. If absent while live and before cutoff, repeat original
exact readback/source verification before the same settlement; never assume an
absence read proves the previous SQL write rolled back. Known settled objects
need no new copy write. M2 independently rereads the entire destination union.

No SQL lock spans I/O. Each I/O phase uses one whole-cohort conservative
monotonic deadline translated from saved server cutoffs minus full status/claim
roundtrip; per-object work does not reset it. Late async results are discarded,
streams are cancelled, and no callback starts SQL settlement or another I/O
after its phase budget. SQL separately rechecks its relevant cutoff after
acquiring every lock and immediately before final authorization. These two
clocks prove separate bounds; neither is physical commit-time evidence.

The storage qualification contract must guarantee atomic conditional create and
persistent erasure markers on exact keys. Data capabilities permit only exact
conditional PUT and GET, never unconditional overwrite, DELETE, metadata change,
copy-to-new-key or caller-selected URL. Eraser capabilities write/read the
zero-byte `erased-v1` marker, never remove the key. With linearized conditional
create and marker replacement: if a data write wins first, erasure replaces it;
if the marker wins first, every later data create fails. An in-flight request
and an expired local signal do not themselves prove remote cancellation.

Qualification covers every writer and credential with access to the destination
namespace, including legacy workers and outstanding signed capabilities, not
only the new adapter. No writer may overwrite a data object or marker outside
the specified eraser transition. Bucket/object lifecycle expiration, manual
DELETE, version rollback and other automatic cleanup must not remove the marker
or reopen its key. A namespace with an old unconditional writer/capability or
marker-removal policy fails qualification and cannot be installed. Unknown
capability revocation or expiry is not proof that its physical request ceased.
No contract here assumes local signal cancellation revokes a signed request.

Registry retirement is irreversible and precedes private erasure. Cleanup
retains exact scan/object/backend generation after private rows disappear; it
must remain able to target the retired key without private mappings or hashes.
Only still-current cleanup token acknowledgement can mark confirmed. Replaced
cleanup claims cannot rebind data or acknowledge a stale write. Exact marker
readback is acknowledged only for a backend whose above conditional/marker
semantics have been separately qualified. If backend semantics, late-writer
exclusion or outcome are unknown, retain unconfirmed retired work for targeted
re-erasure; do not assert remote erasure merely from one DELETE/PUT response. A
confirmed marker cannot be treated as safe for a backend permitting later
unconditional data writes. No such backend is installed by local tests.

M2 observes retained bytes only. Transfer makes no claim of structural decode,
source-to-prepared derivation or executable safety. Later execution must
validate and consume the same immutable bytes using the saved artifact,
independently of these receipts. Existing provider-writer denial remains closed
throughout.

## Atomic transfer and post-transfer cancellation

Transfer checks owner/deletion/terminal first, then exact transfer replay before
preparation-intent lookup or expiry. A new transfer requires immutable admitted
proof, completed copy, original claim, immutable verification, exact unretired
M1 union and original transfer cutoff. Insert the complete transfer receipt
provisionally, retire the original preparation registry union, and erase only
original preparation-private intent/proofs. Do not erase submission, admitted
receipt, M1 cohort or the four new handoff records. Force deferred
complete-state checks, perform the final nonmutating locked cutoff validation,
and commit or roll back the entire operation. Retirement/intent erasure cannot
commit with a missing, changed or incomplete transfer receipt.

Explicit C1 supports no-copy, partial-copy, completed-copy, claimed, verified,
and transferred cases. For all states, original admitted proof remains available
and positive unused funding must independently pass existing reservation,
original attempt, counters, complimentary and absence-of-execution predicates.
The transferred branch validates exact self-contained admitted/transfer proof
rather than requiring the erased intent/source proofs. It requires original
source registry retirement and exact still-live destination cohort. The same
funding owners settle once; transfer existence is never evidence of execution.
Every uncertain or inconsistent state takes conservative unknown handling with
no refund. Raw erasure does not infer financial settlement.

C1's exact private preimage/cascade inventory grows by these four relations.
Copy/claim/verification/transfer documents are captured exactly, then absent in
the terminal postimage. Original source registry is live before ordinary C1 and
already retired after transfer; the expected retirement delta is computed from
that captured state, never an unconditional demand for a changed row.
Destination retirement remains required. Denial seals cover
INSERT/UPDATE/DELETE/TRUNCATE of all new relations; no unconsumed expectation or
transient stage can survive. Terminal replay verifies the consumed snapshot
rather than loading erased private proof. A content-bearing completion/progress
digest is not retained in a permanent tombstone.

Automatic preparation/M1 expiry may cancel admitted, untransferred expired work
using the same positive unused predicates, including verification without a
transfer. It must stop on exact committed transfer and preserve its destination.
Explicit C1 and authorized raw scan/account erasure still win after transfer.
Late copy/verification/transfer cannot rebind retired registry IDs, recreate any
private parent, refund uncertainty or bypass terminal fences.

## Recovery and lock delta

Keep owner/deletion, cancellation/terminal, exact transfer, exact admission,
unadmitted-original order. Original admitted classification becomes:

| Durable unresolved state                                  | Phase before its original cutoff | Cutoff                  |
| --------------------------------------------------------- | -------------------------------- | ----------------------- |
| Missing/partial copy or full union not committed complete | copy                             | copy                    |
| Complete copy without original M2 claim                   | verification                     | verification_claim      |
| Original M2 claim without settled receipt                 | verification                     | verification_settlement |
| Immutable M2 verification without transfer                | transfer                         | transfer                |

At cutoff equality report expired, never synthetic progress or refund. For an
issued claim after verification-read cutoff but before settlement cutoff, phase
verification permits only original in-flight settlement/recovery; a phase string
never permits new reads. Exact committed transfer precedes all cutoffs. Corrupt
or contradictory progress rejects rather than fabricating a phase.

Retain existing outer owner -> ingestion advisory -> scan/history -> lifecycle/
intent/submission/admission scope; saved catalog locks NOWAIT precede original
funding owners. Preserve quota request/reservation/counter/complimentary order.
Then preparation source/output UUID union -> admitted receipt -> transfer
receipt -> M1 fence/cohort -> copy progress -> M2 v2 claim -> M2 v2 verification
-> destination UUID union. V1 M2 siblings remain in their existing deterministic
slot and must be absent for v2. New absent rows serialize on existing outer
scope. FK parent key-share checks cannot acquire any new outer lock late.
Cleanup only locks already-retired registry rows and never subsequently acquires
outer/catalog/funding locks. No shared catalog or global serialization fallback.

Before DDL, attach the precise effective functions, dynamic relation arrays,
trigger ordering, FK/deferred checks, admission/cancellation seals and erasure
closure to this contract. This named delta is not a substitute for that
inventory. New two-session real-role acceptance must cover both winners;
previous stage93 residual-risk acceptance does not qualify this new graph.

## Effective mutation inventory

The read-only source audit identifies these concrete extension points in
`20261012041337_prepare_initial_atomic_admission.sql` (anchors refer to the
immutable baseline):

| Effective owner                                                                                                  | Required delta                                                                                                                               |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `capture_initial_admitted_cancellation_prestate`, line 2530                                                      | Lock transfer before M1, then progress/claim/verification; include their exact private images and distinct pre/post-transfer retained proof. |
| `initial_cancellation_private_catalog`, line 3711                                                                | Add each new table with submission lineage and one-row-per-scan bound; exact OLD-image and cascade closure.                                  |
| `capture_initial_cancellation_private_images` and `erase_initial_cancellation_private_root`, lines 3732 and 4015 | Capture four rows and consume exact cascade witnesses; no broad DELETE exemption.                                                            |
| `capture_initial_cancellation_terminal_snapshot`, line 4242; cleanup catalog/cursor, lines 4324 and 4621         | Include new-row absence/consumption and already-retired source rows in transferred state.                                                    |
| `initial_cancellation_seal_catalog`, line 4646                                                                   | Add all four tables to denial seals and exact dynamic trigger installation.                                                                  |
| `cancel_initial_analysis_explicit`, line 4877                                                                    | Preserve positive-unused accounting and once-only settlement; add transferred prestate and exact new-row erasure.                            |
| `recover_initial_admitted_media`, line 2382                                                                      | Read transfer under canonical scope before missing-intent/expiry; classify original progress without fresh authority.                        |
| Dynamic wrappers/action patches, line 2411                                                                       | Keep transferred/recovery/held precedence in status, finalizer and source execution action.                                                  |
| `initial_admitted_settlement_blocked`, line 2468                                                                 | Detect v2 state for legacy settlement exclusion; this negative fence grants no unused-refund authority.                                      |
| Admission seal member loop, line 2223                                                                            | Deny unauthorized handoff writes during admission sealing, without adding handoff mutations to admission's expected write members.           |

In `20261011205141_prepare_initial_preparation_execution.sql`, preserve
`reject_initial_preparation_provider_writer` and its current prepared-source
execution denial. Do not blindly attach that pre-admission trigger to new
legitimate post-admission handoff rows. Their private guards must permit only
the exact transaction-bound handoff owner while retaining denial on all existing
provider/v1 media writers. Extend `can_cancel_initial_preparation`'s existence
inventory so the old unfunded path cannot cancel a funded v2 handoff.

The four composite FKs use the existing unique `(scan_id, owner_id)` admitted
parent key. No new candidate key is needed; parent digest correlation is checked
under lock. Do not invent a composite FK on `admission_receipt_id`. Every table
contributes at most one image, ordered by scan in generic multi-owner paths;
progress's tuple union is sorted inside that row, not a per-object child family.

Use the existing exact stage/witness discipline: private transaction-bound
staging with owner-computed OLD/NEW images; ordinary DML and custom GUC/token
imitation cannot create a valid stage or consume an expectation. Before/after
guards bind statement, relation, transaction and exact images. Deferred checks
require every expected mutation consumed and stage cleanup. Admission, transfer
and C1 stages cannot overlap. Concrete stage relation names, row caps, trigger
definitions and all raw erasure caller closure still require the mechanical
definition audit before DDL. Representation acceptance is not a waiver of that
remaining source-specific work.

## Required local acceptance

- Changed admission/verification digest or claim token on already completed
  recovery rejects; correct replay after cutoff is unchanged and grants no I/O.
  Duplicate object records and completion do not change saved timestamps.
- Reject source/settlement/completion time regression and full-union late
  completion; require explicit durable complete-copy transition.
- Deny storage qualification for legacy/unconditional writers, outstanding
  unsafe capabilities, marker expiry/removal or lifecycle key reopening.

- Exact media tuple union and aliases across photo/audio/video, optional
  context, one-time starts, partial progress, changed-object conflicts and full
  completion.
- Unknown PUT and SQL-record replies, exact original recovery, no renewed
  cutoff, no new transform/ID/backend and no inferred copy/M2 progress from
  time.
- Deadline equality and late callbacks at copy, claim, read, settlement and
  transfer boundaries; monotonic budgets include entire cohort/round trips.
- Original claim recovery after cutoff, no alternate token/renewal, repeated
  verified/transfer receipt bytes unchanged, exact adapter/protocol correlation.
- Transfer rollback at each authorized mutation/constraint point, exact receipt
  precedes retirement, self-contained recovery after intent deletion.
- Positive-unused C1 before/after each progress stage and transfer, once-only
  original accounting; unknown/dispatched cases never refund. Both winners for
  transfer/C1, transfer/expiry, callback/C1 and account/scan erasure.
- Late data PUT before/after marker, stale cleanup token, missing private proof,
  and targeted retired-key rediscovery. Synthetic storage semantics are labelled
  local only; actual backend qualification remains externally authorized work.
- Actual role denial, fixed owner provenance, sibling rows/no broad cascade
  exceptions, all dynamic/FK/trigger edges and denial-seal tamper tests.
- Full affected database/Edge/tooling gates at the coherent runtime milestone,
  exact shared-checkout manifests, independent review and IC-1 concurrence.

This closes no full S0/native/integrated row and no later
deletion/export/redesign row. New grants or installed/hosted use still need
their named boundaries; do not invent those permissions from successful local
preparation.
