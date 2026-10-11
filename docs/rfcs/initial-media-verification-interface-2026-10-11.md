# IC-1 M2 retained initial-media verification

Status: proposed inactive implementation contract following accepted M1 local
commit `aa9213ce6dd6178ec67c192ac0875eeb270c7b50`. Primary owns all writes. The
initial-engine owner and independent project reviewer must accept this exact
interface and final candidate evidence. No route, native installation, backend
selection, provider invocation or hosted operation is authorized.

## Preparation and durable verification

M1 metadata is not preparation authority. Add fixed service-only operations,
using the original owner/scan/submission/manifest. All owner-bound operations
use M1's original scope validation and error precedence before inspecting
private media. The same read-committed and owner → ingestion advisory →
scan/history → lifecycle/submission/admission → cohort →
preparation/verification → sorted registry discipline applies. No I/O happens
under database locks.

- `claim_initial_media_preparation(p_owner UUID, p_scan UUID,
  p_submission_digest TEXT, p_manifest_digest TEXT)`
  returns
  `{version:1,outcome:"claimed",binding,claim:{token,issued_at,expires_at}}`
  only for a fresh acquisition. The server token is a new UUID. Millisecond
  timestamps are safe UTC integers. Expiry is the lesser of one minute after
  issue and the original fixed cohort deadline. An unexpired claim returns
  `{version:1,outcome:"held",reason:"busy"}` without its token. A lost claim
  response never grants I/O; after expiry a successor can claim the same
  permanent objects only. No operation renews the cohort deadline.
- `settle_initial_media_verification(p_owner UUID, p_scan UUID,
  p_submission_digest TEXT, p_manifest_digest TEXT, p_preparation_token UUID)`
  records one all-items private receipt after the trusted server owner has
  verified actual retained bytes. The SQL routine derives all role evidence from
  the fixed manifest; it takes no replacement items, hashes, URLs or result. It
  returns `{version:1,outcome:"verified",receipt}` on first insertion.
- `get_initial_media_verification(p_owner UUID, p_scan UUID,
  p_submission_digest TEXT, p_manifest_digest TEXT)`
  returns `{version:1,outcome:"replay",receipt}` for the exact saved
  verification, or `{version:1,outcome:"held",reason:"missing"}`. It grants no
  preparation or provider authority. Both claim and settlement also return this
  same replay envelope when an exact receipt already exists, after live
  identity/deletion checks and before gate, lease or expiry checks.

A missing cohort returns held/missing. Different manifest identity conflicts
(`initial_analysis_conflict`, 23505). Retired allocation returns held/retired.
Claim after cohort expiry returns held/expired. Claim requires the existing
server lifecycle gate, with disabled admission held/disabled. A later/unknown
lifecycle, scan, history, provider evidence or completion returns held/in_use.
Settlement with a missing, replaced or expired token returns held/stale. First
receipt insertion requires a current unexpired claim and nonretired pending
operation. The token alone cannot prove that verification finished before
expiry; there is no second durable pre-receipt. Receipt replay ignores the
supplied token after validating its UUID shape; it is known-result recovery,
never proof of fresh storage or provider work. Cancellation or deletion always
wins over receipt replay through M1's scope validation.

Receipts contain only
`{version:1,owner_id,scan_id,submission_digest,
manifest_digest,backend_generation,verified_at}`.
They assert exact retained source/prepared bytes, lengths and digests plus
declared-type signature plausibility only. They do not establish MIME/container
structural validity, decodability, safety, executable derivation, provider
execution or funding. Private claim and receipt rows reference the original
submission by composite owner/scan FK, erase in its transaction and reject
independent mutation/deletion. Claims may replace only expired tokens under the
same scope. Receipts are write-once. Their private digests never enter permanent
cleanup rows. Strong erasure atomically retires permanent objects before private
cascade.

An active preparation claim or any verification receipt excludes ordinary M1
expiry retirement. Retirement and settlement serialize on the original scope;
retirement first makes settlement held/retired, and settlement first makes
retirement held/in_use. C1 cancellation is the explicit abandonment path for
verified but still pending media and removes these private rows; it keeps its
existing exact proof-based refund and unknown-execution rules. Verification must
not be inserted into `initial_analysis_results` or treated as provider evidence.

## Exact retained configuration

`get_initial_media_backend(p_generation UUID)` is a service-only read returning
`{version:1,outcome:"resolved",backend:{generation,provider,direct_endpoint,
private_bucket,namespace,credential_profile}}`,
or `{version:1,outcome:"held",reason:"missing"}`. It resolves only that
immutable M1 generation, including after private erasure. Values satisfy M1's
bounded closed schema. No credential, caller endpoint or current-default
fallback is accepted. Resolver output grants neither write nor cleanup
authority.

The inactive trusted transport maps the saved profile name to separately
provided writer/eraser signers. No secrets are persisted or logged. It
constructs one fixed private object key from the namespace, scan UUID and
permanent object UUID. It rejects redirects and signs a request before one raw
fetch per phase; a signing client's implicit retry behavior is not used.

## Byte owner and storage work

The inactive byte owner strictly decodes the full closed M1 binding, recomputes
its canonical digest and compares the exact original ordered admission. Before
copying it enforces item/role counts, declared and actual buffer lengths and
aggregate bounds, including both supplied roles when one object is shared.
Shared role buffers must compare byte-for-byte equal; then copy each distinct
object once before the first await. Verify declared-type signature, actual
length and SHA256 of every distinct object. Sharing is valid only for the exact
same role tuple within an item. Raw MP4 has no prepared role; text has an empty
cohort. Existing limits remain eight items, ten distinct objects and 28,625,792
bytes. Matching prepared bytes does not establish the executable transform or
MP4 frame/companion derivation.

Preparation receives only a fresh claimed response; replay or held cannot start
storage. The aggregate operation uses one monotonic deadline capped by the
original claim's remaining lifetime, at most twenty seconds, with bounded
actual-stream bytes and chunk/work counts. The shared deadline includes backend
resolution, signing, every PUT/GET body, settlement and any exact recovery read.
Reserve five seconds for settlement/recovery before starting storage;
insufficient budget holds without starting another request. Synchronous
validation is bounded in size and checks elapsed time; it does not claim CPU
preemption. No provider or funding operation belongs here. Before each request
check cancellation/deadline. Dependencies that ignore abort cannot make late
values initiate settlement. A known reply from an already-issued settlement is
not a new verification attempt; after an uncertain/lost reply only exact receipt
reading is permitted.

A nonempty object is written once with conditional create at its original key.
Success or an existing-object conflict still requires direct uncached GET and
actual byte/type verification. An uncertain PUT may only recover by GET of the
same object; no replacement key or unconditional retry. An existing erasure
marker, missing object or mismatch remains unverified. Entire cohort
verification must succeed before settlement; partial work creates no receipt.
Settlement's fresh owner/lifecycle/token/registry check fences cancellation and
retirement that occurred during storage work. A lost settlement response permits
only the exact read, not another preparation/provider invocation.

Erasure remains M1's separately claimed retired-object work. Empty same-key PUT
must replace all private metadata and be verified through a direct uncached
empty GET before acknowledgement. The marker PUT sends exactly zero bytes,
`Content-Type: application/octet-stream`, `Cache-Control: private, no-store` and
one user metadata field `x-amz-meta-merian-state: erased-v1`; it supplies no
other `x-amz-meta-*` fields. A direct uncached GET must return status 200,
`Content-Length: 0`, actual zero bytes, those exact content-type/cache-control
and marker values, no content encoding, and no additional `x-amz-meta-*`
headers. Any missing/extra/mismatched field fails confirmation. Normal object
PUTs contain their exact role content type and
`Cache-Control: private,
no-store` with no user metadata. Marker PUT replaces
the entire object and user metadata set; there is no metadata-preserving copy
operation. HTTP transport headers such as ETag/request IDs are not user metadata
and confer no proof. A stale claim may write only the already permanent marker;
it cannot acknowledge. No physical DELETE, signed URL, public read, multipart,
copy, arbitrary URL or second backend is supplied. Hosted principal/lifecycle
guarantees remain unqualified despite local fake storage tests.

## Required internal pre-dispatch validation

M2 byte retention is not a codec validator. Before enabling a format, the
initial-route/media integration owner must name its concrete bounded structural
validator/decoder and resource limits. It must validate the exact immutable
retained bytes consumed by execution, covering malformed, truncated, polyglot
and decode/decompression expansion cases as applicable. Failure rejects or holds
without provider dispatch or silently replacing media. This is an INTERNAL S0
implementation and acceptance prerequisite, not merely hosted qualification.
Current signature checks do not close it. No provider authorization may rely on
the M2 receipt alone. Executable source-to-prepared transformation remains a
separate attestation requirement as well.

## Evidence and acceptance

Require claim contention/lost response/expiry and expired-token rejection, exact
receipt replay/conflict, fixed backend recovery after erasure, all-items
atomicity, both retirement/settlement race orders, cancellation/scan/account
races, copied-buffer mutation, strict malformed binding/profile rejection,
actual-stream/deadline limits, unknown PUT same-object recovery, both
marker/write orders and late callbacks. Test empty text and distinct/shared
roles. Keep source/prepared byte matching, executable transform attestation,
authenticated private native readers and hosted storage guarantees separate in
the capability matrix. Full affected gates and exact candidate independent
re-review are required. Production gate stays false and backend selection null.
