# Prepared initial-analysis admission

This inactive IC-1 boundary belongs to the initial engine. No live route or
worker imports it. The server gate defaults false. Admission and replay return
identity, never permission to dispatch. Existing capture DTOs are unchanged.

## Identity and retry

`schema.ts`, `semantics.ts` and `canonical.ts` validate a closed bounded v1
input and encode sorted ASCII keys, exact Unicode strings, safe integer numbers
and canonical decimal strings for fractional semantics. Null, absence and
explicit values do not collapse. SQL embeds the same schema; shared vectors
exercise both implementations. `owner_timeline` covers each independent media
owner and ordered description exactly once; video frames and companion audio
belong to their clip. The future route adapters must freeze accepted text in
actual timeline order. They must hold missing chronology rather than invent it.

`prepareInitialAdmission` copies every supplied byte buffer before awaiting,
checks container signatures, length and SHA256, and recomputes WAV
preprocessing. Only its branded result enters `admit`. Signature checks are not
full media validation. Clip-to-frame/audio association is a validated client
lineage claim, not server proof of derivation. The caller still needs ownership,
immutable retention and later exact promotion/derivation qualification. The
in-memory preparation alone cannot support execution or durable media recovery.
It runs the currently imported preprocessing implementation; the brand alone
does not attest that implementation to the retained manifest. Live installation
must resolve the saved implementation or attest exact executing code and
dependencies to that manifest.

The fixed SQL admission uses existing quota/assignment owners inside the same
transaction as the private submission and binding. Changed route, text, media,
order, context or explicit options conflict. Exact replay returns saved identity
before consulting new settings or funding. Failure after quota allocation rolls
back all writes. Private canonical bytes and every owner-derived digest erase on
scan/account deletion; a permanent content-free scan-ID fence prevents reuse.
Generic quota reacquisition, dispatch, settlement, expiry and pruning cannot
operate on these IDs. Pre-row scan deletion erases private evidence while the
original reservation and complimentary credit remain held: the prepared exact
initial cancellation owner can release only with fresh durable non-execution
proof. Raw tombstone erasure remains conservative and leaves funding held.
Account deletion cascades owner quota and usage rows; it does not refund or
reclassify unknown execution. Unknown execution never permits a second provider
call or refund.

The repository requires a caller cancellation signal and the branded fixed
transport from `createInitialAdmissionTransport`. It uses one raw POST to
`/rest/v1/rpc/admit_initial_analysis`, the existing service-key header policy,
no SDK/session refresh or retry loop, and `redirect: error`. Endpoint
configuration must be a bare HTTPS origin (HTTP is restricted to loopback). It
is not selected by request data. The injected fetch is a trusted test/host
dependency and must retain native fetch's single-request semantics.

One 20-second overall deadline covers asset resolution, identity verification,
request and response decoding. A five-second sub-budget covers the entire asset
catalog; the RPC and streamed response share a twelve-second sub-budget, leaving
three seconds for bounded local validation and return. Neither asset iteration
nor recovery resets an in-progress operation's deadline. The caller can shorten
every budget. Deadline timers and abort listeners are released when their owner
finishes. Absolute monotonic deadlines are checked at I/O and read boundaries
even when timer callbacks are delayed. Each stream allows at most 4,096 chunks
and 32 consecutive empty chunks; empty chunks are not retained. Actual asset
streams are limited to 128 KiB each, at most 64 assets and 1 MiB total; the
current retained catalog is about 395 KiB. Both success and error response
bodies are limited to 8 KiB of actual streamed bytes before strict UTF-8 and
JSON decoding. Readers cancel on failure and release their locks without waiting
indefinitely for cancellation acknowledgement.

Asset failure before the write holds configuration unavailable. Once write I/O
may have started, cancellation, timeout, lost/malformed replies and unrecognized
HTTP failures remain unknown. Exact validated SQL denials retain their known
meaning. Late asset or fetch completion is discarded and its stream cancelled;
it cannot launch admission, publish a binding or trigger a retry. Stopping a
local wait does not prove database rollback. `recoverAdmission` uses the exact
saved input with null fresh-admission authority, skips current assets and cannot
allocate, dispatch or refund. Durable native input/operation storage and the
future status/result recovery API remain separate requirements.

## Inactive initial WAV structural validation

`wavValidation.ts:inspectInitialWavStructure` implements the pure internal
`initial-wav-structure-v1` contract. It synchronously checks the exact private
caller-owned byte view, rejects shared storage, validates RIFF/chunk extents,
PCM16/float32 framing and all float samples, and returns only frozen primitive
metadata. Bounded opaque metadata and valid initial rates/channels remain
supported. Structural acceptance does not bypass existing transform budgets.

No live handler or `prepareInitialAdmission` imports it. Later integration must
validate and transform the same private snapshot and qualify a new measured
closure; neither the historical M3 artifact nor saved admission tuples may be
relabelled. Source-copy race proof, other media validation and full initial
execution remain open. See the
[WAV interface RFC](../../../../../docs/rfcs/initial-wav-validation-interface-2026-10-11.md).

## Configuration retention

`configuration-assets-v1.json` pins 60 transitive source/configuration assets at
revision `86e007a5f1b2ae3064bbe21f9fd140a4b3dead4b`, plus external dependency
specifiers and the frozen dependency lock. Its domain-separated digest is stored
with the SQL rollout and admission. `verifyInitialConfigurationAssets` requires
exact streamed bytes at that revision through `git_blob_sha256_v1`; missing,
changed or unrecognized assets hold. It never silently substitutes current code.
The initial-engine release archive owns retention. `sourceArchive.ts` and
`scripts/build_initial_source_archive.ts` now implement local source/config
archive construction and resolution. The builder reads only regular Git blobs at
the saved revision, with replacement objects disabled; dirty checkout files,
symlinks, missing members and altered bytes cannot supply authority. A finite
resolver supports only the exact retained catalog and requested revision. It
verifies the entire archive before exposing copied member streams, without
network access, current-source fallback, dynamic import or evaluation.

Format 1 contains the exact catalog (including lock and external-specifier
inventory) and catalog-ordered `path`, `sha256`, `byte_count`, `base64` members.
Explicit JSON field order, canonical base64 and a single trailing LF define the
only accepted spelling; duplicate/extra/missing fields or members, alternate
spellings and malformed UTF-8 reject. Encoded JSON is capped at 2 MiB and raw
members retain the 128 KiB / 64 files / 1 MiB limits. Offline Git construction
has a 60-second whole-build deadline; resolution has a five-second whole-archive
deadline, composed with caller cancellation and existing stream work limits. The
ordinary admission catalog budget remains five seconds.

Run the local builder with one existing operator-owned output directory:

```bash
deno run --frozen --deny-net --deny-env --allow-run=git \
  --allow-read=. --allow-write=<output-directory> \
  --config services/supabase/functions/deno.json \
  services/supabase/scripts/build_initial_source_archive.ts <output-directory>
```

The CLI emits only byte count and public source digests. It syncs an exclusive
private temporary file, then publishes with an atomic no-replace hard link to
`<archive_sha256>.json`. An existing content address must verify identically;
corrupt files or symlinks reject without replacement. The raw archive SHA256 is
distinct from the domain-separated asset-manifest digest stored by admission.
This operation assumes a trusted local directory and filesystem; it is not
hosted retention or power-loss durability qualification. Local publication
checks cancellation between filesystem operations. A blocked filesystem write,
sync, open or link cannot be preempted: the construction/resolution deadlines do
not guarantee a wall-clock bound for publication. Cancellation after a link may
leave the complete content-addressed artifact; inspect and verify that exact
address before treating any local failure as absence.

The archive does not vendor external dependency bytes or prove which executable
preprocessor/provider runs. Runnable bundle/dependency archival, runtime image
and bootstrap attestation, immutable hosted retention and execution-time
resolution still require implementation and qualification. No live installer
uses this source resolver.

SQL freezes an explicit allowlist of provider-assignment selectors, model,
effective tier and null experiment alongside durable original funding identity
and policy facts. Lease tokens, lease expiry, replay/state and live counters are
excluded. Combined with immutable input and retained builder, prompt, schema,
preprocessing and provider adapter sources, these are the configuration
authority. No live path is allowed to rely on this composition until all
inference-affecting dependencies are covered.

Standard builders use API credentials and Supabase/R2 transport configuration;
these secrets are not stored in snapshots. Authorization and entitlement policy
outputs are frozen, not re-read as inference defaults. Current standard builders
have no fetched prompt or random assignment outside the saved selectors. Model
aliases do not pin provider weights; later result provenance must retain the
actual provider model. Experiments use additional flags, plans and
time-dependent assignment, so marked inputs and both reserved comparison-ID
namespaces are held.

## Remaining S0 boundary

No initial dispatch API or installed cancellation route, durable media staging,
original result capture, completion, status operation, history enrollment or
native installation is provided here. All three route adapters and affected
recovery/cleanup workers must cut over together after old writers are quiescent.
Enabling a gate alone is not a supported rollout. Fresh libraries remove
older-scan compatibility duties, not contention or erasure duties.

`admission_test.ts` covers the private codec/repository and byte preparation.
`transport_test.ts` covers cancellation/deadlines, actual streamed limits, no
retries, late callback suppression and recovery after lost acknowledgement.
`initialAnalysisAdmissionDb.test.ts` covers TS/SQL vectors, retained profiles
and observed database races. `tests/initial_analysis_admission.sql` covers
effective privileges, exact replay, rollback, namespace/expiry holds and
erasure. Candidate evidence and unresolved qualification live in
`.artifacts/initial-analysis-admission/checkpoint.md`; the canonical contracts
are
[database schema](../../../../../docs/backend-and-data/04-database-schema.md),
[API contracts](../../../../../docs/backend-and-data/05-api-contracts.md) and
[retention](../../../../../docs/backend-and-data/17-scientific-observation-retention.md).

## Prepared C1 cancellation database owner

`cancel_initial_analysis` is the fixed service-only database boundary. There is
no installed handler/native transport for it yet. The
[C1 API contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-initial-cancellation-under-ic-1-c1-inactive)
defines exact unused-funding release, held unknown execution, cancellation-only
private recovery receipts and stronger deletion. Fresh pending lifecycle state
is created by admission in the same transaction; missing old state is never
backfilled. The existing generic execution and settlement fences stay closed.
Cancellation cannot modify an already saved scan. No dispatch grant, provider
call, activation or installation is included.

Cancellation also fences terminal scan/job/intent identity writes and rejects
prepared IDs in legacy ingress, recovery and settlement owners. UUID aliases
share the same serialized namespace. Existing generic work makes pending
cancellation unknown and keeps original funding held. Dedicated initial
completion and batch recovery qualification remain separate S0 work.

## Prepared M1 media allocation database owner

The inactive M1 database boundary derives one immutable ordered media cohort
from the admitted input, using only the server-selected original backend
generation. Source/prepared roles share an object only for identical complete
tuples within one item; differing WAV tuples get separate objects and raw MP4 is
source-only. Text has an explicit empty cohort and permanent allocation fence.
Exact replay preserves original destinations and deadline even when defaults or
the gate change. Expiry never creates a replacement cohort or upload authority.

Pending-only whole-cohort retirement excludes later use and never settles
funding. C1 cancellation and scan/account erasure remove private manifests while
atomically retiring every opaque destination. Cleanup leases lock retired
registry rows only; stale acknowledgements cannot confirm markers, and an empty
claim cannot prove a lost acknowledgement succeeded. No actual backend profile,
physical I/O, byte/transform verification, consumption binding, dispatch,
installed reader or worker schedule is supplied. Those remain S0 prerequisites.
The exact closed database envelopes and lock/qualification boundaries are in the
[M1 interface](../../../../../docs/rfcs/initial-media-allocation-interface-2026-10-11.md).

## Prepared M2 retained-byte verification

The inactive M2 byte owner copies bounded original source/prepared objects,
checks the exact M1 manifest and actual bytes, then uses a fresh preparation
claim for conditional writes and uncached same-object verification. Its one
20-second deadline covers RPCs, signing, storage and receipt
settlement/recovery, with five seconds reserved after storage. Partial work,
late callbacks, marker objects and mismatched actual streams cannot produce a
receipt. Unknown PUT outcomes permit one exact GET; unknown settlement permits
the exact receipt read. No provider invocation or funding operation is supplied.

Private preparation/verification rows remain subordinate to the original
submission. First settlement requires a current unexpired token; committed
receipt recovery follows owner/deletion checks and ignores later expiry/gate
changes. Active claims and verified receipts exclude ordinary M1 expiry
retirement. C1 cancellation abandons verified pending media through the original
transaction, without treating it as provider result evidence. Immutable backend
resolution survives private erasure but grants no I/O authority.

The injected storage signer must resolve the saved nonsecret profile to a
separately configured writer/eraser. The owner uses one raw fetch per request;
redirects and signing-client retries are excluded. Marker verification checks
actual empty content and the exact M2 metadata predicate before acknowledging a
current cleanup claim. No production dependency composition, authenticated
native reader, route, real backend or worker schedule is installed. Byte
matching does not attest executable transforms or hosted principal/lifecycle
guarantees. See the
[M2 contract](../../../../../docs/rfcs/initial-media-verification-interface-2026-10-11.md).

M2 receipts prove exact retained byte identity and declared-type signature
plausibility only. They do not validate container structure, decodability,
safety or executable derivation. Initial-route/media integration must provide
bounded structural/decode validation of the exact execution bytes for every
enabled format before dispatch. This remains an internal S0 prerequisite,
including malformed/truncated/polyglot and decode expansion cases as applicable;
M2 or hosted qualification alone cannot close it.

## Inactive no-media preparation v2

`preparationCandidate.ts` and its closed JSON schemas preserve the original
input-v1 semantics inside the explicit no-media v2 candidate and bind every
complete assignment field with a separate canonical digest domain. Shared
Unicode/order vectors run in TypeScript and SQL. They supply no transport or
provider grant. The fixed service database operations and versioned recovery
boundary are specified in the
[v2 API contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-no-media-initial-assignment-v2-inactive).

`tests/initial_saved_assignment.sql` verifies exact retry, drift before funding
writes, promotion rollback, C1/expiry and pre-row erasure. Run the portable
`scripts/test_initial_saved_assignment_contention.py --disposable-container <local-container>`
against an explicitly disposable migrated local database for opposed catalog,
consent and owner/request-lock schedules. It requires local Docker/psql, begins
with the gate disabled, uses synthetic owners and restores the disabled gate. It
never targets a hosted DSN. Full existing accounting and catalog gates remain
required because the comparison is inside shared quota owners. Media
preparation/transport/handoff and full S0 remain separate open work.

## Inactive media-source contract

`media-source-candidate-schema-v2.json` and `mediaSourceCandidate.ts` define a
source-declaration variant of the private preparation candidate. The dormant
database creator handles it in an explicit media branch; no installed handler or
native caller consumes it. Each original source role has exact metadata, indices
and transform options, with `prepared_output.state` fixed to `unresolved`. There
is no fabricated prepared hash or empty successful output. The separate source
semantic validator preserves existing initial route, ordered-text/timeline,
capture association and aggregate source limits without constructing a pretend
admitted input-v1 value.

`mediaPreparationProfile.ts`, `mediaAssignment.ts` and
`mediaPreparationResponse.ts` validate whole-cohort profile identity, exact
saved source mapping and closed metadata-only responses. Empty private catalogs
make fresh selection unavailable. Trusted database-owner installation receipts
record reviewed qualification; they do not independently prove runtime or
storage properties. The migration installs no profile, receipt, backend or
selection.

An accepted dormant allocation freezes source candidate, complete inference and
preparation assignment, fixed original-source object IDs and original deadline
in one transaction. Recovery returns those saved identities before fresh
selection. Revocation returns blocked metadata without replacing them.
Allocation itself supplies no prepared output or upload grant. The execution
extension below prepares original-result records; funding, provider dispatch and
M1 handoff remain unavailable. C1, expiry and strong erasure retire the
permanent source registry before private candidate/assignment/mapping deletion.
Cleanup is a separate metadata-only lease/acknowledgement owner with no
installed transport or scheduler.

Run `tests/initial_media_source_lifecycle.sql` for shared vectors and
rollback-only lifecycle tests. Run
`scripts/test_initial_media_source_contention.py --disposable-container <local-container>`
on a freshly migrated disposable local database for deterministic opposed lock
schedules. The runner uses synthetic installations, retires them and restores
the disabled gate; reset that disposable database before another suite.
Candidate CI executes it explicitly after database/Edge/advisor checks and
before teardown. These tests are not runtime, provider or physical-erasure
qualification. Video associations remain declarations, not verified derivation.
See the
[service contract](../../../../../docs/backend-and-data/05-api-contracts.md#inactive-media-source-candidate-contract).

## Inactive preparation execution coordinator

`preparationExecutionContract.ts` and the shared execution schema validate
source proofs, the original grant, output mapping, complete outcome and closed
RPC reply envelopes. `preparationExecution.ts` exposes a bounded synthetic
coordinator and process-local known-output reconciliation. Only the fresh issue
reply with owned verified source bytes can invoke runtime once. Exact
status/result recovery never invokes it. Phase deadlines use actual cohort rule
caps, absolute monotonic checks and conservative server-clock transfer. Fresh
known output goes directly to registration within its original five-second
allowance. Reconciliation status reads cannot extend that original deadline.

The dependency interface separates read-only original identity verification from
conditional fresh-object creation and read-back. Real storage/runtime adapters,
durable output recovery and qualification are deliberately absent. The fixed
transport resolves origin/key only from trusted server configuration, follows no
redirects and repeats no requests. Source/output private copies reject shared
memory. All production selectors remain empty; no live handler imports these
modules. Media finalization, funding and M1/M2 remain denied at outcome-ready.

Focused synthetic tests are `preparationExecution_test.ts`,
`preparationExecutionTransport_test.ts` and
`tests/initial_preparation_execution.sql`; they do not constitute hardware,
backend, runtime or installed-app qualification. See the
[execution contract](../../../../../docs/backend-and-data/05-api-contracts.md#inactive-original-preparation-execution-contract).

Run `scripts/test_initial_preparation_execution_contention.py` against an
explicitly named freshly migrated disposable local container for phase/C1 races,
duplicate issuance and raw competing-writer barriers. Candidate CI runs it after
resetting its disposable catalog following source-allocation contention. Neither
suite targets a hosted database. Failed schedules remain qualification failures
until a corrected exact candidate passes.

## Inactive handoff metadata and budget validators

`handoff-profile-schema-v1.json` and `handoffProfile.ts` validate closed
profiles and composite protocol manifests, exact canonical digests, supported M1
type pairs/limits, all eight sequential whole-cohort phase ceilings and their
sum. Pure arithmetic checks reserve `45,000 + preparation wall + handoff total`
strictly inside the supplied original expiry and derive fixed cumulative
admission cutoffs. Safe-integer subtraction preserves the boundary near the
maximum supported timestamp.

These are metadata helpers only. They do not install or qualify a backend, check
catalog eligibility, establish original identity, allocate media, issue a grant
or reserve funding. No live handler or existing assignment/grant imports them.
`fixtures/handoff-profile-v1.json` provides synthetic canonical vectors for
future SQL parity; SQL/catalog/assignment binding is still unimplemented.
Existing execution v1 and its 35-second future reserve remain unchanged and do
not become qualified for admission through these helpers. See the
[metadata contract](../../../../../docs/backend-and-data/05-api-contracts.md#inactive-handoff-metadata-and-budget-contract)
and the
[accepted handoff design](../../../../../docs/rfcs/initial-preparation-handoff-2026-10-11.md).

The private SQL handoff codec in migration `20261011224842` mirrors the accepted
Deno schema, domain-separated digests and strict issue/admission budget
arithmetic. `initialHandoffContractMigration.test.ts` pins both schema and
shared vectors; `tests/initial_handoff_contract.sql` exercises parsing,
arithmetic and revoked role access. This remains pure metadata validation,
without catalog installation, saved-assignment binding, actual cohort
qualification or funding authority.

`handoffCatalog.ts` adds private destination/installation declaration codecs and
a conservative one-per-profile-rule association template. Empty SQL catalogs
bind exact immutable source/destination/profile identities and retain revocation
separately. Nullable immutable selection binding cannot retrofit old
generations. The catalog migration itself does not adopt runtime owners;
actual-cohort grant/admission checks and external qualification are separate.
See the database and API contracts for template limits and digest domains. The
Deno helper checks declarations against each other; SQL owns comparison with the
retained private source and destination backend rows.

`qualifiedPreparationCodec.ts` and migration `20261011233227` prepare separate
closed assignment/allocation-v3 and grant/outcome/reply-v2 codecs. Nested
source, output and resolved receipts keep v1 and bind the original v3 assignment
digest. The outcome uses its explicit v2 digest domain. New helpers are revoked
invokers; the codec migration itself changes no resolver, action owner, grant
issuance, funding or route imports. Their context constructor validates supplied
declarations; a future owner must supply and compare the exact retained private
catalog/intent rows. Subordinate SQL helpers consume that constructed context,
not service input. The schema-only reply decoder is not receipt authority.
Original v2/v1 decoders stay unchanged.

Saved grant arithmetic includes the exact handoff profile/installation/protocol,
H, actual ordered-role W and original expiry E. Its strict issue + 45,000 + W +
H < E comparison is metadata validation. Future issuance still requires a fresh
server clock under the original locks, eligibility/deletion checks and the
actual-cohort resource/type/M1 bounds. Outcome coherence validates supplied byte
facts and mapping; it does not verify object bytes, global namespace ownership,
installed artifacts or durable issuance. Internal v1 validation projections are
never emitted or saved as rewritten original receipts. No S0 activation or
external qualification is claimed.

The gated SQL owner transition in `20261012000419` now binds new private media
allocations to immutable original qualification and applies actual-cohort and
fresh locked budget checks at issuance. Saved assignment v3 selects execution v2
while nested source/output/resolved stay v1. Old unissued v2 allocations are
held; already-issued v1 outcomes retain original recovery. Eligibility locks
serialize revocation without replacing saved identity. Raw INSERT and public
action checks share the same closure. This does not adopt either Deno runner or
ordinary HTTP/native routes, fund a request, activate catalogs, or qualify real
storage/adapter behavior. See the database/API owner-transition contracts.

## Inactive admission metadata codecs

`admissionMetadata.ts` and `admission-metadata-schema-v1.json` validate closed
phase-window v1, destination-mapping v2 and `media_binding` v2 metadata against
the original qualified candidate, assignment, catalog and outcome. The validator
snapshots each bounded value before awaiting. It projects initial input v1 from
original source metadata and validated output bytes, preserving ordered text,
context, options and timeline exactly. Input and description digests retain
their existing domains.

The three new domains are `merian.initial-analysis.handoff.phase_window.v1`,
`merian.initial-analysis.handoff.mapping.v2` and
`merian.initial-analysis.handoff.media_binding.v2`, each followed by one newline
and canonical JSON. The window binds original expiry and all eight cumulative
cutoffs with strict remaining-budget arithmetic. Mapping binds the opaque
receipt ID, source/destination generations and exact ordered original byte
identities. It rejects collisions with original objects, cross-ordinal aliases,
incorrect unions and saved-profile resource/type violations. Equal byte tuples
within one ordinal share a destination; different bytes use distinct objects.
Only raw video has null prepared output. The binding includes mapping/window
digests but never an enclosing receipt digest.

Private SQL counterparts share the same closed schema and synthetic vectors.
These remain pure metadata codecs without runtime owner adoption. A digest
proves neither registry freshness nor verified storage bytes, live ownership,
funding or dispatch authority. The
[admitted-proof design](../../../../../docs/rfcs/initial-admitted-proof-2026-10-12.md)
now fixes eleven mandatory complete canonical components, a closed acyclic
manifest, exact accounting/timestamp fields and atomic private erasure. This is
accepted interface design; its complete codec, durable storage and coherent
funded runtime are not implemented by the metadata codecs. Existing M1/M2
readers do not accept these new versions. No RPC, table, live route, generated
capture DTO or activation changes with these codecs. SQL helpers use an empty
search path and revoke execution from PUBLIC and all API roles, including
service_role. The wrapper derives qualified context from original canonical
documents; it cannot accept a prevalidated caller context or access current
selectors.

Qualified preparation context now snapshots candidate, assignment and each
catalog component independently before its first await. The internal context
container adds no aggregate canonical document ceiling: each original component
still satisfies its existing byte, depth and node limits and every existing
semantic/digest check. This preserves large valid text (including escaped and
non-BMP strings) without relaxing a wire limit or granting runtime authority.
The inactive `admittedProof.ts` codec now consumes all eleven fixed canonical
TEXT components plus the closed manifest. It validates original qualified
context, exact projected input, byte counts, domain-separated digests, saved
provider/protocol selection, complete funding and historical accounting links.
It preserves microsecond timestamps without Date conversion and independently
snapshots each component before awaiting. The 2,469,915-byte retained TEXT
ceiling excludes storage overhead. Funding's effective model is distinct from
the attempt's quota model; fallback requires the original free plan and no
complimentary hold. Bucket nonblank semantics match PostgreSQL space trimming;
original bytes are never normalized.

`admitted-proof-schema-v1.json` and complete synthetic golden/negative vectors
also define the private SQL parity boundary. Four revoked helpers provide the
schema, bounded component pre-parser, exact Gregorian timestamp validation and
`internal.validate_initial_admitted_proof`. The composite accepts twelve fixed
TEXT arguments and returns only the computed receipt digest. It reuses the
specialized original metadata/context validators; the component pre-parser alone
is not full proof validation. Each original is bounded before parsing and is
never serialized into one aggregate JSON document. All helpers use empty search
paths and invoker security, with no API-role execution privilege.

These pure decoders check internal historical consistency only. They neither
read current selectors nor prove live ownership, archive availability, policy
eligibility, actual charged rows, unused execution or dispatch authority. Locked
expected-image comparisons, private storage/erasure and the coherent funded
runtime remain open. No runtime caller, public DTO, route or activation changes.
SQL fixture/catalog and Deno schema/vector equality evidence are retained in
`.artifacts/initial-admitted-sql/`; this is not hosted or installed
qualification.

## Inactive admitted recovery response codec

`admissionRecoveryResponse.ts` and `admission-recovery-response-schema-v2.json`
implement the closed version2 `admitted`, `transferred`, and
`held/already_transferred` envelopes from the
[handoff contract](../../../../../docs/rfcs/initial-preparation-handoff-2026-10-11.md).
Every variant carries `authority: none`. Admitted/transferred replies retain
exact M1 binding v2; response version is independent of admission binding v3.
The 32 KiB envelope and 16 KiB binding ceilings apply before acceptance. Nested
identity, ordered cutoffs and the phase-window digest must agree. The decoder
snapshots before hashing and never uses a current clock to grant authority.
Private SQL parsing uses the same schema and synthetic positive/negative
vectors.

This is consistency validation only: arbitrary well-formed receipt digests do
not prove a stored admission or transfer. A transport caller must correlate the
reply to its original operation. The future locked response owner must check
live ownership, deletion and cancellation, then exact transfer, exact admission,
and only then unadmitted intent. Explicit prepared SQL status,
finalization-retry and media-retry branches now return the admitted envelope
from the original receipt. No native decoder, Identify DTO or live HTTP route
adopts it. The earlier synthetic admission and distinct-session recovery probes
were exploratory. The checked-in portable suites now have independent and IC-1
source/retained-runtime concurrence for bounded local recovery, positive-unused
C1, eligible expiry and erasure cases. This does not close the coherent
atomic/M1/C1 checkpoint: final shared-harness matrix and full candidate gates
remain required. Fresh media finalization and live transport adoption remain
closed pending their later reviewed owners.

The Deno codec takes a parsed value and canonicalizes it; SQL requires canonical
TEXT and rejects alternative spellings. Shared semantic vectors do not establish
raw-wire lexical parity. The eventual transport still needs a streamed byte cap
before JSON parsing and original request/account-lease correlation. In
particular, the held envelope contains no owner or scan identity; its digest
alone cannot associate it with the currently displayed operation.

The new revoked `internal.recover_initial_admitted_media` is a private,
admitted-only owner used by those explicit prepared SQL recovery branches. The
shared legacy recovery helper and no-media intent DELETE guard remain unchanged.
It holds canonical owner/deletion/cancellation scope, then locks owner-scoped
admission, submission and receipt in established order. It requires bindingv3, a
positive pending/dispatch-authorized lifecycle and no active admission stage,
then checks complete retained receipt integrity. No intent/source/current
funding or catalog lookup is used. The server clock is sampled after locks and
proof. The pure revoked constructor returns copy before the original copy cutoff
and expired at/after; pre-anchor observation rejects. Elapsed time never invents
verification or transfer progress. A dispatch-authorized lifecycle permits only
historical metadata recovery; even a copy phase carries no copy permission.

Media preparation retries validate their canonical candidate, then compare its
complete original bytes to the locked receipt before replay. Changed supporting
text/order/media cannot fund or recover as the original request. Recovery occurs
before mutable intent lookup and expiry handling. Presence of either v3
admission or receipt routes into full validation, so missing half-state fails
closed. Fresh media finalization is still denied; existing ACLs/signatures are
unchanged.

The five legacy preparation execution endpoints (source settlement, issue,
output registration, outcome settlement and execution status) also intercept
admitted v3 before intent lookup or expiry. They validate the locked original
owner/receipt and assignment digest, then return the existing qualified v2
`held/incoherent` reply with `authority:none`. They never enter legacy automatic
cancellation or return a fresh execution grant. Missing co-retained records fail
closed. Admitted metadata recovery belongs to the dedicated prepared recovery
branches above; no new response union is added to execution endpoints. Raw
scan/account erasure and explicit C1 remain separate owners. Automatic v3 expiry
still needs a reviewed state/deadline policy; the copy-phase `expired` label
grants no cancellation or refund authority.

The original rollback and exploratory committed-session probes remain historical
evidence. Checked-in portable qualification now covers the documented
recovery/deletion orders, service-role C1, eligible expiry and erasure
boundaries with independent and IC-1 source/retained-runtime concurrence. The
final matrix on the complete shared harness and full candidate qualification
remain open; these local SQL results do not qualify media transfer, providers,
workers, HTTP or installed journeys. Transfer precedence still requires its
later durable owner. No transferred response is manufactured from absent
progress or intent rows.

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

The private C1 entry stage now obtains its own locked prestate and current xid;
non-null caller proof/xid is rejected, and no API role has table or routine
access. It cannot arbitrarily update, delete, truncate or commit: its deferred
insertion check deliberately always fails until the closed terminal owner is
implemented. This rollback-only preparation opens no cancellation/refund route.
Future original-owner statement/clock witnesses and post-erasure terminal
validation remain required; see the admitted-proof RFC. No private snapshot may
enter a response, log or durable recovery record.

The original quota finalizer's post-lock sampling expression has a private C1
hook, still behind its unchanged admitted-settlement denial. A current entry
must match original reservation/owner/lease/refund state; the guard recaptures
unchanged locked prestate and generates the clock internally once. No-entry
behavior remains ordinary wall-clock sampling. This is a clock seam only, not an
accounting event witness, action exception, or successful C1 path.

The prepared C1 quota witness ledger instruments the existing quota owners'
original DML sites. Expected images come from the guarded snapshot and bound
clock, with exact BEFORE checks and single winning AFTER consumption. Shared
counter zero-row deletes and unordered link deletes are explicit. All API roles
are denied ledger/registrar access; a trusted migration administrator is outside
that caller boundary, so this is not SQL call-stack attestation. The quota phase
rejects unregistered or unrelated accounting writes in the transaction. All
action fences and unconditional deferred rejection remain closed. At that
quota-only boundary, credit, lifecycle, retirement/erasure and final terminal
witnesses were still absent; a complete quota ledger is not cancellation or
refund authority.

The prepared C1 credit witness records original settlement separately while
retaining quota phase and its guards. It explicitly captures the locked usage
lookup's FOUND before instrumentation. Held credit requires an original clock,
exact released-hold event and a users event incrementing both epoch and
entitlement version, with other fields unchanged. Absent credit has no clock or
events. Original return flags and the existing complete accounting comparator
must pass before the credit witness completes. The existing fence is retained;
credit evidence alone grants no lifecycle, erasure or public action authority.
Later terminal evidence must not depend on rereading erased receipts.

The fixed credit member trigger is SECURITY DEFINER with an empty search_path
and no API EXECUTE grant, so permitted authenticated users updates can inspect
the no-stage condition without access to private proof. It grants no table
privileges or snapshot-returning API. Ordinary direct user writes are tested
independently of the privileged settlement chain.

The prepared lifecycle witness now brackets the existing cancellation UPDATE
with fixed begin/end hooks. It requires closed quota and complete credit
witnesses plus a fresh accounting comparison while the receipt exists, then
captures exactly one full pending-to-cancelled_pre_dispatch lifecycle event.
No-stage legacy calls remain unchanged. Main stage stays quota, preserving
accounting guards, and completed lifecycle evidence blocks further writes. The
admitted transition fence and deferred rejection remain closed; registry
retirement, erasure, cancellation receipt and final deferred proof are still
required before supported C1. See the admitted-proof RFC for this bounded
rollback-only protocol; witness presence grants no action authority.

Prepared retirement witnesses now instrument the existing source/output and M1
destination retirement owners in that order. They require exact original
membership, completed lifecycle/accounting and full fence/registry events;
complete witnesses allow only exact zero-write reentry for later DELETE
triggers. No-stage callers are unchanged. Retirement retains cleanup metadata
and proves no physical deletion. Public C1 composition, terminal proof/seal and
public action exceptions remain absent; see the admitted-proof RFC for the
bounded protocol and current candidate evidence for its validation status.

Authentic C1 capture now additionally freezes a bounded15-relation private
cascade inventory, including source/output mappings and explicit empty
downstream sets. The source mapping is locked before capture; count and byte
preflights precede aggregation. Outside the exact root protocol below, every
private mutation remains denied while the C1 stage survives. Shared
configuration assets and permanent storage metadata remain outside that deletion
inventory. Capture alone grants no deletion authority; public C1, terminal
receipt/proof composition and the surviving denial seal remain unimplemented.
See the admitted-proof RFC's private erasure-image boundary and candidate
evidence for its qualification limits.

The prepared private erasure owner deletes submission before preparation intent
only after original accounting/lifecycle and both retirement proofs complete. It
freezes receipt-independent accounting postimages before the first cascade, then
observes exact unique full-OLD DELETE events with winning AFTER witnesses. Root
closure absence includes initially empty relations. Existing retirement triggers
must make zero-write reentry; private recreation and late provider-attempt
mutation remain denied. This owner is revoked from API roles and is not called
by public C1. Unconditional deferred rejection remains until minimal terminal
receipt, transient-proof consumption and a surviving denial seal are composed
and reviewed. No activation or supported erasure qualification is implied.

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

### Explicit cancellation integration candidate

The current uncommitted candidate routes the service-only cancellation wrapper
to a dedicated revoked C1 compositor. Earlier no-compositor statements above
describe prior private-helper checkpoints. Generic account/legacy erasure
remains separate, exact terminal replay wins, and a pending admitted footprint
with invalid proof fails closed without fallback. See the
[dedicated owner contract](../../../../../docs/rfcs/initial-admitted-proof-2026-10-12.md#dedicated-explicit-cancellation-candidate-october-12)
for the original-owner exceptions and remaining qualification boundaries. Local
synthetic endpoint evidence does not enable activation or qualify the full
atomic checkpoint.
