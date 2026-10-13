# IC-1 admitted media verification and transfer v2

Status: concrete codec design accepted by independent and IC-1 review on October
13, 2026, at contract-design acceptance SHA-256
`a9fc1209f18a4ae859cb4d5add118b86ce22ae49f57feb9a4508ab57978746c5`. The scoped
Deno codec candidate has passed independent and IC-1 source review after the
empty-union digest correction, nine focused test groups, recursive type/lint/
format checks, DTO and dependency contracts, and the complete Edge command:
3,286 passed with 598 steps, zero failed, and 532 database-backed tests ignored.
Those ignored cases are not fresh database qualification; no SQL changed in this
checkpoint. Exact candidate and evidence are retained in
`.artifacts/initial-media-handoff-v2/implementation-candidate-v2.json` and
`codec-validation-summary-v2.json`. The final RFC status update is bound by
`implementation-candidate-v4.json`; code and tests are unchanged from v2. Design
agreement remains in `contract-acceptance.json`. This acceptance is limited to
pure codecs and does not qualify runtime authority. History primary remains the
sole writer. This extends the accepted
[handoff design](initial-preparation-handoff-2026-10-11.md), under the
[dispatch dependency boundary](initial-dispatch-fence-interface-2026-10-13.md).
It neither installs a media backend nor grants provider execution.

The implementation baseline is atomic/M1/C1 commit
`bc2a5af507a0ee56cbdb1a357f5221bec611371b`. Documentation checkpoint
`96a9d1477f031e45d286993134c0e51a05a9e2df` records its bounded acceptance. A
fresh disposable replay matched all 485 migration hashes and applied versions
from accepted DB85. Its effective definitions are retained in
`.artifacts/initial-media-handoff-v2/effective-routines.json` and
`effective-relations.json`, bound by `effective-inventory-receipt.json`. The
467-routine and 63-relation extract is an inventory, not concurrency
qualification; dynamic and unqualified calls still need manual audit. The
inventory database was disposed without activation or application data.

## First implementation boundary

Implement only closed canonical Deno codecs and synthetic vectors for the v2
claim, v2 verification receipt and v1 transfer receipt specified below. Receipt
version numbers are local to their document family; transfer has no existing
version to reinterpret. These codecs establish internal historical consistency,
not existence of stored rows, actual bytes, live ownership, time authority or
permission for I/O, dispatch or settlement. No new tables, SQL mutations,
service grants, native DTOs, routes, configuration installations or dispatch
codecs belong to this first boundary. SQL parity follows a separately reviewed
exact schema candidate; runtime integration follows the complete lock and C1
contract.

Owned initial files are under
`services/supabase/functions/_shared/initialAnalysis/`:

- `mediaHandoffProof.ts`: snapshot and bounded canonical validation, original
  admitted-proof correlation, digest calculation and cross-document checks.
- `media-handoff-proof-schema-v1.json`: closed schemas for the three explicitly
  versioned document families; no extensible metadata maps.
- `mediaHandoffProof_test.ts` and `fixtures/media-handoff-proof-v1.json`:
  synthetic positive/negative vectors, original-proof correlation and mutation
  isolation. Reuse existing admitted-proof fixtures without duplicating their
  large original documents.
- Local `README.md`, canonical API contract and this RFC: precise codec-only
  limits and runtime prerequisites. No change to public Identify schemas.

Reuse `validateAdmittedProof`, `admissionMetadataDigest`, the existing bounded
canonical parser and the accepted mapping/binding schemas. Do not create a
second admitted-proof validator. The codec takes the complete eleven original
canonical components plus manifest, snapshots them using the existing validator,
and checks every new document against that verified original. It does not accept
a caller-supplied claim that an arbitrary digest or context was already
validated. Snapshot the three new documents before the first await as well.

## Closed documents and identity

All UUID and SHA-256 spellings use the existing lowercase canonical forms. All
times are nonnegative safe-integer milliseconds, with the existing phase-window
constraints. Unknown keys, null in place of a required value, duplicate object
identities and reordered object unions reject. An empty media union rejects.
Canonical byte caps apply independently before parsing/hashing; do not serialize
the admitted components and these documents into one aggregate JSON value.

### Original verification claim, version 2

The claim has exactly:

- `version: 2`;
- `binding`: the complete original M1 v2 media binding, byte-for-byte equivalent
  to the canonical admitted `media_binding` component;
- `admission_receipt_digest`: recomputed by `validateAdmittedProof`;
- `verification_adapter_digest`: the original saved handoff profile's exact
  verification adapter digest;
- `claim_token`: one opaque UUID generated by the later database owner;
- `issued_at_ms`: the later owner's post-lock server time, at or after the
  original admission authorization and strictly before the saved
  `verification_claim` cutoff.

The canonical claim cap is 32 KiB; its nested binding retains the existing 16
KiB cap. The claim does not carry a new expiry or lease duration: reads are
bounded by the binding's original `verification` cutoff, and settlement by its
original `verification_settlement` cutoff. Repeated claim recovery returns the
same token and issued time. No token replacement, renewal, new destination, new
transform or new admission is permitted, even after expiry. Recovery after a
cutoff is evidence only and does not extend the applicable phase.

### Verification receipt, version 2

The receipt has exactly:

- `version: 2`;
- `claim`: the complete original version-2 claim;
- `claim_digest`: its domain-separated digest;
- `objects`: the complete destination union, in ascending canonical object UUID
  order, each with exactly `object_id`, `backend_generation`, `content_type`,
  `byte_count` and `sha256`;
- `authorized_at_ms`: the settlement owner's post-lock server authorization
  time, at or after claim issuance and strictly before the original
  `verification_settlement` cutoff.

The canonical receipt cap is 64 KiB and nested claim cap remains 32 KiB. There
are 1–10 unique objects, bounded by the saved profile and 28,625,792 total
unique bytes. The union must equal the admitted mapping's `objects` exactly,
including the destination backend and every byte tuple. The existing admitted
validator already proves original ordinal/role mapping and same-ordinal alias
rules; an arbitrary sorted list with the right aggregate size does not
substitute for it. All required photo/audio/video source and prepared roles must
be represented by that exact union. No URL, storage credential, media buffer or
provider result is stored in these documents.

The receipt describes retained-byte verification only. SQL can compare saved
identities and expected row images; it cannot infer a storage GET or structural
decode from caller-supplied hashes. Actual I/O evidence depends on the named
qualified verifier running against the exact pinned backend and object union.
The codec does not attest the verifier ran. There is no client-reported
completion timestamp pretending to establish server-time or physical-commit
ordering. The later verifier must stop reads and reject late callbacks at its
conservatively translated monotonic read deadline; the SQL settlement owner
separately enforces its final locked settlement cutoff.

### Transfer receipt, version 1

The receipt has exactly:

- `version: 1`;
- `admission_receipt_digest` and `protocol_artifact_digest`, equal to the
  original admitted proof and saved phase window;
- `verification_receipt`: the complete version-2 verification receipt;
- `verification_receipt_digest`: its domain-separated digest;
- `authorized_at_ms`: transfer-owner post-lock authorization time, at or after
  verification authorization and strictly before the saved `transfer` cutoff.

The canonical transfer cap is 96 KiB; the nested verification receipt retains
its 64 KiB cap. Complete M2 proof includes the full original claim, M1 binding
and exact destination union, so it remains self-contained after preparation
intent/proof erasure. It is still subordinate to the private admitted receipt.
No separate private text, digest or funding field moves into a permanent fence.

The three digest domains are, respectively:

- `merian.initial-analysis.handoff.verification-claim.v2\n`;
- `merian.initial-analysis.handoff.verification-receipt.v2\n`;
- `merian.initial-analysis.handoff.transfer-receipt.v1\n`.

Here `\n` denotes one LF byte between the domain and canonical document bytes.
Each digest excludes itself by belonging to the enclosing document or return
value. No cyclic hash construction is allowed. These document-family versions
and exact codec artifact digest must be included in the saved composite protocol
artifact. No old installed artifact may silently adopt these semantics.

## Runtime owners that remain unimplemented

The first codec boundary does not choose physical storage merely to have a place
for a decoded value. Before the SQL/runtime checkpoint, resolve and review these
concrete gaps:

| Owner                     | Existing evidence and required delta                                                                                                                                                                                                                                                  |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M1 v2 recovery            | Read the original admitted binding/mapping and registry union. `allocate_initial_analysis_media` v1 cannot allocate a new cohort or expiry for admitted v3.                                                                                                                           |
| Copy and copy progress    | Reuse immutable-key conditional PUT/exact GET primitives in `mediaStorage.ts` under the saved whole-cohort copy cutoff. Define the durable complete-copy evidence used to enter verification; elapsed time cannot advance recovery phase.                                             |
| Original M2 claim         | Current `initial_analysis_media_preparations` allows renewal and has a 60-second constraint. V2 must enforce one original token and saved phase cutoffs. Choose an explicit versioned extension or separate private v2 owner only after comparing the complete trigger/erasure delta. |
| Verification settlement   | Current `initial_media_verification_action` consumes a v1 binding and token only. V2 must consume the original admitted proof, exact claim, pinned verifier/object evidence and complete immutable receipt under final locked checks.                                                 |
| Transfer                  | No transfer writer/table exists. The accepted `initial_preparation_transfer_receipts` owner must write full M2 proof before original preparation retirement/erasure, force complete-state checks and perform final nonmutating cutoff validation.                                     |
| C1 and expiry             | Current positive-unused C1 only accepts pre-transfer absence of M2 progress. Extend its exact capture, expected images, cascade inventory, terminal snapshot/consumption and denial-seal coverage as one reviewed change; do not exempt arbitrary new rows.                           |
| Erasure and cleanup       | Retire preparation and destination registry unions before private cascades. Explicit post-transfer C1 uses self-contained receipts; raw erasure remains conservative. Cleanup claims never acquire outer owner/catalog locks afterwards.                                              |
| Status and legacy actions | Preserve owner/deletion/cancellation, transfer, admission, original-intent precedence. Original transfer can recover after expiry; missing intent after transfer cannot recreate work. All old execution actions return the agreed no-authority response.                             |

Effective `lock_initial_media_scope` already rejects prepared-source provider
writers and requires admission binding version 1. Preserve that independent SQL
denial; inactive Deno composition alone is insufficient. A v2 branch must enter
through its reviewed outer owner rather than weaken the shared v1 guard. Keep
existing historical v1 recovery and its original shapes intact.

Retain READ COMMITTED and the handoff's common outer owner → ingestion advisory
→ scan/history → lifecycle/intent/submission/admission scope. Resolve saved
catalog locks before any original funding owner. Then follow its single order:
preparation source/output UUID union → admitted receipt → transfer receipt → M1
fence/cohort → M2 claim/receipt → destination UUID union. New FK key-share
reads, statement triggers, absent-row serialization and nested
C1/account/scan/Ghost paths belong in the proposed effective lock delta. No
physical storage or media I/O happens while these SQL locks are held.

The retained catalog extract covers trigger order/definitions, constraints,
incoming FKs, RLS, ACLs and function security settings. Audit dynamic SQL and
unqualified nested calls manually before declaring that inventory complete.
Actual two-session tests under real caller privileges, both transaction orders,
remain required before runtime acceptance. The earlier stage93 residual-risk
acceptance is not evidence for this new graph.

## Structural and transform proof before execution

M2 matching does not prove format structure, decode safety or source-to-prepared
derivation. The separate execution prerequisite must name the exact saved
validator/decoder and transform artifact, supported photo/audio/video formats,
resource bounds and interpretation rules. Validate the same immutable bytes
execution consumes, including malformed/truncated/polyglot and expansion cases.
Neither a generic `validated` flag nor an M2 receipt clears this prerequisite.

A private retained-byte/transfer checkpoint may be accepted with structural
execution qualification still open only if its receipt semantics remain
explicitly limited and every dispatch/result/completion barrier remains closed.
No source-only video publication/review action or extra provider/model retry is
implied. Unknown provider execution permits original outcome/status recovery and
reconciliation only, never another invocation or refund.

## Acceptance and open review items

The codec checkpoint must reject changed owner/scan/admission or adapter,
cross-document token/claim mismatches against the supplied original claim, wrong
original binding, altered ordinal aliases, extra/missing/reordered objects,
changed bytes/backend, incorrect nested digest, unsafe integers, oversized or
malformed canonical values, cutoff equality and time inversion. Test optional
supporting text and source photo/audio/video mapping through complete original
admitted fixtures. Mutating caller objects after validation begins must not
alter accepted evidence. These tests do not claim live ownership or byte I/O.

Include an explicit test with a self-consistent synthetic alternate claim: a
different token with recomputed nested digests may pass consistency validation,
but proves no issuance and authorizes nothing. Original admitted proof predates
token issuance and cannot authenticate it. The later locked durable owner
enforces the stored original token. Likewise, codec time checks establish
ordering and bounds, not provenance of a claimed post-lock timestamp; timestamp
provenance remains the later locked owner's responsibility.

Review the exact version choices, independent caps, digest domains and original
proof correlation before coding. The durable copy-progress shape, physical v2
claim/receipt representation and full C1/lock delta remain open and must close
before SQL mutation implementation. Do not infer their approval from pure codec
acceptance. Focused and complete affected gates, exact manifests, independent
review and IC-1 concurrence precede a coherent local checkpoint.

Activation stays disabled, production access nil, and there is no push,
publication, deployment, hosted scheduling, device installation or distribution
authorization. Required native/integrated acceptance and the subsequent approved
version actions and redesign retain their dependency order.
