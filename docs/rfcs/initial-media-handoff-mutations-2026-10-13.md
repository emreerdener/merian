# Private handoff mutation mechanics candidate 3

Status: independent and IC-1 design concurrence recorded October 13, 2026, for
`.artifacts/initial-media-handoff-v2/runtime-mechanics-v3.md`, SHA-256
`b289d3aaeff8de4c046d75c385dda833775b0be596dbd180d8ee0548521cc3ae`. This is the
agreed implementation design, not implementation, runtime qualification or
activation authority. Representation, protocol and statement-accounting design
choices have concurrence. The
[source-specific lock and erasure closure](initial-media-handoff-lock-erasure-2026-10-13.md)
now has independent and IC-1 design concurrence as well. These reviews close the
pre-DDL design prerequisite for the agreed inactive family; actual
implementation, effective-graph verification and concurrency qualification
remain required. The following candidate text is retained as reviewed.

Proposed mechanical companion to `runtime-contract-v2.md` SHA-256
`0aed34a1f10bc6239643fbef8743344141064315b6d2b0693353b86adaf4f102`. Neither
document is runtime approval. No new DDL has been written. This narrows
remaining stage/provenance choices for read-only review on baseline f7b7181.

## Separate transaction-only stage and exact write ledger

Use two transient relations, `internal.initial_media_handoff_staging` and
`internal.initial_media_handoff_writes`, separate from admission and C1, in
addition to the four durable rows. The stage has no cascade FK: normal
completion must consume it explicitly, and an unfinished stage can never commit.
All API roles are revoked, RLS enabled. Identity columns are scan_id primary
key, owner_id, transaction_id XID8 unique. The closed action enum is start_copy,
record_object, complete_copy, claim, verify, transfer. Only record_object has an
object UUID; only verify has an original claim token; only transfer has an
expected verification digest. Every operation includes original admission
digest. Other argument slots must be SQL NULL.

The guarded INSERT receives only this closed identity/action/argument set. The
BEFORE trigger acquires and validates the complete original scope, then derives
transaction_id, captured prestate, expected mutation images, authorization time,
an empty immutable completion ledger, zero event/cleanup cursors and phase
applying. Supplied derived columns reject. There is at most one handoff action
per transaction; admission/C1 stages and terminal seals exclude entry. Stage
creation cannot be authorized by a GUC, client timestamp, UUID token or caller
JSON. Migration administrators remain trusted and could deliberately assemble
the same guarded protocol; do not claim SQL call-stack authentication.

Stage snapshot and expected ledger each have a 64 MiB ceiling, enforced by
bounded row-count/byte preflight before JSON aggregation, then a column CHECK.
Each row image has a 32 MiB defensive ceiling; closed schema/canonical component
caps remain tighter and independently checked. Expected ledger has at most 64
events, with the exact set derived from original membership. Duplicate
relation/key/ operation events reject. Non-transfer operations expect exactly
one durable INSERT or UPDATE; no DELETE. Record-object stores the sorted new
union and its server time. Copy completion changes only completed_at_ms. Claim
and receipt INSERTs derive canonical values using existing accepted codecs.
Replays return before stage creation, after immutable argument/owner/terminal
checks.

Transfer ledger consists only of:

1. One transfer receipt INSERT.
2. Original source fence transition allocated -> retired (one row).
3. Each original source/output registry transition retired false -> true,
   ascending UUID, with no other changed columns (at most sixteen rows).
4. Exact original preparation-intent DELETE and its private child DELETE set:
   intent one, source_mapping up to eight, source_verification one,
   execution_grant one, output_manifest one, output_mapping up to eight, outcome
   one. At most 21 deleted rows. The root precedes cascading children
   semantically; child event order is not assumed from PostgreSQL FK ordering.

The closed transfer event ceiling is 39; the defensive 64 ceiling does not
permit arbitrary additional events. Prestate must prove all source registry rows
are originally live. A source already retired before first transfer is not an
empty successful delta. The admission/verification/claim/progress/M1 rows are
retained and expected unchanged. No provider/funding/accounting mutation belongs
to any handoff ledger.

## Row, statement and terminal guards

A fixed internal catalog enumerates the four new durable tables, source fence,
source registry and the seven intent-root private relations above. Relation
names are compile-time allowlisted constants, never supplied by an API caller.

The write ledger has `(scan_id, ordinal)` primary key, ordinal 0–63, stage FK ON
DELETE CASCADE, closed statement_key/relation/operation, exact expected OLD and
NEW images, consumed boolean initially false and nullable observed OLD/NEW. Its
insertion guard derives each complete expected entry from the protected captured
stage/action; callers cannot supply image authority. Statements have fixed keys
(one for each single-row transition and one root cascade); registry retirements
use the original sorted UUID positions. Expected entries are unique by
relation/key/operation. Row limits and 64 MiB aggregate preflight are checked
before registration and snapshot aggregation. Each expectation permits one
specific INSERT, UPDATE or DELETE, never generic UPSERT.

BEFORE ROW guards require the current xid-bound stage and one unconsumed exact
OLD/NEW expectation. AFTER ROW calls a revoked invoker event recorder using its
actual OLD/NEW values; it rechecks the expected event, verifies actual current
postimage (or exact deleted-row absence), and changes that ledger member to
consumed with exact observed images. The ledger's guard independently rechecks
the original captured preimage, current postimage, immutable expectation,
transaction and single false-to-true transition; it rejects arbitrary image
replacement or marking a different row consumed. A nested trigger/depth or GUC
alone cannot satisfy this. This proves the captured-to-final registered SQL
transition, not the physical I/O or the identity of a database administrator's
call stack. An administrator able to execute private owners can deliberately
perform equivalent guarded SQL; API roles cannot register or mutate it.

After all expected events, freeze the exact sorted consumed ledger in the stage
under complete pre/post validation. Neither its byte contents nor event count
can change thereafter. Consumption deletes one original ledger row at a time, in
ordinal order, while the complete parent remains present. BEFORE DELETE requires
that row equal the immutable ledger at cleanup_cursor and the untouched suffix
match all remaining children. AFTER DELETE increments only that cursor. No
cascading parent DELETE with ledger children present is permitted. The terminal
stage DELETE requires an exhausted cursor and zero child rows. Its OLD snapshot
retains the entire original and consumed write proof for deferred validation.

## Statement start/end accounting

Row events alone cannot detect an extra zero-row statement. Add guarded
statement state to the protected parent, not a generic additional mutation
permission: a frozen statement graph, next root ordinal, bounded active frame
stack and set of closed frame IDs. The graph is derived from the captured exact
event set and known FK topology, before domain DML. It has at most 32 frames and
depth at most three, with an independently bounded 32 KiB canonical
representation. Each frame names a fixed statement key, allowlisted
relation/operation, parent frame ID or null, and exact expected direct event
indices. Frame arguments/expected events cannot be supplied by a public or
ordinary service caller.

Only the primary fixed owner registers the next root statement by its ordinal;
this guarded transition verifies all preceding root frames closed and no active
frame. BEFORE STATEMENT consumes that registration and enters executing once for
the exact relation/operation. An unregistered, repeated or wrong root statement
rejects before rows. AFTER STATEMENT requires the actual direct row-event set
for that frame equal its expected set, every required descendant frame closed,
and no leftover active descendant. It closes the frame and advances the root
cursor. A zero-row statement where one row was expected therefore raises after
the statement; a later legitimate mutation cannot hide it. This is explicit
AFTER enforcement, not a claim that BEFORE can predict affected rows.

The transfer root sequence is receipt INSERT, source-fence UPDATE, one UPDATE
per original registry UUID, then intent DELETE. Each noncascade root expects one
row. Captured source rows are live; the transfer owner never registers a
zero-change retirement. After source retirement, the intent BEFORE erasure
trigger validates the already-retired exact union and does not call the ordinary
retirement helper again. C1 may legitimately encounter an already-retired union;
it uses its existing separately computed empty witness set, not a handoff frame.

Intent deletion's nested statement graph follows the actual FKs: five direct
children (source_mapping, source_verifications, execution_grants,
output_manifests, outcomes), and output_mapping below output_manifests. The root
intent exists exactly once. A direct FK child DELETE statement is expected even
when its captured child set is empty; that frame explicitly expects zero events.
The grandchild output_mapping statement is expected only if its parent manifest
row was actually deleted. Maximum nested domain depth is three and there are at
most seven statements for this root. PostgreSQL child visitation order is not
assumed. Nested BEFORE STATEMENT admits only a not-yet-started expected child of
the current executing parent after its expected parent DELETE is physically
visible as absent under the already validated BEFORE row guard. The parent's
AFTER recorder may run after FK cascades and is not a prerequisite for entering
a child frame; it must still consume that exact parent event before root
closure; AFTER closes the exact captured child event set. A duplicate empty
cascade frame or a same-relation statement outside its captured graph rejects.
The fixed graph is schema checked against the effective FK catalog; migration
drift fails before use. Ledger/stage bookkeeping has separate private control
guards and does not open arbitrary nested domain statements.

These frames prove the complete registered SQL effect graph, not PostgreSQL
administrator call-stack identity. Equivalently constructed private-owner SQL is
within the already stated trusted administrator boundary. All domain row events
must additionally satisfy exact prestate/expected/postimage guards. Frame
completion alone cannot fabricate an expected row mutation.

Statement registration, row observations, frame closure and root cursor changes
are transactional. A caught failing subtransaction rolls all of that subaction
back; it cannot leave a consumed frame or hide a missing row. Savepoint retries
may execute the still-original registered work only while original deadlines
hold. Test zero-row same relation/operation before and after the proper write,
duplicate registration/statements, empty FK children, nested manifest mapping,
wrong FK parent, and caught subtransaction rollback. After the final denial
seal, even zero-row domain statements reject in BEFORE STATEMENT.

After all events, the primary owner requests guarded phase complete. The guard
requires exact expected/observed ledger membership, complete expected
postimages, original accounting and sibling state unchanged, and full retained
proof validation. For transfer, force only the named transfer-state constraints
while the stage is still available (not the stage-completion constraints);
retirement and erased intent require the exact provisional transfer row. Sample
server time only after all locks and require authorization sample <= final
sample < original relevant cutoff. A clock regression rejects. This final check
does not mutate authority timestamps or extend a deadline.

Before consuming the complete stage, acquire a dedicated denial-only transaction
advisory seal in reserved two-int namespace 1229801542 (`IMHF`), with
`hashtext(scan_id::TEXT)` as the second key and fail-fast acquisition.
Repository migration search has no existing use of that namespace. The detection
predicate checks current backend, database, ExclusiveLock, granted, classid and
objsubid=2; it never mistakes a one-bigint advisory lock for this seal. A
forged/session seal may only over-deny. It cannot prove ownership, provenance or
success. No waiting global lock is added. The seal cannot be undone with session
unlock operations. BEFORE STATEMENT guards reject every further mutation of
handoff, admitted proof, preparation, lifecycle, relevant original accounting,
registry, erasure and competing provider/ingestion tables during this
transaction. The two transient tables allow only the guarded
complete-to-consuming transition, exact parent-present ledger deletions/cursor
advances, and final exhausted stage DELETE. Raw DELETE/TRUNCATE and
identity-changing updates reject. Read-only response construction remains
allowed.

Stage DELETE requires consuming phase, full pre/post proof and an exhausted
frozen ledger; its OLD image supplies final provenance. Deferred
INSERT/UPDATE/DELETE events all require stage absence and complete live
resulting state. Terminal DELETE also revalidates the complete captured OLD
transition; absence alone never proves consumption. Later erasure/mutation in
the same transaction is denied by the seal so deferred validation cannot be
defeated after cleanup. An unfinished or manually removed stage, omitted event,
extra event or statement rollback cannot commit. The seal proves only denial;
state/OLD-image checks establish success. A rolled back savepoint must remove
its stage, events and seal together.

Deferred stage and member events never skip early INSERT/UPDATE phases merely
because the stage was later consumed. Each verifies no transient rows remain and
that the exact action's live poststate is complete. The terminal stage DELETE
additionally verifies its OLD frozen ledger and every observed transition. The
same transaction's denial seal covers durable sources after consumption; the
seal is not used as proof of successful deletion or a reason to skip OLD checks.
This follows the existing admission parent-present ledger consumption model,
without reusing its original-funding stage table or C1's financial witnesses.

## Existing guard compatibility

- Keep `guard_initial_preparation_provider_writer` and v1 media guards closed.
  New four-table DML uses the handoff stage and does not receive a generic
  prepared-source exception. Original admission stages cannot nest handoff.
- Source retirement/intent erasure gets a narrowly computed transfer-stage
  predicate proving its exact OLD/NEW event, receipt and parent snapshot.
  Neither receipt existence alone nor a new boolean flag grants erasure.
  Account/scan and C1 paths retain their distinct authorized predicates.
- New durable DELETE guards allow only the existing exact C1 cascade witness or
  the authenticated raw-erasure root flow after both registries are irreversibly
  retired. They never allow deletion solely because a parent is missing.
- Extend C1 private catalog from fifteen to nineteen relations, each new member
  root submission and row_limit one. Existing capture, expected cascade OLD
  images, accounting image checks, terminal snapshot/survivor predicates and
  statement seals consume those actual rows. Do not add durable tables to the
  transient-cleanup catalog as though they were stage rows.
- C1 prestate validates all accepted progress shapes and the original claim /
  verification / transfer chain. It loads transfer before M1. After transfer the
  intent-root preimages are exact empty sets, source fence/registry already
  retired and destination still live. Source-retirement helper may emit no
  changed source rows; expected C1 images must model that, not fabricate writes.
- Automatic expiry checks committed transfer before any original preparation or
  M1 retirement. Raw deletion still retires destination and private handoff
  rows.
- Every new durable table gets the existing admission/C1 denial-seal triggers,
  independent of whether its family is part of those owners' expected writes.
  Both transient tables participate in cross-owner entry/absence checks and
  terminal seals; neither is an extra C1-erased private child.

## Lock and erasure closure still being bound to effective definitions

Common locks are owner/ingestion/scan-history/lifecycle-intent-submission-
admission; saved catalogs before original funding; source union; admitted
receipt; transfer; M1; progress; claim; verification; destinations. The
transient stage INSERT happens after this scope and acquires no additional
parent FK lock. Ledger FK reads only the protected already-present stage. All
row-state validation queries follow already-held lock order. No stage/I/O
crossing or out-of-order outer reacquisition is allowed.

The retained effective definitions expose an important ordering delta: generic
`cancel_initial_analysis`, `erase_initial_analysis_for_scan_fence`,
`fence_initial_analysis_on_scan_change`, and
`fence_initial_analysis_before_owner_delete` currently DELETE submission before
retiring preparation sources. The submission BEFORE trigger retires destination
objects, so that sequence is destination-before-source. For admitted v3 only,
these canonical owners must prelock the complete new handoff scope and retire
source before destination/private cascade. Preserve legacy-only behavior and
conservative financial classification. Do not leave this to an AFTER child
cascade that would need outer locks too late.

| Effective erasure owner                      | Required admitted-v3 behavior                                                                                                                                                            |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `guard_initial_analysis_tombstone_scope`     | Retain owner NOWAIT / scan advisory try-lock before tombstone; no waiting outer acquisition from inner scope.                                                                            |
| `erase_initial_analysis_for_scan_fence`      | Fence lifecycle, acquire remaining ordered admitted handoff rows, retire source then destination, then submission/intent/cancellation erasure.                                           |
| `guard_initial_analysis_scan_erasure_scope`  | Keep owner NOWAIT / advisory try-lock before scan-change fanout; preserve legacy early return.                                                                                           |
| `fence_initial_analysis_on_scan_change`      | Tombstone first; use already acquired outer scope; erase through ordered admitted root owner without late outer wait.                                                                    |
| `fence_initial_analysis_before_owner_delete` | Preserve raw-delete rejection until existing scan detachment; sorted pre-row scan identities under deleting owner, permanent tombstones, ordered registry retirement, then root cascade. |
| `public.apply_user_tombstone`                | Preserve service-only conservative generic cancellation while owner exists, then detachment and deletion; never route account erasure through positive C1 by implication.                |
| `internal.cancel_initial_analysis`           | Retain unknown/dispatched semantics and no admitted refund; acquire complete admitted erasure scope before source/destination retirement and private deletion.                           |
| `internal.cancel_initial_analysis_explicit`  | Use extended positive C1 proof and exact cascade witness, including transferred empty intent sets, before private evidence disappears.                                                   |

The four durable children FK the existing unique admitted-receipt
`(scan_id, owner_id)` key, NOT `initial_analysis_admissions`; no new admissions
unique constraint is required. They intentionally disappear during C1 submission
cascade. Only the existing minimal terminal cancellation receipt/fences survive;
no post-C1 transfer replay or private progress digest is retained.

Raw erasure must remain possible if private admitted/progress proof is damaged
or absent. Its ordered lock/retirement owner enumerates every actual permanent
source and destination registry row belonging to this scan, with live deletion
or account authority; it does not require successful admitted consistency or
positive-unused accounting. Exact full proof is required for handoff mutation
and positive C1, not conservative privacy erasure. All actual source rows retire
before any destination/root cascade. No refund, rebind or recovered success is
inferred from missing evidence. Source/intent transfer exceptions must
explicitly extend `guard_initial_source_storage`,
`guard_initial_preparation_storage` and `retire_initial_sources_before_erasure`
using their exact stage event, rather than an existence check for transfer
alone. Existing raw terminal/tombstone predicates stay separate.

Existing `retire_initial_media_on_erasure` (submission BEFORE DELETE) and
`retire_initial_sources_before_erasure` (intent BEFORE DELETE) must recognize
already-held/retired exact state without introducing out-of-order locks or
unregistered duplicate statements. Transfer's intent erasure exception is
limited to its exact provisional receipt plus captured OLD and stage witness.
Parent absence, a retired marker, or a forged GUC is not the exception. Raw
user/scan root deletion authorization remains distinct from transfer and
positive C1.

Trigger order uses BEFORE STATEMENT seals first, then existing scope/row guards
and exact handoff event BEFORE guard; immediate FK cascades after parent DELETE
may visit children in any order and must match the exact set, not assumed FK
creation order. AFTER event recorders prove corresponding actual images; named
transfer-state checks run while their stage exists. After explicit ledger/stage
consumption, force all deferred constraints, then perform the final nonmutating
locked cutoff/live-poststate check before returning. No later mutation is
allowed by the transaction seal. Test immediate constraints from transaction
start as well as deferred mode; the writer must explicitly defer only its
required completion constraints before constructing a stage, and restore/check
them before return. Never disable triggers or replica-role protections.

Retain a machine-readable subset of the original inventory with exact
definitions, trigger order and FKs, hash-bound to the captured source manifest.
Replays must compare the post-migration effective definitions with this planned
delta. Raw scan/account race tests cover both orders under actual privileges,
with no assumed global gate or fixture-only proof.

Independent and IC-1 review of this complete stage/ledger and erasure contract
precedes runtime DDL. Source implementation and real-role both-order tests must
then prove the specified paths; design agreement alone is not runtime
acceptance.
