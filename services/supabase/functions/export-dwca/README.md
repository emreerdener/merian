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
no work. Every invocation performs exactly one bounded durable step and returns
synchronously. A one-minute cron keeps advancing due work; no single `waitUntil`
workload owns the complete export.

## Bounded archive pipeline

- `db.ts` reads at most 100 scans at a time with an `id > last_id` keyset.
  Tombstones are excluded. Personal and global scans use matching partial
  indexes. Occurrence pages omit media arrays; multimedia pages omit taxonomy
  and coordinate fields.
- `archive.ts` encodes one occurrence or multimedia page into a work chunk no
  larger than 512 KiB. `advance_export_job_step(...)` commits the strictly
  increasing cursor, aggregate row/byte counters, and chunk manifest before
  releasing that step's claim.
- Temporary chunks use
  `exports/{user}/{job}/work/{phase}/{sequence}-{claim_token}.csv`. The claim
  token prevents a lease-expired PUT from overwriting a replacement worker's
  manifest-selected bytes.
- Once both keyset passes finish, one assembly step streams only the durable
  manifest into `meta.xml`, occurrence CSV, multimedia CSV, and the final ZIP.
  Exact R2 GET byte counts must match the manifest.
- `zip.ts` writes a standards-compliant ZIP32 `STORE` stream with data
  descriptors and incremental CRC-32 values. It does not construct a JSZip
  object or buffer the archive.
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
A lost fence, transient Resend rejection, or completion write failure leaves the
row processing so the lease/watchdog determines the outcome instead of falsely
reporting completion. R2 lifecycle policy remains responsible for deleting
temporary export objects, including an orphan from a worker that died before
staging, and for aborting incomplete multipart sessions after seven days. The
checked-in `docs/r2-lifecycle.json` contract includes both rules.

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

Focused Deno tests cover keyset progression, row/archive budgets, phased
progress, claim-fenced work chunks, exact manifest reads, ZIP compatibility,
bounded multipart upload/abort/provider responses, embedded HTTP-200 completion
errors, pseudonym key failure/rotation, Resend idempotency, canonical claims,
staged retry reuse, and stale-worker fencing. Static contracts lock the
migration and production-source boundaries. The executable database test also
proves the finite rollout deadline, post-deadline claim requirement, and phased
state contract; it lives at `services/supabase/tests/export_dwca_security.sql`
and is checked by the repository-wide privileged-routine catalog validator.
