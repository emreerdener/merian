# identify-describe

Compatibility endpoint for legacy text-only description scans.

The active iOS Describe path now submits through `/identify-multimodal` via the
shared non-visual request builder, but this route remains deployed for older
clients, route-parity tests, and ops compatibility.

The route resolves the canonical scan UUID and checks exact owner completion
before quota/provider work. A repeated or lost-response delivery replays a
stored or reconstructed successful envelope as `200` with
`X-Merian-Idempotent-Replay`; concurrent same-UUID delivery coalesces with the
winner and never makes a second Gemini call. Successful completion persists the
validated response through the response-aware scan finalizer.

## Response Contract

The compatibility route consumes the same executable model/final response
descriptor as the visual routes. Its provider schema is generated from
`merianDescribeModelContract`, which preserves the shared fields and requires
`is_live_capture=false` plus exactly zero for every image-quality value on
text-only input. Its provider descriptions remain text-specific rather than
reusing vision-oriented evidence language. Provider output is runtime-parsed
before normalization, and the complete server-enriched `{ success, data }`
response is parsed again before persistence or delivery.

Invalid nested fields, requiredness, enums, cardinality, string limits, unsafe
integers, or numeric bounds fail closed. A final mismatch returns HTTP `502`
with `identify_response_invalid`; no malformed payload is saved or delivered.
Intentional contract changes require `make generate-edge-dto-contract` followed
by `make validate-edge-dto-contract`.

## Durability

Before provider dispatch, `identify-describe` atomically records a
`scan_ingestion_jobs` row plus a sanitized `scan_ingestion_intents` row through
`_shared/scanIngestionCompatibility.ts`. Setup failure fails closed before paid
work and refunds the unused quota reservation.

- Description text is stored as an `observationContexts` entry in a
  multimodal-shaped replay payload.
- Because no raw media bytes are needed, text-only compatibility intents are
  `resumable = true`.
- `replay-scan-ingestion` can recover retryable failures by invoking
  `/identify-multimodal` with the same `client_scan_id`, subject to the shared
  10-claim server replay ceiling.
- The service-only Auth-backed profile prerequisite runs before paid work and
  again before insertion, closing profile drift and identity retirement races.
- Scan insertion is awaited, never registered as background work. Success is
  impossible without the exact owner row. The shared completion-last
  finalization RPC runs in that required task; if only its post-insert
  bookkeeping fails, the owner row remains the canonical response surface and
  the ledger remains retryable for reconstruction/reconciliation. A failure
  before insertion returns a stable 503.
- Insertion settles through the shared exact-owner persistence boundary. A
  thrown/lost database response or unavailable owner verification does not fail
  committed provider quota; a same-UUID retry resolves the durable row or safely
  reopens only a proven scan-less attempt.
- Dictionary cache enrichment after provider dispatch is nonfatal. A transient
  read falls back to uncached scan enrichment while required persistence still
  runs inside the durable failure boundary.
- Analytics, group tags, and candidate enrichment are optional background work
  registered only after the scan is durably complete.

## Biological Boundary

Text descriptions use the same post-parse processed-material guard as the visual
routes. A description of a manufactured or processed object is non-biological
even when it mentions biological source material, for example a wool rug,
leather jacket, wooden table, paper sheet, cotton textile, prepared food,
artwork, toy, ornament, or species depiction.

Before cache lookup or dictionary writes, `identify-describe` normalizes these
results to `is_biological_subject=false`, clears source-species
`scientific_name`, strips candidates, and prevents
`is_new_to_merian_dictionary`. Demotions emit a structured
`identify-describe/processed_material_demoted` event. Valid biological
descriptions, fossils, pressed plants, dried specimens, and preserved specimens
remain biological.

Dictionary common-name writes preserve any existing
`species_dictionary.common_names.en`; a scan-level name only fills an empty
English name for a normalized biological subject.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/identify-describe/index.ts services/supabase/functions/_shared/scanIngestionCompatibility.ts services/supabase/functions/_shared/identify/subjectClassification.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/identify-describe/index.test.ts services/supabase/functions/_shared/scanIngestionCompatibility_test.ts services/supabase/functions/_shared/identify/contract_test.ts services/supabase/functions/_shared/identify/subjectClassification_test.ts services/supabase/functions/_shared/identify/db_test.ts
```
