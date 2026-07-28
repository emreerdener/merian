# audio-spec

Compatibility endpoint for legacy audio-only scan requests.

The active iOS audio path now routes through `/identify-multimodal`, which
accepts foreground `audioBase64s` and queued `audioR2ObjectKeys`. This route
remains deployed for older callers and focused audio budget tests.

The route checks exact owner/scan completion before R2 audio resolution and
quota reservation. It replays stored or reconstructed success as marked `200`
and coalesces concurrent same-UUID delivery without a second Gemini call. The
response-aware finalizer stores the validated payload only after required audio
cleanup and scan completion.

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

Before provider dispatch, `audio-spec` atomically records a
`scan_ingestion_jobs` row plus a sanitized `scan_ingestion_intents` row through
`_shared/scanIngestionCompatibility.ts`. Setup failure fails closed before paid
work and refunds the unused quota reservation.

- Staged `audio_r2_key` requests are shaped as multimodal replay payloads with
  `audioR2ObjectKeys` and `audioMediaItems`, subject to the shared 10-claim
  server replay ceiling.
- Inline `audio_base64` bytes are never stored in the intent. They are counted
  in `redacted_media_counts`, marked `inline_media_redacted = true`, and remain
  client-retry only.
- Successful background insert delegates to the shared completion-last
  finalization RPC; insert/finalization failures become durable retryable work.
- Staged audio remains inference-only. R2 must confirm deletion with 2xx or
  idempotent 404 before finalization may mark the job complete.

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
