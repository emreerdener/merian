# audio-spec

Compatibility endpoint for legacy audio-only scan requests.

The active iOS audio path now routes through `/identify-multimodal`, which
accepts foreground `audioBase64s` and queued `audioR2ObjectKeys`. This route
remains deployed for older callers and focused audio budget tests.

## Authoritative AI Quota

The authenticated caller's `client_scan_id` is the UUID idempotency key for the
`scan_audio_identification` reservation. Immediately before Gemini dispatch, the
service-role-only database RPC resolves durable entitlement, applies the shared
scan daily ceiling plus per-user/IP minute limits, and selects the model.
Missing user state, database errors, missing policy, or a replay already in
progress fail closed. The reservation is committed before provider dispatch;
provider failure stays charged and enters the retryable `failed` state. Only a
known pre-provider no-op may enter `refunded`; an abandoned `reserved` attempt
expires after ten minutes.

## Durability

Before returning success, `audio-spec` records a `scan_ingestion_jobs` row plus
a sanitized `scan_ingestion_intents` row through
`_shared/scanIngestionCompatibility.ts`.

- Staged `audio_r2_key` requests are shaped as multimodal replay payloads with
  `audioR2ObjectKeys` and `audioMediaItems`, subject to the shared 10-claim
  server replay ceiling.
- Inline `audio_base64` bytes are never stored in the intent. They are counted
  in `redacted_media_counts`, marked `inline_media_redacted = true`, and remain
  client-retry only.
- Successful background insert marks the job `complete`; insert failures mark it
  `failed_retryable`.
- Staged audio remains an inference input only and is deleted after successful
  scan persistence.

## Dictionary Common Names

Audio-only biological results can still warm or create `species_dictionary`
rows, but they share the same dictionary name merge rule as the visual/text
routes: an existing `species_dictionary.common_names.en` value wins over the
scan-level `common_name`. The audio scan name may fill an empty English name,
but it cannot rename an existing species row.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/audio-spec/index.ts services/supabase/functions/_shared/scanIngestionCompatibility.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/audio-spec/index.test.ts services/supabase/functions/_shared/scanIngestionCompatibility_test.ts services/supabase/functions/_shared/identify/db_test.ts
```
