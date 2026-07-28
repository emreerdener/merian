# Darwin Core Archive Worker

`export-dwca` is the service-authenticated worker for queued Darwin Core Archive
(DwC-A) exports. Only the webhook's job UUID is authoritative:

```json
{ "job_id": "00000000-0000-4000-8000-000000000000" }
```

Pre-existing nonterminal jobs and jobs queued during the first two hours after
the migration form a finite rollout cohort. Newly queued cohort webhooks may
also include deprecated canonical user/scope/precision hints for the previously
deployed bundle; this worker never reads them. Jobs created after the private
protocol deadline receive only `job_id` and cannot enter processing without a
claim.

The worker never trusts a caller-supplied user, scope, precision flag, key
version, status, budget, or object key. Public callers can queue personal
exports only; a global export requires a separately reviewed internal
administrative insertion. Every job pins immutable defaults of 5,000 aggregate
CSV rows and an 8 MiB final archive (schema hard maxima: 20,000 rows and 16
MiB).

`claim_export_job_step(...)` locks the canonical queue and work rows, installs a
private two-minute UUID lease, and returns one current phase plus its keyset
cursor and accumulated budgets. A duplicate delivery receives no claim and does
no work. A targeted insertion webhook attempts only its canonical job once,
bounding fan-out during intake bursts. The once-per-minute empty-body cron
invokes a synchronous, sequential global drain: it repeatedly discovers up to
five jobs in oldest-due order and executes one bounded durable phase for each.
It starts no new phase after the 40-second soft cutoff and attempts at most 40
phases per invocation. Failed, terminal, or contended jobs are suppressed for
the rest of that invocation; successfully advanced work re-enters database
ordering behind older due jobs. This raises continuation throughput without
making one `waitUntil` workload own the complete export or allowing concurrent
archive assemblies inside one isolate.

Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`
upgrades every nonterminal job to source snapshot version 2. When a job is
inserted, one database statement materializes the bounded, privacy-projected
occurrence and multimedia JSON DTOs for every eligible scan. Both phases
therefore traverse the same immutable `(job_id, scan_id)` rows and can never mix
taxonomy, media, or privacy revisions from separate live queries. The taxonomy
join uses `confirmed_species_id` when present and otherwise falls back to the
original AI `species_id`. Exact GPS fields are persisted only for a personal job
that explicitly requested them and whose snapshot taxonomy did not require
protected-species redaction.

Only the scope-aware eligibility hash is revalidated against live state before a
page is returned. Ordinary edits after queueing do not change the archive.
Deletion, tombstoning, owner changes, or a privacy/protection change that makes
a row unsafe produces terminal `source_snapshot_changed`. Personal snapshots
deliberately ignore geoprivacy because they export only the requesting owner's
captures. Both scopes still revalidate whether protected-species coordinate
redaction is required, so a conservation escalation cannot release coordinates
under a stale unprotected projection. Immutable DTO rows are purged when the job
becomes terminal.

## Bounded archive pipeline

- Ordered migrations `20260725175312_bound_dwca_export_source_bytes.sql` and
  `20260725180321_validate_dwca_export_source_bounds.sql` bound source rows
  before the Data API can materialize them: at most 24 media URLs of 4 KiB each,
  at most 10 ecological interactions of 2 KiB each, and finite selected taxonomy
  lengths. The first transaction enforces new writes and releases its
  `ALTER TABLE` lock; the second validates legacy rows before activating the
  source-page RPC.
- Snapshot version 2 records the exact UTF-8 byte count of both JSON projections
  before inserting any DTO. Each projection is limited to 256 KiB, total source
  bytes are limited to four times the job archive budget with a 64 MiB hard cap,
  and a row-budget-plus-one lookahead rejects an oversized job without exposing
  its source rows to Edge.
- `db.ts` calls `get_dwca_export_scan_batch(...)` under the active claim. The
  database validates the durable `id > last_id` cursor, reads from immutable job
  DTO rows, revalidates only live scope-aware eligibility, and stops at 100
  scans or 256 KiB of serialized source payload. Sentinels distinguish a
  finished keyset, an unexpectedly oversized first source row, and a revoked
  source. Occurrence DTOs omit media arrays; multimedia DTOs omit taxonomy and
  coordinate fields.
- `archive.ts` uses a fixed-capacity incremental UTF-8 encoder. It appends one
  header or CSV row at a time—without a page-wide string array, `Promise.all`,
  multimedia expansion array, or final `join()`—and can never allocate an output
  chunk larger than 512 KiB. It calculates that bounded chunk's CRC-32 while the
  bytes are already resident. `advance_export_job_step(...)` commits the
  strictly increasing cursor, aggregate row/byte counters, object key, byte
  count, and unsigned CRC before releasing that step's claim.
- Temporary chunks use
  `exports/{user}/{job}/work/{phase}/{sequence}-{claim_token}.csv`. The claim
  token prevents a lease-expired PUT from overwriting a replacement worker's
  manifest-selected bytes.
- Once both keyset passes finish, one assembly step streams only the durable
  manifest into `meta.xml`, occurrence CSV, multimedia CSV, and the final ZIP.
  Exact R2 GET byte counts must match the manifest.
- `zip.ts` writes a standards-compliant ZIP32 `STORE` stream with data
  descriptors. `crc32.ts` combines ordered per-chunk checksums with GF(2)
  composition to obtain each CSV entry checksum in work proportional to chunk
  count, without a JavaScript pass over every archive byte. The ZIP stream
  compares emitted entry lengths with the manifest and fails closed on a
  mismatch. It does not construct a JSZip object or buffer the archive.
- `storage.ts` coalesces the stream into fixed 8 MiB Cloudflare R2 multipart
  parts. It completes the upload only after every part succeeds and attempts to
  abort incomplete uploads on failure. Create/complete XML and Resend response
  bodies are streamed through small byte ceilings. Multipart completion parses
  the XML and rejects S3-compatible `<Error>` documents even when the provider
  has already returned HTTP 200. Individual R2 requests have a 60-second
  deadline; Resend delivery has a 15-second deadline.

The archive contains observation metadata and media URLs, not copied image
bytes. The worker enforces the canonical budget before every work-chunk PUT and
again while uploading the final archive. Exceeding it produces stable terminal
`export_too_large`. Streaming bounds heap use; the small phased claims bound
each Edge invocation's database, encoding, and provider work.

Migration `20260726235158_amortize_dwca_archive_crc.sql` adds the required
`internal.export_job_chunks.crc32` invariant and retires the old advance-RPC
signature. During rollout it fences and restarts only nonterminal jobs still in
occurrence, multimedia, or assembly, using their existing immutable source
snapshot. Legacy temporary manifests are discarded; jobs already delivering a
staged archive are not restarted. Canonical job rows are locked in UUID order
before chunk-table DDL, preserving routine lock order during a live deploy. CRC
byte-length operators are precomputed once per isolate rather than rebuilt per
manifest chunk. Do not increase the 16 MiB schema ceiling from a workstation
benchmark: use production phase/shutdown telemetry and preserve the
bounded-chunk checksum design.

### Runtime resource contract

The Supabase
[canonical Edge Function limits](https://supabase.com/docs/guides/functions/limits)
page, verified 2026-07-26, lists 2 seconds of active CPU per request and 256 MB
of memory. Supabase's
[CPU troubleshooting page](https://supabase.com/docs/guides/troubleshooting/edge-function-cpu-limits)
still lists 200 milliseconds, while the newer
[546 resource-limit guide](https://supabase.com/docs/guides/troubleshooting/edge-function-546-error-response)
lists 2 seconds and 250 MB. Treat these values as platform-controlled and
currently inconsistent documentation—not as additional export capacity. Keep
each durable phase well below the smallest published CPU budget and consult the
canonical page, project metrics, and 546/`CPU Time exceeded` logs before
changing any archive, chunk, page, or drain ceiling.

The cached combiner processed a synthetic 20,000-part, 16,000,000-byte manifest
in approximately 7.3 ms on development hardware, compared with approximately 160
ms when GF(2) matrices were rebuilt for every part. This microbenchmark isolates
checksum composition only; it is neither a production SLA nor a substitute for
maximum-shape staging tests and hosted telemetry.

## Queue health and alerting

Migration `20260726230837_scale_dwca_export_continuations.sql` adds the
service-only `get_dwca_export_queue_health()` RPC and an outstanding-job partial
index. The RPC exposes aggregate backlog, due-job, active/expired-claim, and
oldest-due-age values only; API roles cannot execute it or read private queue
tables.

Every dispatcher call emits one structured `dwca_export_queue_health` event. The
route warns at an oldest-due age of five minutes, 25 outstanding jobs, or any
expired claim; it becomes critical at 15 minutes or 100 outstanding jobs. The
independent **DwC-A Export Queue Health Monitor** workflow runs every five
minutes with the same defaults, writes bounded JSON/Markdown summaries, and
fails at warning by default. During an alert, inspect queue-health and
claim-fenced step logs, repair R2/database/provider availability, and let
durable retries resume. Do not clear private claims or edit work cursors.

`backlog_count` includes every nonterminal job, including work in backoff or
under a live lease. `due_count` and the oldest-due fields describe only work
whose `next_step_at` has arrived and which has no unexpired claim. Consequently,
`queue_drained: true` means that the dispatcher exhausted currently claimable
due work; it can coexist with a nonzero backlog waiting on a lease or retry
deadline.

The 40-step ceiling is a safety bound, not a guaranteed 40-step-per-minute rate.
The soft cutoff is checked between durable phases, and a phase already in flight
is allowed to finish or reach its own deadline. Completion latency therefore
depends on page, R2, Resend, and database duration as well as queue depth. Use
oldest-due age and backlog trends as the capacity signal instead of deriving a
fixed completion SLA from the ceiling.

## Retry and delivery semantics

An upload uses an attempt-fenced key:

```text
exports/{user_id}/{job_id}/{claim_token}.zip
```

A delayed assembly worker therefore cannot overwrite a newer attempt's final
object, and claim-fenced work-chunk names provide the same property during CSV
preparation. Once the winning assembly step stages its object key and signed URL
transactionally, a later delivery step reuses them instead of regenerating the
archive. Email delivery uses Resend's `Idempotency-Key: dwca-export/{job_id}`.
The archive is marked complete only after Resend accepts that idempotent
request.

Generation, storage, and permanent delivery failures become public-safe database
failure codes and fixed messages when the worker still owns the fence, allowing
an immediate new request. The database transition trigger also replaces raw
failure text from a rollout-era worker before the owner-readable row is stored.
A source revision mismatch is terminal because recreating the job is the only
way to establish a new coherent source snapshot. A lost fence, transient Resend
rejection, or completion write failure leaves the row processing so the
lease/watchdog determines the outcome instead of falsely reporting completion.
R2 lifecycle policy remains responsible for deleting temporary export objects,
including an orphan from a worker that died before staging, and for aborting
incomplete multipart sessions after seven days. The checked-in
`docs/r2-lifecycle.json` contract includes both rules.

During the two-hour migration cohort, a previous bundle may already be in
flight. It can finish an unclaimed cohort job, but once the new worker installs
a claim the old worker's status, result, and failure writes cannot alter that
attempt or a terminal result. The new worker never recovers a cohort job already
marked `processing` without a claim; the watchdog fails it after 30 minutes.
Because the previous bundle did not reliably observe update errors, operators
must not manually redeliver a cohort job while its old invocation may still be
active. The existing atomic ghost-profile merge remains able to tombstone a
colliding active export with the stable `owner_changed` code.

## Pseudonymization

Global exports replace owned, non-tombstone user UUIDs with a versioned,
domain-separated HMAC-SHA256 pseudonym. Ownerless account-deletion tombstones
use the generic `Naturebook Citizen Scientist` recorder and are never passed to
the pseudonymizer. Exports never use `SUPABASE_JWT_SECRET`, a raw hash, or a
fallback salt.

Version 1 requires `DWCA_PSEUDONYM_HMAC_KEY_V1`, encoded as Base64 and decoding
to at least 32 random bytes:

```bash
openssl rand -base64 32
```

Store that value in the GitHub `Production` environment. The deploy workflow
validates it and synchronizes it to Supabase Edge secrets. For rotation,
provision and synchronize `..._V2` first, deploy code that can read it, then
change the `export_jobs.pseudonym_key_version` default in a migration. Retain
old versions until every job pinned to them is terminal and past retention.

## Tests

Focused Deno tests cover standard CRC vectors, exact split-checksum composition,
claim-bound byte-aware source pages, completion and oversize/revision sentinels,
incremental fixed-buffer CSV encoding, row/archive budgets, phased progress,
claim-fenced work chunks, exact manifest/CRC reads, ZIP compatibility and
length-mismatch rejection, bounded multipart upload/abort/provider responses,
embedded HTTP-200 completion errors, pseudonym key failure/rotation, Resend
idempotency, canonical claims, staged retry reuse, stale-worker fencing, fair
multi-wave draining, soft-deadline exit, and failure suppression. Static
contracts lock the migrations and production-source boundaries. Executable
database tests prove source constraints, aggregate page byte limits,
creation-time immutable DTOs, authoritative confirmed identity, live privacy
revocation, terminal purge, the finite rollout deadline, post-deadline claim
requirement, queue-health ACL/index behavior, live/expired claim accounting, and
phased state contract in `services/supabase/tests/export_dwca_security.sql` and
`services/supabase/tests/export_dwca_snapshot_security.sql`, plus
`services/supabase/tests/dwca_export_queue_security.sql`; the repository-wide
privileged-routine catalog validator checks the definer RPC.
