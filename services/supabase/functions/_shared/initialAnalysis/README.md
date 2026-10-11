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
