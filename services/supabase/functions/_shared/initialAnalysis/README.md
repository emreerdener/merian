## Private verification-to-admission coordinator

The private [CPM photo request preparer](cpmPhotoExecutionRequest.ts) consumes
the saved allocation, original admission acknowledgement, a trusted server
profile and the supplied AI-role bytes. It has no installed profile. It binds
the supplied bytes to the original account, scan, backend and assignment. It
carries the funding identity from the original receipt to the SQL dispatch
owner. It uses the existing Gemini serializer for the qualified fixture
combination (English, vision compatibility). A lost receipt is handled by the
original recovery owner. See the
[scan guide](../../../../../docs/development-guides/25-scan-to-history.md) for
the distinction between prepared input and permission to send.

`cpmPhotoAdmission.ts` owns recovery-first sequencing, one committed fresh
start, one verification and one admission attempt, then receipt-only
reconciliation. Its injected tests cover identity, uncertainty and deadline
boundaries. The
[CPM contract](../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md)
owns the complete binding and retention requirements. `cpmPhotoVerification` now
consumes actual exact-byte reads with shared JPEG/still-PNG/still-WebP and
bounded HEVC still-item inspectors, one reusable bounded buffer and
complete-cohort lifecycle checks. It feeds the coordinator directly; it is not a
standalone codec or client proof. Remaining HEIF nested-grid/non-alpha
auxiliary/sequence/codec forms, camera/import corpus coverage beyond four local
ImageIO fixtures, PNG/WebP animation policy, installed policy and serving route
composition remain unqualified or absent. The dormant database bridge described
below now implements atomic admission without activating this composition. This
increment is uninstalled and does not qualify physical resource limits or
funding.

The same verifier owner now provides `cpmPhotoVerificationCatalog` for trusted
bootstrap composition. It snapshots at most sixteen supplied entries before any
await, rejects ambiguous mappings and resolves only the saved profile/build/
backend-generation/configuration tuple. It reuses the existing source-backend
decoder and returns frozen dimensions and nonsecret backend metadata. One build
cannot carry conflicting limits and one profile cannot select multiple builds
within a catalog. No entries, environment loader, SQL eligibility bypass or
activation are installed. Retained recovery and held starts bypass the loader;
an unavailable fresh tuple remains held before media I/O. The CPM contract owns
qualification and cross-deployment immutability requirements.

The admission coordinator also derives the prepared schema-2/binding-4
submission projection immediately before its one admission call. It retains the
whole saved content string and ordered base64 context objects, using a distinct
context digest domain. The private SQL projection and coordinator share a
synthetic parity fixture. This does not install SQL admission or change legacy
readers/constraints; the
[CPM contract](../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md)
owns the exact representation and coordinated persistence requirements.

`cpmPhotoAdmissionDb.ts` supplies fixed service-role recovery, begin and atomic
admission calls for the verifier composition. Its closed observation schema is
`cpm-admission-bridge-response-schema-v1.json`; uncertain reads reject rather
than reporting absence. Exact committed recovery does not repeat verification or
funding. The corresponding service-only migration preserves original accounting
owners and legacy routes. No serving route imports this adapter. Seven injected
transport tests cover lost replies, held recovery, deadline/body bounds and
immutable requests. The maintained local bridge runner adds ten committed RPC
ordering schedules with fresh service begin and original funding checks. Earlier
replay covers rollback and role denials. The canonical CPM contract above
records exact evidence and remaining integration/review gaps. The two public
scan-deletion orders exercise the real pre-row `not_found` response and prove
that it changes no admission or funding state; they do not qualify deletion of a
saved scan after a result exists.

The maintained `initial_cpm_admission_bridge_contract.py` additionally checks
exact identity denials, committed policy revocation with original
receipt/funding recovery, rollback and post-C1 denial through actual
service-role calls. A further adapter case covers two photos,64 contexts and the
full32000-unit text aggregate, with excess rejected before transport. The
canonical CPM contract above owns the exact evidence and failure/correction
history. Missing-row and contradictory-state recovery now reject through the
actual reader with rollback preserving the original cohort and funding. Local
verifier/database composition and HTTP recovery overlapping pending COMMIT are
qualified within the loopback harness described below. SQL function execution
continuing beyond its timeout and installed integration remain unqualified.

`createCpmPhotoAdmissionDb` now also provides the verifier's `requireCurrent`
callback. The service-only current-start assertion validates the exact original
attempt/snapshot and complete cohort against current eligibility, ownership and
original expiry. Its acknowledgement grants no lease or restart authority.
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#dormant-current-verification-observation--november-2)
owns the wire boundary. `createCpmPhotoAdmissionRuntime` now joins this adapter,
the immutable verification catalog, existing per-object closure database checks
and actual byte/structure verifier. It compares each loaded binding and target
before the original current-input check, then retains the verifier's checks
around signing/reading and final atomic admission. Trusted bootstrap supplies
profiles and signer/storage transport; no route, profile or signer is installed.
Injected-transport composition is tested. The local runner now also checks tiny
physical JPEGs against actual service SQL through a loopback HTTP shim; the
canonical CPM contract records its exact outcome and timing. PostgREST/JWT, real
signer/storage, representative resource/latency and native integration remain
unqualified.

## Dormant authenticated transfer composition

The source-only
[`initial-photo-transfer`](../../initial-photo-transfer/README.md) facade now
composes the existing issuer and status bridge with authenticated allocation
recovery and an injected immutable policy catalog. No shared owner is replaced
and no serving entrypoint, profile or native caller is installed. The
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#dormant-authenticated-photo-transfer-facade--october-30)
owns its boundaries; the scan guide records local aggregate qualification and
remaining native/provider exclusions. Earlier private-only checkpoint statements
below retain their historical scope.

The coordinated SQL admission batch is under construction. Its private stage
constructor now compares complete verification with the original locked cohort
and captures retained ownership. Its finite member projection and write
witnesses now describe the retained-capacity UPDATE without allocating M1
copies. Closed variant storage now permits private atomic persistence using the
original accounting witnesses; local synthetic admission has committed through
the complete deferred checks. Admitted capacity preserves retained-byte
liability and blocks generic settlement even after private receipt erasure. The
cohort assertion compares original saved roles, attempts, closures and capacity;
private retained-receipt parsing branches without renewing verification. Neither
provides fresh execution authority. C1 now captures permanent
capacity/attempt/closure images separately from private erasure and verifies the
proven-empty CPM destination through the existing retirement and terminal-image
owners. Committed local public cancellation now passes after correcting a legacy
retirement-witness shape constraint, including exact replay without a second
refund and permanent-media preservation. Focused cutoff and peer eligibility
ordering checks pass locally. Private retained reads preserve exact accepted
bytes after policy revocation; the legacy public recovery paths still fail
closed for CPM. A populated upgrade preserves a committed legacy admission, held
funding and a separate pending preparation, with exact internal row hashes;
legacy recovery and public cancellation/replay pass afterward. Held-credit CPM
account erasure also passes rollback/commit with unchanged original accounting
across the privacy fence and exact ownerless retained-media liability. It uses
the existing non-settling account path; explicit C1 alone owns positive-unused
settlement. Actual elapsed expiry, pending CPM upgrade, remaining concurrent
orders and app integration remain unqualified. The canonical CPM contract above
owns its exact scope and validation limits; no bridge or route is installed.

## Inactive bound CPM recovery

`cpmPhotoBoundRecovery` adds a separate closed v3 metadata validator while
preserving `cpmPhotoRecovery` v1. It checks the generation against the validated
assignment; the SQL wrapper binds the opaque configuration digest to the saved
immutable registry row. The
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#october-30--inactive-v3-allocation-backend-projection)
owns projection, authority and native integration limits. This codec installs no
signer, backend profile or route activation.

## Role-aware source MIME candidate — October 30

The existing observation target validator now distinguishes retained originals
from JPEG-only AI/display derivatives. Ticket decoding reuses that validator;
signing still binds the exact submitted type, length and digest. The
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#role-aware-cpm-source-mime-candidate--october-30)
owns the closed vocabulary, immutable profile boundary and coordinated local
qualification: native 20 methods / 42 cases and a fresh-database backend run of
4,099 tests / 748 steps. Physical-format, provider and full-journey
qualification remain open. No original conversion, profile or route installation
is introduced.

## Dormant transient upload ticket

The existing issuer now returns its private issued capability through the closed
`cpm-photo-upload-ticket-schema-v1.json` and `cpmPhotoUploadTicket.ts`
validator. It binds the exact role bytes, saved identity/backend and original
clocks, and rejects header/destination/SigV4 metadata substitutions before
returning. The
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#dormant-transient-cpm-ticket-contract--october-30)
owns the 8 KiB envelope, field bounds, secrecy and compatibility rules. Tests
remain beside the issuer; there is no additional issuer or retry owner. Native
consumption, route/profile installation and provider qualification remain open.

## Typed historical upload-status observation

`cpmPhotoWriteStatus.ts` validates the closed
`cpm-photo-write-status-schema-v1.json` projection against saved allocation
identity, clocks and prior monotonic facts. `createCpmPhotoClosureDb.readStatus`
uses the fixed service RPC once; no begin or retry follows absence or failure.
The
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#dormant-cpm-write-status-service-projection--october-29)
owns its rules and native parity. Tests are in `cpmPhotoWriteStatus_test.ts` and
`cpmPhotoClosureDb_test.ts`. This adapter remains uninstalled.

## Dormant CPM upload issuer

`cpmPhotoUploadIssuer.ts:issueInitialCpmPhotoUpload` consumes the fresh-only
service acknowledgement through `cpmPhotoClosureDb.ts`, reuses saved-role
planning and signs the exact conditional request using explicit host profiles.
Held/unknown results cannot sign or retry; lifecycle is rechecked before signing
and delivery. Tests beside the issuer and bridge use synthetic credentials and
no storage IO. The
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#dormant-cpm-issuer-service-composition--october-29)
owns the private boundary; the
[scan guide](../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--dormant-concrete-upload-issuer-candidate)
owns evidence and remaining hosted/native qualification. No profile, route or
native consumer is installed.

## Inactive CPM write observation

`cpmPhotoWriteObservation.ts` performs one bounded direct read of the exact
original v2 object, yielding only frozen identity/outcome facts after lifecycle
checks and full-byte or retired-marker verification. It reuses the existing
backend codec and deadline owner; its bounded reader hashes incrementally
without retaining media chunks or building an aggregate media buffer. The
[current CPM checkpoint](../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md#november-2--cpm-verification-and-admission-consuming-boundary)
records this implementation and its remaining structural/resource obligations.
This observation has no issuance, settlement or capacity-release authority. The
[scan contract](../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#inactive-cpm-storage-observation)
owns limits, validation status and the remaining production
bridge/payload/memory qualification. Focused synthetic tests are in
`cpmPhotoWriteObservation_test.ts`.

`cpmPhotoWriteClosure.ts:closeInitialCpmPhotoWrite` joins that actual
observation to an injected authoritative database bridge. It freezes original
facts and the marker claim, preserves a settlement reserve within managed
deadlines, and recovers uncertain settlement through an exact receipt read.
Tests live beside it in `cpmPhotoWriteClosure_test.ts`. The bridge and signer
remain uninstalled; the linked scan contract owns their obligations and local
validation/review status.

`cpmPhotoClosureDb.ts:createCpmPhotoClosureDb` provides the dormant service
adapter using environment-owned credentials and a fixed origin. It consumes an
already-owned marker token, never claims one, and preserves exact six-fraction
UTC receipt timestamps through `cpmPhotoWriteClosure.ts` decoding. The
[database service contract](../../../../../docs/backend-and-data/04-database-schema.md#dormant-cpm-closure-service-boundary--october-29)
owns the RPC signatures, limits and qualification status. Tests are in
`cpmPhotoClosureDb_test.ts`; no live route or signer is installed.

`cpmPhotoUploadSpecification.ts:prepareCpmPhotoUploadSpecification` prepares a
frozen conditional-create specification from saved facts and an injected host
profile allowlist. It uses the existing v2 backend and role decoders, preserves
the original expiry and rejects operation/header/metadata overrides. It has no
credentials, signer, network I/O or issuance authority. Its required payload
digest explicitly remains unqualified by the provider. Tests are in
`cpmPhotoUploadSpecification_test.ts`; the linked scan contract owns the
remaining issuance, payload-enforcement and separate marker-writer obligations.

`cpmPhotoMarker.ts:eraseInitialCpmPhotoWrite` is the separate inactive permanent
marker executor. It recovers historical closure first, then preserves one
original snapshot/claim through at most one zero-byte overwrite and the existing
observation/settlement coordinator. Signer substitutions fail before dispatch;
unknown write acknowledgement permits exact recovery, never a repeated PUT.
Tests are in `cpmPhotoMarker_test.ts`. The linked scan contract owns deadlines,
claim fences and unqualified hosted behavior. There is no installed eraser
signer, route or claim-acquisition owner here.

## October 27 — inactive photo CPM content declaration candidate

`cpmPhotoContent.ts` validates a closed, bounded photo declaration and hashes a
private canonical snapshot in its own versioned domain. It preserves logical
reference order, exact text and finite native recipe bit patterns under P1-L1.
It consumes claims, not trusted byte-verification or server-transform proof. No
live route imports it; legacy admission and generated Identify DTOs remain
unchanged. The
[content contract](../../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md)
records the native mapping and remaining consuming-adapter agreement. Source
review cleared the pure codec. Ten focused tests, the full Edge suite and static
checks passed; tooling coverage completed across retained runs after correcting
stale recovery documentation and rerunning a terminal-dependent synthetic test.
The contract records exact counts, skipped tests and the retained failures. No
allocation, upload, funding, dispatch, completion or activation is enabled.

# Prepared initial-analysis admission

This inactive IC-1 boundary belongs to the initial engine. No live route or
worker imports it. The server gate defaults false. Admission and replay return
identity, never permission to dispatch. Existing capture DTOs are unchanged.

## Current local qualification — October 13, 2026

The coherent atomic-admission/original-funding, M1, recovery and C1
cancellation/expiry checkpoint is accepted locally at
`bc2a5af507a0ee56cbdb1a357f5221bec611371b`. Exact shared-checkout gate results,
independent and IC-1 acceptance, the stage93 residual-risk disposition and DB85
disposal are retained in
`.artifacts/initial-atomic-admission/final-gates/local-checkpoint.json` at the
repository root. All 18 portable suites passed 289 checks; full pgTAP, Edge and
affected tooling gates passed. This is not isolated commit-tree or hosted
qualification. Stage93's original eight deadlocks remain unreproduced with
unknown cause; new lock graphs require new qualification.

Earlier incremental qualification statements below describe the stages leading
to that checkpoint; this dated note supersedes their pending-matrix,
uncommitted-compositor and incomplete-C1 status only. It does not change their
technical contracts or make a pure codec authoritative. The later private M2 v2
runtime family is locally qualified as summarized below. Structural validation,
provider dispatch, result capture, completion and native integration remain
open. The next
[S0 dispatch-fence agreement](../../../../../docs/rfcs/initial-dispatch-fence-interface-2026-10-13.md)
is a draft requiring review before implementation. Fresh requests require
photo/audio/video; historical no-media codecs do not expose a new text-only
journey. Activation stays false and ordinary production access nil.

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

## Inactive admitted M2 v2 proof codecs

`mediaHandoffProof.ts` and `media-handoff-proof-schema-v1.json` prepare the
closed original verification claim v2, verification receipt v2 and transfer
receipt v1. Their independent canonical caps are 32, 64 and 96 KiB; nested
documents retain their own ceilings, including the original 16 KiB M1 binding.
The validators consume complete original admitted components through
`validateAdmittedProof`, compare the original binding/profile and exact sorted
destination union, and enforce cross-document identity, digest and saved-cutoff
consistency. Every result has `authority: none` and returns canonical bytes and
a domain-separated digest. Caller inputs are snapshotted before yielding.

The three validation functions are `validateMediaVerificationClaim`,
`validateMediaVerificationReceipt` and `validateMediaTransferReceipt`.
`mediaHandoffProofDigest` checks canonical shape/bounds only; it does not
perform original-proof correlation. Even full consistency validation cannot
establish stored token issuance, timestamp provenance, actual byte reads or
structural validation. A coherent synthetic alternate token can pass; the later
locked owner must enforce its stored original. The candidate's nine synthetic
cohorts reuse the original admitted photo/audio/video fixtures and independently
calculated digests. They do not attest physical media or provider execution.

This candidate supplies no SQL storage/writer, original claim RPC, durable copy
progress, transfer/C1 integration, native DTO or route. Existing M2 v1 behavior
and its admitted-v3 denial remain unchanged. The
[concrete M2 v2 contract](../../../../../docs/rfcs/initial-media-handoff-v2-interface-2026-10-13.md)
records the open durable owner, effective lock, erasure and structural/transform
qualification required before execution. Activation remains false.

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

Raw invocation inserts meet dispatch authority before the preparation row
barrier once their permanent operation fence commits. The contention fixture
requires that exact dispatch denial after allocation and cancellation, then
independently checks the preparation helper's denial for the same identity, the
permanent blocked source barrier and absence of any invocation row. In-flight
allocation and stale-snapshot probes retain their exact scope-busy and isolation
errors. No production trigger is disabled or reordered.

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

### Explicit cancellation integration candidate (historical, October 12)

The October 12 uncommitted candidate routed the service-only cancellation
wrapper to a dedicated revoked C1 compositor. Earlier no-compositor statements
above describe prior private-helper checkpoints. Generic account/legacy erasure
remains separate, exact terminal replay wins, and a pending admitted footprint
with invalid proof fails closed without fallback. See the
[dedicated owner contract](../../../../../docs/rfcs/initial-admitted-proof-2026-10-12.md#dedicated-explicit-cancellation-candidate-october-12)
for the original-owner exceptions and qualification boundaries at that stage.
Those selected local endpoint results alone did not qualify the full atomic
checkpoint; the October 13 status note records its subsequent complete local
acceptance. Neither stage enables activation.

The qualified private SQL parity checkpoint in
`20261013082827_prepare_initial_media_handoff_proof.sql` mirrors these pure
codecs through a kind selector, twelve original TEXT components and three stage
document slots. Later slots must be SQL NULL for earlier stages. All API roles
remain denied; no runtime state or authority is introduced. Independent/IC-1
source review and disposable parity/catalog/role-denial qualification are
recorded in the handoff RFC. This remains pure consistency validation, with no
issuance or media-I/O authority.

Private v2 handoff qualification now has separate `mediaHandoffRows.ts`,
`mediaHandoffStorage.ts`, and `mediaHandoffExecution.ts` owners. They validate
the original private proof chain, pin source/destination backends, retain
verified private bytes through conditional copy, and use one immutable
whole-cohort monotonic deadline derived from the original state observation.
Fresh SQL facts are reloaded before storage and after signing. Unknown SQL
acknowledgement allows bounded original-state recovery and ends that attempt; it
never retries mutation, funding or provider work. Historical status is a
separate read-only entry point. These modules have no production composition or
installed signer. The trusted attestation dependency must verify saved artifacts
and the executing adapter; synthetic tests do not provide installed artifact
qualification.

`services/supabase/scripts/initial_media_handoff_bridge.ts` is a local-only
qualification bridge to the current checkout's owned disposable replay. Each of
its nine fixed methods uses a separate READ COMMITTED transaction, fixed 5s
statement/1s lock limits, bounded subprocess I/O and a post-COMMIT
acknowledgement. No ordinary API role receives access. Real bridge integration,
effective mutation/lock families and the affected runtime gates now have
recorded local evidence, including fresh current-source
owners/readers/transferred-C1/cleanup/video-audio qualification. The full family
passes 172 catalogs / 6,706 assertions and 3,935 Edge tests / 598 steps, strict
lint and advisor gates (warnings retained). Portable runner v8 and CI wiring are
reviewed. The current runner adds a 22nd suite for the legacy four-argument
quota boundary; its new qualification is separate from those retained results.
Runtime activation remains disabled; the combined hosted 22-suite duration is
unqualified. See the runtime RFC and
`.artifacts/initial-media-handoff-v2/runtime-implementation/` for exact source
manifests, independent/IC-1 family decisions, outcomes, disposal and local
commit identity. This is shared-checkout synthetic qualification, not installed
signer/backend, structural media or device qualification. The observed 4,781 ms
video/audio transfer against 5 seconds is not robust tail headroom. Every
provider/execution/activation barrier remains closed.

### S0 accounting composition draft

`dispatchAccounting.ts` is an uncommitted integration draft consuming the shared
AI accounting port. No route installs it and its fixed SQL dispatch/report
producers are not implemented. It exposes only one `invoke` attempt, retaining
no public generic quota lease: a failed, held, cancelled or uncertain dispatch
cannot retry, refund or call the provider. Ordinary accounting remains
unchanged. After a fresh grant is positively received, invocation proceeds
without another foreground-cancellation check. The one-attempt guard is local to
this instance; safe reconstruction requires permanent SQL dispatch uniqueness
and replay without a fresh grant. Foreground cancellation does not cancel
required usage reporting; reporting has its own five-second deadline and failure
cannot discard a valid original outcome. Result validation/storage and
completion still belong to the remaining integrated chain. Successful invocation
returns the original invocation identity alongside its unchanged outcome so the
durable result writer can bind them; that identity is not another execution
capability.

The private transport sends exactly the reviewed fixed operation arguments for
`authorize_initial_analysis_dispatch` and `report_initial_analysis_usage`.
Canonical expected binding is bounded to 2048 bytes, supplied execution evidence
to64 KiB, and each streamed response to8192 bytes within five seconds. It uses
one fetch, no redirects, credentials omitted and no-store. Its evidence check is
structural/canonical only: trusted upstream preparation must bind the exact
original verified buffers and execution, and the future SQL compositor must
validate the complete witness. A digest or injected dependency is not media or
execution authority.

The executable private reply decoders are colocated with the transport:

- Dispatch requires exactly `version = 1`, original `owner_id`, `scan_id`,
  `submission_digest`, `admission_receipt_id`, `admission_receipt_digest`,
  `outcome` and `invocation_id`. Only `fresh` plus a valid original invocation
  UUID grants this local call; `held` requires a null invocation and grants
  nothing. Replay/status documents cannot become a fresh acknowledgement.
- Usage requires exactly `version = 1`, original `owner_id`, `scan_id`,
  `submission_digest`, `invocation_id` and a valid `event_id`. No provider
  output is transmitted as usage; original native usage facts retain their
  existing normalization. Unknown execution uses the canonical empty usage
  object.

These private draft contracts have no Swift/web/admin consumer or generated
Identify DTO change. The SQL producers, phase-specific guards, immutable result
capture, adoption and completion remain required in the same integration before
any callable grant or activation. The
[S0 contract](../../../../../docs/rfcs/initial-dispatch-fence-interface-2026-10-13.md)
owns that boundary. Focused transport tests use synthetic replies and deny
network access; they do not establish database authority or functional
acceptance.

### S0 immutable result capture draft

`resultEvidence.ts` consumes the original dispatch invocation and the route's
validated Identify data before completion entitlement or media promotion. It
requires a draft outcome plus the existing success-envelope semantic validation;
raw provider drafts, refusal and unqualified primary-identification profiles
cannot become durable results. Original provenance must equal the prepared
execution, and original bounded usage facts survive a failed usage report.
Capture copies canonical result/provenance/reference strings synchronously
before hashing awaits, so later caller edits cannot change the submission.

`resultEncoding.ts` traverses the frozen private `resultSchemaV1.ts` definition
with strict unknown-key rejection; it makes no live public parser calls. Only
schema-declared fractional numbers become expanded decimal strings; integer
fields, omission, explicit null, text and array order retain their meanings.
Writes and every recovery decode reject negative zero, non-finite values,
alternate decimal spellings and finite values that change on an IEEE round trip.
Getters, toJSON hooks and sparse arrays are rejected. Public Identify numeric
DTOs remain unchanged. `resultSemanticsV1.ts` preserves the original
primary-result rules and constants. Its result type is inferred from the frozen
definition, not asserted to be a future public DTO. Delivery must use an
explicit compatibility adapter if the public shape diverges. The existing
tooling gate discovers `initial_result_v1_contract_test.ts`: structural
comparison and a full source fingerprint cover the dependency-free public
parser's transitive helpers and constants. Any drift requires an explicit
compatibility decision, including harmless additions; it must never
automatically regenerate or loosen retained v1 rules. Frozen saved evidence and
semantic/scalar vectors cover recovery independently of current capture. The SQL
validator must consume the same frozen rules; that producer and SQL parity
remain required before installation.

The result and separate provenance digests use the reviewed version-one domains
with one actual LF byte. Recovery checks the original reference, independently
retained original provenance, both hashes and the frozen v1 semantic contract,
then returns deeply frozen data. Result/provenance canonical byte limits are1
MiB/ 64 KiB; PostgreSQL JSONB-text limits and whole-result resource
qualification are still pending. Digest possession does not authorize recovery
or execution.

`persistInitialResult` permits one write attempt per call followed by exact
read-back, including after a lost acknowledgement. The read request includes the
original result evidence ID and expected result digest. Missing, mismatched or
unreadable evidence stays held without promotion or another provider call. Only
capture-created values enter this writer; that brand is process-local and is not
durable authority. A second call can attempt an identical write, so fixed SQL
identity/immutability guards and restart recovery remain mandatory.
`resultStore.ts` supplies a fixed private transport for the two reviewed record
and read RPCs. It snapshots the original reference and independently retained
provenance at construction, and snapshots evidence before validation/hash
awaits. The write path requires the original lease; restart recovery can
construct a read-only store without it. Only a correlated explicit `absent`
reply with null evidence becomes absence. Malformed, oversized, mismatched,
timed-out and failed responses remain unavailable, never a new execution grant.

Each write/read has a five-second total budget including validation; requests
and read envelopes are capped at 2,232,320 bytes and write acknowledgements at
8192 bytes. The envelope cap accommodates escaped canonical result/provenance
strings; the inner limits remain 1 MiB and 64 KiB. Responses stream under these
limits, late bodies are cancelled, redirects are rejected and no automatic retry
occurs. The fixed RPC argument/reply decoders remain private draft transport
contracts. The uncommitted S0 candidate now implements private SQL record/read
producers; no public RPC wrapper/grant or live route imports these owners. See
the result integration status below for its scoped validation and remaining
acceptance.

The focused tests include the composed dispatch → usage-report failure →
immutable capture → lost result-write acknowledgement → exact read-back path
with one provider invocation. These are synthetic Edge boundary checks, not
PostgreSQL, hosted, native delivery or full user-journey qualification. The
remaining integrated chain must consume this evidence before adoption and atomic
completion; these files are not a standalone release.

### S0 SQL structural consumption draft

`20261103074331_consume_initial_analysis.sql` begins the same uncommitted
integration with frozen private invoker helpers. `initial_result_v1_sql.ts`
emits the SQL schema directly from the frozen Edge v1 definition; the existing
contract test checks exact migration-block parity. The fixed data/provenance
parser checks canonical spelling, canonical and JSONB-text byte limits, closed
structure, decimal syntax/ranges, UTF-16 string lengths and embedded provenance
agreement. It now also applies frozen primary semantics, exact provider usage
shapes, closed result-wrapper identities and actual-LF result/provenance digest
checks. All API execution is revoked. No result writer, dispatch authority,
witness recognition or grant is added by this draft section.

The maintained `initial_result_v1_contract.sql` covers structural/canonical
vectors, primary/usage/digest cases and helper privilege boundaries on a
disposable database. Syntactically valid supplied identities and hashes are not
original authority: the consuming writer must compare them and the provenance
with retained locked invocation/admission facts, then consume its exact
transaction witness before inserting a result. Those steps remain unfinished.
The structural matcher alone is not result acceptance; it must remain behind the
canonical parser's aggregate depth/node limits. Deno retains exact IEEE
round-trip validation. Keep this migration with the complete integrated chain;
it is not a standalone release or callable intermediate milestone.

### S0 consuming witness images draft

The same migration now fixes dispatch/report/result statement groups and a
private row-image normalizer for their six touched relations. The catalog names
statement order and row-count modes only: exact expected images, original
charge-link count and trigger/FK effects still belong to the unfinished
compositor. The private staging mechanics described below do not establish those
original facts. Completion deliberately has no catalog until its actual writers
and projection are integrated. No existing writer or guard recognizes these
helpers, and API execution is revoked.

Witness comparisons use an exact secret-redacted row projection. Only the quota
row's `lease_token` is replaced with `lease_sha256`, using canonical lowercase
UUID text, UTF-8 and SHA256. SQL NULL means no row; a JSON null lease stays a
null digest, never an empty/placeholder hash. Every other field is retained;
exact column allowlists reject missing/new schema fields. Expected-image and
OLD/NEW verification must share this normalizer. The digest is correlation only,
never a lease credential or execution authority. The maintained
`initial_consuming_images.sql` tests these boundaries and the inactive catalog.

### S0 transaction witness mechanics draft

The same migration adds API-inaccessible `initial_consuming_staging` and an
unattached member-trigger adapter for dispatch/result mechanics. Expectations
are immutable, exact redacted row images grouped by the fixed statement catalog.
The private representation is bounded to 8 MiB and 256 rows per group; these are
implementation bounds awaiting integrated resource qualification, not new media
limits. Each BEFORE row records a unique pending index; queued AFTER events must
consume the corresponding exact image once. Statement completion requires all
expected rows and no unmatched pending rows, including zero-row groups.

Immediate deletion requires a sealed witness. Deferred entry/deletion checks
reject leftovers and validate the captured terminal deletion image. A
denial-only transaction advisory latch prevents recreation after successful
removal. Complete subtransaction rollback removes its latch, stage and SQL
effects together; no external work runs inside the transaction. Constraints
already immediate reject entry, and caught statement failures cannot retain
partial progress.

This isolated mechanics draft originally withheld report/completion authority:
`ON CONFLICT DO NOTHING` can execute BEFORE INSERT without AFTER INSERT. The
integrated owners below now model attempted images, validate actual conflict
winners and require original identity/fence and terminal assertions. Neither the
stage nor its advisory latch supplies original authority. See
[report integration](#s0-original-report-integration) and
[completion integration](#original-completion-preparation-private-inactive) for
the current implementation and remaining qualification.

`initial_consuming_stage.sql` isolates legacy user triggers in a rollback-only
disposable fixture while retaining foreign keys. It exercises result-stage
lifetime, both-row pairing, multi-row original-link deletion, missing/suppressed
members, savepoint rollback, immediate constraints and actual API-role denials.
Its dispatch fixture stops after the link group and rolls back; it does not
qualify a real dispatch, admission, accounting, completion or native journey.

### S0 accounting candidate preparation

`internal.complete_identification_usage` remains the accounting writer. Its
private `prepare_identification_usage_event` helper returns all 26 event fields,
including the six previously implicit defaults, after the original invocation
lock and existing-event early return. Validation, metadata and pricing semantics
are preserved. The helper is volatile and API-inaccessible; it reads pricing but
performs no writes or owner/receipt/invocation lookup. A future report witness
must reuse this once-prepared row rather than reprice or regenerate defaults.
The insert retains `ON CONFLICT DO NOTHING` and links the actual existing
winner.

The maintained `identification_invocation_accounting.sql` rollback fixture adds
full attempted/effective row observation, invocation-only linkage, invalid-input
zero-write replay and an existing unknown winner with BEFORE but no AFTER
insert. These checks do not instrument pricing-call count or establish
concurrent winner behavior; those remain required in the report integration. No
report stage, initial invocation creation, grant or production route is opened
by extraction. The
[dispatch RFC](../../../../../docs/rfcs/initial-dispatch-fence-interface-2026-10-13.md)
owns the integration contract.

### S0 original report integration

The subsequent draft now supports report witness mechanics and installs
report-only observers on usage INSERT and invocation UPDATE. The earlier
unattached/report-denied descriptions above are historical for this operation;
dispatch and result remain unattached. A one-time candidate attachment preserves
original identity; AFTER STATEMENT locks and binds the actual source-key winner.
Inserted rows require exact BEFORE/AFTER equality. Zero AFTER rows explicitly
mean existing-winner resolution, including suppression when a different-ID
winner already exists; they do not prove ON CONFLICT. Missing winners or missing
AFTER for the candidate itself fail. Exact event/link checks repeat on terminal
deletion and under trusted-owner deferred validation.

API-revoked `internal.report_initial_analysis_usage` supplies the fixed original
producer: existing outer scope, retained admission/submission proof and digest,
sorted original invocation/alias validation, original lease and provider
snapshot, then the existing writer. Its exact replay skips new usage parsing and
witness creation. The shared pure `identification_usage_matches_invocation`
validator checks saved attribution for both reporting and accounted cancellation
without repricing. No public RPC or service execution grant is installed;
initial creation and provider execution remain denied.

`identification_invocation_accounting.sql` now instruments the real pricing
estimator through an OID-preserving rollback delegate, and covers exact
candidate, existing winner, zero-write replay, suppression, missing observations
and terminal damage. The append-only guard remains active in its own denial
case; deliberate terminal-fault cases bypass only that guard and roll back.
Original failures are retained in HQ100. The existing invocation-erasure runner
adds `--report-witness existing`, `inserted-commit` and `producer`: existing
observes peer-PID blocking for event rollback/commit and both erasure orders;
erasure blockers roll back, so this does not prove late reporting after
committed deletion. Inserted-commit avoids repeating schedules. Producer covers
original identities, canonical usage, 26 malformed attribution winner/replay
cases, unchanged funding, API denial and actual-role deferred commit. Fixtures
retain a guarded admission but inject invocation/dispatch state; they do not
qualify dispatch provenance or initial end-to-end execution. The same
owned-database, cron, manifest and evidence rules apply; no additional runtime
or production permission is introduced.

### S0 original invocation classification draft

The invocation owner now has a nullable original admission-receipt association
and an immutable `is_initial_analysis` flag, without a foreign key or new
row-first accounting lookup. A migration preflight rejects detectable existing
invocation/initial-operation-fence overlaps before assigning ordinary defaults.
It cannot classify already-anonymized historical rows and is not a complete
historical audit. The row-image allowlist includes both new columns.

Initial invocation creation remains denied. Classified rows permit the existing
row-local accounting event update and exact scan/account erasure or explicit C1
retirement. That transition clears owner, scan, reservation, lease digest and
original receipt association together, preserving classification, event and all
other accounting fields. It requires original owner/receipt locks, irreversible
operation fence, and either a scan-deletion tombstone or the current C1 writing
witness. Independent deferred checks using captured original identity require
complete private erasure and, for C1, the exact terminal proof and cleanup.
Missing receipt or partial clearing fails closed. The provider barrier
recognizes the same validated transition. Direct row-update backstops use
NOWAIT/try-lock; outer erasure prelocks receipt, sorted reservations and
invocations before the existing media-member lock tail.

Five-minute unknown accounting remains unchanged and row-local. Thirty-day
pruning and direct deletion use the same complete retired-row predicate. A
missing receipt alone never qualifies. Existing-tombstone owner deletion also
enters retirement even when the ordinary erasure callback does not run again.

`initial_invocation_retention.sql` checks the inactive boundary and actual
unknown accounting; `identification_invocation_accounting.sql` covers ordinary
behavior. The maintained bounded erasure runner reuses the existing guarded
admission fixture and exact local replay owner:

```bash
python3 services/supabase/scripts/test_initial_invocation_erasure.py \
  --container "$DISPOSABLE_CONTAINER" \
  --evidence-dir "$EVIDENCE_DIRECTORY" \
  --replay-manifest "$EXACT_REPLAY_MANIFEST"
```

Each run requires a fresh owned local database with every current migration;
dispose it afterward, including on failure. It commits a synthetic photo
admission, then injects only the still-unavailable initial invocation before
exercising real scan/raw-owner erasure in a new transaction. The current179
assertions retain the original30 erasure/account cases and add accounted
capture, atomic stage entry, ledger/funding freezes and
invocation/lifecycle-witness mechanics. They cover original identity,
existing-tombstone fallback, receipt mismatch/absence, partial clearing, event
preservation, deferred private-root proof, immediate-constraint denial,
invocation-only discovery and exact rollback. Generic cancellation remains held;
positive-unused C1 and selected actual public account composition retain their
real guards. Fixture corruption is explicitly isolated. Mechanical witness cases
separately isolate only the original retirement/provider row barriers inside
rollback; every new witness/member check remains enabled. A separate
real-retirement case retains all production guards. The integrated public-C1
cases also retain those guards and force deferred validation after cleanup;
original initial dispatch remains injected. The local lifecycle switch is
disabled before fixture commit.

`--complimentary` selects a real held complimentary credit through guarded
admission. The default uses quota funding; an additional assertion verifies the
requested original funding state before cancellation. Both use the same exact
funding-image checks. Six private-result cases inject only future producer
prestate, then restore the named storage/provider barriers before public C1.
They check exact result capture and erasure for pending/dispatched execution and
completed usage, exact rollback after suppressed deletion or terminal failure,
and denial after a completion already exists. These synthetic containers do not
qualify result production, semantic validation, terminal delivery, or the
opposing concurrent completion schedule.

`--c1-races-only` runs the funding and media-profile assertions and controlled
C1/accounting schedules without repeating the rollback assertions. After C1
commits, those schedules also exercise the actual thirty-day reconciler prune on
the old synthetic invocation without a permanent scan tombstone. They compare
the exact surviving usage event, cancellation receipt, lifecycle and funding,
verify saved cancellation replay, and require a post-prune accounting report to
reject the missing invocation without changing its original usage event. This
exercises the manual reconciler owner, not automatic cron timing.

`--public-c1-only` selects 31 assertions covering guarded funding/media-profile
admission, the integrated public cancellation cases and exact rollback. It skips
the mechanical witness suites and concurrency schedules. `--media-vector`
selects one of the existing guarded admission fixtures: 1 vision photo with
description, 2 multimodal photo, 3 audio, 4 photo/audio, 5 video frames, or 6
video/audio. The original receipt's input profile must match the selected
fixture. These are synthetic SQL media contracts, not bytes/provider/native
qualification or CPM photo admission; a run qualifies only its recorded vector
and funding variant.

`--cpm-photo --public-c1-only` instead reuses the existing committed CPM photo
fixture and its 140 setup assertions, then runs the 31 integrated C1 assertions.
It verifies the requested funding mode and original three-attempt media cohort.
Successful cancellation may change only the original attempts' retirement bits;
capacity reservations and write closures remain exact, and private role mappings
must disappear. Failed calls restore those retained records in the full
snapshot. This is SQL qualification of the client-prepared-photo contract, not a
native app run, actual storage deletion, or successful
dispatch/result/completion. The standalone committed-CPM runner uses the same
extracted setup owner.

`--cpm-photo --c1-races-only` uses that same guarded setup with two
funding/profile assertions and the controlled C1/accounting schedules. It
commits cancellation, checks late reporting and manual pruning, and compares the
original CPM capacity, closure and retired-attempt images after commit and again
after pruning. The 31 rollback assertions are not repeated in this mode. Each
run records its own funding mode; neither option qualifies all
account/cohort/concurrency combinations.

`--cpm-photo --account-erasure` reuses the same 140-check admission setup, then
injects the original classified invocation and calls the real service-role
`apply_user_tombstone` owner. It checks rollback against all internal tables,
users and usage events; commits deletion; and verifies retained liability and
invocation identity in a fresh session. Classified work requires a completed
ownerless permanent scan tombstone and no C1 receipt at both user-delete
witnesses. Funding stays exact until account deletion; permanent CPM capacity
may unlink its owner, attempts retire, and closures remain unchanged. The
original invocation retains every field except the five retirement fields and
its newly assigned accounting event. The captured event allows only the existing
anonymization changes, including removal of identifying metadata keys. By
default this mode covers pending/unknown accounting for its recorded funding
variant. Adding `--account-reported` first records synthetic successful usage
through the existing accounting owner. It then preserves the original event ID
and every event field except the documented anonymization changes, including a
fresh-session comparison. This verifies already-recorded usage preservation, not
provider execution or successful analysis completion. Neither variant runs the
31 C1 cases, account races, public scientific retention, actual blob deletion or
all media/cohort combinations.

`--size-preflight` selects two guarded funding/profile assertions and focused
structural size checks, skipping the full erasure suite and race schedules. It
supports media_sources or `--cpm-photo`. Disposable, rollback-scoped padding on
preparation intent and receipt exercises their duplicated representation without
weakening production byte limits. An aggregation tripwire proves rejection
occurs before constructing private arrays; the actual public call must roll
accounting back. A near-limit accepted case uses escaped control and multibyte
text; CPM additionally proves its retained contribution can push an
otherwise-fitting composite over the limit. This is near-boundary structural
qualification, not valid producer-content coverage, exact one-byte endpoints,
independent null/empty enumeration, or peak-memory/runtime qualification.

`--resource-case five_small|five_declared_max --media-vector 6` selects two
funding/profile assertions and fresh-backend observations of capture with
rollback, actual service-role accounted C1 with immediate-check rollback,
deferred commit, and saved replay on another new backend. Admission, invocation
injection and correctness projections run elsewhere. The observer verifies the
container backend PID, namespace and process start identity before and after
each operation. It records database call/transaction duration, client wall time,
before/after memory-context totals and Linux `VmRSS`/`VmHWM`. The high-water
mark is process-lifetime RSS, including shared mappings and startup; it is not
an allocator or container peak, and subtracting its baseline does not establish
an incremental peak. The ten-second statement deadline is a harness limit, not a
resource acceptance threshold. No admission budget or business limit changes.
The declared-max case reaches five-source media byte declarations, with small
supporting text and no actual blob IO. Neither mode qualifies the maximum
combined private/CPM/result state, production budgets, deployment capacity or
installed behavior. Existing resource fixture generators have one shared owner
in `initial_atomic_admission_resource.py`; the older refundable C1 resource
suite retains its separate synthetic budget and historical failures.

`--cpm-photo --resource-case cpm_photo` uses the same four isolated operations
with the existing guarded committed CPM photo fixture. The separate observer
requires its one capacity row, three attempts and three closures, records
canonical candidate/input byte sizes, compares exact original retained images
after both rollbacks and expected retired images after commit/replay. The
140-check setup and original funding variant remain explicit. Legacy resource
modes verify an empty CPM cohort through the same observer. These observations
include retained CPM copies but do not establish maximum combined policy state,
maximum supporting text, result production, actual media IO or a production
memory/latency budget. All correctness projections and scalar size queries stay
outside measured backends; no admission budget or business limit is widened.

The runner also observes exact blockers in two controlled schedules: the actual
reconciler holds the invocation before erasure (including rejection of reverse
owner acquisition), and erasure commits before an original late report reuses
its accounting event. It checks rollback preservation, retained-row pruning and
fresh-session event uniqueness. The later race phase commits synthetic
retirement. Only this disposable's accounting cron is suspended after saving its
prior state; the runner rejects an in-flight execution without cancelling it and
restores the prior active state even on failure. These schedules qualify manual
accounting/scan erasure, not the scheduler, public account deletion or C1.

Generic cancellation holds with `55000 initial_analysis_cancellation_incomplete`
when a classified invocation matches the scan or the locked admission's original
reservation. This check precedes saved cancellation replay and private erasure.
The positive-unused refundable C1 proof remains unchanged. Explicit cancellation
with known execution now uses the complete non-refunding witness variant in the
draft public composer.

The draft's `capture_initial_accounted_cancellation_prestate` validates original
receipt/lease/assignment and captures the unchanged producer's exact event and
funding. `begin_initial_cancellation_stage` requires exactly one returned/stored
server-derived stage; failure rolls reconciliation back. Accounted stages have
no refund clock or quota/credit witness. The public composer retires the exact
original invocation, completes lifecycle/media/private/receipt witnesses and
consumes all eight terminal proof rows. Premature completion remains denied.

`initial_cancellation_invocation_witness` now records a server-derived exact
five-field correlation retirement and frozen event. Mandatory BEFORE statement,
row and AFTER statement guards enforce pending→writing→observed→complete and
independently recheck the invocation, event, reservation, provider attempt,
actual links/counters, complimentary hold and owner epoch. Direct phase writes,
zero/extra/no-op statements, wrong images and unrelated-trigger attacks gain no
usable retirement authority. Trigger depth supplements exact facts; it is not a
capability. Accounted funding mutations are denied at statement level, even with
zero rows. Witness RLS/API denial and actual terminal seal are installed;
terminal proof/cleanup membership is installed. The256KiB witness bound is a
rejection limit, not measured resource qualification. The accounted capture now
measures the complete 64 MiB representation before constructing private,
registry or CPM aggregates. It counts every duplicated private component and
JSON framing; the same private component mapping and CPM row normalization serve
measurement and construction. The private-image owner also includes framing in
its own unchanged 64 MiB bound. Constructed images must exactly match their
estimated serialized sizes. These checks do not qualify peak memory or execution
time: earlier receipt validation, per-row serialization, retained copies and
terminal proofs still need resource measurement.

The private deferred `require_initial_invocation_erasure` trigger runs as its
trusted owner with an empty search path, retaining all exact retirement and
survivor checks. Direct execution remains revoked from public/API roles. The
public composer's definer privileges do not survive its return; a deferrable
trigger must therefore retain its own private read authority through a real
service-role commit. The retention SQL test checks owner, definer mode, search
path and ACL. Focused C1, classified scan erasure and classified account erasure
checks now force immediate validation under `service_role` and separately keep
checks deferred through commit under that role. Earlier fixtures that reset the
role before forcing checks do not establish this transaction-completion claim.

The shared lifecycle owners now recognize both settlement variants. Before a
known-execution lifecycle mutation, the exact invocation witness must be
complete, its retired invocation and usage event must match captured images, and
original receipt/funding must remain unchanged. No quota/credit witnesses are
permitted. Known pending work becomes `cancelled_unknown`; dispatch-authorized
work becomes `cancelled_dispatched`. Unused work retains its genuine refund
proof and `cancelled_pre_dispatch` transition. The phase helper is only a
predicate, not authority. Lifecycle event derivation uses immutable
variant/prestate so deferred stage-INSERT evidence still works after live
witnesses are cleaned up.

Four rollback-only lifecycle positives cover pending/dispatched state with
unknown/completed accounting, alongside negative mutation and incomplete-chain
checks. The actual unused public cancellation additionally forces deferred
constraints after stage and lifecycle-witness cleanup. The initial live-phase
check in event derivation broke that case; the failed run, correction and
independent verification are retained. The subsequent integrated cases exercise
complete accounted cancellation through the public owner.

Shared source/destination retirement, private-root erasure and receipt owners
now accept the accounted variant through the same exact witness order. The last
receipt-dependent accounting check occurs before submission deletion; subsequent
checks validate the captured invocation/event identities and actual surviving
funding. Frozen accounting images include the retired invocation, unchanged
usage event and actual quota links for accounted work. Submission then intent
cascades must observe every captured deletion before the matching unknown or
already-authorized receipt can be written. Unused receipt/refund behavior stays
covered by the actual public cancellation regression.

The focused suite adds five mechanical positive cases (four lifecycle/accounting
combinations and zero-write media reentry), eighteen negative/hold cases and
exact rollback. They reach both root deletions and the matching observed receipt
with the new guards enabled. Initial dispatch/retirement authority is still
isolated for these earlier rollback-only cases. The subsequent integrated public
cases use all retirement guards, complete terminal cleanup and independent
captured proofs. These cases do not qualify frozen-result deletion, all
media/funding variants or the complete transaction/concurrency graph.

Terminal capture rejects mixed refund/invocation witness families before
aggregation. Accounted cleanup has exactly eight rows; unused keeps its existing
maximum of sixteen. The same64/128MiB bounds apply. Invocation cleanup follows
credit and precedes lifecycle, retaining existing relative order. Captured stage
INSERT/DELETE, terminal DELETE and invocation retirement checks independently
validate final state after live witnesses disappear. No checker relies on
another checker firing first. The real public cases exercise both deferred
orders, suppressed cleanup, late rollback, altered captured evidence and
seal-protected mutation denial. Initial invocation INSERT remains unavailable.

Use `--c1-races` to select the changed public-cancellation/accounting schedules
instead of the older scan-erasure schedules; it is mutually exclusive with
`--assertions-only`. Reconciler-first observes the exact invocation blocker,
rejects reverse owner acquisition with NOWAIT and preserves identity on
rollback. C1-first commits cancellation while an original late report waits and
then reuses the existing event. An independent observer connection checks
funding and saved-receipt replay in a new transaction. It is an existing
connection, not a newly opened one. These race connections use trusted database
sessions with service claims; the separate integrated assertions exercise
`SET ROLE
service_role`. This qualifies the selected pending/unknown race, not
all media, funding, account deletion, scheduler or the full concurrency graph.

Permanent account deletion uses existing scan-tombstone retirement for
classified pre-row identities before the original receipt disappears. Its sorted
owner/advisory scope includes invocation-only identities, validates scan/owner
associations and rejects original-reservation aliasing. Existing tombstones
explicitly enter the retirement/cleanup fallback. Ordinary work keeps generic
cancellation; retained public observations keep scientific detachment. This
branch introduces no refund, credit release or explicit C1 transaction seal.
Missing original receipt denies the whole account transaction.

The focused fixture exercises actual public account success, existing
tombstones, reservation-alias denial and later malformed identity failure after
an observed earlier retirement, followed by full captured-image rollback. One
family-rank AI scientific-retention case composes with that retirement. A quota
mutation tripwire allows only owner anonymization or deletion of unchanged
funding; counter images stay equal. Event checks use the surviving invocation's
`event_id`, because account anonymization deliberately clears event `source_id`.
The pre-call event count includes any scientific fixture backfill. Dispatch is
still injected; these cases do not qualify all account/scientific variants,
complimentary funding or the complete concurrency graph.

Use `--assertions-only` to check this changed boundary on a fresh exact replay
without repeating unchanged contention schedules. The runner records that scope;
it never counts skipped schedules as executed.

Before enabling initial creation, complete frozen-result/all-media/funding C1
qualification, remaining public account variants, affected catalog and
whole-graph checks. Producer-derived witnesses, report-conflict handling,
completion and native delivery remain pending. No hosted or installed journey is
qualified by these bounded SQL checks.

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

The draft's schema installation uses one outer `DO`/dynamic statement, with
session timeout SET/RESET outside it. This preserves the classification locks
through guard installation when fresh replay executes statements individually,
as well as on normal migration apply. A fresh pinned-CLI replay exposed SQLSTATE
25P01 in the earlier top-level LOCK form despite successful incremental apply;
the failure and correction remain recorded. No top-level transaction control or
weaker lock acquisition was added.

### S0 original result integration (November 3)

The uncommitted consuming migration adds private
`record_initial_analysis_result` and `read_initial_analysis_result` producers on
the existing immutable result owner. Report and result share
`lock_initial_dispatched_original`; recovery has no supplied lease but derives
the unique invocation through retained original
owner/scan/admission/funding/provider proof. All API execution remains revoked.
The public transport names remain unavailable and no production route is
composed. Earlier result fixtures inject dispatch; the private original dispatch
runner below now exercises guarded admission and the actual dispatch writer.

A result write binds the stable evidence UUID, exact canonical content/digest,
input/configuration/funding identities and original provenance. Frozen schema
validation precedes schema-directed conversion of fractional-number strings for
exact JSONB equality against numeric invocation provenance; other strings,
integers, nulls, omissions and array order remain unchanged. This SQL comparison
does not replace Edge IEEE round-trip validation. Stored encoded content and
hashes remain unchanged. A valid late result does not require successful
accounting, reprice an unknown event or authorize another inference.

Bound result stages consume one exact INSERT through paired statement/row
observers. Entry validates the original candidate, both business guards require
the bound active statement, and immediate/deferred terminal checks require the
exact surviving row and original proof. Unbound mechanics fixtures cannot pass
either production guard. Exact replay compares all six stored columns and writes
nothing. Read recovery returns validated original evidence or explicit null
absence; it cannot create evidence or execution authority.

The focused local runner's `--report-witness result` mode reuses guarded
admission, injects dispatch only, and exercises result/recovery, conflicts,
unknown accounting, direct/unbound writes, suppressed/mutated rows and actual
service-role deferred commit. Local injected-photo checks cover both orders of
result/scan-tombstone erasure and a blocked read after committed erasure.
Whole-result resources, all-media account/C1 ordering and the combined user
journey remain required. Completion/adoption must preserve or deliberately adapt
retained admission roots and `dispatch_authorized`, which currently identify
original authority; this is not a fresh lease-eligibility check. Current
receipts and remaining work live in the History continuation packet, not a
deployment claim.

### Private original dispatch integration (November 3, inactive)

The uncommitted consuming migration extends the existing transaction stage with
redacted original prestate and one prepared invocation. The private
`commit_initial_analysis_dispatch` composes the existing invocation writer,
quota core and lifecycle owner. It adds no permanent dispatch table, public
wrapper, API grant or execution route.

Entry locks the original owner/scan scope, validates the retained live admission
and original lease, and captures exact ordered quota links, referenced counter
images and retained-root fingerprints. The invocation writer prepares its ID,
start time and native price once. The quota core attaches complete expected
images using its one sampled clock before any business mutation. Paired
statement/row observers then consume quota commit, original link deletion,
invocation insertion and the exact pending-to-authorized lifecycle transition.
Immediate and deferred checks require those exact terminal images, unchanged
counters and retained roots, and no replacement links. Successful stage removal
retains the transaction's stage-reuse denial latch. An unchanged SQL no-op is
not another dispatch grant; a later changed terminal image must fail commit.

Fresh dispatch requires original reserved funding, a pending lifecycle and no
invocation matching either scan or reservation. A committed replay cannot issue
another fresh grant. Report/result and C1 retain separate witnesses. Saved
configuration validation, the actual installed executable and consumption of the
same verified media buffers remain mandatory uninstalled executor boundaries;
caller digests or a SQL success cannot stand in for them.

`services/supabase/scripts/test_initial_dispatch.py` requires a fresh owned
replay receipt and uses `fixtures/initial_dispatch.sql` only in that disposable
database. It exercises actual service-role dispatch, API privilege denials,
wrong original identity/provenance, suppression and mutation faults, deferred
terminal checks and committed replay. Its guarded CPM fixture supports absent or
complimentary funding; executed variants and failures are recorded separately.
Its `--media-vector` and `--journey` variants exercise guarded legacy photo,
audio and video admission plus actual private dispatch, synthetic immutable
result, original accounting, replay/read and C1. The separate
`test_initial_dispatch_races.py` verifies both committed dispatch/C1 orders.
This does not qualify provider execution, adoption, completion or the integrated
app journey. The History continuation packet owns exact executed variants,
current evidence and remaining checks.

### Completion event vocabulary (inactive)

The private `initial_completion_event_catalog_v1` in the consuming migration
names the fixed row/statement events for legacy/CPM media, absent/consumed/paid
release funding, and absent/new/existing species association. It returns only
closed metadata (maximum64 events) and has no API execution grants. The current
consuming stage binds original completion preparation and settlement, and the
private legacy producer below consumes the complete event sequence. Unfinished
commit is rejected. This metadata vocabulary alone cannot authorize a write.

Completion requires interleaved events because scan triggers invoke the existing
species-count owner, whose data-modifying CTEs interleave owner and count row
observations. Its conflict-suppressed INSERT has an attempted BEFORE row but no
committed AFTER row. The integrated observer verifies its exact locked winner;
that narrow exception cannot excuse suppressed scan, adoption, settlement or
completion writes. The isolated ordering probe and metadata/privilege catalog
checks do not qualify the real completion triggers or terminal assertions.
`services/supabase/tests/initial_completion_events.sql` preserves this boundary.

### Original completion preparation (private, inactive)

`internal.prepare_initial_completion_v1` reuses the retained-result reader's
original identity and deletion/cancellation checks, locks the original funding
and retained media cohort, and derives a scan projection from immutable input
and result evidence. CPM additionally revalidates its original role, positive
closure and retained-capacity proof. The result includes bounded existing root
fingerprints and a redacted owner image for the pending completion stage; it
writes no scan, settlement, adoption receipt or completion and has no API grant.
`begin_initial_completion_stage_v1` binds that preparation to the existing
transaction stage. Its guard recomputes original facts, rejects altered
projections/roots and stale clocks, and preserves the once-prepared completion
time. The transaction latch remains shared with dispatch/report/result. The
existing settlement owner now attaches its once-sampled credit prefix and
observes the exact hold/owner statements and rows. Prefix replacement, repeat
settlement, extra statements, row suppression and mutation are denied. Stage
sealing/removal requires the full scan/completion suffix and its terminal
assertions; a partial settlement rolls back at commit. Legacy settlement first
requires the existing terminal transfer proof. CPM settlement remains denied
until its original adoption payload is prepared and bound; a verifier build
digest is not that proof. The prefix constructor enforces this prerequisite
during independent stage-guard recomputation too, so direct attachment cannot
bypass the settlement caller.

Taxonomy uses the exact existing dictionary identity. Private CPM projection
keeps absent capture telemetry null and labels its once-sampled server timestamp
as completion time. Legacy capture fields retain their saved values; timestamp
conversion runs in UTC. Scientific/review initial fields and the original
invocation accounting marker are explicit. Missing or null life-stage and
reproductive-condition values remain null: the discarded audio-subject side
channel cannot be reconstructed from a species name. Any intended normalization
must happen before the executor freezes its result.

`services/supabase/scripts/test_initial_completion_preparation.py` exercises
real private dispatch and synthetic retained results before this read-only
projection. It checks API denial, unchanged original state and
absent/new/existing dictionary association. Its temporary scan-shaped table
checks column constraints without claiming production scan-trigger execution. It
also runs original legacy SQL handoff owners with synthetic byte attestations,
checks rollback-only funding prefixes and exact event faults, and denies both
ordinary and direct CPM prefix attachment before adoption proof. These checks do
not exercise physical blob IO. Its `--journey-only` mode additionally executes
the private legacy completion producer, actual scan/species events, committed
settlement, exact replay and later review. CPM adoption, completed-scan/account
erasure qualification, preferred-goal progress and completion-backed native
delivery remain pending.

`prepare_initial_completion_legacy_media_v1` independently prepares the private
legacy media references after reusing original result/account locks and the
terminal transfer assertion. It follows the immutable owner timeline, excluding
video frames and companion audio as separate owners. Photo/audio references use
the mapped prepared object when present, otherwise the mapped source. Video uses
its original mapped raw source and the first original frame as its optional
poster. Exact content type, byte count, hash and transfer receipt digest remain
bound; no URL is retained. The projection is bounded to64KiB in canonical and
JSONB forms. CPM is denied by this legacy-only preparer.

This function writes no stage, settlement, scan, adoption or completion, grants
no ticket, and has no API execution grant. Its shared terminal-media image
constructor can also run after the original funding prefix, without repeating
fresh held-credit preparation. Protected delivery owners remain pending. The
focused runner's `--media-only` mode checks this read-only boundary without
repeating funding prefix tests; mixed-media fixtures freeze a reversed owner
order before admission to distinguish owner order from source/inference order.

The private stage now accepts a one-way request to prepare its completion suffix
after the exact original funding events. The guard constructs the suffix itself;
callers cannot supply its projection or entitlement. It checks unchanged
original roots, result, admission, invocation and quota, then samples the
existing entitlement resolver once. That historical snapshot remains fixed if
rollout changes later. The suffix binds exact media/descriptions and the
original plan, settlement, timestamp, privacy and species association. Its tail
images preserve absolute event ordinals and distinguish an attempted species
INSERT from the locked conflict winner. Preparation alone does not authorize a
completed scan. The integrated observer consumes the exact fixed statement and
row sequence, checks the actual species winner and permits sealing/removal only
after immediate terminal assertions. A deferred check repeats those assertions
after stage removal. Original invocation, quota and accounting event
identity/digest remain unchanged.

`complete_initial_analysis_legacy_v1` privately composes original preparation,
settlement, exact scan insertion and immutable completion projection storage.
Exact replay takes original account/deletion locks and returns the saved
receipt/projection without settling again or overwriting later scan changes.
Completed scans use their immutable result/completion association to skip
obsolete ingestion backups in the existing copy and legacy review owners; role,
owner, enrollment, review-revision and scientific guards still apply. The
existing scan-deletion request owner samples completed classification under its
owner/scan locks before tombstone cleanup; completed scans skip legacy
failed-job settlement because their original funding already settled. Its
tombstone and cleanup owners remain unchanged. A locked same-owner pending
tombstone remains sufficient for deletion-request replay after cleanup erases
the completion association; ownership and history refusal still precede that
branch. Local committed request/retry/erasure checks and independent fix
verification cover this SQL boundary; physical cleanup remains separate. There
is no API execution grant or activation. The local `--race-order` suite covers
one committed completion/C1 order per fresh fixture; it does not qualify device
behavior or physical media. Independent integration review and the remaining
all-media/erasure/schema gates are required before acceptance.

The local runner's `--report-after` mode commits completion before the original
usage report and verifies that completion invents no usage event. The later
report retains the original invocation identity; exact completion replay still
preserves later notes and legacy Reject/Undo. Its optional `--account-erase`
checks the existing account-tombstone owner after that journey: rollback,
committed private completion erasure, retained invocation and anonymized
original event, fresh-session checks and denied completion replay. These
selected SQL checks do not qualify account races, funding transitions before
cascade deletion, physical cleanup or native account behavior.

The focused `--primary-review` fixture selects synthetic primary-schema
provenance before admission and retains its first result through the existing
result writer. It exercises the existing verified-species confirmation and clear
owner, exact retry, stale-revision denial and completion replay preserving both
later states. This covers the non-null-primary SQL review branch without
rewriting an admitted configuration or retained result. It does not attest
compiled configuration, perform a taxonomy lookup or qualify provider execution.

The receipt's `funding_binding_version` is the retained funding snapshot codec
version (currently1), not admission `binding_version`3/4. Its
`finalized_media_binding_digest` is the original terminal transfer digest. The
completion projection digest uses SHA-256 over UTF-8
`merian.initial-analysis.completion-projection.v1`, LF, then the existing IC-1
canonical encoding. Both canonical and JSONB size limits remain64KiB for the
projection and16KiB for the receipt. The runner checks cross-language digest
agreement and changed-settlement rejection; complete executable-schema/shared
boundary vectors remain required before completion acceptance.

`completion-schema-v1.json` now describes the closed private receipt and
projection shapes; `completionContract.ts` snapshots and checks the paired
documents before a consumer receives their canonical originals. It validates
cross-document identities and digests, settlement consistency, media variants
and order, UTC calendar timestamps without losing microseconds, and both
canonical and JSONB byte ceilings. This is a prepared decoder, not an API or
authorization check. The private server adapter below binds the saved original
request; authenticated native delivery still needs its existing account and
operation fences. The inactive native `InitialCompletionDocuments` consumer now
uses the generated schema and a strict IC-1 canonical codec.
`generate_initial_completion_contract.ts` owns its generated schema and shared
synthetic fixtures; `initial_completion_contract_test.ts` detects drift. The
next native retained-result validator uses
`initial_completion_result_vectors.ts` as its synthetic parity source. It checks
each expected verdict with the frozen `decodeInitialResult` owner, including
original invocation/provenance, domain digests, strict decimal strings, exact
Unicode bytes, required fields and omission versus null. The new vectors pass
Deno validation and are emitted to the native fixture. The inactive
`InitialRetainedResult` candidate consumes them and the generated frozen
`InitialRetainedResultSchema`; all37 vectors passed in the nine-method native
suite and independent parity verification. Ordinary public-result Codable
decoding is not a substitute for this private retained-result contract.
`test_initial_completion_contract.py` checks those fixtures against the existing
SQL schema matcher, canonical bytes, digest and JSONB limits in an owned local
disposable replay. Shared parity passed7Deno tests/89steps and31SQL
vectors/157checks; selected native compilation/tests passed19methods with no
skips. Native delivery and available History import remain unfinished. The local
`test_initial_completion_documents.py` reuses guarded original journeys to check
SQL output in memory; it never writes completion bodies to evidence logs.

`read_initial_completion_v1` now prepares private delivery under the existing
original-result owner/deletion locks. It returns immutable canonical completion
and retained result evidence, or explicit absence, without invoking completion,
settlement, media verification or AI execution. No HTTP/RPC permission or native
caller is installed. Local CPM/photo/audio/video reader checks and Engine source
review passed. These cover committed deletion-request denial, not physical
erasure or concurrent read/delete orders.

`completionDelivery.ts` binds the reply to independently saved original
reference, result digest, provenance and admission/input fields. The existing
`resultStore.ts` exposes `readCompletion` only when those binding fields were
supplied at construction, using one fixed request, five-second deadline and
2,398,208-byte envelope cap. Explicit absence never authorizes execution. Lost
responses, invalid data and cancellation never retry or finalize.
`test_initial_completion_delivery.py` and
`validate_initial_completion_delivery.ts` exercise actual local SQL output
through this transport in memory, with expected facts copied independently from
admission/submission/invocation. The bridge has no network permission and emits
only pass/fail. Local CPM/photo/audio/video bridge checks passed and Engine
independently verified their source applicability and disposal. CPM covers both
absence and found; the three legacy media cases cover found.

Original CPM admission acknowledgement is prepared separately in
`cpmCompletionAdmission.ts` and its closed schema. The private
`read_initial_cpm_completion_admission_v1` reader matches saved candidate,
assignment and backend binding, retaining exact original admission and receipt
facts before dispatch and after adoption. It grants no execution authority and
leaves the older boolean recovery contract unchanged. The local
`test_initial_cpm_completion_admission.py` runner crosses actual SQL replies
through the decoder before dispatch and around completion; it retains no reply
bodies. The shared native generator now derives the twelve admission fields from
the backend validator and includes acknowledgement schema/byte vectors. The
inactive native decoder passed focused validation and independent review;
authenticated serving and native durable pinning remain open. See the
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md) for
bounds, original context correlation and denial behavior.

The inactive `completionStatusRequest.ts` decoder prepares closed admission and
completion status requests, bound to an already authenticated owner and exact
saved scan. Admission matches the eight native `CpmBinding` facts, not a full
server assignment. The new private `read_initial_cpm_saved_admission_v1`
resolves that retained assignment under lifecycle locks and reuses the exact
admission reader. `resultStore.ts` validates the private context and returns
only the existing acknowledgement; no assignment escapes to the client-facing
value. Unknown/mixed requests, absent or contradictory state and cancelled reads
never fall through to legacy repair or execution. Request/response limits and
inactive serving status are owned by the API contract above. Focused synthetic
transport checks and disposable SQL-to-transport qualification pass before
dispatch and across completion, including committed deletion denial. The new
decoder suite is listed in both explicit shared-helper CI lists.

First acquisition uses `discover_initial_completion_v1` and
`completionAcquisition.ts` through the existing `resultStore.ts` transport. The
closed 4KiB saved admission explicitly supports input schema1/2 without changing
the older admission repository. The locked reader discovers original result and
invocation facts; absent result/completion returns null `pending`, never
execution authority. Found delivery is correlated with the saved admission and
original invocation provenance before returning a result association. The fixed
request retains the five-second deadline and has a separate 2,541,568-byte cap.
It accepts no caller-selected result. Source reviews passed; no API grant,
native first-trust/pinning or consumer is installed.
`test_initial_completion_acquisition.py` and
`validate_initial_completion_acquisition.ts` reuse guarded all-media delivery
journeys, independently supplied admission and expected original identities,
field-tampering checks, unchanged-state snapshots and committed deletion denial.
The additional legacy-photo before-result case uses an actual original dispatch
without manufacturing a result or completion. Bridges run without network
permission and log pass/fail only. See the
[canonical completion contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-original-completion-document-decoder-inactive)
for the distinction between first discovery and pinned replay.

### CPM terminal retention preparation (inactive)

The private `initial_cpm_photo_retention_policies` catalog binds one exact
original write policy to a distinct terminal build, qualification-evidence
digest and reviewed revision. It installs no policy. Payloads are immutable;
eligibility can only move to revoked. The build must cover terminal reader and
inspector code, dependencies, fixed configuration and compatibility with the
saved backend reader/marker protocol. A verifier hash or revision alone does not
qualify retention.

`prepare_initial_cpm_retention_v1` reconstructs original admission/result and
source/AI/display identities under the existing completion locks. It checks live
positive closures, ownership, cancellation/deletion/retirement fences and
current retention/write/backend eligibility. The caller releases the transaction
before I/O. `cpmPhotoRetention.ts` reopens all saved objects through the
existing bounded byte reader and shared image inspectors, with terminal-only
current-state checks; it does not relax pre-admission authorization. One
reusable buffer is cleared on exit. The proof contains the complete original
roster and both `verification_started_at_ms` and `verified_at_ms`.

The entire verification interval is bounded by150seconds (six existing20second
reads plus at most30seconds of control/inspection), age at adoption by30seconds,
and clock skew by1second. An immutable policy may narrow those ceilings. These
limits are not measured deployment qualification. SQL samples adoption time and
checks the interval after reconstructing the original bindings.
`prepare_initial_cpm_adoption_candidate_v1` only returns a candidate; it neither
stores an ownership receipt nor grants settlement. The private
`complete_initial_analysis_cpm_v1` now binds that candidate to the original
completion stage before settlement. The existing ordered `media.adopt` event
requires the exact transfer row and checks freshness again after settlement; any
failure rolls back funding and all completion writes. The same transaction
inserts the scan and immutable completion receipt/projection. The pre-adoption
cohort assertion remains strict; a separate post-adoption assertion requires the
exact retained source/AI/display cohort and transfer binding. No API grant or
installed policy enables this path. Protected display delivery and native import
remain pending.

Expired write capabilities are never renewed. A previously admitted, positively
closed cohort may be reverified while still live; retirement or marker claims
deny verification. Revocation denies new adoption and must not rewrite eventual
committed recovery or obstruct authorized erasure. Completed replay validates
historical bindings without fresh bytes or current policy eligibility. Adopted
originals and their preparation intent are protected from ordinary retirement;
only the existing scan/account erasure fence permits retirement and transfer
removal. Legacy v3 copy/retire behavior remains separate.

The focused disposable `test_initial_cpm_retention.py` covers the reader, policy
immutability/revocation, binding/interval rejection and unchanged original
state. It does not qualify contention orders, expired-capability schedules,
physical retention, adoption, hosted installation or native delivery.
`test_initial_cpm_completion.py` exercises actual settlement/adoption, exact
replay, atomic faults, policy revocation, peer preservation and adoption-event
expiry. `test_initial_cpm_adoption_erasure.py` adds existing scan/account
erasure owners. `test_initial_cpm_adoption_races.py` exercises both
completion/C1 orders; `test_initial_cpm_adoption_account_races.py` holds a
synthetic proof across the transaction boundary and exercises both
account-erasure orders. Completion-first account erasure retains the existing
ownerless scientific tombstone; account-first leaves no public scan. Both erase
private completion authority and retain the original retired-media liability and
anonymized accounting. `test_initial_cpm_completion_replay.py` checks a waiting
proofless replay against the first committed completion, including unchanged
settlement and retained-media images. Pre-adoption scan deletion must return
`not_found` because no scan exists yet; marker workers cannot claim live
originals. Retirement-first qualification therefore uses the actual
C1/account-erasure owners, followed by separate post-adoption scan deletion and
marker cleanup checks. These checks are under qualification; their presence
alone is not passing evidence. Resource measurements and full affected-surface
gates remain required.

### Completion-backed description bytes (inactive)

`completionDescriptions.ts` implements the pure byte handoff for the planned
completion-backed available History representation. It retains the original
schema1 ordered string array or schema2 CPM base64 contexts and their existing
domain-separated digest. It is not an endpoint, owner check, SQL completion
writer, native decoder or execution grant. Existing History unavailable records
and installed readers are unchanged.

Pages contain at most24,576 decoded bytes within a65,536-byte wire envelope.
Offsets refer to bytes and may split a UTF-8 scalar; only the completed item is
decoded. A terminal page has `next_byte_offset:null`; other pages advance by
exactly their decoded length. Empty CPM items have one empty terminal page. The
collector rejects gaps, repetitions, changed totals/identities, invalid UTF-8
and alternate base64, then reconstructs the entire original ordered canonical
representation and validates its original digest before yielding reusable text.
BOM, NUL, whitespace and normalization distinctions remain exact. Any page
failure poisons the collector. A page alone proves neither a completed set nor
authorization. The future transport must recheck account, scan, analysis and
deletion fences for every page.

The
[completion/History contract](../../../../../docs/rfcs/initial-completion-history-interface-2026-10-11.md)
tracks the coordinated SQL/Edge/native handoff. Paged delivery avoids expanding
near-limit legacy input into a larger History result or widening existing
limits. `completionDescriptions_test.ts` covers those bounds, original domains,
Unicode, empty sets/items, incomplete collections, tampering and forward
progress. Actual available-History delivery remains unimplemented and
unqualified.

### Compiled-v1 source preparation (inactive)

The private S0 executor must resolve the saved asset catalog before dispatch.
`services/supabase/scripts/initial_configuration_build.ts` checks a trusted Deno
parser/resolver graph against that one catalog and the exact staged source
bytes, including its import map and frozen lock. It rejects extra runtime source
paths, dynamic imports, missing modules, changed SDK roots, changed transitive
edges and source drift. The current graph has 58 local runtime files and two
erased TypeScript-only contracts outside the archive. Its three npm roots reach
51 packages; 14 additional package records in Deno's output belong to unused
configuration entries and are reported separately, not qualified as execution.
The normalized synthetic-path graph fixture retains no developer paths. Tests
run in the existing isolated source-archive lane and read the pinned Git
archive, not live AI source. The checker also reads the import map from verified
staged bytes. This inactive preparation does not freeze unrelated AI
development. Run
`bash services/supabase/scripts/build_initial_source_archive_test.sh` for the
archive and compiled-source checks together.

This source inventory does **not** attest a bundled/deployed artifact or grant
execution. Actual artifact module/dependency bytes, bundling/runtime settings,
runtime environment restrictions, exact saved execution snapshot comparison and
same-buffer media consumption still need integration before installing the
compiled-v1 binding. The existing production factory remains the only provider
composition; downloaded archive code is never executed and a missing saved
configuration has no current-default fallback. The focused source checker is
preparatory tooling, not a replacement for that mandatory installation gate.

`initial_configuration_artifact.ts` inventories actual ESZIP2.3 bytes without
loading any bundled code. It validates framing, checksums where present, exact
nonoverlapping source/map ranges, redirect targets and npm reference indices,
and hashes every emitted body, including opaque VFS and runtime metadata. Array
inspection keeps a32 MiB allocation ceiling. Stream inspection consumes at most
1 MiB chunks and2 MiB headers under the offline compiler's64 MiB output
envelope; it closes its reader on success, rejection or cancellation. These are
tooling bounds, not changes to media or installed-worker limits, and are not
measured RSS guarantees. It supports only the pinned compiler's
no-checksum/SHA256 v2.3 forms; unknown encodings fail closed.

An offline build of the six archived roots with the already cached immutable
compiler image produced40,847,823 decoded bytes, retained as7,574,971 gzip bytes
within the existing32 MiB retention bound. The original uncompressed retention
attempt failed at that bound and is preserved. Incremental hashing and
compressed retention resolved that tooling allocation problem without raising
compiler memory, temporary storage or retained-file ceilings. Its59 JavaScript
frames contain58 archived files plus the inspection entrypoint; all58 source-map
content declarations match the archived source hashes. The compiler additionally
embeds all65 locked npm packages and six npm roots, including unused import-map
entries. They are accounted for separately from the51-package runtime source
graph:65 archives passed the frozen lock's SHA512 checks, and1,633 published
files plus1,283 identified empty Deno warning markers match all2,916 VFS bodies.
The byte multiset does not independently establish VFS path mapping.

A subsequent offline build froze the verified source/package paths,
configuration, lock and resolver metadata into an immutable local image before
compilation. It used the pinned compiler with no host mounts or network. The
emitted artifact is40,847,831 bytes, retained as7,572,492 gzip bytes; the byte
inspector and compiler producer agree on its hash. All58 source declarations and
all2,916 VFS bodies match the frozen inputs. The compiler is explicitly trusted
to produce the mapping and emitted code; source-map declarations and matching
body hashes are supporting checks, not independent semantic proof. The failed
build-frontend preparation and earlier retention failure remain recorded.

These are inspection bundles, not installed routes, deployment identities or
execution authority. The existing deployment owner must inspect and upload the
same retained bytes without rebuilding, then bind the installed runtime to that
artifact. Full saved-snapshot comparison and same verified media-buffer
consumption remain required before dispatch. The local frozen-input image is
retained as a pending build product; it grants no release permission.

The inactive `completionStatusResponse.ts` encoder and generated closed status
schema project existing validated acquisition facts into bounded canonical
scalar fields for native transport. Inner receipt, projection and result bytes
remain unchanged; pending has only null result fields. Three shared fixtures
cover pending, found and exact Unicode. Focused Deno/generator parity passed;
focused native byte/limit/transport/pin checks passed with independent runtime
verification. Live status-route integration remains open.
