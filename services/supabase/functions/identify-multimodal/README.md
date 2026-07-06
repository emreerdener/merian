# identify-multimodal

Primary scan-ingestion Edge Function for mixed media. The iOS client uses this
endpoint for still images, audio, short video captures, description context, and
combined submissions.

## Request Contract

The endpoint accepts authenticated user requests through `withEdgeHandler`.
Media can arrive inline for foreground requests or as staged Cloudflare R2
object keys for queued/offline requests.

Common fields:

```json
{
  "user_id": "ignored-client-value",
  "client_scan_id": "00000000-0000-0000-0000-000000000001",
  "r2ObjectKeys": ["staging/user-id/photo.webp"],
  "audioR2ObjectKeys": ["staging/user-id/audio.wav"],
  "videoR2ObjectKeys": ["staging/user-id/playback.mp4"],
  "videoFrameCount": 5,
  "visualMediaItems": [
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 0 }
  ],
  "audioMediaItems": [
    { "kind": "video_audio", "clipIndex": 0 }
  ],
  "observation_contexts": [
    {
      "freeText": "Growing beside the porch light",
      "addedAt": "2026-07-05T03:00:00.000Z"
    }
  ]
}
```

`user_id` is retained for legacy request shape compatibility, but ownership is
derived from the JWT user. Staged keys must belong to that user and remain under
the expected `staging/` prefix. Inline base64 media is size-checked before
decode; staged media is fetched through bounded stream readers.

## Media Rules

- Still images are Gemini visual inputs and durable scan/display media.
- Standalone audio and extracted video audio are Gemini audio inputs. They are
  not public scan media and consumed staging objects are deleted after
  finalization.
- Video inference is represented by sampled image frames plus optional extracted
  audio. The playback `.mp4` is not sent to Gemini.
- New video scans require durable playback video promotion. If
  `videoR2ObjectKeys` is non-empty, every requested video must be promoted and
  persisted in `scans.video_storage_urls` and `scans.captured_media` before the
  request is successful.
- `captured_media` is the canonical scan timeline. Video frames collapse behind
  one video item with a poster thumbnail; sampled frames must not become
  standalone shareable image media.

## Ingestion Durability

For staged or queued requests, `client_scan_id` becomes the server scan id and
the ingestion ledger key.

The endpoint writes two server-side records before AI inference:

- `scan_ingestion_jobs`: the mutable state machine for claim, stage,
  retryability, required media counts, upload-session ids, and
  `manifest_checksum`.
- `scan_ingestion_intents`: the sanitized replay intent for the accepted
  request. It stores telemetry, observation context, media descriptors, staged
  object keys, upload-session ids, and `payload_checksum`.

Replay intents deliberately do not store raw base64 media bytes or local device
paths. If a request used inline foreground media, the intent is marked
`resumable = false` and `inline_media_redacted = true`; the iOS queue remains
the recovery source for that request. Staged-media requests are resumable
because the payload contains only server-owned object keys and metadata.

Compatibility scan-producing endpoints (`identify`, `identify-describe`, and
`audio-spec`) write the same job/intent ledger before returning success. Their
sanitized intents target this endpoint for replay and preserve the legacy route
name as `compatibilityEndpoint`; inline base64 media remains redacted and
non-resumable.

## Recovery And Health

- `/check-scan-status` is the owner-safe polling endpoint. It reports completed
  scan rows and, when requested, server-side ingestion job state.
- `/replay-scan-ingestion` claims due resumable staged or text-only intents and
  dispatches them back through this endpoint with the same `client_scan_id`.
- `/reconcile-scan-media-assets` repairs or abandons staged media lifecycle
  drift but does not replay AI inference.
- `/scan-media-health` reports stuck jobs, stale media assets, missing replay
  intents, and non-resumable redacted intents for operations.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/identify-multimodal/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/identify-multimodal/index.test.ts services/supabase/functions/_shared/scanIngestionIntents_test.ts services/supabase/functions/_shared/scanIngestionJobs_test.ts
```

Database integration tests require a running local Supabase Postgres instance.
