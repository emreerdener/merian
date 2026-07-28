# audio-spec

Compatibility endpoint for legacy audio-only scan requests.

The active iOS audio path now routes through `/identify-multimodal`, which
accepts foreground `audioBase64s` and queued `audioR2ObjectKeys`. This route
remains deployed for older callers and focused audio budget tests.

The route checks exact owner/scan completion before R2 audio resolution and
quota reservation. It replays stored or reconstructed success as marked `200`
and coalesces concurrent same-UUID delivery without a second Gemini call. The
response-aware finalizer stores the validated payload only after required audio
promotion and scan completion. It also establishes the service-only, Auth-backed
profile prerequisite before paid work and repeats that check before the owner
insert so account retirement or merge cannot be crossed silently.

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
- Scan insertion is awaited, never registered as background work. Success is
  impossible without the exact owner row. The shared completion-last
  finalization RPC runs in that required task; if only its post-insert
  bookkeeping fails, the owner row remains the canonical response surface and
  the ledger remains retryable for reconstruction/reconciliation.
- If an old caller sends both `audio_base64` and `audio_r2_key`, the inline
  bytes are authoritative. The unused key is a filename hint only and is never
  fetched, ledgered, finalized, or deleted.
- Standalone audio is promoted and retained in `audio_storage_urls`,
  `captured_media`, and normalized ready audio assets. A pre-insert failure
  best-effort removes the newly promoted public object only after an owner read
  proves the row absent and requires the client to stage its retained local
  recording again. An ambiguous write/read response preserves quota and audio
  until exact-owner retry recovery proves the outcome.
- Dictionary cache enrichment after provider dispatch is nonfatal. A transient
  read falls back to uncached scan enrichment while required persistence still
  runs inside the durable failure boundary.

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
