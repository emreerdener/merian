# identify-describe

Compatibility endpoint for legacy text-only description scans.

The active iOS Describe path now submits through `/identify-multimodal` via the
shared non-visual request builder, but this route remains deployed for older
clients, route-parity tests, and ops compatibility.

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

Before returning success, `identify-describe` records a `scan_ingestion_jobs`
row plus a sanitized `scan_ingestion_intents` row through
`_shared/scanIngestionCompatibility.ts`.

- Description text is stored as an `observationContexts` entry in a
  multimodal-shaped replay payload.
- Because no raw media bytes are needed, text-only compatibility intents are
  `resumable = true`.
- `replay-scan-ingestion` can recover retryable failures by invoking
  `/identify-multimodal` with the same `client_scan_id`, subject to the shared
  10-claim server replay ceiling.
- Successful background insert marks the job `complete`; insert failures mark it
  `failed_retryable`.

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
