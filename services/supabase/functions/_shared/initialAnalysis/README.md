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
original reservation and complimentary credit remain held: the future exact
initial cancellation/settlement owner must prove non-execution before release.
Account deletion cascades owner quota and usage rows; it does not refund or
reclassify unknown execution. Unknown execution never permits a second provider
call or refund.

The repository issues one logical adapter call and performs no retry itself. Its
injected PromiseLike RPC and asset reader do not yet enforce transport
deadlines, cancellation or disabled underlying retries. A bounded,
cancellation-aware, no-retry transport is an unsatisfied live-installation
prerequisite; a timeout must remain unknown and cannot prove a write was
cancelled. Lost acknowledgement is unknown. `recoverAdmission` uses saved exact
input and null fresh-admission authority; absent or deleted evidence cannot be
reconstructed. Neither response is a dispatch grant. Durable native
input/operation storage and the future status/result recovery API remain
separate requirements.

## Configuration retention

`configuration-assets-v1.json` pins 60 transitive source/configuration assets at
revision `86e007a5f1b2ae3064bbe21f9fd140a4b3dead4b`, plus external dependency
specifiers and the frozen dependency lock. Its domain-separated digest is stored
with the SQL rollout and admission. `verifyInitialConfigurationAssets` requires
exact bytes at that revision through `git_blob_sha256_v1`; missing, changed or
unrecognized assets hold. It never silently substitutes current code. The
initial-engine release archive owns retention. This checkpoint validates source
resolution; production bundle/dependency archival and execution-time resolution
of the saved manifest still require implementation and qualification.

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

No initial dispatch/cancellation API, durable media staging, original result
capture, completion, status operation, history enrollment or native installation
is provided here. All three route adapters and affected recovery/cleanup workers
must cut over together after old writers are quiescent. Enabling a gate alone is
not a supported rollout. Fresh libraries remove older-scan compatibility duties,
not contention or erasure duties.

`admission_test.ts` covers the private codec/repository and byte preparation.
`initialAnalysisAdmissionDb.test.ts` covers TS/SQL vectors, retained profiles
and observed database races. `tests/initial_analysis_admission.sql` covers
effective privileges, exact replay, rollback, namespace/expiry holds and
erasure. Candidate evidence and unresolved qualification live in
`.artifacts/initial-analysis-admission/checkpoint.md`; the canonical contracts
are
[database schema](../../../../../docs/backend-and-data/04-database-schema.md),
[API contracts](../../../../../docs/backend-and-data/05-api-contracts.md) and
[retention](../../../../../docs/backend-and-data/17-scientific-observation-retention.md).
