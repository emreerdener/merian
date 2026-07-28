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
    {
      "kind": "image",
      "sourceIndex": 0,
      "focusRegion": {
        "x": 0.125,
        "y": 0.25,
        "width": 0.5,
        "height": 0.4,
        "source": "vision_objectness"
      }
    },
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

Clients send the UUID `client_scan_id` as `Idempotency-Key` and preserve both
values across transport, authentication, and queue retries. The database scopes
that key by user and quota operation, so simultaneous duplicate requests cannot
reserve twice. A known pre-provider validation no-op explicitly refunds; once
the reservation is committed, provider errors remain consumed because spend may
already have occurred and transition to `failed` so a new metered retry can use
the same logical key. An uncommitted reservation expires after ten minutes, and
its per-attempt fencing token rejects delayed settlement after retry.

## Model And Generation Invariants

Each accepted scan makes exactly one primary identification
`_genAI.models.generateContent` call. The model comes from the atomic
`scan_identification` database policy; the current policy is:

- Free: `gemini-2.5-flash`
- Pro: `gemini-2.5-pro`

The same transaction resolves the durable plan and entitlement version, applies
the plan's UTC-day scan ceiling, and consumes the shared per-user/IP minute
limits. Missing user rows, entitlement/database errors, disabled or missing
policy, and exhausted counters fail closed before provider dispatch.

The route retains the existing modality-specific system instructions,
temperature `0.1`, seed `42`, `maxOutputTokens: 8192`, Pro thinking budget
`5000`, structured response schema, image/media resolution, and safety behavior.
Latency optimization must happen around this call, not by changing its economics
or identification semantics.

## Response Contract

`_shared/identify/contract.ts` is the executable boundary for both Gemini model
output and the complete response returned to iOS. It generates the structured
provider schema and the checked-in Swift DTO block, while its runtime parser
enforces nested types, requiredness, nullability, enum values, cardinality and
string limits, safe integers, and numeric bounds.

The route validates the provider object immediately after JSON extraction. It
validates the full `{ success, data }` envelope again after sanitization,
dictionary hydration, candidate enrichment, and server-added fields, before
durable video finalization, persistence, or HTTP success. A final mismatch marks
the ingestion job retryable and returns HTTP `502` with
`identify_response_invalid`; internal contract detail is logged but not exposed.

Run `make generate-edge-dto-contract` and `make validate-edge-dto-contract` for
intentional response changes. The root Swift fields are generated as optional
for staggered rollout compatibility, but the server contract remains strict
before delivery.

## Media Rules

- Still images are Gemini visual inputs and durable scan/display media.
- A still-image descriptor may include `focusRegion` with top-left-normalized
  bounds and `source: "vision_objectness"`. Valid regions identify the likely
  primary subject in the prompt while the complete image remains the only Gemini
  visual part. Invalid, out-of-bounds, non-finite, and video-frame focus regions
  are stripped without failing the request.
- Standalone audio and extracted video audio are Gemini audio inputs. Standalone
  audio is also durable scan media: it is promoted into `audio_storage_urls`,
  represented in `captured_media`, and normalized as a ready audio asset for
  optional Explore sharing. Extracted `video_audio` remains inference-only and
  is deleted after finalization because the playback MP4 is the public artifact.
- Video inference is represented by sampled image frames plus optional extracted
  audio. The playback `.mp4` is not sent to Gemini.
- New video scans require durable playback video promotion. If
  `videoR2ObjectKeys` is non-empty, every requested video must be promoted and
  persisted in `scans.video_storage_urls` and `scans.captured_media` before the
  request is successful.
- `captured_media` is the canonical scan timeline. Video frames collapse behind
  one video item with a poster thumbnail; sampled frames must not become
  standalone shareable image media.
- Video audio metadata is evidence-based. `captured_media` includes a video
  audio reference only when extracted audio was actually provided, and generated
  media rows should set `has_audio` from that reference rather than from
  `kind === "video"`.

## Ingestion Durability

For staged or queued requests, `client_scan_id` becomes the server scan id and
the ingestion ledger key.

The endpoint writes two server-side records before AI inference:

- `scan_ingestion_jobs`: the mutable state machine for claim, stage,
  retryability, required media counts, upload-session ids, and
  `manifest_checksum`.
- `scan_ingestion_intents`: the sanitized replay intent for the accepted
  request. It stores telemetry, observation context, media descriptors, staged
  object keys, upload-session ids, accepted focus metadata, and
  `payload_checksum`.

`begin_scan_ingestion` performs upload-session lookup, job claim, intent upsert,
server-side checksum canonicalization, and the `ai_inference_started` transition
in one service-role-only database round trip. Checksums are calculated only
after resolved upload-session ids have been merged into the stored payload. The
handler retains the former helper sequence only as a rolling-deployment fallback
when the migration is not yet visible.

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

## Latency And Authentication Boundary

Public requests inject `requireClaimsAuth` into `withEdgeHandler`. The claims
policy is isolated from the wrapper's default `getUser` path, so unrelated
authenticated functions keep their established authentication semantics while
all routes share one exact Supabase SDK graph. `auth.getClaims(token)` verifies
the project's ES256 signature through cached JWKS, after which Merian validates
issuer, audience, expiration/not-before, role, and `sub`. Anonymous and
authenticated users are valid; public `service_role` use is rejected. Internal
replay is recognized first and retains its exact platform-managed service
credential (`SUPABASE_SERVER_API_KEY`, the deploy-synchronized
`MERIAN_SUPABASE_SERVER_API_KEY`, a named JSON `SUPABASE_SECRET_KEYS` value, the
singular `SUPABASE_SECRET_KEY` local/manual fallback, or the migration-only
`SUPABASE_SERVICE_ROLE_KEY` legacy fallback) plus explicit replay-user checks.
Named non-JWT secrets use `apikey` only; database access uses the server
environment key rather than the request value.

The Gemini timer stops immediately after `generateContent` returns, before
finish-reason processing, JSON parsing, dictionary work, or persistence. After
parsing, `hydrate_identification_dictionary` returns cached primary-species data
and candidate common names in one service-role-only RPC. Moderation, required
media promotion, and the scan insert complete before the route returns success
for every current multimodal observation. This durability boundary ensures the
returned `scan_id` is immediately usable by Field Chat, Explore sharing, field
trips, and owner sync. Analytics, group tags, and candidate enrichment remain
optional `EdgeRuntime.waitUntil` work. The duplicate-protected scan insert is
followed by an owner-scoped read-back; a no-op collision or moderation branch
therefore cannot resolve into HTTP success without the owner row.
Terminal media-policy rejection returns generic customer-facing code
`observation_rejected` with HTTP 400, while operational failures in moderation,
promotion, species resolution, or scan insertion return retryable
`scan_persistence_failed` with HTTP 503.

Successful responses add diagnostic headers without changing the JSON body:

- `Server-Timing`: `auth`, `body_read`, `tier`, `pre_gemini_db`, `gemini`,
  `dictionary`, `post_gemini`, and `edge_total`.
- `X-Merian-Edge-Region`: the observed Edge region when available.

The structured `multimodal/latency` event is tagged by tier, model, image count,
payload bytes, Edge region, and constrained-network state. It must not include
user ID, scan ID, species, coordinates, media keys, or request contents.

Late shutter context is sent separately to `/update-scan-context`, keyed by the
same `scan_id`; it never changes this request or creates another model call.

## Recovery And Health

- `/check-scan-status` is the owner-safe polling endpoint. It reports completed
  scan rows and, when requested, server-side ingestion job state.
- `/replay-scan-ingestion` claims due resumable staged or text-only intents and
  dispatches them back through this endpoint with the same `client_scan_id`. Its
  service-authenticated durable claim count derives a separate deterministic
  quota UUID for each replay attempt, so a committed foreground reservation
  cannot block recovery and a dispatch retry cannot double-reserve. Replay
  claims are capped at 10 per sanitized intent; exhausted jobs become
  `failed_terminal / server_replay_limit_reached`.
- `/reconcile-scan-media-assets` repairs or abandons staged media lifecycle
  drift but does not replay AI inference.
- `/scan-media-health` reports stuck jobs, stale media assets, missing replay
  intents, and non-resumable redacted intents for operations.

## Biological Boundary

The primary subject must be an organism, organism part, fossil, or preserved
specimen before the response can write or enrich species data. Manufactured or
processed objects stay non-biological even when made from biological material:
wool rugs/kilims/carpets, leather goods, wooden furniture, paper/cardboard,
cotton or linen fabric, prepared food, toys, artwork, ornaments, and
printed/painted/sculpted species depictions must not be identified as the source
organism.

After parsing and sanitization, the route calls the shared
`normalizeProcessedMaterialSubject(...)` guard before `isIdentifiedBio` is
computed. A demoted result keeps the object `common_name` when useful for the
non-biological Insight, but clears source-species `scientific_name`, candidates,
biology-only fields, and `is_new_to_merian_dictionary`. Demotions emit a
structured `multimodal/processed_material_demoted` event.

Dictionary writes also preserve existing canonical English names. If a
`species_dictionary.common_names.en` value already exists, a scan-level
`common_name` cannot replace it; scan names only fill an empty English name for
a normalized biological subject.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/identify-multimodal/index.ts services/supabase/functions/update-scan-context/index.ts services/supabase/functions/_shared/identify/latencyDb.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net --allow-read services/supabase/functions/identify-multimodal/index.test.ts services/supabase/functions/_tests/auth.test.ts services/supabase/functions/_shared/identify/latencyDb_test.ts services/supabase/functions/_shared/scanIngestionIntents_test.ts services/supabase/functions/_shared/scanIngestionJobs_test.ts services/supabase/functions/_tests/migrationMediaContract.test.ts
```

Database integration tests require a running local Supabase Postgres instance.
