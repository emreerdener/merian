# IC-1 M1 initial-media allocation and retirement

Status: proposed bounded inactive prerequisite, October 11, 2026. C1 is locally
accepted at `990cb63dd3cda2ff706f29457b3c2cedeae9f488`. This contract prepares
allocation and retirement, not verified bytes, executable transforms, upload
permission, provider dispatch, saved-scan media or an installed reader. The
history primary is sole writer; the initial-engine owner and an independent
project reviewer review the exact contract and candidate evidence.

## Identity, roles and budgets

One admitted operation has one immutable ordered allocation cohort. The fixed
allocator derives it from the original validated submission and admission
digest; callers supply no replacement media tuples, object keys or item lists.
Description input has an explicit empty cohort. Every non-video item has
explicit `source` and `prepared` roles with object UUID, content type, byte
count and SHA256. Share an object within an item only when all three byte/type
fields are identical under the admitted semantics; never deduplicate across
items or by digest alone. Differing source and normalized WAV tuples allocate
distinct objects. Raw MP4 is source-only; its `prepared` role is null and it is
not provider-consumed evidence.

The full admitted media tuple is retained in each private manifest item,
including transform parameters and input/source/clip/frame indexes.
Frame/companion grouping is declared input, not proof of derivation from the
clip. Source retention, prepared-byte matching and trusted executable
transformation are three separate verification levels; none is supplied by this
allocation checkpoint.

Current input limits imply at most eight items, ten distinct objects and
28,625,792 distinct retained bytes: 5 MiB aggregate images, two WAV items with
up to 2,700,000 bytes for each role, and one 12 MiB source clip. Enforce those
bounds without expanding admission limits. Allocation is atomic for the entire
ordered cohort; no replacement cohort follows an unknown response or expired
deadline.

## Immutable backend and private records

Each object binds a non-secret immutable backend-generation UUID. Its retained
configuration names provider, direct endpoint, private bucket, fixed namespace
and credential-profile identity; it contains no credentials. Cleanup resolves
the original generation, never current defaults. The backend-generation argument
is an assertion of server selection, not caller authority: first allocation
requires equality with a separately configured server rollout selection. Exact
replay compares the original generation and ignores changed defaults. A
different assertion conflicts. Generation records are insert-only and cannot be
updated or deleted, including before first use. No actual profile is seeded or
hosted bucket created by this increment. The ordinary public scan bucket and
history configuration are not fallback targets.

`initial_analysis_media_cohorts` is private immutable
operation/owner/submission, backend generation, five-minute allocation deadline
and ordered manifest. Its foreign key to the original private submission enables
authoritative erasure. Role mappings and hashes are erased with it. A separate
permanent `initial_analysis_media_registry` retains only logical
operation/object/backend identities, monotonic retirement and content-free
cleanup coordination. A permanent `initial_analysis_media_allocation_fences` row
stores operation ID and `allocated | retired` even for an empty text-only
cohort; it prevents replacement after private erasure. It retains no deadline,
owner, manifest, digest or input. It has no owner, media hash/type, transform or
result reference. Object UUID is its lifetime generation and cannot be reused or
redirected. Every registry object is committed before any future physical I/O,
including objects from an interrupted allocation. The allocation transaction
either commits the complete cohort or nothing.

The manifest digest uses the existing bounded canonical encoder with the
distinct prefix `merian.initial-analysis.media-allocation.v1\n`. It binds owner,
operation, original submission digest, backend generation, deadline and ordered
items. Neither it nor its role digests survive strong private evidence erasure.

## Fixed service operations and recovery

These functions are service-only; private tables deny all direct API-role access
and enable RLS. No route, native adapter or scheduled worker is installed. UUID
arguments use PostgreSQL UUID types, digests are lowercase 64-character SHA256
text, and mutation/read outcomes below are closed JSON objects.

- `allocate_initial_analysis_media(p_owner UUID, p_scan UUID,
  p_submission_digest TEXT, p_backend_generation UUID)`
  derives the whole cohort. First allocation requires the default-off lifecycle
  gate, matching server backend selection and the exact pending original
  operation. It returns `{version:1,outcome:"allocated",binding}`. An existing
  exact live allocation returns `{version:1,outcome:"replay",binding}` after
  checking the original requested backend. Replay does not consult current
  defaults or the gate.
- `get_initial_analysis_media(p_owner UUID, p_scan UUID,
  p_submission_digest TEXT)`
  never allocates. An existing live allocation returns
  `{version:1,outcome:"replay",binding}`. No allocation returns
  `{version:1,outcome:"held",reason:"missing"}`. This absence is metadata only
  and does not authorize a successor.
- Both operations return `{version:1,outcome:"held",reason:"retired"}` for a
  still-live same-owner private cohort retired by M1 itself. Expired but not
  retired allocations return
  `{version:1,outcome:"held",reason:"expired",binding}` containing only the
  original metadata. Deadline, destinations and backend never change. Retirement
  takes precedence over expiry. Erased private bindings cannot be reconstructed
  from permanent registry rows.
- `retire_initial_analysis_media(p_owner UUID, p_scan UUID,
  p_submission_digest TEXT)`
  returns `{version:1,outcome:"retired"}` for a newly retired or already retired
  exact private cohort. Missing allocation returns
  `{version:1,outcome:"held",reason:"missing"}`; before its deadline returns
  `{version:1,outcome:"held",reason:"not_expired"}`. A later or unknown
  lifecycle phase/use returns `{version:1,outcome:"held",reason:"in_use"}`.
  Retirement never settles funding. Cancellation/deletion owns earlier
  retirement and private erasure through authoritative lifecycle hooks.
- `claim_initial_analysis_media_erasure()` returns `{version:1,outcome:"empty"}`
  or
  `{version:1,outcome:"claimed",object:{scan_id,
  object_id,backend_generation,claim_token,claim_expires_at}}`.
  Tokens are UUIDs; timestamps use UTC epoch milliseconds as safe integers. It
  selects one already retired, unconfirmed object whose existing one-minute
  lease is absent/expired.
- `finish_initial_analysis_media_erasure(p_object UUID, p_claim UUID,
  p_success BOOLEAN)`
  returns `{version:1,outcome:"acknowledged"}` on a current unexpired
  retired-object claim, otherwise `{version:1,outcome:"stale"}` with no changes.
  Success records marker confirmation; failure releases only that lease. A lost
  acknowledgement remains unknown to that caller. The durable registry
  independently suppresses confirmed objects or makes unconfirmed retired
  objects eligible after lease expiry. An empty claim is never confirmation:
  another worker, an active lease or skipped locked row can produce it. Exact
  positive confirmation would require a separately implemented read; no other
  destination is ever permitted.

All three owner-bound operations apply owner/foreign, tombstone and terminal
lifecycle checks before private cohort or registry lookup. C1 cancellation or
stronger deletion always takes precedence: return the closed cancelled/deleted
denial, never a retired outcome or binding. Idempotent retirement applies only
to a still-live same-owner cohort retired by M1 itself. Erasure hooks may
inspect and retire registry rows internally without exposing them. These
operations first lock and validate the live owner and original
submission/admission. Foreign, missing or erased private identity raises
`initial_analysis_owner_unavailable` (`P0002`); a live same-owner tombstone or
cancellation raises `initial_analysis_deleted` or `initial_analysis_cancelled`
(`55000`). Invalid arguments raise `initial_analysis_input_invalid` (`22023`);
changed original digest/backend raises `initial_analysis_conflict` (`23505`).
Unavailable first-allocation gate/profile or inconsistent durable evidence
raises `initial_analysis_unavailable` (`55000`). No detail contains private
values. The three owner-bound operations require read committed isolation; other
isolation raises `initial_analysis_isolation_unavailable` (`25000`). Transport
uncertainty is not one of these known SQL denials.

The closed binding contains `version:1`, `owner_id`, `scan_id`,
`submission_digest`, `backend_generation`, `expires_at` (UTC epoch
milliseconds), `manifest_digest` and `items`. Each item contains only `index`,
exact admitted `input`, `source`, and nullable `prepared`; roles contain only
`object_id`, `content_type`, `byte_count`, and `sha256`. The digest covers the
binding without its `manifest_digest`. Private roles necessarily retain admitted
hashes, types, lengths and provenance. Only the permanent cleanup projection is
content-free. No envelope contains bytes, physical URLs/keys, credentials,
funding or provider permission. A lost/malformed mutation response is unknown
until exact original reconciliation, never proof of rollback. Allocation and
replay are metadata, not physical upload authority, even before expiry.

The five-minute deadline bounds eligibility for future preparation admission; it
is not a dispatch lease and never changes on replay. Expiry alone does not allow
retirement. Retirement additionally requires exactly `pending_pre_dispatch`, the
matching live original admission/submission, and absence of scans, histories,
initial results/completions, legacy jobs/intents and provider invocation
evidence. Any unknown/future lifecycle phase holds. This checkpoint has no
consumed-media binding operation. Before any future consumer is installed, its
durable binding/use state must participate in this same owner-first retirement
exclusion; an active dispatch/result/completion or saved scan can never be
retired by deadline expiry. Empty cohorts use exactly the same one-time
allocation and retirement states, with zero cleanup objects.

## Locks, erasure and physical limits

Allocation/recovery/retirement use owner → ingestion advisory → existing scan/
history → lifecycle/submission/admission → private cohort → registry in object
UUID order. No network I/O occurs under database locks. Cancellation already
owns the outer scope and original accounting; private submission deletion
cascades cohort erasure and atomically retires every operation registry object.
Account and scan deletion use the same authoritative hooks, including pre-row
state. Cleanup lease operations lock only retired registry rows and never
acquire outer owner/accounting locks. This prevents a new reverse dependency.

A future trusted writer may use only a copied server buffer or an exact scoped
internal source-read receipt. It must verify format/length/digest and recheck
live lifecycle after I/O before recording any binding. No arbitrary client URL
or hash assertion establishes that authority. Source/prepared storage work and
private reads are not primary provider execution and never independently consume
or refund scan funding.

The proposed direct private R2 transport follows create-only nonempty writes and
permanent erasure markers; it is not implemented here. Erasure requires an
unconditional zero-byte PUT to the same original key,
`application/octet-stream`, private/no-store, erased-marker metadata and no
retained private hash metadata. Confirm empty content and marker through direct
uncached reads before successful acknowledgement. Retirement commits before
marker authority. A stale marker write remains safe because retirement never
reverses; a stale claim cannot acknowledge success. No DELETE,
signed-write/read, multipart, copy or unconditional nonempty write path is
supplied. Hosted qualification must prove every relevant principal and lifecycle
rule respects those constraints in both late-write race orders. Actual backend
guarantees remain unqualified, even after local mocked tests.

Current native captured-media readers require HTTPS media references and do not
understand this private capability. A separately implemented authenticated
reader is required before completion/native acceptance. Do not leak private keys
into captured media or silently promote private evidence into ordinary public
storage. Executable transformation attestation and provider dispatch also remain
separate IC-1 prerequisites. Activation stays false and ordinary access nil.

## Acceptance

Require exact replay/conflict, explicit empty input, role sharing/differing WAV,
aggregate limits, backend immutability, both allocation/retirement/erasure race
orders, lease expiry/stale acknowledgement and full private erasure with
retained opaque cleanup capability. Test actual API-role privileges and rollback
of partial cohort allocation. Run full affected local gates and independent
exact candidate re-review before committing. Installed, hosted and final CI
evidence remain separate rows with named owners and authorization.
