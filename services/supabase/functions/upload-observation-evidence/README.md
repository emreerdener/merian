# Private observation evidence upload

Prepared `POST upload-observation-evidence` authenticates the owner and uploads
one immutable photo cohort for a new child analysis. The media gate remains
false. There is no native production caller or activation authorization yet.

The request uses `application/octet-stream`: four unsigned big-endian bytes give
the UTF-8 JSON metadata length (1–4096), followed by that metadata and the raw
photo bytes concatenated in its order. Exact metadata fields are
`schema_version: 1`, `observation_id`, `analysis_id`, and `photos`. Each of the
1–5 photos has exactly `media_id`, `content_type` (`image/jpeg` or `image/png`),
and positive integer `byte_count`. Combined photo bytes cannot exceed 5 MiB.
Trailing bytes, missing bytes, duplicate identities and unsupported types fail
before reservation. No base64, public URL, caller owner or claimed digest is
accepted. The server hashes its owned buffers.

The service-only cohort RPC freezes all descriptors and a common five-minute
expiry atomically. Exact retries recover the original objects. Changed content
or order conflicts. A private immutable cohort row survives expired receipt
cleanup, preventing analysis-ID reuse or renewed deadlines; it cascades with
private history and is removed by the observation deletion fence. Missing
receipts require a new analysis identity, never replacement object allocation.

`handler.ts` validates every reservation before writing the first object. The
private bucket uses conditional PUT and HEAD tuple verification; completion
rechecks owner/deletion even on ready replay. Analysis admission also preserves
the frozen image subsequence; interleaved descriptions remain allowed.
Cleaned-up photo identities cannot be rebound to description-only analysis. A
lost response retries the same frame and IDs. Partial failures do not assert
readiness or start inference. Existing expiry/erasure obligations cover
abandoned objects; no cleanup worker is activated here. Permanent erasure
markers block delayed writes.

A shared 120-second deadline covers body ingestion, all RPCs and all storage
transports. Each RPC also has a 12-second bound. HTTP 200 returns exactly
`schema_version: 1`, `observation_id`, `analysis_id`, and ordered `items` with
`kind: "image"`, `media_id`, `content_type`, `byte_count`, `sha256`, suitable
for V2 analysis admission. It returns no storage key, object UUID or URL and
never changes selection or consumes inference quota. All responses use private
no-store. Actual inference additionally validates the executable media contract.

See the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#private-reanalysis-photo-upload)
and [history owner](../_shared/analysisHistory/README.md). Focused
route/handler, receipt storage, catalog and two-session concurrency checks cover
this boundary. Native capture/queue integration and private-bucket runtime
qualification remain required before activation.
