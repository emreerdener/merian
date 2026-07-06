# identify-describe

Compatibility endpoint for legacy text-only description scans.

The active iOS Describe path now submits through `/identify-multimodal` via the
shared non-visual request builder, but this route remains deployed for older
clients, route-parity tests, and ops compatibility.

## Durability

Before returning success, `identify-describe` records a `scan_ingestion_jobs`
row plus a sanitized `scan_ingestion_intents` row through
`_shared/scanIngestionCompatibility.ts`.

- Description text is stored as an `observationContexts` entry in a
  multimodal-shaped replay payload.
- Because no raw media bytes are needed, text-only compatibility intents are
  `resumable = true`.
- `replay-scan-ingestion` can recover retryable failures by invoking
  `/identify-multimodal` with the same `client_scan_id`.
- Successful background insert marks the job `complete`; insert failures mark it
  `failed_retryable`.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/identify-describe/index.ts services/supabase/functions/_shared/scanIngestionCompatibility.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/identify-describe/index.test.ts services/supabase/functions/_shared/scanIngestionCompatibility_test.ts
```
