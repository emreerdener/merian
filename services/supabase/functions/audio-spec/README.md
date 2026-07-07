# audio-spec

Compatibility endpoint for legacy audio-only scan requests.

The active iOS audio path now routes through `/identify-multimodal`, which
accepts foreground `audioBase64s` and queued `audioR2ObjectKeys`. This route
remains deployed for older callers and focused audio budget tests.

## Durability

Before returning success, `audio-spec` records a `scan_ingestion_jobs` row plus
a sanitized `scan_ingestion_intents` row through
`_shared/scanIngestionCompatibility.ts`.

- Staged `audio_r2_key` requests are shaped as multimodal replay payloads with
  `audioR2ObjectKeys` and `audioMediaItems`.
- Inline `audio_base64` bytes are never stored in the intent. They are counted
  in `redacted_media_counts`, marked `inline_media_redacted = true`, and remain
  client-retry only.
- Successful background insert marks the job `complete`; insert failures mark it
  `failed_retryable`.
- Staged audio remains an inference input only and is deleted after successful
  scan persistence.

## Dictionary Common Names

Audio-only biological results can still warm or create
`species_dictionary` rows, but they share the same dictionary name merge rule as
the visual/text routes: an existing `species_dictionary.common_names.en` value
wins over the scan-level `common_name`. The audio scan name may fill an empty
English name, but it cannot rename an existing species row.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/audio-spec/index.ts services/supabase/functions/_shared/scanIngestionCompatibility.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/audio-spec/index.test.ts services/supabase/functions/_shared/scanIngestionCompatibility_test.ts services/supabase/functions/_shared/identify/db_test.ts
```
