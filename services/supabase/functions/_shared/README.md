# `_shared` Directory

The `_shared` repository contains the core abstraction domains that power
Merian's globally isolated Deno Edge Functions.

Rather than fragmenting logic recursively through every function directory, the
shared dependencies are grouped by domain. Keep new shared code here only when
multiple functions need the same behavior and the ownership boundary is clear.

## Infrastructure Map

- **`edgeHandler.ts`**: Authenticated user-facing function wrapper, custom-auth
  `serveEdge(...)` registration, preflight handling, background task dispatch,
  structured operational logging, auth timing, and additive `Server-Timing`
  propagation. Both wrappers assign a server-owned request UUID and add
  `X-Request-ID` to every response. Expected thrown failures use
  `PublicHttpError`; explicit safe response failures use
  `publicErrorResponse(...)`. Audited returned `4xx` application contracts are
  still supported, while unexpected exceptions become `500 internal_error` and
  ordinary returned `5xx` bodies keep their status but receive a generic
  status-derived envelope. Raw exception details remain server-side.
- **`http.ts`**: CORS headers, JSON responses, parameter validation,
  constant-time comparison helpers, and the canonical bounded request readers.
  `parseJsonBody(...)` is the ordinary object API;
  `readRequestBodyWithinLimit(...)` preserves exact signed webhook bytes; media
  adapters delegate to `readBoundedJsonBody(...)`. They validate JSON media type
  where applicable, declared and actual byte counts while streaming, and invalid
  UTF-8. `readByteStreamWithinLimit(...)` coalesces tiny transport chunks into a
  geometrically growing bounded buffer, so memory tracks accepted bytes instead
  of attacker-influenced chunk count. Every route selects a reviewed
  `JSON_BODY_LIMITS` class (`small`, `standard`, or `bulk`) or an explicit
  media-specific ceiling. Do not add a direct `req.json()`, `req.text()`, or
  unbounded clone to a production handler.
- **`auth.ts`**: Shared bearer parsing, claims validation, and the compatibility
  Auth-server `getUser` strategy used by existing authenticated endpoints.
- **`clientAddress.ts`**: Shared proxy-observed client-address extraction and
  purpose-separated daily HMAC derivation. Abuse controls store only the HMAC; a
  missing proxy address joins a conservative shared fail-safe bucket.
- **`claimsAuth.ts`**: Opt-in cached-JWKS `getClaims` authentication for
  latency-sensitive routes. It explicitly validates issuer, audience,
  expiration/not-before, role, and `sub`; accepts anonymous and authenticated
  users; and rejects `service_role`. All functions share the same exact Supabase
  SDK, but keeping this policy out of `edgeHandler.ts` prevents an implicit
  fleet-wide authentication change. Internal replay keeps its separate
  timing-safe service credential path.
- **`aws.ts`**: Cloudflare R2/S3-compatible presigned upload, object HEAD/copy,
  and batch deletion helpers. `deleteR2Objects` uses `mapWithConcurrencyLimit`
  internally so lifecycle workers do not run unbounded delete fanout. Prefix
  helpers classify `staging/`, `quarantine/`, and `exports/` as temporary,
  `public_uploads/free|pro/` as scan media, and `avatars/` as durable profile
  media. Scan purge flows must use `deleteScanMediaR2Objects(...)`; avatar
  replacement must use `deleteAvatarR2Object(...)` with the owning user ID.
- **`mediaBudgets.ts`**: Shared media byte ceilings, allowed staging content
  types, inline/staged audio and image validation, clip-count limits, and
  `Content-Length` prechecks. The shared staging cap is six files so one video
  scan can sign five sampled inference frames plus one playback clip; image,
  audio, and video sub-limits still prevent broad over-batching. Request and
  response bodies that may be chunked or omit `Content-Length` must be consumed
  through `readRequestJsonWithinBudget`, `readResponseArrayBufferWithinBudget`,
  or `readStreamArrayBufferWithinBudget` so the byte counter rejects oversized
  streams before V8 can allocate past the Edge heap budget. The request JSON
  adapter delegates to `http.ts`; `mediaBudgets.ts` owns only the larger
  reviewed ceiling and media-specific error copy.
- **`concurrency.ts`**: Ordered promise mapping with a fixed worker width. Use
  `mapWithConcurrencyLimit` for fanout work such as APNs delivery or remote
  object operations where unbounded `Promise.all(...)` could spike sockets,
  heap, provider throttles, or Postgres writes.
- **`scanMediaAssets.ts`**: Normalized scan-media lifecycle helpers. Upload
  signing creates staged scan-media asset rows with `scan_id` null until the
  final scan exists, identify finalization marks them promoted/deleted/failed,
  and write paths make best-effort `scan_media_assets` refresh calls after scan
  inserts or video repair updates. The `reconcile-scan-media-assets` worker owns
  stale staged-row repair and abandonment cleanup, while checking active
  ingestion jobs before abandoning staged upload-session media. Composer and
  status paths prefer ready display/playback asset rows before falling back to
  `captured_media` and legacy arrays. Generated video rows derive `has_audio`
  only from captured-media audio references; legacy video arrays default false
  because they cannot prove an audio companion survived. `scan-media-health`
  reads the same lifecycle state for deploy smoke checks and operational drift
  alerts, but does not mutate media rows.
- **`scanIngestionJobs.ts`**: Durable scan-ingestion job helpers. The active
  multimodal path claims a job row after media validation, updates server-side
  stages through inference/finalization/failure, and `/check-scan-status`
  exposes the owner-safe job state when the scan row is not complete yet. Claims
  include expected media counts, staged object keys, recovered upload-session
  ids, and a normalized manifest checksum so retries, server replay, and repair
  work can detect accidental media-shape drift.
- **`scanIngestionIntents.ts`**: Sanitized scan-ingestion replay intent helpers.
  `identify-multimodal` records telemetry, observation context, media
  descriptors (including validated still-image focus regions), staged object
  keys, upload-session ids, and payload checksums into `scan_ingestion_intents`
  without raw base64 media bytes or local device paths. Inline-media requests
  are marked non-resumable so `replay-scan-ingestion` and health checks know
  they still depend on the client queue. Server replay is capped at 10 claims
  per sanitized intent before the paired job is marked
  `failed_terminal / server_replay_limit_reached`.
- **`audioProcessing.ts`**: Shared WAV decode/trim/resample/encode pipeline used
  by `audio-spec` and `identify-multimodal`.
- **`external.ts`**: Wikipedia and GBIF enrichment helpers used by identify,
  enrichment, species refresh, and dictionary paths. All returned reference
  image URLs pass through `externalImagePolicy.ts` before the enrichment object
  is returned.
- **`externalImagePolicy.ts`**: Exact third-party reference-media denylist. The
  current rule suppresses every resized/query variant below
  `inaturalist-open-data.s3.amazonaws.com/photos/605615444/` while leaving other
  iNaturalist and GBIF media untouched. Keep it aligned with the iOS
  `ExternalReferenceImagePolicy`; use a new cleanup/prevention migration for
  every added outlier.
- **`gemini.ts`**: Global `GoogleGenAI` client setup plus structured-output and
  JSON extraction helpers.
- **`biology.ts`**: Shared structured biological generation helpers retained for
  functions that still need text-only ecological generation. Externally
  reachable callers must pass the model selected by the database quota policy;
  service-only maintenance callers pass their reviewed system model explicitly.
- **`aiQuota.ts`**: Service-role client for the atomic `reserve_ai_quota(...)`
  and `finalize_ai_quota_reservation(...)` RPCs. It validates UUID idempotency
  keys, uses `clientAddress.ts` with an optional dedicated override or built-in
  server-only Supabase key, maps fail-closed database errors to stable HTTP
  codes, and exposes a fenced provider lease. A route commits immediately before
  a provider attempt; provider failures remain charged but become retryable, and
  only a proven pre-provider no-op may refund.
- **`groupTagQuota.ts`**: Optional identification group-tag enrichment behind
  its own database-selected model and quota operation. Quota/provider failures
  are recorded without discarding the successful primary identification.
- **`entitlement.ts`**: Durable user-tier resolver for non-provider feature
  checks and telemetry. It reads `users` on every call, includes the monotonic
  `entitlement_version`, and returns `503 ai_entitlement_unavailable` on a query
  error or missing row. Edge isolate memory is never an entitlement authority.
- **`posthog.ts`**: Best-effort PostHog HTTP capture helpers.
- **`subscriptionPass.ts`**: Exact product policy for the detached `pro_week`
  pass, including the 7-day duration. The webhook derives purchase time from
  authoritative CustomerInfo `non_subscriptions`, never directly from an event.
- **`explore.ts`**: Explore UUID/hashtag validation, public author identity
  sync, feed-card hashtag/pro-badge/username hydration, and shared
  social-surface helpers.
- **`publicSpeciesProjection.ts`**: Public species projection sanitizer that
  prevents private scan/user fields from leaking into dictionary and Explore
  responses. It also filters exact denied external media from normalized rows,
  legacy comma-separated caches, and first-image projections without changing
  the public DTO shape.
- **`speciesContentProvenance.ts`**: Provenance mapping for scheduled species
  content refresh outputs.
- **`taxonomy.ts`**: Taxonomic normalization helpers and test-backed taxonomy
  transformations.
- **`scanIngestionCompatibility.ts`**: Compatibility ledger for scan-producing
  legacy endpoints. `/identify`, `/identify-describe`, and `/audio-spec` record
  `scan_ingestion_jobs` plus multimodal-shaped sanitized
  `scan_ingestion_intents` before returning success. Staged media and text-only
  intents can be replayed through `replay-scan-ingestion`; inline base64 media
  is redacted and marked non-resumable.

## Identify Subdomain

`_shared/identify/` is the shared inference stack used by `identify`,
`identify-multimodal`, `identify-describe`, and `audio-spec` where behavior is
identical:

- **`clientPayload.ts`**: Cache-hit payload hydration shared by identify
  endpoints.
- **`context.ts`**: Telemetry context normalization, month/time handling, and
  ecological field clamping.
- **`db.ts`**: Scan insert/update helpers, species cache writes, and shared
  database boundaries.
- **`latencyDb.ts`**: Thin service-role RPC client for atomic ingestion setup
  (`begin_scan_ingestion`, including its server-canonicalized session ids and
  checksums) and combined primary/candidate dictionary hydration
  (`hydrate_identification_dictionary`). Keep rollout compatibility fallbacks in
  the calling route, not in this module.
- **`media.ts`**: Image/audio media resolution from inline payloads and R2
  staging keys.
- **`moderation.ts`**: Gemini safety evaluation, abuse strikes, and safe media
  promotion.
- **`schema.ts`**: Gemini response schema definitions.
- **`thresholds.ts`**: Tier-specific confidence thresholds mirrored by
  `MerianConfig`.
- **`types.ts`**: Shared TypeScript DTOs for the identify family.
